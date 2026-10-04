module duende.codegen.d.expressions;

import duende.ast;
import std.array;
import std.string;
import std.conv;
import std.format;

/**
 * Expression generation for D code.
 * This module handles all types of expressions: literals, binary operations,
 * function calls, method calls, property access, etc.
 */
mixin template DExpressionsMixin() {
    /**
     * Generate D code for any expression.
     * This is the main entry point for expression generation.
     */
    /**
     * Generate an expression that should have the given D type.
     * Empty, auto, and void leave the expression untyped.
     */
    private string generateExpected(string expected, Expression expr) {
        if (!expr) return "";
        if (!expected.length || expected == "auto" || expected == "void")
            return generateExpression(expr);
        string prev = exprExpectedType;
        exprExpectedType = expected;
        string code = generateExpression(expr);
        exprExpectedType = prev;
        return code;
    }

    // expectedNode is the Duende type of this expression. Child expressions opt in.
    private string generateWithNode(TypeNode node, string expected, Expression expr) {
        TypeNode prev = exprExpectedNode;
        exprExpectedNode = node;
        string code = generateExpected(expected, expr);
        exprExpectedNode = prev;
        return code;
    }

    string generateExpression(Expression expr) {
        // The expected type applies to this expression. Nested expressions opt in.
        string expected = exprExpectedType;
        TypeNode expectedNode = exprExpectedNode;
        exprExpectedType = "";
        exprExpectedNode = TypeNode.init;
        if (auto literal = cast(LiteralExpression)expr) {
            return generateLiteral(literal);
        }
        if (auto variable = cast(VariableExpression)expr) {
            if (auto renamed = variable.name in bindingRenames) return *renamed;
            return variable.name;
        }
        if (auto binary = cast(BinaryExpression)expr) {
            return generateBinaryExpression(binary);
        }
        if (auto unary = cast(UnaryExpression)expr) {
            return generateUnaryExpression(unary);
        }
        if (auto call = cast(CallExpression)expr) {
            return generateCallExpression(call);
        }
        // Support pseudo-call form for builtin-like safeCast with first arg as TypeLiteralExpression, via CallExpression handling
        if (auto assignment = cast(AssignmentExpression)expr) {
            string rhsExpected;
            TypeNode rhsNode;
            if (auto viPtr = assignment.variable in variableTypes) {
                rhsExpected = viPtr.dType;
                rhsNode = viPtr.typeNode;
            }
            string rhs = generateWithNode(rhsNode, rhsExpected, assignment.value);
            // If assigning an unqualified enum member to an enum-typed variable, qualify it with the enum name
            if (assignment.variable in variableTypes) {
                auto vi = variableTypes[assignment.variable];
                if (vi.type == DuendeType.CUSTOM && vi.custom.length && (cast(VariableExpression)assignment.value) !is null) {
                    if (auto _ = vi.custom in enumTypes) {
                        if (rhs.indexOf('.') == -1) {
                            rhs = vi.custom ~ "." ~ rhs;
                        }
                    }
                }
            }
            return assignment.variable ~ " = " ~ rhs;
        }
        if (auto propAssignment = cast(PropertyAssignmentExpression)expr) {
            return generateExpression(propAssignment.object) ~ "." ~ propAssignment.property ~ " = " ~ generateExpression(propAssignment.value);
        }
        if (auto indexAssignment = cast(IndexAssignmentExpression)expr) {
            return generateIndexAssignment(indexAssignment);
        }
        if (auto interpolation = cast(StringInterpolationExpression)expr) {
            return generateStringInterpolation(interpolation);
        }
        if (auto index = cast(IndexExpression)expr) {
            return generateExpression(index.object) ~ "[" ~ generateExpression(index.index) ~ "]";
        }
        if (auto property = cast(PropertyExpression)expr) {
            return generatePropertyExpression(property);
        }
        if (auto bytes = cast(BytesLiteralExpression)expr) {
            return generateBytesLiteral(bytes);
        }
        if (auto list = cast(ListLiteralExpression)expr) {
            return generateListLiteral(list, expected, expectedNode);
        }
        if (auto dict = cast(DictLiteralExpression)expr) {
            return generateDictLiteral(dict, expected, expectedNode);
        }
        if (auto method = cast(MethodCallExpression)expr) {
            return generateMethodCall(method);
        }
        if (auto regex = cast(RegexLiteralExpression)expr) {
            return generateRegexLiteral(regex);
        }
        if (auto constructor = cast(ConstructorCallExpression)expr) {
            return generateConstructorCall(constructor);
        }
        if (auto lambda = cast(LambdaExpression)expr) {
            return generateLambdaExpression(lambda);
        }
        if (auto resultConstructor = cast(ResultConstructorExpression)expr) {
            return generateResultConstructor(resultConstructor, expected);
        }
        if (auto maybeConstructor = cast(MaybeConstructorExpression)expr) {
            return generateMaybeConstructor(maybeConstructor, expected);
        }
        if (auto unwrap = cast(UnwrapExpression)expr) {
            return generateUnwrapExpression(unwrap, expected);
        }
        if (auto tryBlock = cast(TryBlockExpression)expr) {
            return generateTryBlockExpression(tryBlock, expected, expectedNode);
        }
        if (auto panic = cast(PanicExpression)expr) {
            return generatePanicExpression(panic);
        }
        if (auto matchExpr = cast(MatchExpression)expr) {
            return generateMatchExpression(matchExpr, expected);
        }
        if (auto castExpr = cast(CastExpression)expr) {
            return generateCastExpression(castExpr);
        }

        return "";
    }

    /**
     * Generate literal values (integers, floats, strings, booleans).
     */
    private string generateLiteral(LiteralExpression literal) {
    switch (literal.type) {
            case DuendeType.INT:
                if (literal.intMinMagnitude) return "0L";
                return to!string(literal.value.get!long) ~ "L";
            case DuendeType.FLOAT:
                {
                    string s = to!string(literal.value.get!double);
                    if (s.indexOf('.') == -1 && s.indexOf('e') == -1 && s.indexOf('E') == -1) {
                        s ~= ".0";
                    }
                    return s;
                }
            case DuendeType.STRING:
                {
                    // Escape backslashes and double quotes for valid D string literal
                    auto raw = literal.value.get!string;
                    auto esc = raw.replace("\\", "\\\\").replace("\"", "\\\"");
                    return `"` ~ esc ~ `"`;
                }
            case DuendeType.BOOL:
                return to!string(literal.value.get!bool);
            case DuendeType.DATE:
                // No date literals; dates are constructed via functions like now(), date(), etc.
                return "";
            case DuendeType.BYTES:
            case DuendeType.VOID:
            case DuendeType.LIST:
            case DuendeType.DICT:
            case DuendeType.REGEX:
            case DuendeType.AUTO:
            case DuendeType.STRUCT:
            case DuendeType.FRAME:
            case DuendeType.ENUM:
            case DuendeType.PROTOCOL:
            case DuendeType.CUSTOM:
            case DuendeType.RESULT:
            case DuendeType.MAYBE:
                return "";
            default:
                return "";
        }
    }

    /**
     * Generate binary expressions (arithmetic, logical, comparison).
     */
    private string generateBinaryExpression(BinaryExpression binary) {
        // Special-case bytes concatenation: use '~' in D
        if (binary.operator == "+") {
            bool leftIsBytes = isBytesExpression(binary.left);
            bool rightIsBytes = isBytesExpression(binary.right);
            if (leftIsBytes || rightIsBytes) {
                return "(" ~ generateExpression(binary.left) ~ " ~ " ~ generateExpression(binary.right) ~ ")";
            }
            return "duende_add(" ~ generateExpression(binary.left) ~ ", " ~ generateExpression(binary.right) ~ ")";
        }
        return "(" ~ generateExpression(binary.left) ~ " " ~
               binary.operator ~ " " ~ generateExpression(binary.right) ~ ")";
    }

    /**
     * Generate unary expressions (negation, logical not).
     */
    private string generateUnaryExpression(UnaryExpression unary) {
        if (unary.operator == "-") {
            if (auto lit = cast(LiteralExpression)unary.operand) {
                if (lit.intMinMagnitude) return "long.min";
            }
        }
        return "(" ~ unary.operator ~ generateExpression(unary.operand) ~ ")";
    }

    /**
     * Generate function calls including built-in functions.
     * This handles print, input, math functions, date/time functions, file I/O, etc.
     */
    private string generateCallExpression(CallExpression call) {
        // Named arguments are placed by the shared binder (the same one semantic analysis validated)
        if (call.argumentNames.canFind!(n => n.length > 0)) {
            if (auto params = call.name in functionSignatures) {
                return generateBoundCall(call, *params);
            }
        }
        Expression[] args = call.arguments;
        // Without names, arguments line up with parameters positionally
        bool argsAligned = true;
        // safeCast(type, value) -> Result!T with strict conversion rules
        if (call.name == "safeCast") {
            if (call.arguments.length != 2) {
                return "Result!(string).error(\"safeCast requires (type, value)\")"; // should not happen
            }
            auto typeArg = call.arguments[0];
            auto valArg = call.arguments[1];
            DuendeType t = DuendeType.AUTO;
            string innerTypeName;
            if (auto tl = cast(TypeLiteralExpression)typeArg) {
                t = tl.type;
                innerTypeName = toDTypeSimple(t);
            } else if (auto ve = cast(VariableExpression)typeArg) {
                // Fallback: allow int/float/string variable names if tracked as types? keep simple for now
                string n = ve.name;
                if (n == "int") t = DuendeType.INT; else if (n == "float") t = DuendeType.FLOAT; else if (n == "string") t = DuendeType.STRING; else if (n == "bool") t = DuendeType.BOOL; else if (n == "bytes") t = DuendeType.BYTES;
                innerTypeName = toDTypeSimple(t);
            }
            requiredImports["std.conv"] = true;
            requiredImports["std.math"] = true;
            string v = generateExpression(valArg);
            switch (t) {
                case DuendeType.INT:
                    return "(() { auto __v = " ~ v ~ "; try { static if (is(typeof(__v) : double) || is(typeof(__v) : float) || is(typeof(__v) : real)) { if (isNaN(__v)) return Result!long.error(\"NaN\"); return Result!long.ok(cast(long)__v); } else if (is(typeof(__v) == string)) { auto __d = __v.to!double; if (isNaN(__d)) return Result!long.error(\"NaN\"); return Result!long.ok(cast(long)__d); } else { return Result!long.ok(__v.to!long); } } catch (Exception e) { return Result!long.error(e.msg); } })()";
                case DuendeType.FLOAT:
                    return "(() { auto __v = " ~ v ~ "; try { static if (is(typeof(__v) == string)) { auto __d = __v.to!double; return Result!double.ok(__d); } else { return Result!double.ok(__v.to!double); } } catch (Exception e) { return Result!double.error(e.msg); } })()";
                case DuendeType.STRING:
                    return "Result!string.ok((" ~ v ~ ").to!string)";
                case DuendeType.BOOL:
                    return "(() { auto __v = " ~ v ~ "; static if (is(typeof(__v) == string)) { return Result!bool.ok(__v == \"true\"); } else static if (is(typeof(__v) : long)) { return Result!bool.ok(__v != 0); } else { return Result!bool.ok((__v).to!bool); } })()";
                case DuendeType.BYTES:
                    return "(() { auto __v = " ~ v ~ "; static if (is(typeof(__v) == string)) { return Result!(ubyte[]).ok(cast(ubyte[])__v); } else { return Result!(ubyte[]).error(\"unsupported\"); } })()";
                default:
                    return "Result!string.error(\"unsupported type\")";
            }
        }
        if (call.name == "len") {
            string obj = call.arguments.length > 0 ? generateExpression(call.arguments[0]) : "";
            return obj ~ ".length.to!long";
        }
        // System built-ins
        if (call.name == "osName") {
            return "duende_osName()";
        }
        if (call.name == "osVersion") {
            return "duende_osVersion()";
        }
        if (call.name == "cpuArch") {
            return "duende_cpuArch()";
        }
        if (call.name == "args") {
            return "duende_args()";
        }
        if (call.name == "print") {
            return generatePrintCall(call);
        }
        if (call.name == "input") {
            return generateInputCall(call);
        }

        // Sleep: sleep(n) where n is milliseconds
        if (call.name == "sleep") {
            string arg = call.arguments.length > 0 ? generateExpression(call.arguments[0]) : "0";
            return "Thread.sleep(dur!(\"msecs\")(" ~ arg ~ "))";
        }

        // Encoding utility as free function: fromBytes(bytes) -> string
        if (call.name == "fromBytes") {
            if (call.arguments.length == 1) {
                return "cast(string)((" ~ generateExpression(call.arguments[0]) ~ ").idup)";
            }
        }

        // std.encoding provider interop: wrap bytes arguments as immutable when required
        // utf8Decode(Bytes), utf16LEDecode(Bytes), utf16BEDecode(Bytes)
        if (call.name == "utf8Decode" || call.name == "utf16LEDecode" || call.name == "utf16BEDecode") {
            if (call.arguments.length == 1) {
                auto a0 = generateExpression(call.arguments[0]);
                return call.name ~ "(cast(immutable(ubyte)[])" ~ a0 ~ ")";
            }
        }
        // base64Encode(Bytes), hexEncode(Bytes)
        if (call.name == "base64Encode" || call.name == "hexEncode") {
            if (call.arguments.length == 1) {
                auto a0 = generateExpression(call.arguments[0]);
                return call.name ~ "(cast(immutable(ubyte)[])" ~ a0 ~ ")";
            }
        }
        // convertToString(string, Bytes) -> ensure 2nd arg immutable bytes
        if (call.name == "convertToString") {
            if (call.arguments.length == 2) {
                auto a0 = generateExpression(call.arguments[0]);
                auto a1 = generateExpression(call.arguments[1]);
                return "convertToString(" ~ a0 ~ ", cast(immutable(ubyte)[])" ~ a1 ~ ")";
            }
        }

        // Date/time builtins
        if (call.name == "now") {
            requiredImports["std.datetime.systime"] = true;
            return "Clock.currTime()";
        }
        if (call.name == "utcNow") {
            requiredImports["std.datetime.systime"] = true;
            requiredImports["std.datetime.timezone"] = true;
            return "Clock.currTime(UTC())";
        }
        if (call.name == "date") {
            requiredImports["std.datetime.systime"] = true;
            requiredImports["std.datetime.date"] = true;
            if (call.arguments.length == 3) {
                auto y = generateExpression(call.arguments[0]);
                auto m = generateExpression(call.arguments[1]);
                auto d = generateExpression(call.arguments[2]);
                return "SysTime(DateTime(" ~ y ~ ", " ~ m ~ ", " ~ d ~ ", 0, 0, 0))";
            }
        }
        if (call.name == "dateTime") {
            requiredImports["std.datetime.systime"] = true;
            requiredImports["std.datetime.date"] = true;
            if (call.arguments.length == 6) {
                auto y = generateExpression(call.arguments[0]);
                auto m = generateExpression(call.arguments[1]);
                auto d = generateExpression(call.arguments[2]);
                auto hh = generateExpression(call.arguments[3]);
                auto mm = generateExpression(call.arguments[4]);
                auto ss = generateExpression(call.arguments[5]);
                return "SysTime(DateTime(" ~ y ~ ", " ~ m ~ ", " ~ d ~ ", " ~ hh ~ ", " ~ mm ~ ", " ~ ss ~ "))";
            }
        }
        if (call.name == "parseDate") {
            requiredImports["std.datetime.systime"] = true;
            if (call.arguments.length >= 1) {
                auto s = generateExpression(call.arguments[0]);
                return "SysTime.fromISOExtString(" ~ s ~ ")";
            }
        }
        if (call.name == "formatDate") {
            requiredImports["std.datetime.systime"] = true;
            if (call.arguments.length == 2) {
                auto dt = generateExpression(call.arguments[0]);
                auto fmt = generateExpression(call.arguments[1]);
                return "duende_formatDate(" ~ dt ~ ", " ~ fmt ~ ")";
            }
        }
        if (call.name == "toUTC") {
            requiredImports["std.datetime.systime"] = true;
            if (call.arguments.length == 1) {
                auto dt = generateExpression(call.arguments[0]);
                return "(" ~ dt ~ ").toUTC()";
            }
        }
        if (call.name == "toLocal") {
            requiredImports["std.datetime.systime"] = true;
            if (call.arguments.length == 1) {
                auto dt = generateExpression(call.arguments[0]);
                return "(" ~ dt ~ ").toLocalTime()";
            }
        }
        if (call.name == "toTZ") {
            requiredImports["std.datetime.systime"] = true;
            requiredImports["std.datetime.timezone"] = true;
            requiredImports["core.time"] = true;
            if (call.arguments.length == 2 || call.arguments.length == 3) {
                auto dt = generateExpression(call.arguments[0]);
                auto h = generateExpression(call.arguments[1]);
                string m = call.arguments.length == 3 ? generateExpression(call.arguments[2]) : "0";
                return "(() { auto __off = hours(" ~ h ~ ") + minutes(" ~ m ~ "); auto __tz = new immutable SimpleTimeZone(__off); return (" ~ dt ~ ").toOtherTZ(__tz); })()";
            }
        }
        if (call.name == "year") {
            requiredImports["std.datetime.systime"] = true;
            auto dt = generateExpression(call.arguments[0]);
            return "cast(long)(" ~ dt ~ ").year";
        }
        if (call.name == "month") {
            requiredImports["std.datetime.systime"] = true;
            auto dt = generateExpression(call.arguments[0]);
            return "cast(long)(cast(int)(" ~ dt ~ ").month)";
        }
        if (call.name == "day") {
            requiredImports["std.datetime.systime"] = true;
            auto dt = generateExpression(call.arguments[0]);
            return "cast(long)(" ~ dt ~ ").day";
        }
        if (call.name == "hour") {
            requiredImports["std.datetime.systime"] = true;
            auto dt = generateExpression(call.arguments[0]);
            return "cast(long)(" ~ dt ~ ").hour";
        }
        if (call.name == "minute") {
            requiredImports["std.datetime.systime"] = true;
            auto dt = generateExpression(call.arguments[0]);
            return "cast(long)(" ~ dt ~ ").minute";
        }
        if (call.name == "second") {
            requiredImports["std.datetime.systime"] = true;
            auto dt = generateExpression(call.arguments[0]);
            return "cast(long)(" ~ dt ~ ").second";
        }
        if (call.name == "dayOfWeek") {
            requiredImports["std.datetime.systime"] = true;
            auto dt = generateExpression(call.arguments[0]);
            return "cast(long)(cast(int)(" ~ dt ~ ").dayOfWeek)";
        }
        if (call.name == "daysBetween") {
            requiredImports["std.datetime.systime"] = true;
            requiredImports["core.time"] = true;
            if (call.arguments.length == 2) {
                auto a = generateExpression(call.arguments[0]);
                auto b = generateExpression(call.arguments[1]);
                return "duende_daysBetween(" ~ a ~ ", " ~ b ~ ")";
            }
        }
        if (call.name == "addDays") {
            requiredImports["std.datetime.systime"] = true;
            requiredImports["core.time"] = true;
            if (call.arguments.length == 2) {
                auto dt = generateExpression(call.arguments[0]);
                auto n = generateExpression(call.arguments[1]);
                return "(" ~ dt ~ ") + dur!(\"days\")(" ~ n ~ ")";
            }
        }
        if (call.name == "addHours") {
            requiredImports["std.datetime.systime"] = true;
            requiredImports["core.time"] = true;
            if (call.arguments.length == 2) {
                auto dt = generateExpression(call.arguments[0]);
                auto n = generateExpression(call.arguments[1]);
                return "(" ~ dt ~ ") + dur!(\"hours\")(" ~ n ~ ")";
            }
        }
        if (call.name == "addMinutes") {
            requiredImports["std.datetime.systime"] = true;
            requiredImports["core.time"] = true;
            if (call.arguments.length == 2) {
                auto dt = generateExpression(call.arguments[0]);
                auto n = generateExpression(call.arguments[1]);
                return "(" ~ dt ~ ") + dur!(\"minutes\")(" ~ n ~ ")";
            }
        }
        if (call.name == "addSeconds") {
            requiredImports["std.datetime.systime"] = true;
            requiredImports["core.time"] = true;
            if (call.arguments.length == 2) {
                auto dt = generateExpression(call.arguments[0]);
                auto n = generateExpression(call.arguments[1]);
                return "(" ~ dt ~ ") + dur!(\"seconds\")(" ~ n ~ ")";
            }
        }

        // Math built-ins
        string castDouble(string e) { return "cast(double)(" ~ e ~ ")"; }
        if (call.name == "toRadians") {
            if (call.arguments.length == 1) {
                auto x = generateExpression(call.arguments[0]);
                requiredImports["std.math"] = true;
                return "toRadians(" ~ castDouble(x) ~ ")";
            }
        }
        if (call.name == "toDegrees") {
            if (call.arguments.length == 1) {
                auto x = generateExpression(call.arguments[0]);
                requiredImports["std.math"] = true;
                return "toDegrees(" ~ castDouble(x) ~ ")";
            }
        }
        if (call.name == "sin") {
            auto x = call.arguments.length > 0 ? generateExpression(call.arguments[0]) : "0.0";
            requiredImports["std.math"] = true;
            return "sin(" ~ castDouble(x) ~ ")";
        }
        if (call.name == "cos") {
            auto x = call.arguments.length > 0 ? generateExpression(call.arguments[0]) : "0.0";
            requiredImports["std.math"] = true;
            return "cos(" ~ castDouble(x) ~ ")";
        }
        if (call.name == "tan") {
            auto x = call.arguments.length > 0 ? generateExpression(call.arguments[0]) : "0.0";
            requiredImports["std.math"] = true;
            return "tan(" ~ castDouble(x) ~ ")";
        }
        if (call.name == "sinDeg") {
            auto x = call.arguments.length > 0 ? generateExpression(call.arguments[0]) : "0.0";
            requiredImports["std.math"] = true;
            return "sinDeg(" ~ castDouble(x) ~ ")";
        }
        if (call.name == "cosDeg") {
            auto x = call.arguments.length > 0 ? generateExpression(call.arguments[0]) : "0.0";
            requiredImports["std.math"] = true;
            return "cosDeg(" ~ castDouble(x) ~ ")";
        }
        if (call.name == "tanDeg") {
            auto x = call.arguments.length > 0 ? generateExpression(call.arguments[0]) : "0.0";
            requiredImports["std.math"] = true;
            return "tanDeg(" ~ castDouble(x) ~ ")";
        }
        if (call.name == "sqrt") {
            auto x = call.arguments.length > 0 ? generateExpression(call.arguments[0]) : "0.0";
            requiredImports["std.math"] = true;
            return "sqrt(" ~ castDouble(x) ~ ")";
        }
        if (call.name == "pow") {
            string a = call.arguments.length > 0 ? generateExpression(call.arguments[0]) : "0.0";
            string b = call.arguments.length > 1 ? generateExpression(call.arguments[1]) : "1.0";
            requiredImports["std.math"] = true;
            return "pow(" ~ castDouble(a) ~ ", " ~ castDouble(b) ~ ")";
        }
        if (call.name == "log") {
            auto x = call.arguments.length > 0 ? generateExpression(call.arguments[0]) : "1.0";
            requiredImports["std.math"] = true;
            return "log(" ~ castDouble(x) ~ ")"; // natural logarithm
        }
        if (call.name == "exp") {
            auto x = call.arguments.length > 0 ? generateExpression(call.arguments[0]) : "0.0";
            requiredImports["std.math"] = true;
            return "exp(" ~ castDouble(x) ~ ")";
        }
        if (call.name == "floor") {
            auto x = call.arguments.length > 0 ? generateExpression(call.arguments[0]) : "0.0";
            requiredImports["std.math"] = true;
            return "floor(" ~ castDouble(x) ~ ")";
        }
        if (call.name == "ceil") {
            auto x = call.arguments.length > 0 ? generateExpression(call.arguments[0]) : "0.0";
            requiredImports["std.math"] = true;
            return "ceil(" ~ castDouble(x) ~ ")";
        }
        if (call.name == "round") {
            auto x = call.arguments.length > 0 ? generateExpression(call.arguments[0]) : "0.0";
            requiredImports["std.math"] = true;
            return "round(" ~ castDouble(x) ~ ")";
        }
        if (call.name == "abs") {
            auto x = call.arguments.length > 0 ? generateExpression(call.arguments[0]) : "0";
            requiredImports["std.math"] = true;
            return "abs(" ~ x ~ ")"; // works for ints and floats
        }
        if (call.name == "roundTo") {
            if (call.arguments.length == 2) {
                auto x = generateExpression(call.arguments[0]);
                auto n = generateExpression(call.arguments[1]);
                requiredImports["std.math"] = true;
                return "roundTo(" ~ castDouble(x) ~ ", " ~ n ~ ")";
            }
        }
        if (call.name == "formatFloat") {
            if (call.arguments.length == 2) {
                auto x = generateExpression(call.arguments[0]);
                auto n = generateExpression(call.arguments[1]);
                requiredImports["std.format"] = true; requiredImports["std.math"] = true;
                return "formatFloat(" ~ castDouble(x) ~ ", " ~ n ~ ")";
            }
        }
        
        // File I/O builtins
        // readText(path) -> Result!string
        if (call.name == "readText") {
            requiredImports["std.file"] = true;
            string p = call.arguments.length > 0 ? generateExpression(call.arguments[0]) : "\"\"";
            return "(() { try { auto __c = std.file.readText(" ~ p ~ "); return Result!string.ok(__c); } catch (Exception e) { return Result!string.error(e.msg); } })()";
        }
        // readBytes(path) -> Result!(ubyte[])
        if (call.name == "readBytes") {
            requiredImports["std.file"] = true;
            string p = call.arguments.length > 0 ? generateExpression(call.arguments[0]) : "\"\"";
            return "(() { try { auto __b = cast(ubyte[])std.file.read(" ~ p ~ "); return Result!(ubyte[]).ok(__b); } catch (Exception e) { return Result!(ubyte[]).error(e.msg); } })()";
        }
        // writeText(path, text) -> Result!bool
        if (call.name == "writeText") {
            requiredImports["std.file"] = true;
            string p = call.arguments.length > 0 ? generateExpression(call.arguments[0]) : "\"\"";
            string s = call.arguments.length > 1 ? generateExpression(call.arguments[1]) : "\"\"";
            return "(() { try { std.file.write(" ~ p ~ ", " ~ s ~ "); return Result!bool.ok(true); } catch (Exception e) { return Result!bool.error(e.msg); } })()";
        }
        // writeBytes(path, bytes) -> Result!bool
        if (call.name == "writeBytes") {
            requiredImports["std.file"] = true;
            string p = call.arguments.length > 0 ? generateExpression(call.arguments[0]) : "\"\"";
            string b = call.arguments.length > 1 ? generateExpression(call.arguments[1]) : "cast(ubyte[])[]";
            return "(() { try { std.file.write(" ~ p ~ ", " ~ b ~ "); return Result!bool.ok(true); } catch (Exception e) { return Result!bool.error(e.msg); } })()";
        }
        // appendText(path, text) -> Result!bool
        if (call.name == "appendText") {
            requiredImports["std.file"] = true;
            string p = call.arguments.length > 0 ? generateExpression(call.arguments[0]) : "\"\"";
            string s = call.arguments.length > 1 ? generateExpression(call.arguments[1]) : "\"\"";
            return "(() { try { std.file.append(" ~ p ~ ", " ~ s ~ "); return Result!bool.ok(true); } catch (Exception e) { return Result!bool.error(e.msg); } })()";
        }
        // appendBytes(path, bytes) -> Result!bool
        if (call.name == "appendBytes") {
            requiredImports["std.file"] = true;
            string p = call.arguments.length > 0 ? generateExpression(call.arguments[0]) : "\"\"";
            string b = call.arguments.length > 1 ? generateExpression(call.arguments[1]) : "cast(ubyte[])[]";
            return "(() { try { std.file.append(" ~ p ~ ", " ~ b ~ "); return Result!bool.ok(true); } catch (Exception e) { return Result!bool.error(e.msg); } })()";
        }
        // readLines(path) -> Result!(string[])
        if (call.name == "readLines") {
            requiredImports["std.file"] = true; requiredImports["std.string"] = true; requiredImports["std.array"] = true;
            string p = call.arguments.length > 0 ? generateExpression(call.arguments[0]) : "\"\"";
            return "(() { try { auto __t = std.file.readText(" ~ p ~ "); auto __ls = __t.splitLines().array; return Result!(string[]).ok(__ls); } catch (Exception e) { return Result!(string[]).error(e.msg); } })()";
        }
        // writeLines(path, string[]) -> Result!bool
        if (call.name == "writeLines") {
            requiredImports["std.file"] = true; requiredImports["std.string"] = true;
            string p = call.arguments.length > 0 ? generateExpression(call.arguments[0]) : "\"\"";
            string arr = call.arguments.length > 1 ? generateExpression(call.arguments[1]) : "cast(string[])[]";
            return "(() { try { string __joined = " ~ arr ~ ".length ? std.array.join(" ~ arr ~ ", \"\\n\") : \"\"; std.file.write(" ~ p ~ ", __joined); return Result!bool.ok(true); } catch (Exception e) { return Result!bool.error(e.msg); } })()";
        }
        // appendLines(path, string[]) -> Result!bool
        if (call.name == "appendLines") {
            requiredImports["std.file"] = true; requiredImports["std.string"] = true; requiredImports["std.array"] = true;
            string p = call.arguments.length > 0 ? generateExpression(call.arguments[0]) : "\"\"";
            string arr = call.arguments.length > 1 ? generateExpression(call.arguments[1]) : "cast(string[])[]";
            return "(() { try { string __joined = " ~ arr ~ ".length ? std.array.join(" ~ arr ~ ", \"\\n\") : \"\"; std.file.append(" ~ p ~ ", __joined); return Result!bool.ok(true); } catch (Exception e) { return Result!bool.error(e.msg); } })()";
        }
        // fileExists(path) -> bool
        if (call.name == "fileExists") {
            requiredImports["std.file"] = true;
            string p = call.arguments.length > 0 ? generateExpression(call.arguments[0]) : "\"\"";
            return "std.file.exists(" ~ p ~ ") && std.file.isFile(" ~ p ~ ")";
        }
        // dirExists(path) -> bool
        if (call.name == "dirExists") {
            requiredImports["std.file"] = true;
            string p = call.arguments.length > 0 ? generateExpression(call.arguments[0]) : "\"\"";
            return "std.file.exists(" ~ p ~ ") && std.file.isDir(" ~ p ~ ")";
        }
        // deleteFile(path) -> Result!bool
        if (call.name == "deleteFile") {
            requiredImports["std.file"] = true;
            string p = call.arguments.length > 0 ? generateExpression(call.arguments[0]) : "\"\"";
            return "(() { try { std.file.remove(" ~ p ~ "); return Result!bool.ok(true); } catch (Exception e) { return Result!bool.error(e.msg); } })()";
        }
        // listDir(path) -> Result!(string[])
        if (call.name == "listDir") {
            requiredImports["std.file"] = true; requiredImports["std.array"] = true;
            string p = call.arguments.length > 0 ? generateExpression(call.arguments[0]) : "\".\"";
            return "(() { import std.file : dirEntries, SpanMode; import std.array : array; try { auto rng = dirEntries(" ~ p ~ ", SpanMode.shallow); string[] names; foreach (e; rng) names ~= e.name; return Result!(string[]).ok(names); } catch (Exception e) { return Result!(string[]).error(e.msg); } })()";
        }
        // makeDir(path) -> Result!bool
        if (call.name == "makeDir") {
            requiredImports["std.file"] = true;
            string p = call.arguments.length > 0 ? generateExpression(call.arguments[0]) : "\"\"";
            return "(() { try { std.file.mkdirRecurse(" ~ p ~ "); return Result!bool.ok(true); } catch (Exception e) { return Result!bool.error(e.msg); } })()";
        }
        // removeDir(path) -> Result!bool (recursive)
        if (call.name == "removeDir") {
            requiredImports["std.file"] = true;
            string p = call.arguments.length > 0 ? generateExpression(call.arguments[0]) : "\"\"";
            return "(() { try { std.file.rmdirRecurse(" ~ p ~ "); return Result!bool.ok(true); } catch (Exception e) { return Result!bool.error(e.msg); } })()";
        }
        // getCwd() -> Result!string
        if (call.name == "getCwd") {
            requiredImports["std.file"] = true;
            return "(() { try { auto __d = std.file.getcwd(); return Result!string.ok(__d); } catch (Exception e) { return Result!string.error(e.msg); } })()";
        }
        // fileSize(path) -> Result!long
        if (call.name == "fileSize") {
            requiredImports["std.file"] = true;
            string p = call.arguments.length > 0 ? generateExpression(call.arguments[0]) : "\"\"";
            return "(() { try { auto __s = std.file.getSize(" ~ p ~ "); return Result!long.ok(cast(long)__s); } catch (Exception e) { return Result!long.error(e.msg); } })()";
        }
        // getMetadata(path) -> Result!(string[string])
        if (call.name == "getMetadata") {
            requiredImports["std.file"] = true; requiredImports["std.conv"] = true;
            string p = call.arguments.length > 0 ? generateExpression(call.arguments[0]) : "\"\"";
            return "(() { try { string[string] m; m[\"isDir\"] = std.file.isDir(" ~ p ~ ").to!string; m[\"isFile\"] = std.file.isFile(" ~ p ~ ").to!string; m[\"size\"] = (cast(long)std.file.getSize(" ~ p ~ ")).to!string; return Result!(string[string]).ok(m); } catch (Exception e) { return Result!(string[string]).error(e.msg); } })()";
        }
        // joinPath(a, b, ...) -> string
        if (call.name == "joinPath") {
            requiredImports["std.path"] = true;
            auto buf = appender!string();
            buf ~= "buildPath(";
            foreach (i, arg; call.arguments) {
                if (i > 0) buf ~= ", ";
                buf ~= generateExpression(arg);
            }
            buf ~= ")";
            return buf.data;
        }
        if (call.name == "min") {
            string a = call.arguments.length > 0 ? generateExpression(call.arguments[0]) : "0";
            string b = call.arguments.length > 1 ? generateExpression(call.arguments[1]) : a;
            return "((" ~ a ~ ") < (" ~ b ~ ") ? (" ~ a ~ ") : (" ~ b ~ "))";
        }
        if (call.name == "max") {
            string a = call.arguments.length > 0 ? generateExpression(call.arguments[0]) : "0";
            string b = call.arguments.length > 1 ? generateExpression(call.arguments[1]) : a;
            return "((" ~ a ~ ") > (" ~ b ~ ") ? (" ~ a ~ ") : (" ~ b ~ "))";
        }

        // Default case: regular function call or constructor call for lowercase type names
        // If the callee name matches a known frame/struct/enum type, treat it as a constructor.
        if (call.name in frameTypes) {
            auto res = appender!string();
            res ~= "new " ~ call.name ~ "(";
            foreach (i, arg; args) { if (i > 0) res ~= ", "; res ~= generateCallArg(call.name, i, arg, argsAligned); }
            res ~= ")";
            return res.data;
        }
        // For structs, constructor is a plain call but ensure it is recognized as a type even if lowercase
        if (call.name in enumTypes) {
            // Enums are not constructible by call; fall through to regular function
        }
        auto result = appender!string();
        result ~= call.name ~ "(";

        foreach (i, arg; args) {
            if (i > 0) result ~= ", ";
            result ~= generateCallArg(call.name, i, arg, argsAligned);
        }

        result ~= ")";
        return result.data;
    }

    /**
     * Argument expression, typed from the callee parameter when the arguments line up.
     */
    private string generateCallArg(string callee, size_t index, Expression arg, bool aligned) {
        string expected;
        if (aligned) {
            if (auto pList = callee in functionSignatures) {
                auto params = *pList;
                if (index < params.length && params[index].type != DuendeType.AUTO)
                    expected = renderParamType(params[index]);
            }
        }
        return generateExpected(expected, arg);
    }

    /**
     * Generate a call to a module function whose arguments use names.
     *
     * Arguments are placed in parameter order. Supplied arguments are evaluated exactly once,
     * left to right in source order, and defaults for skipped parameters are evaluated after
     * them. When parameter order would evaluate side-effecting arguments in a different order,
     * those arguments are first bound to temporaries in source order.
     */
    private string generateBoundCall(CallExpression call, Parameter[] params) {
        auto binding = bindArguments(call.name, params, call.arguments.length, call.argumentNames);
        // Semantic analysis reports binding errors before code generation runs
        assert(binding.ok, "unbound arguments reached code generation for '" ~ call.name ~ "'");

        // Emit up to the last supplied parameter; D fills trailing defaults itself
        long lastNeeded = -1;
        foreach (j, ai; binding.argForParam) if (ai >= 0) lastNeeded = cast(long)j;

        // Documented evaluation order: supplied arguments by source index, then defaults by parameter index
        bool needsTemps = false;
        long prevKey = -1;
        foreach (j; 0 .. cast(size_t)(lastNeeded + 1)) {
            long ai = binding.argForParam[j];
            Expression e = ai >= 0 ? call.arguments[ai] : params[j].defaultValue;
            if (isEffectFreeArgument(e)) continue;
            long key = ai >= 0 ? ai : cast(long)(call.arguments.length + j);
            if (key < prevKey) { needsTemps = true; break; }
            prevKey = key;
        }

        // Arguments are typed from the parameter they bind to
        long[] paramForArg = new long[call.arguments.length];
        foreach (j, ai; binding.argForParam) if (ai >= 0) paramForArg[ai] = cast(long)j;
        string expectedFor(long j) {
            return params[j].type == DuendeType.AUTO ? "" : renderParamType(params[j]);
        }

        string[] argCode;
        argCode.length = call.arguments.length;
        string temps;
        if (needsTemps) {
            int id = ++matchCounter;
            foreach (i, a; call.arguments) {
                string code = generateExpected(expectedFor(paramForArg[i]), a);
                if (isEffectFreeArgument(a)) { argCode[i] = code; continue; }
                string tmp = format("__du_arg_%s_%s", id, i);
                temps ~= "auto " ~ tmp ~ " = " ~ code ~ "; ";
                argCode[i] = tmp;
            }
        } else {
            foreach (i, a; call.arguments) argCode[i] = generateExpected(expectedFor(paramForArg[i]), a);
        }

        string[] parts;
        foreach (j; 0 .. cast(size_t)(lastNeeded + 1)) {
            long ai = binding.argForParam[j];
            parts ~= ai >= 0 ? argCode[ai] : generateExpected(expectedFor(j), params[j].defaultValue);
        }
        string direct = call.name ~ "(" ~ parts.join(", ") ~ ")";
        if (!needsTemps) return direct;
        return "(() { " ~ temps ~ "return " ~ direct ~ "; })()";
    }

    // Literals and plain variable reads cannot observe or cause side effects, so their evaluation order is free
    private bool isEffectFreeArgument(Expression e) {
        if (e is null) return true;
        if (cast(LiteralExpression)e !is null) return true;
        if (cast(VariableExpression)e !is null) return true;
        if (cast(BytesLiteralExpression)e !is null) return true;
        if (auto s = cast(StringInterpolationExpression)e) return s.expressions.length == 0;
        if (auto u = cast(UnaryExpression)e) return (u.operator == "-" || u.operator == "+") && isEffectFreeArgument(u.operand);
        return false;
    }

    /**
     * Generate print function calls.
     */
    private string generatePrintCall(CallExpression call) {
        if (call.arguments.length == 0) {
            return "writeln()";
        }
        return "writeln(" ~ generateExpression(call.arguments[0]) ~ ")";
    }

    /**
     * Generate input function calls with optional prompts.
     */
    private string generateInputCall(CallExpression call) {
        if (call.arguments.length == 0) {
            return "readln().strip()";
        }
        return "(() { write(" ~ generateExpression(call.arguments[0]) ~ "); return readln().strip(); })()";
    }

    /**
     * Generate string interpolation expressions.
     * Handles format strings and date formatting.
     */
    private string generateStringInterpolation(StringInterpolationExpression interpolation) {
        auto result = appender!string();
        result ~= "format(\"";

        // We'll collect transformed arguments separately to allow date-aware formatting
        string[] argExprs;

        for (size_t i = 0; i < interpolation.parts.length; i++) {
            // Escape quotes and percents in literal parts for D format string
            string part = interpolation.parts[i].replace("\\", "\\\\").replace("\"", "\\\"").replace("%", "%%");
            result ~= part;
            if (i < interpolation.expressions.length) {
                string fmt = (interpolation.formats.length > i && interpolation.formats[i].length) ? interpolation.formats[i].strip() : null;
                auto expr = interpolation.expressions[i];
                bool isDate = isDateExpression(expr);
                if (fmt.length && isDate) {
                    // Use "%s" in format string and push pre-formatted date argument
                    result ~= "%s";
                    string f = fmt;
                    if (f.length && f[0] == '%') { /* keep as-is */ } else { f = "%" ~ f; }
                    string fEsc = f.replace("\\", "\\\\").replace("\"", "\\\"");
                    argExprs ~= "duende_formatDate(" ~ generateExpression(expr) ~ ", \"" ~ fEsc ~ "\")";
                } else {
                    if (fmt.length) {
                        if (fmt[0] != '%') fmt = "%" ~ fmt;
                        result ~= fmt;
                    } else {
                        result ~= "%s";
                    }
                    argExprs ~= generateExpression(expr);
                }
            }
        }

        result ~= "\"";
        foreach (arg; argExprs) {
            result ~= ", " ~ arg;
        }

        result ~= ")";
        return result.data;
    }

    /**
     * Generate property access expressions.
     * Handles built-in properties like length, empty, keys, values, etc.
     */
    private string generatePropertyExpression(PropertyExpression property) {
        string obj = generateExpression(property.object);

        switch (property.property) {
            case "length":
                return obj ~ ".length.to!long";
            case "empty":
                return obj ~ ".empty";
            case "hit":
                return obj ~ ".hit";
            case "first":
                // None when the list is empty. A stored -1 or "-1" stays Some.
                return "duende_list_first(" ~ obj ~ ")";
            case "last":
                return "duende_list_last(" ~ obj ~ ")";
            case "keys":
                return obj ~ ".keys";
            case "values":
                return obj ~ ".values";
            default:
                return obj ~ "." ~ property.property;
        }
    }

    /**
     * Generate byte array literals.
     */
    private string generateBytesLiteral(BytesLiteralExpression bytes) {
        auto result = appender!string();
        result ~= "[";
        foreach (i, value; bytes.values) {
            if (i > 0) result ~= ", ";
            result ~= "cast(ubyte)" ~ to!string(value);
        }
        result ~= "]";
        return result.data;
    }

    /**
     * Generate list literals (arrays in D).
     */
    private string generateListLiteral(ListLiteralExpression list, string expected, TypeNode expectedNode) {
        auto result = appender!string();
        TypeNode elementNode;
        string elementType;
        if (expectedNode.present && expectedNode.base == DuendeType.LIST && expectedNode.args.length) {
            elementNode = expectedNode.args[0];
            elementType = toDTypeNode(elementNode);
        } else if (expected.endsWith("[]")) {
            elementType = expected[0 .. $-2];
        }

        if (list.elements.length == 0) {
            string ty = "string[]";
            if (expected.length && expected != "auto" && expected != "void") ty = expected;
            result ~= "(" ~ ty ~ ").init";
            return result.data;
        }
        result ~= "[";
        foreach (i, element; list.elements) {
            if (i > 0) result ~= ", ";
            result ~= generateWithNode(elementNode, elementType, element);
        }
        result ~= "]";
        return result.data;
    }

    /**
     * Generate dictionary literals (associative arrays in D).
     */
    private string generateDictLiteral(DictLiteralExpression dict, string expected, TypeNode expectedNode) {
        auto result = appender!string();
        TypeNode keySlot;
        TypeNode valueSlot;
        if (expectedNode.present && expectedNode.base == DuendeType.DICT) {
            if (expectedNode.args.length >= 2) {
                keySlot = expectedNode.args[0];
                valueSlot = expectedNode.args[1];
            } else {
                keySlot = TypeNode.of(DuendeType.STRING);
                valueSlot = TypeNode.of(DuendeType.STRING);
            }
        }
        if (dict.keys.length == 0) {
            string ty = "string[string]";
            if (expected.length && expected != "auto" && expected != "void") ty = expected;
            result ~= "(" ~ ty ~ ").init";
        } else {
            result ~= "[";
            foreach (i, key; dict.keys) {
                if (i > 0) result ~= ", ";
                result ~= emitInSlot(key, keySlot) ~ ": " ~ emitInSlot(dict.values[i], valueSlot);
            }
            result ~= "]";
        }
        return result.data;
    }

    // A float slot widens an int. Other slots keep the written value's type.
    private string emitInSlot(Expression expr, TypeNode slot) {
        if (!slot.present || slot.unknown || (slot.base == DuendeType.AUTO && !slot.inferred))
            return generateExpression(expr);
        if (slot.base == DuendeType.FLOAT)
            return "cast(double)(" ~ generateExpression(expr) ~ ")";
        return generateWithNode(slot, toDTypeNode(slot), expr);
    }

    private string generateIndexAssignment(IndexAssignmentExpression indexAssignment) {
        TypeNode slot;
        DuendeType collection = DuendeType.VOID;
        if (auto ve = cast(VariableExpression)indexAssignment.object) {
            if (auto viPtr = ve.name in variableTypes) {
                auto node = viPtr.typeNode;
                collection = node.base;
                if (node.base == DuendeType.LIST && node.args.length) slot = node.args[0];
                else if (node.base == DuendeType.DICT && node.args.length >= 2) slot = node.args[1];
                else if (node.base == DuendeType.DICT) slot = TypeNode.of(DuendeType.STRING);
            }
        }
        string value = slot.present ? emitInSlot(indexAssignment.value, slot) : generateExpression(indexAssignment.value);
        string objectCode = generateExpression(indexAssignment.object);
        string indexCode = generateExpression(indexAssignment.index);
        if (collection == DuendeType.LIST)
            return "duende_list_put(" ~ objectCode ~ ", " ~ indexCode ~ ", " ~ value ~ ")";
        if (collection == DuendeType.DICT)
            return "duende_dict_put(" ~ objectCode ~ ", " ~ indexCode ~ ", " ~ value ~ ")";
        return objectCode ~ "[" ~ indexCode ~ "] = " ~ value;
    }

    /**
     * Generate byte array literals from list expressions.
     * Used when a list is assigned to a bytes variable.
     */
    private string generateBytesLiteralFromList(ListLiteralExpression list) {
        auto result = appender!string();
        result ~= "[";
        foreach (i, element; list.elements) {
            if (i > 0) result ~= ", ";
            // Convert the element to an integer and cast to ubyte
            if (auto literal = cast(LiteralExpression)element) {
                if (literal.type == DuendeType.INT) {
                    result ~= "cast(ubyte)" ~ to!string(literal.value.get!long);
                } else {
                    result ~= "cast(ubyte)" ~ generateExpression(element);
                }
            } else {
                result ~= "cast(ubyte)" ~ generateExpression(element);
            }
        }
        result ~= "]";
        return result.data;
    }

    /**
     * Generate regex literals.
     */
    private string generateRegexLiteral(RegexLiteralExpression regex) {
        return format(`std.regex.regex(r"%s")`, regex.pattern);
    }

    /**
     * Generate method calls on objects.
     * Handles string methods, array methods, regex methods, etc.
     */
    private string generateMethodCall(MethodCallExpression method) {
        string obj = generateExpression(method.object);
        bool objIsRegex = isRegexExpression(method.object);
        bool objIsBytes = isBytesExpression(method.object);
        auto argsList = method.arguments;

        switch (method.method) {
            // String APIs
            case "split":
                if (argsList.length == 1) {
                    return "split(" ~ obj ~ ", " ~ generateExpression(argsList[0]) ~ ")";
                }
                break;
            case "join":
                if (argsList.length == 1) {
                    auto arg0 = generateExpression(argsList[0]);
                    return "std.array.join(" ~ obj ~ ", " ~ arg0 ~ ")";
                }
                break;
            case "toUpperCase":
                return "toUpper(" ~ obj ~ ")";
            case "toLowerCase":
                return "toLower(" ~ obj ~ ")";
            case "trim":
                return "strip(" ~ obj ~ ")";
            case "substring":
                if (argsList.length == 2) {
                    return obj ~ "[" ~ generateExpression(argsList[0]) ~ ".." ~ generateExpression(argsList[1]) ~ "]";
                }
                break;
            case "indexOf":
                if (argsList.length == 1) {
                    auto arg0 = generateExpression(argsList[0]);
                    return "(() { auto __i = std.string.indexOf(" ~ obj ~ ", " ~ arg0 ~ "); return (__i < 0 ? -1L : cast(long)__i); })()";
                }
                break;
            case "lastIndexOf":
                if (argsList.length == 1) {
                    auto arg0 = generateExpression(argsList[0]);
                    return "(() { auto __i = std.string.lastIndexOf(" ~ obj ~ ", " ~ arg0 ~ "); return (__i < 0 ? -1L : cast(long)__i); })()";
                }
                break;
            case "startsWith":
                if (argsList.length == 1) {
                    return "startsWith(" ~ obj ~ ", " ~ generateExpression(argsList[0]) ~ ")";
                }
                break;
            case "endsWith":
                if (argsList.length == 1) {
                    return "endsWith(" ~ obj ~ ", " ~ generateExpression(argsList[0]) ~ ")";
                }
                break;
            case "contains":
                if (argsList.length == 1) {
                    return "canFind(" ~ obj ~ ", " ~ generateExpression(argsList[0]) ~ ")";
                }
                break;
            case "matches":
                if (argsList.length == 1) {
                    auto arg0 = generateExpression(argsList[0]);
                    bool arg0IsRegex = isRegexExpression(method.arguments[0]);
                    if (objIsRegex) {
                        return "!matchFirst(" ~ arg0 ~ ", " ~ obj ~ ").empty";
                    } else if (arg0IsRegex) {
                        return "!matchFirst(" ~ obj ~ ", " ~ arg0 ~ ").empty";
                    } else {
                        return "canFind(" ~ obj ~ ", " ~ arg0 ~ ")";
                    }
                }
                break;
            case "toString":
                return obj;
            case "toInt":
                return obj ~ ".to!long";
            case "toFloat":
                return obj ~ ".to!double";
            case "toBool":
                return "(" ~ obj ~ " == \"true\")";
            case "toBytes":
                // Return a mutable byte slice from a string
                return "(cast(ubyte[])(cast(immutable(ubyte)[])(" ~ obj ~ "))).dup";
            case "fromBytes":
                if (method.arguments.length == 1) {
                    return "cast(string)((" ~ generateExpression(method.arguments[0]) ~ ").idup)";
                }
                break;
            case "compare":
                if (argsList.length == 1) {
                    auto arg0 = generateExpression(argsList[0]);
                    return "(() { auto __c = std.string.cmp(" ~ obj ~ ", " ~ arg0 ~ "); return (__c < 0 ? -1L : (__c > 0 ? 1L : 0L)); })()";
                }
                break;
            case "equals":
                if (argsList.length == 1) {
                    return "(" ~ obj ~ " == " ~ generateExpression(argsList[0]) ~ ")";
                }
                break;
            case "notEquals":
                if (argsList.length == 1) {
                    return "(" ~ obj ~ " != " ~ generateExpression(argsList[0]) ~ ")";
                }
                break;
            case "format":
                {
                    auto buf = appender!string();
                    buf ~= "format(" ~ obj;
                    foreach (arg; argsList) {
                        buf ~= ", " ~ generateExpression(arg);
                    }
                    buf ~= ")";
                    return buf.data;
                }
            case "formatNumber":
                {
                    auto buf = appender!string();
                    buf ~= "format(" ~ obj;
                    foreach (arg; argsList) {
                        buf ~= ", " ~ generateExpression(arg);
                    }
                    buf ~= ")";
                    return buf.data;
                }
            case "isEmpty":
                return "(" ~ obj ~ ".length == 0)";
            case "length":
                if (method.arguments.length == 0) {
                    return obj ~ ".length.to!long";
                }
                break;
            case "charAt":
                if (argsList.length == 1) {
                    auto i = generateExpression(argsList[0]);
                    return "duende_char_at(" ~ obj ~ ", " ~ i ~ ")";
                }
                break;
            case "charCodeAt":
                if (argsList.length == 1) {
                    auto i = generateExpression(argsList[0]);
                    return "cast(long)(" ~ obj ~ "[" ~ i ~ "])";
                }
                break;
            case "add":
                if (argsList.length == 1) {
                    // Append preserving element type; caller must pass correct type
                    return obj ~ " ~= " ~ generateExpression(argsList[0]);
                }
                break;
            case "slice":
                if (argsList.length == 2) {
                    return obj ~ "[" ~ generateExpression(argsList[0]) ~
                           ".." ~ generateExpression(argsList[1]) ~ "]";
                }
                break;
            case "sort":
                // In-place sort for lists (string[]). Uses std.algorithm.sorting.sort
                // Returns a SortedRange, which our statement wrapper will ignore; side-effect sorts the array.
                if (method.arguments.length == 0) {
                    requiredImports["std.algorithm.sorting"] = true;
                    return "sort(" ~ obj ~ ")";
                }
                break;
            // Bytes APIs
            case "upper":
                // ASCII uppercase using string helpers, return bytes
                return "(cast(ubyte[])(toUpper(cast(string)" ~ obj ~ "))).dup";
            case "lower":
                return "(cast(ubyte[])(toLower(cast(string)" ~ obj ~ "))).dup";
            case "find":
                if (argsList.length == 1) {
                    auto needle = generateExpression(argsList[0]);
                    return "(() { import std.algorithm.searching : find; auto __du_data = " ~ obj ~ "; auto __du_needle = " ~ needle ~ "; auto __r = find(__du_data, __du_needle); return (__r.length == 0 ? -1L : cast(long)(__r.ptr - __du_data.ptr)); })()";
                }
                break;
            case "has":
                if (argsList.length == 1) {
                    return "(" ~ generateExpression(argsList[0]) ~ " in " ~ obj ~ ") !is null";
                }
                break;
            case "get":
                if (argsList.length == 1) {
                    return "duende_dict_get(" ~ obj ~ ", " ~ generateExpression(argsList[0]) ~ ")";
                }
                break;
            case "items":
                return "duende_dict_items(" ~ obj ~ ")";
            case "test":
                if (argsList.length == 1) {
                    auto arg0 = generateExpression(argsList[0]);
                    if (objIsRegex) {
                        return "!matchFirst(" ~ arg0 ~ ", " ~ obj ~ ").empty";
                    } else {
                        return "!matchFirst(" ~ obj ~ ", " ~ arg0 ~ ").empty";
                    }
                }
                break;
            case "matchFirst":
                if (argsList.length == 1) {
                    auto arg0 = generateExpression(argsList[0]);
                    if (objIsRegex) {
                        return "matchFirst(" ~ arg0 ~ ", " ~ obj ~ ")";
                    } else {
                        return "matchFirst(" ~ obj ~ ", " ~ arg0 ~ ")";
                    }
                }
                break;
            case "matchAll":
                if (argsList.length == 1) {
                    auto arg0 = generateExpression(argsList[0]);
                    if (objIsRegex) {
                        return "matchAll(" ~ arg0 ~ ", " ~ obj ~ ").array";
                    } else {
                        return "matchAll(" ~ obj ~ ", " ~ arg0 ~ ").array";
                    }
                }
                break;
            case "replace":
                if (argsList.length == 2) {
                    auto arg0 = generateExpression(argsList[0]);
                    auto arg1 = generateExpression(argsList[1]);
                    if (objIsRegex) {
                        return "replaceAll(" ~ arg0 ~ ", " ~ obj ~ ", " ~ arg1 ~ ")";
                    } else {
                        return "std.string.replace(" ~ obj ~ ", " ~ arg0 ~ ", " ~ arg1 ~ ")";
                    }
                }
                break;
            default:
                break;
        }

        // Default case: regular method call
        auto result = appender!string();
        result ~= obj ~ "." ~ method.method ~ "(";
        foreach (i, arg; argsList) {
            if (i > 0) result ~= ", ";
            result ~= generateExpression(arg);
        }
        result ~= ")";
        return result.data;
    }

    /**
     * Generate constructor calls for structs and frames.
     */
    private string generateConstructorCall(ConstructorCallExpression constructor) {
        auto result = appender!string();

        // Check if this is a frame (class) type that needs 'new'
        if (constructor.typeName in frameTypes) {
            result ~= "new " ~ constructor.typeName ~ "(";
        } else {
            // Struct constructor
            result ~= constructor.typeName ~ "(";
        }

        foreach (i, arg; constructor.arguments) {
            if (i > 0) result ~= ", ";
            result ~= generateExpression(arg);
        }

        result ~= ")";
        return result.data;
    }

    /**
     * Generate lambda expressions (delegates in D).
     */
    private string generateLambdaExpression(LambdaExpression lambda) {
        auto result = appender!string();

        // Create a delegate with explicit parameter types
        result ~= "delegate(long ";
        foreach (i, param; lambda.parameters) {
            if (i > 0) result ~= ", long ";
            result ~= param;
        }
        result ~= ") { return ";
        result ~= generateExpression(lambda.body);
        result ~= "; }";

        return result.data;
    }

    /**
     * Generate try block expressions.
     */
    private string generateTryBlockExpression(TryBlockExpression expr, string expected, TypeNode expectedNode) {
        auto result = appender!string();
        result ~= "(() {\n";
        indentLevel++;
        // A return inside the closure returns from the closure, not from main
        auto savedEmittingIntMain = emittingIntMain;
        auto savedReturnType = currentFunctionReturnType;
        auto savedReturnInner = currentFunctionReturnInnerType;
        auto savedReturnCustom = currentFunctionReturnCustomTypeName;
        auto savedReturnNode = currentFunctionReturnNode;
        auto savedReturnDType = currentFunctionReturnDType;
        auto savedVariables = variableTypes.dup;
        emittingIntMain = false;
        currentFunctionReturnType = expectedNode.present ? expectedNode.base : DuendeType.AUTO;
        currentFunctionReturnInnerType = DuendeType.VOID;
        currentFunctionReturnCustomTypeName = null;
        currentFunctionReturnNode = expectedNode;
        currentFunctionReturnDType = expected;
        scope(exit) {
            emittingIntMain = savedEmittingIntMain;
            currentFunctionReturnType = savedReturnType;
            currentFunctionReturnInnerType = savedReturnInner;
            currentFunctionReturnCustomTypeName = savedReturnCustom;
            currentFunctionReturnNode = savedReturnNode;
            currentFunctionReturnDType = savedReturnDType;
            variableTypes = savedVariables;
        }
        
        foreach (stmt; expr.statements) {
            result ~= generateStatement(stmt);
        }
        
        indentLevel--;
        result ~= indent() ~ "})()";
        return result.data;
    }

    // Helper methods for expression analysis
    
    /**
     * Check if an expression represents a regex value.
     */
    private bool isRegexExpression(Expression expr) {
        if (cast(RegexLiteralExpression)expr !is null) return true;
        if (auto call = cast(CallExpression)expr) {
            if (call.name == "regex") return true;
        }
        if (auto ve = cast(VariableExpression)expr) {
            if (ve.name in variableTypes) {
                auto vi = variableTypes[ve.name];
                if (vi.type == DuendeType.REGEX) return true;
            }
        }
        return false;
    }

    /**
     * Check if a variable holds a date value.
     */
    private bool isDateVariable(string name) {
        if (name in variableTypes) {
            auto vi = variableTypes[name];
            return vi.type == DuendeType.DATE;
        }
        return false;
    }

    /**
     * Check if a function call produces a date value.
     */
    private bool isDateConstructorCall(CallExpression call) {
        return call.name == "date" || call.name == "dateTime" || call.name == "parseDate" || call.name == "now" || call.name == "utcNow";
    }

    /**
     * Check if an expression represents a date value.
     */
    private bool isDateExpression(Expression expr) {
        if (auto ve = cast(VariableExpression)expr) {
            return isDateVariable(ve.name);
        }
        if (auto call = cast(CallExpression)expr) {
            if (isDateConstructorCall(call)) return true;
            // Methods that return a date
            if (call.name == "toUTC" || call.name == "toLocal" || call.name == "toTZ" || call.name == "addDays" || call.name == "addHours" || call.name == "addMinutes" || call.name == "addSeconds") return true;
        }
        if (auto pe = cast(PropertyExpression)expr) {
            // Heuristic: leave unknown
            return false;
        }
        return false;
    }

    /** Determine if an expression is bytes (ubyte[]) for specialized codegen */
    private bool isBytesExpression(Expression expr) {
        // Byte literals
        if (cast(BytesLiteralExpression)expr !is null) return true;
        // Variable declared as bytes
        if (auto ve = cast(VariableExpression)expr) {
            if (ve.name in variableTypes) {
                return variableTypes[ve.name].type == DuendeType.BYTES;
            }
        }
        // toBytes call on string
        if (auto mc = cast(MethodCallExpression)expr) {
            if (mc.method == "toBytes") return true;
        }
        return false;
    }

    /** Generate explicit type casts: int(x), float(x), string(x) */
    private string generateCastExpression(CastExpression c) {
        string inner = generateExpression(c.value);
        switch (c.targetType) {
            case DuendeType.INT:
                // Be forgiving: if input is NaN, return 0; if string fails to parse, return 0
                // Use static if on typeof to keep code efficient for known types, and accept qualifiers via ':'
                return "(() { auto __x = " ~ inner ~ "; " ~
                       "static if (is(typeof(__x) : double) || is(typeof(__x) : float) || is(typeof(__x) : real)) { " ~
                           "return (isNaN(__x) ? 0L : cast(long)__x); " ~
                       "} else static if (is(typeof(__x) == string)) { " ~
                           "try { auto __d = __x.to!double; return (isNaN(__d) ? 0L : cast(long)__d); } catch(Exception) { return 0L; } " ~
                       "} else { return __x.to!long; } })()";
            case DuendeType.FLOAT:
                return inner ~ ".to!double";
            case DuendeType.STRING:
                return inner ~ ".to!string";
            default:
                // Unsupported target type for now; pass-through
                return inner;
        }
    }
}
