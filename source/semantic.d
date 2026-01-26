module duende.semantic;

import duende.ast;
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

// Minimal type info for checking
struct TypeInfo {
	DuendeType base;
	string custom; // for CUSTOM types
}

private TypeInfo typeInfo(DuendeType t, string custom = null) {
	return TypeInfo(t, custom);
}

private string typeInfoToString(TypeInfo t) {
	import std.format : format;
	final switch (t.base) {
		case DuendeType.CUSTOM:
			return t.custom.length ? format("%s(%s)", DuendeType.CUSTOM, t.custom) : format("%s", DuendeType.CUSTOM);
		case DuendeType.RESULT:
		case DuendeType.MAYBE:
		case DuendeType.LIST:
		case DuendeType.DICT:
		case DuendeType.INT:
		case DuendeType.FLOAT:
		case DuendeType.STRING:
		case DuendeType.BOOL:
		case DuendeType.BYTES:
		case DuendeType.VOID:
		case DuendeType.REGEX:
		case DuendeType.DATE:
		case DuendeType.AUTO:
		case DuendeType.STRUCT:
		case DuendeType.FRAME:
		case DuendeType.ENUM:
		case DuendeType.PROTOCOL:
			return t.base.to!string;
	}
}

private bool typeCompatible(TypeInfo need, TypeInfo got) {
	// AUTO accepts anything
	if (need.base == DuendeType.AUTO) return true;
	if (got.base == DuendeType.AUTO) return true; // unknown -> don't over-report
	if (need.base == got.base) {
		if (need.base == DuendeType.CUSTOM) {
			if (need.custom.length && got.custom.length)
				return need.custom == got.custom;
		}
		return true;
	}
	// allow INT -> FLOAT
	if (need.base == DuendeType.FLOAT && got.base == DuendeType.INT) return true;
	// allow implicit conversion to STRING from any non-void type
	if (need.base == DuendeType.STRING && got.base != DuendeType.VOID) return true;
	// allow list literal to assign to list type (no inner-type checking here)
	if (need.base == DuendeType.LIST && got.base == DuendeType.LIST) return true;
	// allow dict literal to assign to dict type (no key/value type checking here)
	if (need.base == DuendeType.DICT && got.base == DuendeType.DICT) return true;
	// allow assigning bytes-typed literal from list<int>
	if (need.base == DuendeType.BYTES && got.base == DuendeType.BYTES) return true;
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
	// top-level variables (globals)
	private TypeInfo[string] globals;
	// enum name -> values set
	private string[][string] enums; // map enum name -> list of values
	// recursion guard
	private size_t maxDepth = 10_000;
	// whether module has any imports (providers may inject symbols)
	private bool hasImports;

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
				globals[v.name] = typeInfo(v.type, v.customTypeName);
			} else if (auto en = cast(EnumDeclaration)s) {
				enums[en.name] = en.values.dup;
			} else if (cast(ImportDeclaration)s) {
				hasImports = true;
			}
		}
		// Pass 2: analyze statements with a scope stack
		ScopeEnv env;
		// seed with globals
		foreach (k, t; globals) env.define(k, t);
		foreach (s; prog.statements) {
			visitStmt(s, sourcePath, errs, env, 0);
		}
	}

	// Simple scope chain
	private struct ScopeEnv {
		TypeInfo[string] table;
		ScopeEnv* parent;
		bool inLoop;

		void define(string name, TypeInfo t) { table[name] = t; }
		bool lookup(string name, out TypeInfo t) {
			if (name in table) { t = table[name]; return true; }
			if (parent is null) return false;
			return parent.lookup(name, t);
		}
		ScopeEnv child() {
			ScopeEnv c; c.parent = &this; c.inLoop = this.inLoop; return c;
		}
	}

	private void visitStmt(Statement s, string sourcePath, SemanticErrorCollector errs, ref ScopeEnv env, size_t depth) {
		if (s is null) return;
		if (depth > maxDepth) return; // safety
		if (auto vd = cast(VariableDeclaration)s) {
			auto ti = typeInfo(vd.type, vd.customTypeName);
			env.define(vd.name, ti);
			// analyze initializer
			if (vd.initializer !is null) {
				auto et = visitExpr(vd.initializer, sourcePath, errs, env, depth + 1);
				bool specialOk = false;
				// Special-case: allow bytes initialized from a list literal of ints
				if (ti.base == DuendeType.BYTES) {
					if (cast(ListLiteralExpression)vd.initializer !is null) {
						// Optionally, could validate element types/ranges; accept for now
						specialOk = true;
					}
				}
				if (!typeCompatible(ti, et) && !specialOk) {
					auto pos = normalizePos(vd.position, sourcePath);
					errs.addError(
						"Initializer type does not match declared type of '" ~ vd.name ~ "' (need=" ~ typeInfoToString(ti) ~ ", got=" ~ typeInfoToString(et) ~ ")",
						pos);
				}
			}
			return;
		}
		if (auto f = cast(FunctionDeclaration)s) {
			// function body: new scope with params
			auto child = env.child();
			child.inLoop = false; // Reset loop context
			foreach (p; f.parameters) {
				child.define(p.name, typeInfo(p.type, p.customTypeName));
			}
			foreach (st; f.body) visitStmt(st, sourcePath, errs, child, depth + 1);
			return;
		}
		if (auto m = cast(MethodDeclaration)s) {
			auto child = env.child();
			child.inLoop = false; // Reset loop context
			foreach (p; m.parameters) child.define(p.name, typeInfo(p.type, p.customTypeName));
			foreach (st; m.body) visitStmt(st, sourcePath, errs, child, depth + 1);
			return;
		}
		if (auto sd = cast(StructDeclaration)s) {
			foreach (m; sd.methods) visitStmt(m, sourcePath, errs, env, depth + 1);
			return;
		}
		if (auto fd = cast(FrameDeclaration)s) {
			foreach (m; fd.methods) visitStmt(m, sourcePath, errs, env, depth + 1);
			return;
		}
		if (auto es = cast(ExpressionStatement)s) {
			visitExpr(es.expression, sourcePath, errs, env, depth + 1);
			return;
		}
		if (auto rs = cast(ReturnStatement)s) {
			visitExpr(rs.value, sourcePath, errs, env, depth + 1);
			return;
		}
		if (auto ifs = cast(IfStatement)s) {
			visitExpr(ifs.condition, sourcePath, errs, env, depth + 1);
			auto thenScope = env.child();
			foreach (st; ifs.thenBranch) visitStmt(st, sourcePath, errs, thenScope, depth + 1);
			if (ifs.elifClauses.length) {
				foreach (ec; ifs.elifClauses) {
					visitExpr(ec.condition, sourcePath, errs, env, depth + 1);
					auto ecScope = env.child();
					foreach (st; ec.body) visitStmt(st, sourcePath, errs, ecScope, depth + 1);
				}
			}
			auto elseScope = env.child();
			foreach (st; ifs.elseBranch) visitStmt(st, sourcePath, errs, elseScope, depth + 1);
			return;
		}
		if (auto fs = cast(ForStatement)s) {
			// loop var is int
			auto child = env.child();
			child.inLoop = true;
			child.define(fs.variable, typeInfo(DuendeType.INT));
			visitExpr(fs.start, sourcePath, errs, child, depth + 1);
			visitExpr(fs.end, sourcePath, errs, child, depth + 1);
			foreach (st; fs.body) visitStmt(st, sourcePath, errs, child, depth + 1);
			return;
		}
		if (auto fi = cast(ForInStatement)s) {
			auto child = env.child();
			child.inLoop = true;
			child.define(fi.variable, typeInfo(DuendeType.AUTO));
			visitExpr(fi.iterable, sourcePath, errs, child, depth + 1);
			foreach (st; fi.body) visitStmt(st, sourcePath, errs, child, depth + 1);
			return;
		}
		if (auto ws = cast(WhileStatement)s) {
			visitExpr(ws.condition, sourcePath, errs, env, depth + 1);
			auto loopScope = env.child();
			loopScope.inLoop = true;
			foreach (st; ws.body) visitStmt(st, sourcePath, errs, loopScope, depth + 1);
			return;
		}
		if (auto ms = cast(MatchStatement)s) {
			visitExpr(ms.subject, sourcePath, errs, env, depth + 1);
			foreach (c; ms.cases) {
				auto armScope = env.child();
				if (auto okp = cast(ResultOkPattern)c.pattern) {
					if (okp.bindName.length) armScope.define(okp.bindName, typeInfo(DuendeType.AUTO));
				}
				if (auto errp = cast(ResultErrorPattern)c.pattern) {
					if (errp.bindName.length) armScope.define(errp.bindName, typeInfo(DuendeType.AUTO));
				}
				foreach (st; c.body) visitStmt(st, sourcePath, errs, armScope, depth + 1);
			}
			return;
		}
		if (auto bs = cast(BreakStatement)s) {
			if (!env.inLoop) {
				auto pos = normalizePos(bs.position, sourcePath);
				errs.addError("Invalid use of 'break' outside of a loop", pos);
			}
			return;
		}
		if (auto cs = cast(ContinueStatement)s) {
			if (!env.inLoop) {
				auto pos = normalizePos(cs.position, sourcePath);
				errs.addError("Invalid use of 'continue' outside of a loop", pos);
			}
			return;
		}
		// other statements ok
	}

	private TypeInfo visitExpr(Expression e, string sourcePath, SemanticErrorCollector errs, ref ScopeEnv env, size_t depth) {
		if (e is null) return typeInfo(DuendeType.VOID);
		if (depth > maxDepth) return typeInfo(DuendeType.AUTO);
		if (auto lit = cast(LiteralExpression)e) return typeInfo(lit.type);
		if (cast(BytesLiteralExpression)e !is null) return typeInfo(DuendeType.BYTES);
		if (cast(RegexLiteralExpression)e !is null) return typeInfo(DuendeType.REGEX);
		if (auto ll = cast(ListLiteralExpression)e) {
			foreach (el; ll.elements) { visitExpr(el, sourcePath, errs, env, depth + 1); }
			return typeInfo(DuendeType.LIST);
		}
		if (auto dl = cast(DictLiteralExpression)e) {
			foreach (i, k; dl.keys) {
				visitExpr(k, sourcePath, errs, env, depth + 1);
				visitExpr(dl.values[i], sourcePath, errs, env, depth + 1);
			}
			return typeInfo(DuendeType.DICT);
		}
		if (auto ve = cast(VariableExpression)e) {
			// Treat known enum names as type-like values (for qualified access Color.Red)
			if (ve.name in enums) return typeInfo(DuendeType.CUSTOM, ve.name);
			TypeInfo t;
			if (!env.lookup(ve.name, t)) {
				// Allow bare enum member usage (e.g., ACTIVE) by resolving to its enum type
				auto en = resolveEnumForValue(ve.name);
				if (en !is null) return typeInfo(DuendeType.CUSTOM, en);
				// Consider TitleCase identifiers as type-like (providers or user-defined)
				if (ve.name.length && ve.name[0] >= 'A' && ve.name[0] <= 'Z') {
					return typeInfo(DuendeType.CUSTOM, ve.name);
				}
				auto pos = normalizePos(ve.position, sourcePath);
				errs.addError("Use of undefined variable '" ~ ve.name ~ "'", pos);
				return typeInfo(DuendeType.AUTO);
			}
			return t;
		}
		if (auto ae = cast(AssignmentExpression)e) {
			TypeInfo t;
			bool ok = env.lookup(ae.variable, t);
			if (!ok) {
				auto pos = normalizePos(ae.position, sourcePath);
				errs.addError("Assignment to undefined variable '" ~ ae.variable ~ "'", pos);
				// Still analyze RHS to continue
				visitExpr(ae.value, sourcePath, errs, env, depth + 1);
				return typeInfo(DuendeType.AUTO);
			}
			auto rhs = visitExpr(ae.value, sourcePath, errs, env, depth + 1);
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
				return typeInfo(f.returnType, f.returnCustomTypeName);
			}
			return typeInfo(DuendeType.AUTO);
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
			if (!skipObject) {
				visitExpr(me.object, sourcePath, errs, env, depth + 1);
			}
			foreach (a; me.arguments) visitExpr(a, sourcePath, errs, env, depth + 1);
			return typeInfo(DuendeType.AUTO);
		}
		if (auto be = cast(BinaryExpression)e) {
			auto lt = visitExpr(be.left, sourcePath, errs, env, depth + 1);
			auto rt = visitExpr(be.right, sourcePath, errs, env, depth + 1);
			// simple arithmetic typing
			if (lt.base == DuendeType.FLOAT || rt.base == DuendeType.FLOAT) return typeInfo(DuendeType.FLOAT);
			if (lt.base == DuendeType.INT && rt.base == DuendeType.INT) return typeInfo(DuendeType.INT);
			return typeInfo(DuendeType.AUTO);
		}
		if (auto ue = cast(UnaryExpression)e) {
			return visitExpr(ue.operand, sourcePath, errs, env, depth + 1);
		}
		if (auto ie = cast(IndexExpression)e) {
			visitExpr(ie.object, sourcePath, errs, env, depth + 1);
			visitExpr(ie.index, sourcePath, errs, env, depth + 1);
			return typeInfo(DuendeType.AUTO);
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
			visitExpr(pe.object, sourcePath, errs, env, depth + 1);
			return typeInfo(DuendeType.AUTO);
		}
		if (auto pae = cast(PropertyAssignmentExpression)e) {
			visitExpr(pae.object, sourcePath, errs, env, depth + 1);
			visitExpr(pae.value, sourcePath, errs, env, depth + 1);
			return typeInfo(DuendeType.AUTO);
		}
		if (auto se = cast(StringInterpolationExpression)e) {
			foreach (ex; se.expressions) visitExpr(ex, sourcePath, errs, env, depth + 1);
			return typeInfo(DuendeType.STRING);
		}
		if (auto me2 = cast(MatchExpression)e) {
			visitExpr(me2.subject, sourcePath, errs, env, depth + 1);
			foreach (c; me2.cases) {
				auto armScope = env.child();
				if (auto okp = cast(ResultOkPattern)c.pattern) {
					if (okp.bindName.length) armScope.define(okp.bindName, typeInfo(DuendeType.AUTO));
				}
				if (auto errp = cast(ResultErrorPattern)c.pattern) {
					if (errp.bindName.length) armScope.define(errp.bindName, typeInfo(DuendeType.AUTO));
				}
				visitExpr(c.value, sourcePath, errs, armScope, depth + 1);
			}
			return typeInfo(DuendeType.AUTO);
		}
		if (auto rc = cast(ResultConstructorExpression)e) {
			visitExpr(rc.value, sourcePath, errs, env, depth + 1);
			return typeInfo(DuendeType.RESULT);
		}
		if (auto mc = cast(MaybeConstructorExpression)e) {
			if (mc.value !is null) visitExpr(mc.value, sourcePath, errs, env, depth + 1);
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
			child.inLoop = false;
			foreach (p; le.parameters) child.define(p, typeInfo(DuendeType.AUTO));
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

	private void checkFunctionCall(CallExpression ce, string sourcePath, SemanticErrorCollector errs, ref ScopeEnv env, size_t depth) {
		// Only check functions declared in this module; ignore providers/builtins
		if (!(ce.name in functions)) return;
		auto f = functions[ce.name];

		// Build mapping param->provided arg index
		bool[string] provided;
		size_t positionalIndex = 0;
		// First pass: validate named args
		foreach (i, arg; ce.arguments) {
			string an = (i < ce.argumentNames.length) ? ce.argumentNames[i] : "";
			if (an.length == 0) continue; // positional, later
			// find parameter by name
			long pi = -1;
			foreach (j, p; f.parameters) { if (p.name == an) { pi = cast(long)j; break; } }
				if (pi < 0) {
					auto pos = getExprPos(arg, sourcePath);
				errs.addError("Unknown named parameter '" ~ an ~ "' for function '" ~ ce.name ~ "'", pos);
				continue;
			}
			if (auto prev = an in provided) {
					auto pos = getExprPos(arg, sourcePath);
				errs.addError("Duplicate argument for parameter '" ~ an ~ "' in call to '" ~ ce.name ~ "'", pos);
				continue;
			}
			provided[an] = true;
			// type-check this arg
			auto need = f.parameters[pi];
			auto got = visitExpr(arg, sourcePath, errs, env, depth + 1);
			if (!typeCompatible(typeInfo(need.type, need.customTypeName), got)) {
				auto pos = getExprPos(arg, sourcePath);
				errs.addError("Argument type mismatch for parameter '" ~ need.name ~ "' in call to '" ~ ce.name ~ "'", pos);
			}
		}

		// Second pass: consume positional args in parameter order, skipping params already provided by name
		foreach (p; f.parameters) {
			if (p.name in provided) continue;
			// find next positional arg
			while (positionalIndex < ce.arguments.length && ce.argumentNames[positionalIndex].length != 0) {
				positionalIndex++;
			}
			if (positionalIndex < ce.arguments.length) {
				auto arg = ce.arguments[positionalIndex++];
				auto got = visitExpr(arg, sourcePath, errs, env, depth + 1);
				if (!typeCompatible(typeInfo(p.type, p.customTypeName), got)) {
					auto pos = getExprPos(arg, sourcePath);
					errs.addError("Argument type mismatch for parameter '" ~ p.name ~ "' in call to '" ~ ce.name ~ "'", pos);
				}
				provided[p.name] = true;
			} else {
				// no more positional args; parameter must have default
				if (p.defaultValue is null) {
					auto pos = normalizePos(ce.position, sourcePath);
					errs.addError("Missing argument for parameter '" ~ p.name ~ "' in call to '" ~ ce.name ~ "'", pos);
				}
			}
		}

		// Extra positional args beyond parameters?
		// Count non-named args
		size_t positionalCount = 0;
		foreach (i, _; ce.arguments) {
			if (ce.argumentNames[i].length == 0) positionalCount++;
		}
		// Number of parameters not provided by name or defaulted used to match positionally
		size_t nonNamedParams = 0;
		foreach (p; f.parameters) if (!(p.name in provided)) nonNamedParams++;
		if (positionalCount > f.parameters.length) {
			auto pos = normalizePos(ce.position, sourcePath);
			errs.addError("Too many arguments in call to '" ~ ce.name ~ "'", pos);
		}
	}
}

// Public entrypoint used by the compiler
void analyzeModule(Program program, string moduleName, string sourcePath, SemanticErrorCollector errorCollector) {
	auto analyzer = new SemanticAnalyzer();
	analyzer.analyzeModule(program, moduleName, sourcePath, errorCollector);
}


