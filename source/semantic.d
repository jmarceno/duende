module duende.semantic;

import duende.ast;
import duende.binding : bindArguments;
import std.algorithm : canFind;
import std.conv : to;
import std.array : appender;
import std.string : join;

// Centralized semantic error type and collector (imported by compiler)
struct SemanticError {
	string message;
	string file;
	int line;
	int column;

	this(string message, string file, int line, int column) {
		this.message = message;
		this.file = file;
		this.line = line;
		this.column = column;
	}

	string toString() const {
		return file ~ ":" ~ line.to!string ~ ":" ~ column.to!string ~ ": " ~ message;
	}
}

class SemanticErrorCollector {
	SemanticError[] errors;

	void addError(string message, string file, int line, int column) {
		errors ~= SemanticError(message, file, line, column);
	}

	void addError(string message, SourcePosition pos, string fallbackFile = "") {
		auto p = normalizePos(pos, fallbackFile);
		errors ~= SemanticError(message, p.file, p.line, p.column);
	}

	bool hasErrors() const { return errors.length > 0; }

	void reportAll() const {
		import std.stdio : writeln;
		foreach (e; errors) writeln("Error: " ~ e.toString());
	}
}

private TypeNode typeInfo(DuendeType t, string custom = null) {
	return TypeNode.of(t, custom);
}

private string typeInfoToString(TypeNode t) {
	return t.describe();
}

private bool isComparisonOp(string op) {
	return op == "==" || op == "!=" || op == "<" || op == ">" || op == "<=" || op == ">=";
}

private bool isLogicalOp(string op) {
	return op == "&&" || op == "||";
}

private bool isPermissive(TypeNode t) {
	if (!t.present || t.unknown) return true;
	return t.base == DuendeType.AUTO && !t.inferred;
}

private TypeNode resolveAuto(TypeNode declared, TypeNode initType) {
	if (declared.base != DuendeType.AUTO || declared.inferred) return declared;
	if (isPermissive(initType)) return TypeNode.unknownType();
	TypeNode inf = initType;
	inf.inferred = true;
	inf.unknown = false;
	inf.present = true;
	return inf;
}

private TypeNode stringDict() {
	return TypeNode.generic(DuendeType.DICT, [
		TypeNode.of(DuendeType.STRING),
		TypeNode.of(DuendeType.STRING)
	]);
}

private TypeNode declaredNode(TypeNode node, DuendeType fallback, string custom = null) {
	TypeNode t = node.present ? node : TypeNode.of(fallback, custom);
	// A bare dict is the old string dictionary. It does not stringify new values.
	if (t.base == DuendeType.DICT && t.args.length < 2) return stringDict();
	return t;
}

// Dictionary slots do not accept the general implicit conversion to string.
private bool elementCompatible(TypeNode need, TypeNode got) {
	if (isPermissive(need) || isPermissive(got)) return true;
	if (need.base == DuendeType.FLOAT && got.base == DuendeType.INT && need.args.length == 0) return true;
	if (need.base != got.base) return false;
	if (need.base == DuendeType.CUSTOM) {
		if (need.name.length && got.name.length) return need.name == got.name;
		return true;
	}
	if (need.args.length == 0 || got.args.length == 0) return true;
	if (need.args.length != got.args.length) return false;
	foreach (i, arg; need.args) {
		if (!elementCompatible(arg, got.args[i])) return false;
	}
	return true;
}

private bool typeCompatible(TypeNode need, TypeNode got) {
	if (isPermissive(need) || isPermissive(got)) return true;
	if (need.base == DuendeType.DICT && got.base == DuendeType.DICT)
		return elementCompatible(need, got);
	if (need.base == got.base) {
		if (need.base == DuendeType.CUSTOM) {
			if (need.name.length && got.name.length)
				return need.name == got.name;
			return true;
		}
		if (need.args.length == 0) return true;
		if (got.args.length == 0) return true;
		if (need.args.length != got.args.length) return false;
		foreach (i, arg; need.args) {
			if (!typeCompatible(arg, got.args[i])) return false;
		}
		return true;
	}
	// allow INT -> FLOAT
	if (need.base == DuendeType.FLOAT && got.base == DuendeType.INT) return true;
	// allow implicit conversion to STRING from any non-void type
	if (need.base == DuendeType.STRING && got.base != DuendeType.VOID) return true;
	return false;
}

private SourcePosition normalizePos(SourcePosition pos, string fileFallback) {
	SourcePosition p = pos;
	if (p.line <= 0) p.line = 1;
	if (p.column <= 0) p.column = 1;
	if (!p.file.length) p.file = fileFallback;
	return p;
}

// Analyzer
class SemanticAnalyzer {
	// function name -> declaration
	private FunctionDeclaration[string] functions;
	// One symbol record: the recursive type plus whether the binding may be reassigned.
	private struct Binding {
		TypeNode type;
		bool mutable;
	}
	private struct FieldSymbol {
		TypeNode type;
		bool mutable;
	}
	private struct AggregateSymbol {
		bool isFrame;
		FieldSymbol[string] fields;
		bool[string] mutatingMethods;
	}
	// top-level variables (globals)
	private Binding[string] globals;
	// enum name -> values set
	private string[][string] enums; // map enum name -> list of values
	// struct/frame name -> fields and which methods write those fields
	private AggregateSymbol[string] aggregates;
	// protocols declared in this module
	private ProtocolDeclaration[string] protocols;
	// recursion guard
	private size_t maxDepth = 10_000;
	// whether module has any imports (providers may inject symbols)
	private bool hasImports;
	private TypeNode currentReturn;
	private bool hasCurrentReturn;
	private string currentFunctionName;

	private string resolveEnumForValue(string valueName) {
		foreach (enumName, vals; enums) {
			if (vals.canFind(valueName)) return enumName;
		}
		return null;
	}

	void analyzeModule(Program prog, string moduleName, string sourcePath, SemanticErrorCollector errs) {
		if (prog is null) return;
		// Pass 1: collect functions and globals
		foreach (s; prog.statements) {
			if (auto f = cast(FunctionDeclaration)s) {
				functions[f.name] = f;
			} else if (auto v = cast(VariableDeclaration)s) {
				globals[v.name] = Binding(declaredNode(v.typeNode, v.type, v.customTypeName), v.isMutable);
			} else if (auto en = cast(EnumDeclaration)s) {
				enums[en.name] = en.values.dup;
			} else if (auto st = cast(StructDeclaration)s) {
				rememberStruct(st);
			} else if (auto fr = cast(FrameDeclaration)s) {
				rememberFrame(fr);
			} else if (cast(ImportDeclaration)s) {
				hasImports = true;
			} else if (auto pd = cast(ProtocolDeclaration)s) {
				protocols[pd.name] = pd;
			}
		}
		// Conformance: every protocol method without a default must be defined by the implementer
		foreach (s; prog.statements) {
			if (auto st = cast(StructDeclaration)s) checkConformance("Struct", st.name, st.annotations, st.methods, sourcePath, errs);
			else if (auto fr = cast(FrameDeclaration)s) checkConformance("Frame", fr.name, fr.annotations, fr.methods, sourcePath, errs);
		}
		// Pass 2: analyze statements with a scope stack
		ScopeEnv env;
		// seed with globals
		foreach (k, b; globals) env.define(k, b.type, b.mutable);
		foreach (s; prog.statements) {
			visitStmt(s, sourcePath, errs, env, 0);
		}
	}

	private void rememberStruct(StructDeclaration st) {
		AggregateSymbol agg;
		agg.isFrame = false;
		foreach (fd; st.fields) {
			agg.fields[fd.name] = FieldSymbol(declaredNode(fd.typeNode, fd.type, fd.customTypeName), false);
		}
		aggregates[st.name] = agg;
	}

	private void rememberFrame(FrameDeclaration fr) {
		AggregateSymbol agg;
		agg.isFrame = true;
		foreach (fd; fr.fields) {
			agg.fields[fd.name] = FieldSymbol(declaredNode(fd.typeNode, fd.type, fd.customTypeName), fd.isMutable);
		}
		bool[string] direct;
		foreach (m; fr.methods) {
			if (methodAssignsThis(m)) direct[m.name] = true;
		}
		bool[string] mut = direct;
		bool changed = true;
		while (changed) {
			changed = false;
			foreach (m; fr.methods) {
				if (m.name in mut) continue;
				if (methodCallsMutatingThis(m, mut)) {
					mut[m.name] = true;
					changed = true;
				}
			}
		}
		agg.mutatingMethods = mut;
		aggregates[fr.name] = agg;
	}

	// Simple scope chain. Mutability lives on the binding, next to its type.
	private struct ScopeEnv {
		Binding[string] table;
		ScopeEnv* parent;

		void define(string name, TypeNode t, bool mutable) { table[name] = Binding(t, mutable); }
		bool lookup(string name, out Binding b) {
			if (auto p = name in table) { b = *p; return true; }
			if (parent is null) return false;
			return parent.lookup(name, b);
		}
		ScopeEnv child() {
			ScopeEnv c; c.parent = &this; return c;
		}
	}

	private void visitStmt(Statement s, string sourcePath, SemanticErrorCollector errs, ref ScopeEnv env, size_t depth) {
		if (s is null) return;
		if (depth > maxDepth) return; // safety
		if (auto vd = cast(VariableDeclaration)s) {
			auto ti = declaredNode(vd.typeNode, vd.type, vd.customTypeName);
			if (ti.base == DuendeType.DICT) vd.typeNode = ti;
			if (vd.initializer !is null) {
				TypeNode expect = (ti.base == DuendeType.AUTO) ? TypeNode.init : ti;
				auto et = visitExpr(vd.initializer, sourcePath, errs, env, depth + 1, expect);
				bool specialOk = false;
				// Special-case: allow bytes initialized from a list literal of ints
				if (ti.base == DuendeType.BYTES) {
					if (cast(ListLiteralExpression)vd.initializer !is null) {
						// Optionally, could validate element types/ranges; accept for now
						specialOk = true;
					}
				}
				if (ti.base == DuendeType.AUTO) {
					applyInferred(vd, ti, et);
				} else if (!typeCompatible(ti, et) && !specialOk) {
					auto pos = normalizePos(vd.position, sourcePath);
					errs.addError(
						"Initializer type does not match declared type of '" ~ vd.name ~ "' (need=" ~ typeInfoToString(ti) ~ ", got=" ~ typeInfoToString(et) ~ ")",
						pos);
				}
			}
			rejectMutableStruct(vd, ti, sourcePath, errs);
			vd.valueIsShared = typeIsShared(ti);
			env.define(vd.name, ti, vd.isMutable);
			return;
		}
		if (auto sd = cast(StructDeclaration)s) {
			foreach (m; sd.methods) visitMethod(m, sd.name, false, sourcePath, errs, env, depth + 1);
			return;
		}
		if (auto fd = cast(FrameDeclaration)s) {
			foreach (m; fd.methods) visitMethod(m, fd.name, true, sourcePath, errs, env, depth + 1);
			return;
		}
		if (auto f = cast(FunctionDeclaration)s) {
			// function body: new scope with params
			auto child = env.child();
			foreach (p; f.parameters) {
				child.define(p.name, declaredNode(p.typeNode, p.type, p.customTypeName), true);
			}
			auto savedReturn = currentReturn;
			bool savedHas = hasCurrentReturn;
			string savedName = currentFunctionName;
			currentReturn = declaredNode(f.returnTypeNode, f.returnType, f.returnCustomTypeName);
			hasCurrentReturn = true;
			currentFunctionName = f.name;
			foreach (st; f.body) visitStmt(st, sourcePath, errs, child, depth + 1);
			currentReturn = savedReturn;
			hasCurrentReturn = savedHas;
			currentFunctionName = savedName;
			return;
		}
		if (auto m = cast(MethodDeclaration)s) {
			auto child = env.child();
			foreach (p; m.parameters) child.define(p.name, declaredNode(p.typeNode, p.type, p.customTypeName), true);
			auto savedReturn = currentReturn;
			bool savedHas = hasCurrentReturn;
			string savedName = currentFunctionName;
			currentReturn = declaredNode(m.returnTypeNode, m.returnType, null);
			hasCurrentReturn = true;
			currentFunctionName = m.name;
			foreach (st; m.body) visitStmt(st, sourcePath, errs, child, depth + 1);
			currentReturn = savedReturn;
			hasCurrentReturn = savedHas;
			currentFunctionName = savedName;
			return;
		}
		if (auto es = cast(ExpressionStatement)s) {
			visitExpr(es.expression, sourcePath, errs, env, depth + 1);
			return;
		}
		if (auto rs = cast(ReturnStatement)s) {
			if (rs.value !is null && hasCurrentReturn && !isPermissive(currentReturn) && currentReturn.base != DuendeType.VOID) {
				auto et = visitExpr(rs.value, sourcePath, errs, env, depth + 1, currentReturn);
				if (!typeCompatible(currentReturn, et)) {
					auto pos = normalizePos(rs.position, sourcePath);
					errs.addError(
						"Return type does not match '" ~ currentFunctionName ~ "' (need=" ~ typeInfoToString(currentReturn) ~ ", got=" ~ typeInfoToString(et) ~ ")",
						pos);
				}
			} else {
				visitExpr(rs.value, sourcePath, errs, env, depth + 1);
			}
			return;
		}
		if (auto ifs = cast(IfStatement)s) {
			visitExpr(ifs.condition, sourcePath, errs, env, depth + 1);
			auto thenScope = env.child();
			foreach (st; ifs.thenBranch) visitStmt(st, sourcePath, errs, thenScope, depth + 1);
			auto elseScope = env.child();
			foreach (st; ifs.elseBranch) visitStmt(st, sourcePath, errs, elseScope, depth + 1);
			return;
		}
		if (auto fs = cast(ForStatement)s) {
			// loop var is int
			auto child = env.child();
			child.define(fs.variable, typeInfo(DuendeType.INT), false);
			visitExpr(fs.start, sourcePath, errs, child, depth + 1);
			visitExpr(fs.end, sourcePath, errs, child, depth + 1);
			foreach (st; fs.body) visitStmt(st, sourcePath, errs, child, depth + 1);
			return;
		}
		if (auto fi = cast(ForInStatement)s) {
			auto child = env.child();
			auto it = visitExpr(fi.iterable, sourcePath, errs, child, depth + 1);
			TypeNode elem = TypeNode.unknownType();
			if (it.base == DuendeType.LIST && it.args.length) {
				elem = it.args[0];
				elem.inferred = true;
			} else if (it.base == DuendeType.DICT && it.args.length >= 2) {
				elem = it.args[1];
				elem.inferred = true;
			} else if (it.base == DuendeType.DICT) {
				elem = TypeNode.of(DuendeType.STRING);
			} else if (it.base == DuendeType.STRING) {
				elem = TypeNode.of(DuendeType.STRING);
			}
			child.define(fi.variable, elem, false);
			foreach (st; fi.body) visitStmt(st, sourcePath, errs, child, depth + 1);
			return;
		}
		if (auto ws = cast(WhileStatement)s) {
			visitExpr(ws.condition, sourcePath, errs, env, depth + 1);
			auto loopScope = env.child();
			foreach (st; ws.body) visitStmt(st, sourcePath, errs, loopScope, depth + 1);
			return;
		}
		if (auto ms = cast(MatchStatement)s) {
			Pattern[] pats; Expression[] guards;
			foreach (c; ms.cases) { pats ~= c.pattern; guards ~= c.guard; }
			visitMatch(ms.subject, pats, guards, false, normalizePos(ms.position, sourcePath), sourcePath, errs, env, depth,
				(size_t i, ref ScopeEnv armScope) {
					foreach (st; ms.cases[i].body) visitStmt(st, sourcePath, errs, armScope, depth + 1);
				});
			return;
		}
		// other statements ignored for now (Break/Continue validity handled elsewhere)
	}

	private TypeNode visitExpr(Expression e, string sourcePath, SemanticErrorCollector errs, ref ScopeEnv env, size_t depth, TypeNode expected = TypeNode.init) {
		if (e is null) return typeInfo(DuendeType.VOID);
		if (depth > maxDepth) return TypeNode.unknownType();
		if (auto lit = cast(LiteralExpression)e) {
			if (lit.intMinMagnitude) {
				auto pos = getExprPos(lit, sourcePath);
				errs.addError("Integer literal 9223372036854775808 is outside the signed 64-bit int range. The minimum value is written -9223372036854775808", pos);
				return TypeNode.unknownType();
			}
			return typeInfo(lit.type);
		}
		if (cast(BytesLiteralExpression)e !is null) return typeInfo(DuendeType.BYTES);
		if (cast(RegexLiteralExpression)e !is null) return typeInfo(DuendeType.REGEX);
		if (auto ll = cast(ListLiteralExpression)e) {
			if (expected.present && expected.base == DuendeType.BYTES) {
				foreach (el; ll.elements) visitExpr(el, sourcePath, errs, env, depth + 1, typeInfo(DuendeType.INT));
				return typeInfo(DuendeType.BYTES);
			}
			TypeNode elemExpected;
			bool checkElem = expected.present && expected.base == DuendeType.LIST && expected.args.length > 0;
			if (checkElem) elemExpected = expected.args[0];
			TypeNode seen;
			bool haveSeen = false;
			foreach (el; ll.elements) {
				auto et = visitExpr(el, sourcePath, errs, env, depth + 1, checkElem ? elemExpected : TypeNode.init);
				if (checkElem && !typeCompatible(elemExpected, et)) {
					errs.addError(
						"List element type does not match (need=" ~ typeInfoToString(elemExpected) ~ ", got=" ~ typeInfoToString(et) ~ ")",
						getExprPos(el, sourcePath));
				}
				if (!isPermissive(et)) {
					if (!haveSeen) {
						seen = et;
						haveSeen = true;
					} else if (!typeCompatible(seen, et) && !typeCompatible(et, seen)) {
						errs.addError("List elements have inconsistent types", getExprPos(el, sourcePath));
					}
				}
			}
			if (checkElem) return expected;
			if (haveSeen) return TypeNode.generic(DuendeType.LIST, [seen]);
			return typeInfo(DuendeType.LIST);
		}
		if (auto dl = cast(DictLiteralExpression)e) {
			TypeNode keyExpect;
			TypeNode valExpect;
			bool check = expected.present && expected.base == DuendeType.DICT;
			if (check) {
				if (expected.args.length >= 2) {
					keyExpect = expected.args[0];
					valExpect = expected.args[1];
				} else {
					keyExpect = TypeNode.of(DuendeType.STRING);
					valExpect = TypeNode.of(DuendeType.STRING);
				}
			}
			if (dl.keys.length == 0) {
				if (check) return expected.args.length >= 2 ? expected : stringDict();
				errs.addError("Empty dictionary needs a dict<K, V> type", getExprPos(dl, sourcePath));
				return TypeNode.unknownType();
			}
			TypeNode seenKey;
			TypeNode seenVal;
			bool haveKey = false;
			bool haveVal = false;
			bool concrete = true;
			foreach (i, k; dl.keys) {
				auto kt = visitExpr(k, sourcePath, errs, env, depth + 1, check ? keyExpect : TypeNode.init);
				auto vt = visitExpr(dl.values[i], sourcePath, errs, env, depth + 1, check ? valExpect : TypeNode.init);
				if (check && !elementCompatible(keyExpect, kt)) {
					errs.addError(
						"Dictionary key type does not match (need=" ~ typeInfoToString(keyExpect) ~ ", got=" ~ typeInfoToString(kt) ~ ")",
						getExprPos(k, sourcePath));
				}
				if (check && !elementCompatible(valExpect, vt)) {
					errs.addError(
						"Dictionary value type does not match (need=" ~ typeInfoToString(valExpect) ~ ", got=" ~ typeInfoToString(vt) ~ ")",
						getExprPos(dl.values[i], sourcePath));
				}
				if (isPermissive(kt) || isPermissive(vt)) concrete = false;
				if (!isPermissive(kt)) {
					if (!haveKey) {
						seenKey = kt;
						haveKey = true;
					} else if (!elementCompatible(seenKey, kt) && !elementCompatible(kt, seenKey)) {
						errs.addError("Dictionary keys have inconsistent types", getExprPos(k, sourcePath));
					}
				}
				if (!isPermissive(vt)) {
					if (!haveVal) {
						seenVal = vt;
						haveVal = true;
					} else if (!elementCompatible(seenVal, vt) && !elementCompatible(vt, seenVal)) {
						errs.addError("Dictionary values have inconsistent types", getExprPos(dl.values[i], sourcePath));
					}
				}
			}
			if (check) return expected.args.length >= 2 ? expected : stringDict();
			if (concrete && haveKey && haveVal) return TypeNode.generic(DuendeType.DICT, [seenKey, seenVal]);
			return TypeNode.unknownType();
		}
		if (auto ve = cast(VariableExpression)e) {
			// Treat known enum names as type-like values (for qualified access Color.Red)
			if (ve.name in enums) return typeInfo(DuendeType.CUSTOM, ve.name);
			Binding b;
			if (!env.lookup(ve.name, b)) {
				// Allow bare enum member usage (e.g., ACTIVE) by resolving to its enum type
				auto en = resolveEnumForValue(ve.name);
				if (en !is null) return typeInfo(DuendeType.CUSTOM, en);
				// Consider TitleCase identifiers as type-like (providers or user-defined)
				if (ve.name.length && ve.name[0] >= 'A' && ve.name[0] <= 'Z') {
					return typeInfo(DuendeType.CUSTOM, ve.name);
				}
				auto pos = normalizePos(ve.position, sourcePath);
				errs.addError("Use of undefined variable '" ~ ve.name ~ "'", pos);
				return TypeNode.unknownType();
			}
			return b.type;
		}
		if (auto ae = cast(AssignmentExpression)e) {
			Binding b;
			bool ok = env.lookup(ae.variable, b);
			if (!ok) {
				auto pos = normalizePos(ae.position, sourcePath);
				errs.addError("Assignment to undefined variable '" ~ ae.variable ~ "'", pos);
				// Still analyze RHS to continue
				visitExpr(ae.value, sourcePath, errs, env, depth + 1);
				return TypeNode.unknownType();
			}
			TypeNode t = b.type;
			if (!b.mutable) {
				auto pos = normalizePos(ae.position, sourcePath);
				errs.addError("Cannot assign to let binding '" ~ ae.variable ~ "'", pos);
			}
			auto rhs = visitExpr(ae.value, sourcePath, errs, env, depth + 1, t);
			bool specialOk = false;
			if (t.base == DuendeType.BYTES && cast(ListLiteralExpression)ae.value !is null) {
				specialOk = true;
			}
			if (!typeCompatible(t, rhs) && !specialOk) {
				auto pos = normalizePos(ae.position, sourcePath);
				errs.addError(
					"Assigned expression type does not match variable '" ~ ae.variable ~ "' (need=" ~ typeInfoToString(t) ~ ", got=" ~ typeInfoToString(rhs) ~ ")",
					pos);
			}
			return t;
		}
		if (auto ce = cast(CallExpression)e) {
			checkFunctionCall(ce, sourcePath, errs, env, depth + 1);
			// Return type if known
			if (ce.name in functions) {
				auto f = functions[ce.name];
				return declaredNode(f.returnTypeNode, f.returnType, f.returnCustomTypeName);
			}
			return TypeNode.unknownType();
		}
		if (auto me = cast(MethodCallExpression)e) {
			// Not type-checking methods for now; just traverse
			// But suppress undefined errors for provider type qualifiers (e.g., Terminal.method())
			bool skipObject = false;
			if (auto ov = cast(VariableExpression)me.object) {
				if (ov.name.length && ov.name[0] >= 'A' && ov.name[0] <= 'Z') {
					skipObject = true; // treat as external type qualifier
				}
			}
			TypeNode ot;
			if (!skipObject) {
				ot = visitExpr(me.object, sourcePath, errs, env, depth + 1);
			}
			bool checkedArg = false;
			if (me.method == "add" && ot.base == DuendeType.LIST && ot.args.length && me.arguments.length >= 1) {
				auto at = visitExpr(me.arguments[0], sourcePath, errs, env, depth + 1, ot.args[0]);
				if (!elementCompatible(ot.args[0], at)) {
					errs.addError(
						"List element type does not match (need=" ~ typeInfoToString(ot.args[0]) ~ ", got=" ~ typeInfoToString(at) ~ ")",
						getExprPos(me.arguments[0], sourcePath));
				}
				checkedArg = true;
			} else if ((me.method == "get" || me.method == "has") && ot.base == DuendeType.DICT && me.arguments.length >= 1) {
				TypeNode keyNeed = ot.args.length ? ot.args[0] : typeInfo(DuendeType.STRING);
				auto kt = visitExpr(me.arguments[0], sourcePath, errs, env, depth + 1, keyNeed);
				if (!elementCompatible(keyNeed, kt)) {
					errs.addError(
						"Dictionary key type does not match (need=" ~ typeInfoToString(keyNeed) ~ ", got=" ~ typeInfoToString(kt) ~ ")",
						getExprPos(me.arguments[0], sourcePath));
				}
				checkedArg = true;
			}
			foreach (i, a; me.arguments) {
				if (checkedArg && i == 0) continue;
				visitExpr(a, sourcePath, errs, env, depth + 1);
			}
			rejectNamedArguments(me.argumentNames, me.arguments, "method '" ~ me.method ~ "'", sourcePath, errs);
			if (ot.base == DuendeType.CUSTOM && ot.name.length) {
				if (auto agg = ot.name in aggregates) {
					if (agg.isFrame && (me.method in agg.mutatingMethods) && receiverIsLet(me.object, env)) {
						string rname = receiverName(me.object);
						errs.addError(
							"Cannot call mutating method '" ~ me.method ~ "' on let binding '" ~ rname ~ "'",
							getExprPos(me, sourcePath));
					}
				}
			}
			if (me.method == "get" && ot.base == DuendeType.DICT) {
				TypeNode valT = ot.args.length >= 2 ? ot.args[1] : typeInfo(DuendeType.STRING);
				return TypeNode.generic(DuendeType.MAYBE, [valT]);
			}
			if (me.method == "has" && ot.base == DuendeType.DICT) return typeInfo(DuendeType.BOOL);
			if (me.method == "slice" && ot.base == DuendeType.LIST) return ot;
			return TypeNode.unknownType();
		}
		if (auto be = cast(BinaryExpression)e) {
			auto lt = visitExpr(be.left, sourcePath, errs, env, depth + 1);
			auto rt = visitExpr(be.right, sourcePath, errs, env, depth + 1);
			if (isComparisonOp(be.operator) || isLogicalOp(be.operator)) return typeInfo(DuendeType.BOOL);
			if (be.operator == "+" && lt.base == DuendeType.STRING && rt.base == DuendeType.STRING) return typeInfo(DuendeType.STRING);
			bool leftNum = lt.base == DuendeType.INT || lt.base == DuendeType.FLOAT;
			bool rightNum = rt.base == DuendeType.INT || rt.base == DuendeType.FLOAT;
			if (leftNum && rightNum) {
				if (lt.base == DuendeType.FLOAT || rt.base == DuendeType.FLOAT) return typeInfo(DuendeType.FLOAT);
				return typeInfo(DuendeType.INT);
			}
			return TypeNode.unknownType();
		}
		if (auto ue = cast(UnaryExpression)e) {
			if (ue.operator == "-" ) {
				if (auto lit = cast(LiteralExpression)ue.operand) {
					if (lit.intMinMagnitude) return typeInfo(DuendeType.INT);
				}
			}
			if (ue.operator == "!") {
				visitExpr(ue.operand, sourcePath, errs, env, depth + 1);
				return typeInfo(DuendeType.BOOL);
			}
			return visitExpr(ue.operand, sourcePath, errs, env, depth + 1);
		}
		if (auto ie = cast(IndexExpression)e) {
			auto ot = visitExpr(ie.object, sourcePath, errs, env, depth + 1);
			TypeNode indexExpect = typeInfo(DuendeType.INT);
			if (ot.base == DuendeType.DICT)
				indexExpect = ot.args.length ? ot.args[0] : typeInfo(DuendeType.STRING);
			auto it = visitExpr(ie.index, sourcePath, errs, env, depth + 1, indexExpect);
			if (ot.base == DuendeType.LIST || ot.base == DuendeType.STRING) {
				if (!elementCompatible(typeInfo(DuendeType.INT), it))
					errs.addError("Index must be int", getExprPos(ie.index, sourcePath));
			} else if (ot.base == DuendeType.DICT) {
				if (!elementCompatible(indexExpect, it)) {
					errs.addError(
						"Dictionary key type does not match (need=" ~ typeInfoToString(indexExpect) ~ ", got=" ~ typeInfoToString(it) ~ ")",
						getExprPos(ie.index, sourcePath));
				}
			}
			if (ot.base == DuendeType.LIST && ot.args.length) return ot.args[0];
			if (ot.base == DuendeType.DICT && ot.args.length >= 2) return ot.args[1];
			if (ot.base == DuendeType.DICT) return typeInfo(DuendeType.STRING);
			if (ot.base == DuendeType.STRING) return typeInfo(DuendeType.STRING);
			return TypeNode.unknownType();
		}
		if (auto ia = cast(IndexAssignmentExpression)e) {
			auto ot = visitExpr(ia.object, sourcePath, errs, env, depth + 1);
			TypeNode keyExpect = typeInfo(DuendeType.INT);
			TypeNode valExpect;
			if (ot.base == DuendeType.DICT) {
				keyExpect = ot.args.length ? ot.args[0] : typeInfo(DuendeType.STRING);
				valExpect = ot.args.length >= 2 ? ot.args[1] : typeInfo(DuendeType.STRING);
			} else if (ot.base == DuendeType.LIST && ot.args.length) {
				valExpect = ot.args[0];
			} else if (ot.base == DuendeType.STRING) {
				errs.addError("Cannot assign through a string index", getExprPos(ia, sourcePath));
			}
			auto kt = visitExpr(ia.index, sourcePath, errs, env, depth + 1, keyExpect);
			if ((ot.base == DuendeType.LIST || ot.base == DuendeType.DICT) && !elementCompatible(keyExpect, kt)) {
				errs.addError(
					"Index type does not match (need=" ~ typeInfoToString(keyExpect) ~ ", got=" ~ typeInfoToString(kt) ~ ")",
					getExprPos(ia.index, sourcePath));
			}
			auto vt = visitExpr(ia.value, sourcePath, errs, env, depth + 1, valExpect);
			if (valExpect.present && !elementCompatible(valExpect, vt)) {
				errs.addError(
					"Assigned element type does not match (need=" ~ typeInfoToString(valExpect) ~ ", got=" ~ typeInfoToString(vt) ~ ")",
					getExprPos(ia.value, sourcePath));
			}
			if (valExpect.present) return valExpect;
			return TypeNode.unknownType();
		}
		if (auto pe = cast(PropertyExpression)e) {
			// Special-case: Enum access like Color.Red
			if (auto ve = cast(VariableExpression)pe.object) {
				if (auto valsPtr = ve.name in enums) {
					auto vals = *valsPtr;
					// Validate enum member name
					if (!vals.canFind(pe.property)) {
						auto pos = normalizePos(pe.position, sourcePath);
						errs.addError("Unknown enum value '" ~ pe.property ~ "' for enum '" ~ ve.name ~ "'", pos);
					}
					// Expression type is the enum type itself
					return typeInfo(DuendeType.CUSTOM, ve.name);
				}
				// Provider-backed type qualifier like Terminal.stdout
				if (ve.name.length && ve.name[0] >= 'A' && ve.name[0] <= 'Z') {
					// Skip visiting object to avoid undefined-variable error; allow property chain
					return typeInfo(DuendeType.AUTO);
				}
			}
			// Default behavior
			auto ot = visitExpr(pe.object, sourcePath, errs, env, depth + 1);
			if (ot.base == DuendeType.CUSTOM && ot.name.length) {
				if (auto agg = ot.name in aggregates) {
					if (auto ft = pe.property in agg.fields) return ft.type;
				}
			}
			if (ot.base == DuendeType.LIST) {
				if (pe.property == "length") return typeInfo(DuendeType.INT);
				if (pe.property == "empty") return typeInfo(DuendeType.BOOL);
				if ((pe.property == "first" || pe.property == "last") && ot.args.length)
					return TypeNode.generic(DuendeType.MAYBE, [ot.args[0]]);
			}
			if (ot.base == DuendeType.DICT) {
				if (pe.property == "length") return typeInfo(DuendeType.INT);
				if (pe.property == "empty") return typeInfo(DuendeType.BOOL);
				TypeNode keyT = ot.args.length ? ot.args[0] : typeInfo(DuendeType.STRING);
				TypeNode valT = ot.args.length >= 2 ? ot.args[1] : typeInfo(DuendeType.STRING);
				if (pe.property == "keys") return TypeNode.generic(DuendeType.LIST, [keyT]);
				if (pe.property == "values") return TypeNode.generic(DuendeType.LIST, [valT]);
			}
			return TypeNode.unknownType();
		}
		if (auto pae = cast(PropertyAssignmentExpression)e) {
			auto ot = visitExpr(pae.object, sourcePath, errs, env, depth + 1);
			checkPropertyWrite(pae, ot, sourcePath, errs, env);
			visitExpr(pae.value, sourcePath, errs, env, depth + 1);
			return typeInfo(DuendeType.AUTO);
		}
		if (auto se = cast(StringInterpolationExpression)e) {
			foreach (ex; se.expressions) visitExpr(ex, sourcePath, errs, env, depth + 1);
			return typeInfo(DuendeType.STRING);
		}
		if (auto me2 = cast(MatchExpression)e) {
			Pattern[] pats; Expression[] guards;
			foreach (c; me2.cases) { pats ~= c.pattern; guards ~= c.guard; }
			visitMatch(me2.subject, pats, guards, true, normalizePos(me2.position, sourcePath), sourcePath, errs, env, depth,
				(size_t i, ref ScopeEnv armScope) {
					auto c = me2.cases[i];
					auto at = visitExpr(c.value, sourcePath, errs, armScope, depth + 1, expected);
					if (expected.present && !isPermissive(expected) && expected.base != DuendeType.VOID && !typeCompatible(expected, at)) {
						errs.addError(
							"Match arm type does not match expected type (need=" ~ typeInfoToString(expected) ~ ", got=" ~ typeInfoToString(at) ~ ")",
							getExprPos(c.value, sourcePath));
					}
				});
			if (expected.present && !isPermissive(expected)) return expected;
			return TypeNode.unknownType();
		}
		if (auto rc = cast(ResultConstructorExpression)e) {
			TypeNode innerExp;
			if (expected.present && expected.base == DuendeType.RESULT && expected.args.length)
				innerExp = expected.args[0];
			auto vt = visitExpr(rc.value, sourcePath, errs, env, depth + 1, innerExp);
			if (expected.present && expected.base == DuendeType.RESULT) return expected;
			if (!isPermissive(vt)) return TypeNode.generic(DuendeType.RESULT, [vt]);
			return typeInfo(DuendeType.RESULT);
		}
		if (auto mc = cast(MaybeConstructorExpression)e) {
			TypeNode innerExp;
			if (expected.present && expected.base == DuendeType.MAYBE && expected.args.length)
				innerExp = expected.args[0];
			if (mc.value !is null) visitExpr(mc.value, sourcePath, errs, env, depth + 1, innerExp);
			if (expected.present && expected.base == DuendeType.MAYBE) return expected;
			return typeInfo(DuendeType.MAYBE);
		}
		if (auto ue2 = cast(UnwrapExpression)e) {
			visitExpr(ue2.result, sourcePath, errs, env, depth + 1);
			visitExpr(ue2.defaultValue, sourcePath, errs, env, depth + 1);
			return typeInfo(DuendeType.AUTO);
		}
		if (auto te = cast(TryBlockExpression)e) {
			foreach (st; te.statements) visitStmt(st, sourcePath, errs, env, depth + 1);
			return typeInfo(DuendeType.AUTO);
		}
		if (auto cc = cast(ConstructorCallExpression)e) {
			foreach (a; cc.arguments) visitExpr(a, sourcePath, errs, env, depth + 1);
			rejectNamedArguments(cc.argumentNames, cc.arguments, "constructor '" ~ cc.typeName ~ "'", sourcePath, errs);
			return typeInfo(DuendeType.CUSTOM, cc.typeName);
		}
		if (auto ce2 = cast(CastExpression)e) {
			visitExpr(ce2.value, sourcePath, errs, env, depth + 1);
			return typeInfo(ce2.targetType);
		}
		if (auto tl = cast(TypeLiteralExpression)e) {
			return typeInfo(tl.type, tl.customTypeName);
		}
		if (auto le = cast(LambdaExpression)e) {
			auto child = env.child();
			foreach (p; le.parameters) child.define(p, typeInfo(DuendeType.AUTO), true);
			visitExpr(le.body, sourcePath, errs, child, depth + 1);
			return typeInfo(DuendeType.AUTO);
		}
		// default unknown
		return typeInfo(DuendeType.AUTO);
	}

	// Best-effort to recover a SourcePosition for any Expression
	private SourcePosition getExprPos(Expression e, string file) {
		if (e is null) return SourcePosition(1,1,file);
		// Try classes that mix in PositionMixin
		if (auto n = cast(LiteralExpression)e) return normalizePos(n.position, file);
		if (auto n = cast(VariableExpression)e) return normalizePos(n.position, file);
		if (auto n = cast(CallExpression)e) return normalizePos(n.position, file);
		if (auto n = cast(StringInterpolationExpression)e) return normalizePos(n.position, file);
		if (auto n = cast(IndexExpression)e) return normalizePos(n.position, file);
		if (auto n = cast(PropertyExpression)e) return normalizePos(n.position, file);
		if (auto n = cast(PropertyAssignmentExpression)e) return normalizePos(n.position, file);
		if (auto n = cast(IndexAssignmentExpression)e) return normalizePos(n.position, file);
		if (auto n = cast(BytesLiteralExpression)e) return normalizePos(n.position, file);
		if (auto n = cast(ListLiteralExpression)e) return normalizePos(n.position, file);
		if (auto n = cast(DictLiteralExpression)e) return normalizePos(n.position, file);
		if (auto n = cast(MethodCallExpression)e) return normalizePos(n.position, file);
		if (auto n = cast(RegexLiteralExpression)e) return normalizePos(n.position, file);
		if (auto n = cast(BinaryExpression)e) return normalizePos(n.position, file);
		if (auto n = cast(UnaryExpression)e) return normalizePos(n.position, file);
		if (auto n = cast(AssignmentExpression)e) return normalizePos(n.position, file);
		if (auto n = cast(ConstructorCallExpression)e) return normalizePos(n.position, file);
		if (auto n = cast(ResultConstructorExpression)e) return normalizePos(n.position, file);
		if (auto n = cast(MaybeConstructorExpression)e) return normalizePos(n.position, file);
		if (auto n = cast(UnwrapExpression)e) return normalizePos(n.position, file);
		if (auto n = cast(MatchExpression)e) return normalizePos(n.position, file);
		// Fallback
		return SourcePosition(1,1,file);
	}

	private void visitMethod(MethodDeclaration m, string typeName, bool isFrame, string sourcePath, SemanticErrorCollector errs, ref ScopeEnv env, size_t depth) {
		auto child = env.child();
		child.define("this", typeInfo(DuendeType.CUSTOM, typeName), isFrame);
		foreach (p; m.parameters) child.define(p.name, declaredNode(p.typeNode, p.type, p.customTypeName), true);
		auto savedReturn = currentReturn;
		bool savedHas = hasCurrentReturn;
		string savedName = currentFunctionName;
		currentReturn = declaredNode(m.returnTypeNode, m.returnType, null);
		hasCurrentReturn = true;
		currentFunctionName = m.name;
		foreach (st; m.body) visitStmt(st, sourcePath, errs, child, depth + 1);
		currentReturn = savedReturn;
		hasCurrentReturn = savedHas;
		currentFunctionName = savedName;
	}

	private void applyInferred(VariableDeclaration vd, ref TypeNode ti, TypeNode et) {
		auto resolved = resolveAuto(ti, et);
		if (!resolved.inferred) return;
		ti = resolved;
		vd.typeNode = resolved;
		vd.type = resolved.base;
		if (resolved.base == DuendeType.CUSTOM && resolved.name.length) vd.customTypeName = resolved.name;
		vd.innerType = resolved.legacyInner();
		vd.innerCustomTypeName = resolved.legacyInnerCustom();
	}

	private bool typeIsShared(TypeNode t) {
		if (t.base == DuendeType.LIST || t.base == DuendeType.DICT || t.base == DuendeType.BYTES) return true;
		if (t.base == DuendeType.CUSTOM && t.name.length) {
			if (auto agg = t.name in aggregates) return agg.isFrame;
		}
		if (t.base == DuendeType.FRAME) return true;
		return false;
	}

	private void rejectMutableStruct(VariableDeclaration vd, TypeNode ti, string sourcePath, SemanticErrorCollector errs) {
		if (!vd.isMutable) return;
		if (ti.base != DuendeType.CUSTOM || !ti.name.length) return;
		if (auto agg = ti.name in aggregates) {
			if (!agg.isFrame) {
				auto pos = normalizePos(vd.position, sourcePath);
				errs.addError("Struct '" ~ ti.name ~ "' cannot be declared with var; use let", pos);
			}
		}
	}

	private bool receiverIsLet(Expression obj, ref ScopeEnv env) {
		if (auto ve = cast(VariableExpression)obj) {
			Binding b;
			if (env.lookup(ve.name, b)) return !b.mutable;
		}
		return false;
	}

	private string receiverName(Expression obj) {
		if (auto ve = cast(VariableExpression)obj) return ve.name;
		return "value";
	}

	private void checkPropertyWrite(PropertyAssignmentExpression pae, TypeNode ot, string sourcePath, SemanticErrorCollector errs, ref ScopeEnv env) {
		if (ot.base != DuendeType.CUSTOM || !ot.name.length) return;
		auto agg = ot.name in aggregates;
		if (agg is null) return;
		if (!agg.isFrame) {
			errs.addError("Cannot assign to field '" ~ pae.property ~ "' of struct '" ~ ot.name ~ "'", getExprPos(pae, sourcePath));
			return;
		}
		if (receiverIsLet(pae.object, env)) {
			errs.addError("Cannot mutate let binding '" ~ receiverName(pae.object) ~ "'", getExprPos(pae, sourcePath));
			return;
		}
		if (auto field = pae.property in agg.fields) {
			if (!field.mutable) {
				errs.addError("Cannot assign to let field '" ~ pae.property ~ "' of frame '" ~ ot.name ~ "'", getExprPos(pae, sourcePath));
			}
		}
	}

	private bool methodAssignsThis(MethodDeclaration m) {
		foreach (st; m.body) if (stmtWritesThis(st, null)) return true;
		return false;
	}

	private bool methodCallsMutatingThis(MethodDeclaration m, bool[string] mut) {
		foreach (st; m.body) if (stmtWritesThis(st, mut)) return true;
		return false;
	}

	// mut is null when looking for direct field writes. Otherwise also follow this.method calls.
	private bool stmtWritesThis(Statement s, bool[string] mut) {
		if (s is null) return false;
		if (auto es = cast(ExpressionStatement)s) return exprWritesThis(es.expression, mut);
		if (auto rs = cast(ReturnStatement)s) return exprWritesThis(rs.value, mut);
		if (auto ds = cast(DeferStatement)s) return exprWritesThis(ds.call, mut);
		if (auto ifs = cast(IfStatement)s) {
			if (exprWritesThis(ifs.condition, mut)) return true;
			foreach (st; ifs.thenBranch) if (stmtWritesThis(st, mut)) return true;
			foreach (el; ifs.elifClauses) {
				if (exprWritesThis(el.condition, mut)) return true;
				foreach (st; el.body) if (stmtWritesThis(st, mut)) return true;
			}
			foreach (st; ifs.elseBranch) if (stmtWritesThis(st, mut)) return true;
			return false;
		}
		if (auto fs = cast(ForStatement)s) {
			if (exprWritesThis(fs.start, mut) || exprWritesThis(fs.end, mut)) return true;
			foreach (st; fs.body) if (stmtWritesThis(st, mut)) return true;
			return false;
		}
		if (auto fi = cast(ForInStatement)s) {
			if (exprWritesThis(fi.iterable, mut)) return true;
			foreach (st; fi.body) if (stmtWritesThis(st, mut)) return true;
			return false;
		}
		if (auto ws = cast(WhileStatement)s) {
			if (exprWritesThis(ws.condition, mut)) return true;
			foreach (st; ws.body) if (stmtWritesThis(st, mut)) return true;
			return false;
		}
		if (auto ms = cast(MatchStatement)s) {
			if (exprWritesThis(ms.subject, mut)) return true;
			foreach (c; ms.cases) foreach (st; c.body) if (stmtWritesThis(st, mut)) return true;
			return false;
		}
		if (auto f = cast(FunctionDeclaration)s) {
			foreach (st; f.body) if (stmtWritesThis(st, mut)) return true;
		}
		return false;
	}

	private bool exprWritesThis(Expression e, bool[string] mut) {
		if (e is null) return false;
		if (auto pa = cast(PropertyAssignmentExpression)e) {
			if (auto ve = cast(VariableExpression)pa.object) {
				if (ve.name == "this") return true;
			}
			return exprWritesThis(pa.object, mut) || exprWritesThis(pa.value, mut);
		}
		if (auto ia = cast(IndexAssignmentExpression)e) {
			return exprWritesThis(ia.object, mut) || exprWritesThis(ia.index, mut) || exprWritesThis(ia.value, mut);
		}
		if (auto mc = cast(MethodCallExpression)e) {
			if (mut !is null) {
				if (auto ve = cast(VariableExpression)mc.object) {
					if (ve.name == "this" && (mc.method in mut)) return true;
				}
			}
			if (exprWritesThis(mc.object, mut)) return true;
			foreach (a; mc.arguments) if (exprWritesThis(a, mut)) return true;
			return false;
		}
		if (auto ae = cast(AssignmentExpression)e) return exprWritesThis(ae.value, mut);
		if (auto ce = cast(CallExpression)e) {
			foreach (a; ce.arguments) if (exprWritesThis(a, mut)) return true;
			return false;
		}
		if (auto be = cast(BinaryExpression)e) return exprWritesThis(be.left, mut) || exprWritesThis(be.right, mut);
		if (auto ue = cast(UnaryExpression)e) return exprWritesThis(ue.operand, mut);
		if (auto ie = cast(IndexExpression)e) return exprWritesThis(ie.object, mut) || exprWritesThis(ie.index, mut);
		if (auto pe = cast(PropertyExpression)e) return exprWritesThis(pe.object, mut);
		if (auto se = cast(StringInterpolationExpression)e) {
			foreach (ex; se.expressions) if (exprWritesThis(ex, mut)) return true;
			return false;
		}
		if (auto cc = cast(ConstructorCallExpression)e) {
			foreach (a; cc.arguments) if (exprWritesThis(a, mut)) return true;
			return false;
		}
		return false;
	}

	private void checkConformance(string kind, string typeName, Annotation[] annotations, MethodDeclaration[] methods,
			string sourcePath, SemanticErrorCollector errs) {
		foreach (ann; annotations) {
			if (ann.name != "Implements") continue;
			foreach (protoName; ann.arguments) {
				auto pd = protoName in protocols;
				if (pd is null) continue; // declared in another module; the D compiler still checks it
				foreach (sig; (*pd).methods) {
					if (sig.hasDefaultImplementation) continue;
					bool found = false;
					foreach (m; methods) {
						if (m.name == sig.name && m.parameters.length == sig.parameters.length) { found = true; break; }
					}
					if (!found) {
						errs.addError(kind ~ " '" ~ typeName ~ "' implements protocol '" ~ protoName ~ "' but does not define method '" ~ sig.name ~ "' with " ~ sig.parameters.length.to!string ~ " parameter(s)",
							SourcePosition(1, 1, sourcePath));
					}
				}
			}
		}
	}

	/**
	 * Shared analysis of match statements and expressions.
	 *
	 * Each arm gets its own scope: Ok(x)/Error(e) bindings are typed from the subject, the guard
	 * sees those bindings and must be a bool, then the arm body/value is visited by `visitArm`.
	 *
	 * Coverage rules (guarded arms never count toward coverage):
	 *   - enum subjects must name every value, or have a `_` arm;
	 *   - Result subjects must have both Ok(...) and Error(...) arms, or a `_` arm;
	 *   - a match expression on any other type must have a `_` arm (bool may instead cover true and false);
	 *   - a match statement on any other type may leave values unmatched, which then do nothing.
	 * An arm that can never be selected, because earlier unguarded arms already match everything
	 * it could match, is an error.
	 */
	private void visitMatch(Expression subject, Pattern[] pats, Expression[] guards, bool isExpression, SourcePosition matchPos,
			string sourcePath, SemanticErrorCollector errs, ref ScopeEnv env, size_t depth,
			scope void delegate(size_t, ref ScopeEnv) visitArm) {
		auto st = visitExpr(subject, sourcePath, errs, env, depth + 1);

		enum Domain { open, enumeration, result, boolean }
		Domain domain = Domain.open;
		string enumName;
		if (st.base == DuendeType.CUSTOM && st.name.length && (st.name in enums)) {
			domain = Domain.enumeration; enumName = st.name;
		} else if (st.base == DuendeType.RESULT) {
			domain = Domain.result;
		} else if (st.base == DuendeType.BOOL) {
			domain = Domain.boolean;
		} else if (isPermissive(st)) {
			// Subject type unknown here: infer the domain from the patterns
			foreach (p; pats) {
				if (cast(ResultOkPattern)p !is null || cast(ResultErrorPattern)p !is null) { domain = Domain.result; break; }
			}
			if (domain == Domain.open) {
				foreach (p; pats) {
					auto ep = cast(ExpressionPattern)p;
					if (ep is null) continue;
					auto ve = cast(VariableExpression)ep.expr;
					string en = ve !is null ? resolveEnumForValue(ve.name) : enumOfQualified(ep.expr);
					if (en is null) { enumName = null; break; }
					if (enumName !is null && enumName != en) { enumName = null; break; }
					enumName = en;
				}
				if (enumName !is null) domain = Domain.enumeration;
			}
		}
		TypeNode okType = (st.base == DuendeType.RESULT && st.args.length) ? st.args[0] : typeInfo(DuendeType.AUTO);

		bool coveredAll = false;
		bool[string] covered; // unguarded keys seen: enum values, "Ok"/"Error", "true"/"false"
		foreach (i, p; pats) {
			auto patPos = patternPos(p, matchPos, sourcePath);
			auto armScope = env.child();
			string key;
			if (auto okp = cast(ResultOkPattern)p) {
				if (okp.bindName.length) armScope.define(okp.bindName, okType, false);
				key = "Ok";
			} else if (auto errp = cast(ResultErrorPattern)p) {
				if (errp.bindName.length) armScope.define(errp.bindName, typeInfo(DuendeType.STRING), false);
				key = "Error";
			} else if (auto ep = cast(ExpressionPattern)p) {
				visitExpr(ep.expr, sourcePath, errs, env, depth + 1);
				if (domain == Domain.enumeration) key = enumValueOf(ep.expr, enumName);
				else if (domain == Domain.boolean) {
					if (auto lit = cast(LiteralExpression)ep.expr) {
						if (lit.type == DuendeType.BOOL && lit.value.convertsTo!bool) key = lit.value.get!bool ? "true" : "false";
					}
				}
			}
			bool unguarded = guards[i] is null;
			bool isWildcard = cast(WildcardPattern)p !is null;

			if (coveredAll || (key.length && (key in covered))) {
				errs.addError("Unreachable match arm: earlier arms without guards already match every value it could match", patPos);
			}
			if (guards[i] !is null) {
				auto gt = visitExpr(guards[i], sourcePath, errs, armScope, depth + 1, typeInfo(DuendeType.BOOL));
				if (!isPermissive(gt) && gt.base != DuendeType.BOOL) {
					errs.addError("Match guard must be a bool (got=" ~ typeInfoToString(gt) ~ ")", getExprPos(guards[i], sourcePath));
				}
			}
			visitArm(i, armScope);

			if (!unguarded) continue;
			if (isWildcard) coveredAll = true;
			if (key.length) covered[key] = true;
			final switch (domain) {
				case Domain.enumeration:
					bool all = true;
					foreach (v; enums[enumName]) if (!(v in covered)) { all = false; break; }
					if (all) coveredAll = true;
					break;
				case Domain.result:
					if (("Ok" in covered) && ("Error" in covered)) coveredAll = true;
					break;
				case Domain.boolean:
					if (("true" in covered) && ("false" in covered)) coveredAll = true;
					break;
				case Domain.open:
					break;
			}
		}

		if (coveredAll) return;
		string what = isExpression ? "Match expression" : "Match";
		final switch (domain) {
			case Domain.enumeration:
				string[] missing;
				foreach (v; enums[enumName]) if (!(v in covered)) missing ~= v;
				errs.addError(what ~ " on enum '" ~ enumName ~ "' does not cover " ~ missing.join(", ") ~ "; add arms without guards for them or a final '_' arm", matchPos);
				break;
			case Domain.result:
				string[] missingR;
				if (!("Ok" in covered)) missingR ~= "Ok(...)";
				if (!("Error" in covered)) missingR ~= "Error(...)";
				errs.addError(what ~ " on a Result does not cover " ~ missingR.join(" and ") ~ "; add arms without guards for them or a final '_' arm", matchPos);
				break;
			case Domain.boolean:
			case Domain.open:
				if (isExpression) {
					errs.addError("Match expression does not cover every value; add a final '_' arm (arms with guards do not count)", matchPos);
				}
				break;
		}
	}

	// Enum value named by a pattern expression (ACTIVE or Status.ACTIVE), or null
	private string enumValueOf(Expression e, string enumName) {
		if (auto ve = cast(VariableExpression)e) {
			if (enums[enumName].canFind(ve.name)) return ve.name;
		}
		if (auto pe = cast(PropertyExpression)e) {
			if (auto ve = cast(VariableExpression)pe.object) {
				if (ve.name == enumName && enums[enumName].canFind(pe.property)) return pe.property;
			}
		}
		return null;
	}

	// Enum named by a qualified pattern like Status.ACTIVE, or null
	private string enumOfQualified(Expression e) {
		if (auto pe = cast(PropertyExpression)e) {
			if (auto ve = cast(VariableExpression)pe.object) {
				if (auto vals = ve.name in enums) {
					if ((*vals).canFind(pe.property)) return ve.name;
				}
			}
		}
		return null;
	}

	private SourcePosition patternPos(Pattern p, SourcePosition fallback, string file) {
		SourcePosition pos;
		if (auto w = cast(WildcardPattern)p) pos = w.position;
		else if (auto ep = cast(ExpressionPattern)p) pos = ep.position;
		else if (auto okp = cast(ResultOkPattern)p) pos = okp.position;
		else if (auto errp = cast(ResultErrorPattern)p) pos = errp.position;
		if (pos.line == 0) return fallback;
		return normalizePos(pos, file);
	}

	// Methods and constructors are not bound by name yet; reject names instead of silently passing them positionally
	private void rejectNamedArguments(const string[] names, Expression[] args, string what, string sourcePath, SemanticErrorCollector errs) {
		foreach (i, an; names) {
			if (an.length) {
				errs.addError("Named argument '" ~ an ~ "' is not supported in call to " ~ what ~ ": named arguments are only supported for functions", getExprPos(args[i], sourcePath));
			}
		}
	}

	private void checkFunctionCall(CallExpression ce, string sourcePath, SemanticErrorCollector errs, ref ScopeEnv env, size_t depth) {
		// Only check functions declared in this module; ignore providers/builtins
		if (!(ce.name in functions)) {
			// Named arguments are bound against the callee's declared parameters, which are only known
			// for functions declared in this module; elsewhere they would be silently passed positionally
			foreach (i, an; ce.argumentNames) {
				if (an.length) {
					errs.addError("Named argument '" ~ an ~ "' is not supported in call to '" ~ ce.name ~ "': named arguments require a function declared in this module", getExprPos(ce.arguments[i], sourcePath));
				}
			}
			// The callee is unknown here (builtin or provider), but direct calls in its arguments,
			// such as print(f(x: 1)), still need their arguments bound and checked
			foreach (arg; ce.arguments) {
				if (cast(CallExpression)arg !is null) visitExpr(arg, sourcePath, errs, env, depth + 1);
			}
			return;
		}
		auto f = functions[ce.name];

		auto binding = bindArguments(ce.name, f.parameters, ce.arguments.length, ce.argumentNames);
		foreach (be; binding.errors) {
			auto pos = be.argIndex >= 0 ? getExprPos(ce.arguments[be.argIndex], sourcePath) : normalizePos(ce.position, sourcePath);
			errs.addError(be.message, pos);
		}

		// Type-check every supplied argument once, in source order
		long[] paramForArg = new long[ce.arguments.length];
		paramForArg[] = -1;
		foreach (j, ai; binding.argForParam) if (ai >= 0) paramForArg[ai] = cast(long)j;
		foreach (i, arg; ce.arguments) {
			if (paramForArg[i] < 0) {
				visitExpr(arg, sourcePath, errs, env, depth + 1);
				continue;
			}
			auto need = f.parameters[paramForArg[i]];
			auto needType = declaredNode(need.typeNode, need.type, need.customTypeName);
			auto got = visitExpr(arg, sourcePath, errs, env, depth + 1, needType);
			if (!typeCompatible(needType, got)) {
				errs.addError("Argument type mismatch for parameter '" ~ need.name ~ "' in call to '" ~ ce.name ~ "'", getExprPos(arg, sourcePath));
			}
		}
	}
}

// Public entrypoint used by the compiler
void analyzeModule(Program program, string moduleName, string sourcePath, SemanticErrorCollector errorCollector) {
	auto analyzer = new SemanticAnalyzer();
	analyzer.analyzeModule(program, moduleName, sourcePath, errorCollector);
}


