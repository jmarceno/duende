module duende.builtins;

import duende.ast;

// Inventory of compiler builtins. Each contract is arity, argument and result
// types, and the effects that matter for callers. Provider functions are absent
// on purpose: an unknown provider keeps no fabricated signature (DU-12).
//
// Math names are builtins and still require `import std.math`. Hash, encoding,
// process, and network helpers are providers, not entries in this table.

enum BuiltinAccept {
    any,
    exact,
    lenSubject,
    number,
    typeArg
}

enum BuiltinReturnKind {
    fixed,
    sameNumber,
    widerNumber,
    castResult
}

enum BuiltinEffect {
    none = 0,
    reads = 1 << 0,
    writes = 1 << 1,
    mayFail = 1 << 2
}

struct BuiltinParam {
    string name;
    BuiltinAccept accept;
    TypeNode type;
    bool optional;
}

struct BuiltinContract {
    string name;
    BuiltinParam[] params;
    BuiltinReturnKind retKind;
    TypeNode result;
    int effect;
    bool variadic;
    int minArgs;
}

BuiltinContract* findBuiltin(string name) {
    return name in builtinTable();
}

ref BuiltinContract[string] builtinTable() {
    static BuiltinContract[string] table;
    static bool ready = false;
    if (!ready) {
        ready = true;
        fillBuiltins(table);
    }
    return table;
}

private TypeNode T(DuendeType base) {
    return TypeNode.of(base);
}

private TypeNode listOf(TypeNode inner) {
    return TypeNode.generic(DuendeType.LIST, [inner]);
}

private TypeNode resultOf(TypeNode inner) {
    return TypeNode.generic(DuendeType.RESULT, [inner]);
}

private TypeNode stringDict() {
    return TypeNode.generic(DuendeType.DICT, [T(DuendeType.STRING), T(DuendeType.STRING)]);
}

private BuiltinParam param(string name, BuiltinAccept accept, TypeNode type = TypeNode.init, bool optional = false) {
    BuiltinParam p;
    p.name = name;
    p.accept = accept;
    p.type = type;
    p.optional = optional;
    return p;
}

private BuiltinParam exact(string name, DuendeType base, bool optional = false) {
    return param(name, BuiltinAccept.exact, T(base), optional);
}

private void add(ref BuiltinContract[string] table, BuiltinContract c) {
    if (c.minArgs == 0 && !c.variadic) {
        int required = 0;
        foreach (p; c.params) if (!p.optional) required++;
        c.minArgs = required;
    }
    table[c.name] = c;
}

private BuiltinContract fixedCall(string name, BuiltinParam[] params, TypeNode result, int effect, bool variadic = false, int minArgs = 0) {
    BuiltinContract c;
    c.name = name;
    c.params = params;
    c.retKind = BuiltinReturnKind.fixed;
    c.result = result;
    c.effect = effect;
    c.variadic = variadic;
    c.minArgs = minArgs;
    return c;
}

private void fillBuiltins(ref BuiltinContract[string] table) {
    auto strings = listOf(T(DuendeType.STRING));
    int io = BuiltinEffect.reads | BuiltinEffect.writes | BuiltinEffect.mayFail;
    int readFail = BuiltinEffect.reads | BuiltinEffect.mayFail;

    add(table, fixedCall("print", [param("value", BuiltinAccept.any, TypeNode.init, true)], T(DuendeType.VOID), BuiltinEffect.writes));
    add(table, fixedCall("input", [exact("prompt", DuendeType.STRING, true)], T(DuendeType.STRING), BuiltinEffect.reads | BuiltinEffect.writes));
    add(table, fixedCall("len", [param("value", BuiltinAccept.lenSubject)], T(DuendeType.INT), BuiltinEffect.none));

    BuiltinContract cast_;
    cast_.name = "safeCast";
    cast_.params = [param("target", BuiltinAccept.typeArg), param("value", BuiltinAccept.any)];
    cast_.retKind = BuiltinReturnKind.castResult;
    cast_.effect = BuiltinEffect.mayFail;
    add(table, cast_);

    add(table, fixedCall("osName", [], T(DuendeType.STRING), BuiltinEffect.reads));
    add(table, fixedCall("osVersion", [], T(DuendeType.STRING), BuiltinEffect.reads));
    add(table, fixedCall("cpuArch", [], T(DuendeType.STRING), BuiltinEffect.reads));
    add(table, fixedCall("args", [], strings, BuiltinEffect.reads));
    add(table, fixedCall("sleep", [exact("ms", DuendeType.INT)], T(DuendeType.VOID), BuiltinEffect.writes));
    add(table, fixedCall("fromBytes", [exact("data", DuendeType.BYTES)], T(DuendeType.STRING), BuiltinEffect.none));

    add(table, fixedCall("now", [], T(DuendeType.DATE), BuiltinEffect.reads));
    add(table, fixedCall("utcNow", [], T(DuendeType.DATE), BuiltinEffect.reads));
    add(table, fixedCall("date", [exact("year", DuendeType.INT), exact("month", DuendeType.INT), exact("day", DuendeType.INT)], T(DuendeType.DATE), BuiltinEffect.none));
    add(table, fixedCall("dateTime", [
        exact("year", DuendeType.INT), exact("month", DuendeType.INT), exact("day", DuendeType.INT),
        exact("hour", DuendeType.INT), exact("minute", DuendeType.INT), exact("second", DuendeType.INT)
    ], T(DuendeType.DATE), BuiltinEffect.none));
    add(table, fixedCall("parseDate", [exact("text", DuendeType.STRING)], T(DuendeType.DATE), BuiltinEffect.none));
    add(table, fixedCall("formatDate", [exact("instant", DuendeType.DATE), exact("pattern", DuendeType.STRING)], T(DuendeType.STRING), BuiltinEffect.none));
    add(table, fixedCall("toUTC", [exact("instant", DuendeType.DATE)], T(DuendeType.DATE), BuiltinEffect.none));
    add(table, fixedCall("toLocal", [exact("instant", DuendeType.DATE)], T(DuendeType.DATE), BuiltinEffect.none));
    add(table, fixedCall("toTZ", [exact("instant", DuendeType.DATE), exact("hours", DuendeType.INT), exact("minutes", DuendeType.INT, true)], T(DuendeType.DATE), BuiltinEffect.none));
    foreach (name; ["year", "month", "day", "hour", "minute", "second", "dayOfWeek"]) {
        add(table, fixedCall(name, [exact("instant", DuendeType.DATE)], T(DuendeType.INT), BuiltinEffect.none));
    }
    add(table, fixedCall("daysBetween", [exact("start", DuendeType.DATE), exact("end", DuendeType.DATE)], T(DuendeType.INT), BuiltinEffect.none));
    foreach (name; ["addDays", "addHours", "addMinutes", "addSeconds"]) {
        add(table, fixedCall(name, [exact("instant", DuendeType.DATE), exact("amount", DuendeType.INT)], T(DuendeType.DATE), BuiltinEffect.none));
    }

    add(table, fixedCall("readText", [exact("path", DuendeType.STRING)], resultOf(T(DuendeType.STRING)), readFail));
    add(table, fixedCall("readBytes", [exact("path", DuendeType.STRING)], resultOf(T(DuendeType.BYTES)), readFail));
    add(table, fixedCall("writeText", [exact("path", DuendeType.STRING), exact("text", DuendeType.STRING)], resultOf(T(DuendeType.BOOL)), io));
    add(table, fixedCall("writeBytes", [exact("path", DuendeType.STRING), exact("data", DuendeType.BYTES)], resultOf(T(DuendeType.BOOL)), io));
    add(table, fixedCall("appendText", [exact("path", DuendeType.STRING), exact("text", DuendeType.STRING)], resultOf(T(DuendeType.BOOL)), io));
    add(table, fixedCall("appendBytes", [exact("path", DuendeType.STRING), exact("data", DuendeType.BYTES)], resultOf(T(DuendeType.BOOL)), io));
    add(table, fixedCall("readLines", [exact("path", DuendeType.STRING)], resultOf(strings), readFail));
    add(table, fixedCall("writeLines", [exact("path", DuendeType.STRING), param("lines", BuiltinAccept.exact, strings)], resultOf(T(DuendeType.BOOL)), io));
    add(table, fixedCall("appendLines", [exact("path", DuendeType.STRING), param("lines", BuiltinAccept.exact, strings)], resultOf(T(DuendeType.BOOL)), io));
    add(table, fixedCall("fileExists", [exact("path", DuendeType.STRING)], T(DuendeType.BOOL), BuiltinEffect.reads));
    add(table, fixedCall("dirExists", [exact("path", DuendeType.STRING)], T(DuendeType.BOOL), BuiltinEffect.reads));
    add(table, fixedCall("deleteFile", [exact("path", DuendeType.STRING)], resultOf(T(DuendeType.BOOL)), io));
    add(table, fixedCall("listDir", [exact("path", DuendeType.STRING, true)], resultOf(strings), readFail));
    add(table, fixedCall("makeDir", [exact("path", DuendeType.STRING)], resultOf(T(DuendeType.BOOL)), io));
    add(table, fixedCall("removeDir", [exact("path", DuendeType.STRING)], resultOf(T(DuendeType.BOOL)), io));
    add(table, fixedCall("getCwd", [], resultOf(T(DuendeType.STRING)), readFail));
    add(table, fixedCall("fileSize", [exact("path", DuendeType.STRING)], resultOf(T(DuendeType.INT)), readFail));
    add(table, fixedCall("getMetadata", [exact("path", DuendeType.STRING)], resultOf(stringDict()), readFail));
    add(table, fixedCall("joinPath", [exact("a", DuendeType.STRING), exact("b", DuendeType.STRING)], T(DuendeType.STRING), BuiltinEffect.none, true, 2));

    BuiltinContract abs_;
    abs_.name = "abs";
    abs_.params = [param("x", BuiltinAccept.number)];
    abs_.retKind = BuiltinReturnKind.sameNumber;
    abs_.effect = BuiltinEffect.none;
    add(table, abs_);

    foreach (name; ["min", "max"]) {
        BuiltinContract c;
        c.name = name;
        c.params = [param("a", BuiltinAccept.number), param("b", BuiltinAccept.number)];
        c.retKind = BuiltinReturnKind.widerNumber;
        c.effect = BuiltinEffect.none;
        add(table, c);
    }
    foreach (name; ["floor", "ceil", "round", "sqrt", "log", "exp", "sin", "cos", "tan", "sinDeg", "cosDeg", "tanDeg", "toRadians", "toDegrees"]) {
        add(table, fixedCall(name, [param("x", BuiltinAccept.number)], T(DuendeType.FLOAT), BuiltinEffect.none));
    }
    add(table, fixedCall("pow", [param("base", BuiltinAccept.number), param("exp", BuiltinAccept.number)], T(DuendeType.FLOAT), BuiltinEffect.none));
    add(table, fixedCall("roundTo", [param("x", BuiltinAccept.number), exact("n", DuendeType.INT)], T(DuendeType.FLOAT), BuiltinEffect.none));
    add(table, fixedCall("formatFloat", [param("x", BuiltinAccept.number), exact("n", DuendeType.INT)], T(DuendeType.STRING), BuiltinEffect.none));
}
