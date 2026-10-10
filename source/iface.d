module duende.iface;

import duende.ast;
import std.algorithm : canFind;
import std.array : join, split;

// A module's public contract. Semantic analysis reads this instead of treating
// imported names as unknown. User-defined types use a module-qualified name
// (`module.Type`). list, dict, Result, and Maybe stay the same type in every
// module; only their arguments are qualified.
enum ExportKind {
    function_,
    variable,
    aggregate,
    enum_,
    protocol,
    moduleAlias
}

enum ExportStatus {
    concrete,
    unknown,
    pending
}

struct ExportField {
    string name;
    TypeNode type;
    bool mutable;
}

struct ExportMethod {
    string name;
    Parameter[] parameters;
    TypeNode returnType;
    bool mutating;
    bool hasDefaultImplementation;
}

struct ExportSymbol {
    string name;
    ExportKind kind;
    ExportStatus status;
    TypeNode type;
    bool mutable;
    bool isFrame;
    Parameter[] parameters;
    ExportField[] fields;
    ExportMethod[] methods;
    string[] enumValues;
    string moduleTarget;
    Expression initializer;
    int line;
    int column;
}

struct InterfaceError {
    string message;
    string file;
    int line;
    int column;
}

class ModuleInterface {
    string moduleName;
    string sourcePath;
    ImportDeclaration[] imports;
    ExportSymbol[string] symbols;
    // Local name -> canonical module, for this module's own imports.
    string[string] moduleAliases;
    // Selective and wildcard names. Looked up live so inference sees resolved types.
    ImportedRef[string] importedRefs;
    // public import re-exports: local alias -> canonical module.
    string[string] reexports;
}

struct ImportedRef {
    string moduleName;
    string symbol;
}

struct ImportView {
    ModuleInterface[string] ifaces;
    string[string] modules;
    ExportSymbol[string] symbols;
}

ModuleInterface[string] buildModuleInterfaces(ModuleInterface[string] seed, ref InterfaceError[] errors) {
    linkImports(seed);
    resolvePendingExports(seed, errors);
    return seed;
}

ModuleInterface declaredInterface(string moduleName, string sourcePath, Program program, ImportDeclaration[] imports) {
    auto iface = new ModuleInterface();
    iface.moduleName = moduleName;
    iface.sourcePath = sourcePath;
    iface.imports = imports;
    if (program is null) return iface;

    bool[string] localTypes;
    foreach (s; program.statements) {
        if (auto st = cast(StructDeclaration)s) localTypes[st.name] = true;
        else if (auto fr = cast(FrameDeclaration)s) localTypes[fr.name] = true;
        else if (auto en = cast(EnumDeclaration)s) localTypes[en.name] = true;
        else if (auto pr = cast(ProtocolDeclaration)s) localTypes[pr.name] = true;
    }

    foreach (s; program.statements) {
        if (auto f = cast(FunctionDeclaration)s) {
            ExportSymbol sym;
            sym.name = f.name;
            sym.kind = ExportKind.function_;
            sym.type = qualify(declared(f.returnTypeNode, f.returnType, f.returnCustomTypeName), moduleName, localTypes);
            sym.status = isOpen(sym.type) ? ExportStatus.unknown : ExportStatus.concrete;
            foreach (p; f.parameters) sym.parameters ~= copyParam(p, moduleName, localTypes);
            iface.symbols[f.name] = sym;
        } else if (auto v = cast(VariableDeclaration)s) {
            ExportSymbol sym;
            sym.name = v.name;
            sym.kind = ExportKind.variable;
            sym.mutable = v.isMutable;
            sym.initializer = v.initializer;
            sym.line = v.position.line;
            sym.column = v.position.column;
            TypeNode declaredType = declared(v.typeNode, v.type, v.customTypeName);
            if (declaredType.base == DuendeType.AUTO && !declaredType.inferred) {
                sym.status = ExportStatus.pending;
            } else {
                sym.type = qualify(declaredType, moduleName, localTypes);
                sym.status = isOpen(sym.type) ? ExportStatus.unknown : ExportStatus.concrete;
            }
            iface.symbols[v.name] = sym;
        } else if (auto st = cast(StructDeclaration)s) {
            iface.symbols[st.name] = aggregateSymbol(st.name, false, st.fields, null, st.methods, null, moduleName, localTypes);
        } else if (auto fr = cast(FrameDeclaration)s) {
            iface.symbols[fr.name] = aggregateSymbol(fr.name, true, null, fr.fields, fr.methods, mutatingMethodsOf(fr.methods), moduleName, localTypes);
        } else if (auto en = cast(EnumDeclaration)s) {
            ExportSymbol sym;
            sym.name = en.name;
            sym.kind = ExportKind.enum_;
            sym.status = ExportStatus.concrete;
            sym.type = TypeNode.of(DuendeType.CUSTOM, moduleName ~ "." ~ en.name);
            sym.enumValues = en.values.dup;
            iface.symbols[en.name] = sym;
        } else if (auto pr = cast(ProtocolDeclaration)s) {
            ExportSymbol sym;
            sym.name = pr.name;
            sym.kind = ExportKind.protocol;
            sym.status = ExportStatus.concrete;
            sym.type = TypeNode.of(DuendeType.CUSTOM, moduleName ~ "." ~ pr.name);
            foreach (method; pr.methods) {
                ExportMethod em;
                em.name = method.name;
                em.returnType = qualify(declared(method.returnTypeNode, method.returnType), moduleName, localTypes);
                foreach (p; method.parameters) em.parameters ~= copyParam(p, moduleName, localTypes);
                em.hasDefaultImplementation = method.hasDefaultImplementation;
                sym.methods ~= em;
            }
            iface.symbols[pr.name] = sym;
        }
    }
    return iface;
}

ImportView importView(ModuleInterface[string] ifaces, string importer, ImportDeclaration[] imports, ref InterfaceError[] errors) {
    ImportView view;
    view.ifaces = ifaces;
    string file = importer;
    if (auto iface = importer in ifaces) file = iface.sourcePath;
    foreach (imp; imports) {
        string dep = resolveModuleName(ifaces, importer, imp.modulePath);
        if (!dep.length) continue;
        string shortName = imp.moduleAlias.length ? imp.moduleAlias : imp.modulePath[$-1];
        view.modules[shortName] = dep;
        if (imp.items.length) {
            foreach (item; imp.items) {
                string local = item.localAlias.length ? item.localAlias : item.name;
                if (auto sym = item.name in ifaces[dep].symbols) {
                    view.symbols[local] = *sym;
                } else {
                    errors ~= InterfaceError(
                        "Module '" ~ dep ~ "' has no public symbol '" ~ item.name ~ "'",
                        file, 1, 1);
                }
            }
        } else if (imp.isWildcard) {
            foreach (name, sym; ifaces[dep].symbols) view.symbols[name] = sym;
        }
        foreach (aliasName, target; ifaces[dep].reexports) view.modules[aliasName] = target;
    }
    return view;
}

private void linkImports(ModuleInterface[string] ifaces) {
    foreach (iface; ifaces) {
        foreach (imp; iface.imports) {
            string dep = resolveModuleName(ifaces, iface.moduleName, imp.modulePath);
            if (!dep.length) continue;
            string shortName = imp.moduleAlias.length ? imp.moduleAlias : imp.modulePath[$-1];
            iface.moduleAliases[shortName] = dep;
            if (imp.isPublic) iface.reexports[shortName] = dep;
            if (imp.items.length) {
                foreach (item; imp.items) {
                    string local = item.localAlias.length ? item.localAlias : item.name;
                    iface.importedRefs[local] = ImportedRef(dep, item.name);
                }
            } else if (imp.isWildcard) {
                foreach (name, sym; ifaces[dep].symbols)
                    iface.importedRefs[name] = ImportedRef(dep, name);
            }
        }
    }
}

private void resolvePendingExports(ModuleInterface[string] ifaces, ref InterfaceError[] errors) {
    int limit = 1;
    foreach (iface; ifaces) limit += cast(int)iface.symbols.length;
    bool progress = true;
    int guard = 0;
    while (progress && guard++ < limit + 2) {
        progress = false;
        string[] names;
        ModuleInterface[] owners;
        ExportSymbol[] updates;
        foreach (iface; ifaces) {
            foreach (name, sym; iface.symbols) {
                if (sym.kind != ExportKind.variable || sym.status != ExportStatus.pending) continue;
                auto got = inferExpr(sym.initializer, iface, ifaces);
                if (got.status == ExportStatus.pending) continue;
                sym.status = got.status;
                sym.type = got.type;
                owners ~= iface;
                names ~= name;
                updates ~= sym;
                progress = true;
            }
        }
        foreach (i, sym; updates) owners[i].symbols[names[i]] = sym;
    }
    foreach (iface; ifaces) {
        foreach (name, sym; iface.symbols) {
            if (sym.kind == ExportKind.variable && sym.status == ExportStatus.pending) {
                errors ~= InterfaceError(
                    "Cannot infer the type of '" ~ name ~ "' across an import cycle; declare its type",
                    iface.sourcePath,
                    sym.line > 0 ? sym.line : 1,
                    sym.column > 0 ? sym.column : 1);
            }
        }
    }
}

private struct Infer {
    TypeNode type;
    ExportStatus status;
    static Infer pending() { Infer r; r.status = ExportStatus.pending; r.type = TypeNode.unknownType(); return r; }
    static Infer open() { Infer r; r.status = ExportStatus.unknown; r.type = TypeNode.unknownType(); return r; }
    static Infer known(TypeNode t) {
        Infer r;
        r.type = t;
        r.status = isOpen(t) ? ExportStatus.unknown : ExportStatus.concrete;
        return r;
    }
}

private Infer joinInfer(Infer a, Infer b) {
    if (a.status == ExportStatus.pending || b.status == ExportStatus.pending) return Infer.pending();
    if (a.status == ExportStatus.unknown || b.status == ExportStatus.unknown) return Infer.open();
    return a;
}

private Infer inferExpr(Expression e, ModuleInterface iface, ModuleInterface[string] ifaces) {
    if (e is null) return Infer.open();
    if (auto lit = cast(LiteralExpression)e) return Infer.known(TypeNode.of(lit.type));
    if (cast(BytesLiteralExpression)e !is null) return Infer.known(TypeNode.of(DuendeType.BYTES));
    if (auto ue = cast(UnaryExpression)e) {
        auto inner = inferExpr(ue.operand, iface, ifaces);
        if (ue.operator == "!") {
            if (inner.status != ExportStatus.concrete) return inner;
            return Infer.known(TypeNode.of(DuendeType.BOOL));
        }
        return inner;
    }
    if (auto be = cast(BinaryExpression)e) {
        auto lt = inferExpr(be.left, iface, ifaces);
        auto rt = inferExpr(be.right, iface, ifaces);
        auto joined = joinInfer(lt, rt);
        if (joined.status != ExportStatus.concrete) return joined;
        if (be.operator == "==" || be.operator == "!=" || be.operator == "<" || be.operator == ">" || be.operator == "<=" || be.operator == ">=" || be.operator == "&&" || be.operator == "||")
            return Infer.known(TypeNode.of(DuendeType.BOOL));
        if (be.operator == "+" && lt.type.base == DuendeType.STRING && rt.type.base == DuendeType.STRING)
            return Infer.known(TypeNode.of(DuendeType.STRING));
        bool leftNum = lt.type.base == DuendeType.INT || lt.type.base == DuendeType.FLOAT;
        bool rightNum = rt.type.base == DuendeType.INT || rt.type.base == DuendeType.FLOAT;
        if (leftNum && rightNum) {
            if (lt.type.base == DuendeType.FLOAT || rt.type.base == DuendeType.FLOAT)
                return Infer.known(TypeNode.of(DuendeType.FLOAT));
            return Infer.known(TypeNode.of(DuendeType.INT));
        }
        return Infer.open();
    }
    if (auto ll = cast(ListLiteralExpression)e) {
        if (!ll.elements.length) return Infer.open();
        Infer seen = inferExpr(ll.elements[0], iface, ifaces);
        foreach (el; ll.elements[1 .. $]) seen = joinInfer(seen, inferExpr(el, iface, ifaces));
        if (seen.status != ExportStatus.concrete) return seen;
        return Infer.known(TypeNode.generic(DuendeType.LIST, [seen.type]));
    }
    if (auto dl = cast(DictLiteralExpression)e) {
        if (!dl.keys.length) return Infer.open();
        Infer key = inferExpr(dl.keys[0], iface, ifaces);
        Infer val = inferExpr(dl.values[0], iface, ifaces);
        foreach (i, k; dl.keys) {
            if (i == 0) continue;
            key = joinInfer(key, inferExpr(k, iface, ifaces));
            val = joinInfer(val, inferExpr(dl.values[i], iface, ifaces));
        }
        auto joined = joinInfer(key, val);
        if (joined.status != ExportStatus.concrete) return joined;
        return Infer.known(TypeNode.generic(DuendeType.DICT, [key.type, val.type]));
    }
    if (auto ve = cast(VariableExpression)e) return inferName(ve.name, iface, ifaces);
    if (auto pe = cast(PropertyExpression)e) {
        if (auto obj = cast(VariableExpression)pe.object) {
            if (auto mod = obj.name in iface.moduleAliases) {
                if (auto dep = *mod in ifaces) return inferExport(*dep, pe.property);
            }
        }
        return Infer.open();
    }
    if (auto ce = cast(CallExpression)e) {
        auto callee = inferName(ce.name, iface, ifaces);
        if (callee.status != ExportStatus.concrete) return callee;
        foreach (a; ce.arguments) {
            auto arg = inferExpr(a, iface, ifaces);
            if (arg.status == ExportStatus.pending) return Infer.pending();
        }
        return callee;
    }
    if (auto me = cast(MethodCallExpression)e) {
        if (auto obj = cast(VariableExpression)me.object) {
            if (auto mod = obj.name in iface.moduleAliases) {
                if (auto dep = *mod in ifaces) {
                    auto callee = inferExport(*dep, me.method);
                    if (callee.status != ExportStatus.concrete) return callee;
                    foreach (a; me.arguments) {
                        auto arg = inferExpr(a, iface, ifaces);
                        if (arg.status == ExportStatus.pending) return Infer.pending();
                    }
                    return callee;
                }
            }
        }
        return Infer.open();
    }
    if (auto cc = cast(ConstructorCallExpression)e) {
        if (auto sym = cc.typeName in iface.symbols) {
            if (sym.kind == ExportKind.aggregate || sym.kind == ExportKind.enum_)
                return Infer.known(sym.type);
        }
        if (auto r = cc.typeName in iface.importedRefs) {
            if (auto dep = r.moduleName in ifaces) return inferExport(*dep, r.symbol);
        }
        return Infer.open();
    }
    if (auto rc = cast(ResultConstructorExpression)e) {
        if (!rc.isOk) return Infer.known(TypeNode.generic(DuendeType.RESULT, [TypeNode.of(DuendeType.STRING)]));
        auto inner = inferExpr(rc.value, iface, ifaces);
        if (inner.status != ExportStatus.concrete) return inner;
        return Infer.known(TypeNode.generic(DuendeType.RESULT, [inner.type]));
    }
    if (auto mc = cast(MaybeConstructorExpression)e) {
        if (!mc.isSome || mc.value is null)
            return Infer.known(TypeNode.generic(DuendeType.MAYBE, [TypeNode.of(DuendeType.STRING)]));
        auto inner = inferExpr(mc.value, iface, ifaces);
        if (inner.status != ExportStatus.concrete) return inner;
        return Infer.known(TypeNode.generic(DuendeType.MAYBE, [inner.type]));
    }
    if (auto ce2 = cast(CastExpression)e) return Infer.known(TypeNode.of(ce2.targetType));
    return Infer.open();
}

private Infer inferName(string name, ModuleInterface iface, ModuleInterface[string] ifaces) {
    if (auto sym = name in iface.symbols) return inferSymbol(*sym);
    if (auto r = name in iface.importedRefs) {
        if (auto dep = r.moduleName in ifaces) return inferExport(*dep, r.symbol);
    }
    return Infer.open();
}

private Infer inferExport(ModuleInterface dep, string name) {
    if (auto sym = name in dep.symbols) return inferSymbol(*sym);
    return Infer.open();
}

private Infer inferSymbol(ExportSymbol sym) {
    if (sym.kind == ExportKind.variable) {
        if (sym.status == ExportStatus.pending) return Infer.pending();
        if (sym.status == ExportStatus.unknown) return Infer.open();
        return Infer.known(sym.type);
    }
    if (sym.kind == ExportKind.function_) {
        if (sym.status != ExportStatus.concrete) return Infer.open();
        return Infer.known(sym.type);
    }
    if (sym.status != ExportStatus.concrete) return Infer.open();
    return Infer.known(sym.type);
}

private ExportSymbol aggregateSymbol(string name, bool isFrame, Parameter[] structFields, VariableDeclaration[] frameFields, MethodDeclaration[] methods, bool[string] mutating, string moduleName, bool[string] localTypes) {
    ExportSymbol sym;
    sym.name = name;
    sym.kind = ExportKind.aggregate;
    sym.status = ExportStatus.concrete;
    sym.isFrame = isFrame;
    sym.type = TypeNode.of(DuendeType.CUSTOM, moduleName ~ "." ~ name);
    if (structFields !is null) {
        foreach (f; structFields) {
            ExportField field;
            field.name = f.name;
            field.type = qualify(declared(f.typeNode, f.type, f.customTypeName), moduleName, localTypes);
            field.mutable = false;
            sym.fields ~= field;
        }
    }
    if (frameFields !is null) {
        foreach (f; frameFields) {
            ExportField field;
            field.name = f.name;
            field.type = qualify(declared(f.typeNode, f.type, f.customTypeName), moduleName, localTypes);
            field.mutable = f.isMutable;
            sym.fields ~= field;
        }
    }
    foreach (m; methods) {
        ExportMethod em;
        em.name = m.name;
        em.returnType = qualify(declared(m.returnTypeNode, m.returnType, null), moduleName, localTypes);
        foreach (p; m.parameters) em.parameters ~= copyParam(p, moduleName, localTypes);
        em.mutating = mutating !is null && (m.name in mutating) !is null;
        sym.methods ~= em;
    }
    return sym;
}

// Which frame methods write fields, including methods that call those methods on this.
bool[string] mutatingMethodsOf(MethodDeclaration[] methods) {
    bool[string] direct;
    foreach (m; methods) {
        if (methodAssignsThis(m)) direct[m.name] = true;
    }
    bool[string] mut = direct;
    bool changed = true;
    while (changed) {
        changed = false;
        foreach (m; methods) {
            if (m.name in mut) continue;
            if (methodCallsMutatingThis(m, mut)) {
                mut[m.name] = true;
                changed = true;
            }
        }
    }
    return mut;
}

private bool methodAssignsThis(MethodDeclaration m) {
    foreach (st; m.body) if (stmtWritesThis(st, null)) return true;
    return false;
}

private bool methodCallsMutatingThis(MethodDeclaration m, bool[string] mut) {
    foreach (st; m.body) if (stmtWritesThis(st, mut)) return true;
    return false;
}

private bool stmtWritesThis(Statement s, bool[string] mut) {
    if (s is null) return false;
    if (auto vd = cast(VariableDeclaration)s) return exprWritesThis(vd.initializer, mut);
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
        foreach (c; ms.cases) {
            if (auto ep = cast(ExpressionPattern)c.pattern) if (exprWritesThis(ep.expr, mut)) return true;
            if (exprWritesThis(c.guard, mut)) return true;
            foreach (st; c.body) if (stmtWritesThis(st, mut)) return true;
        }
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
    if (auto ia = cast(IndexAssignmentExpression)e)
        return exprWritesThis(ia.object, mut) || exprWritesThis(ia.index, mut) || exprWritesThis(ia.value, mut);
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
    if (auto rc = cast(ResultConstructorExpression)e) return exprWritesThis(rc.value, mut);
    if (auto mc2 = cast(MaybeConstructorExpression)e) return exprWritesThis(mc2.value, mut);
    if (auto uw = cast(UnwrapExpression)e) return exprWritesThis(uw.result, mut) || exprWritesThis(uw.defaultValue, mut);
    if (auto casted = cast(CastExpression)e) return exprWritesThis(casted.value, mut);
    if (auto pe2 = cast(PanicExpression)e) return exprWritesThis(pe2.message, mut);
    if (auto ll = cast(ListLiteralExpression)e) {
        foreach (el; ll.elements) if (exprWritesThis(el, mut)) return true;
    }
    if (auto dl = cast(DictLiteralExpression)e) {
        foreach (i, key; dl.keys) if (exprWritesThis(key, mut) || exprWritesThis(dl.values[i], mut)) return true;
    }
    if (auto te = cast(TryBlockExpression)e) {
        foreach (st; te.statements) if (stmtWritesThis(st, mut)) return true;
    }
    if (auto me = cast(MatchExpression)e) {
        if (exprWritesThis(me.subject, mut)) return true;
        foreach (c; me.cases) {
            if (auto ep = cast(ExpressionPattern)c.pattern) if (exprWritesThis(ep.expr, mut)) return true;
            if (exprWritesThis(c.guard, mut) || exprWritesThis(c.value, mut)) return true;
        }
    }
    return false;
}

private Parameter copyParam(Parameter p, string moduleName, bool[string] localTypes) {
    Parameter q = p;
    q.typeNode = qualify(declared(p.typeNode, p.type, p.customTypeName), moduleName, localTypes);
    q.type = q.typeNode.base;
    if (q.typeNode.base == DuendeType.CUSTOM) q.customTypeName = q.typeNode.name;
    else if (q.typeNode.legacyCustom().length) q.customTypeName = q.typeNode.legacyCustom();
    return q;
}

string resolveModuleName(ModuleInterface[string] ifaces, string importer, string[] path) {
    string mod = path.join(".");
    if (mod in ifaces) return mod;
    auto parts = importer.split(".");
    if (parts.length > 1) {
        string candidate = parts[0 .. $-1].join(".") ~ "." ~ mod;
        if (candidate in ifaces) return candidate;
    }
    return null;
}

private TypeNode declared(TypeNode node, DuendeType fallback, string custom = null) {
    TypeNode t = node.present ? node : TypeNode.of(fallback, custom);
    if (t.base == DuendeType.DICT && t.args.length < 2) {
        return TypeNode.generic(DuendeType.DICT, [
            TypeNode.of(DuendeType.STRING),
            TypeNode.of(DuendeType.STRING)
        ]);
    }
    return t;
}

private bool isOpen(TypeNode t) {
    if (!t.present || t.unknown) return true;
    return t.base == DuendeType.AUTO && !t.inferred;
}

private TypeNode qualify(TypeNode t, string moduleName, bool[string] localTypes) {
    TypeNode o = t;
    o.args = t.args is null ? null : t.args.dup;
    if (o.base == DuendeType.CUSTOM && o.name.length && (o.name in localTypes) && !o.name.canFind("."))
        o.name = moduleName ~ "." ~ o.name;
    foreach (i, a; o.args) o.args[i] = qualify(a, moduleName, localTypes);
    if ((o.base == DuendeType.LIST || o.base == DuendeType.RESULT || o.base == DuendeType.MAYBE) && o.args.length && o.args[0].base == DuendeType.CUSTOM)
        o.name = o.args[0].name;
    return o;
}
