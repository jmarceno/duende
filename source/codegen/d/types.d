module duende.codegen.d.types;

import duende.ast;
import std.string;
import std.conv;

/**
 * Type mapping and utility functions for D code generation.
 * This module contains functions to convert Duende types to D types,
 * and generate helper types like Result and Maybe.
 */
mixin template DTypeMixin() {
    /**
     * Convert a Duende type to its corresponding D type string.
     * 
     * Params:
     *   type = The Duende type to convert
     *   customTypeName = Optional custom type name for struct/frame/enum types
     *   innerType = Inner type for generic types like Result/Maybe
     * 
     * Returns: String representation of the D type
     */
    private string toDType(DuendeType type, string customTypeName = null, DuendeType innerType = DuendeType.VOID) {
    switch (type) {
            case DuendeType.INT: return "long";
            case DuendeType.FLOAT: return "double";
            case DuendeType.STRING: return "string";
            case DuendeType.BOOL: return "bool";
            case DuendeType.BYTES: return "ubyte[]";
            case DuendeType.VOID: return "void";
            case DuendeType.LIST:
                // Map list<T> -> D 'T[]'. For untyped list (no inner/custom), default to string[]
                string elem;
                if (customTypeName && customTypeName.length) {
                    elem = customTypeName;
                } else if (innerType == DuendeType.VOID) {
                    elem = "string";
                } else {
                    elem = toDTypeSimple(innerType);
                    if (!elem.length || elem == "auto" || elem == "void") elem = "string";
                }
                return elem ~ "[]";
            case DuendeType.DICT: return "string[string]";
            case DuendeType.REGEX: return "auto";
            case DuendeType.DATE: return "SysTime";
            case DuendeType.AUTO: return "auto";
            case DuendeType.STRUCT: return customTypeName ? customTypeName : "auto";
            case DuendeType.FRAME: return customTypeName ? customTypeName : "auto";
            case DuendeType.ENUM: return customTypeName ? customTypeName : "auto";
            case DuendeType.PROTOCOL: return customTypeName ? customTypeName : "auto";
            case DuendeType.CUSTOM: return customTypeName ? customTypeName : "auto";
            case DuendeType.RESULT:
                if (customTypeName && customTypeName.length > 0) return "Result!(" ~ customTypeName ~ ")";
                return "Result!(" ~ toDTypeSimple(innerType) ~ ")";
            case DuendeType.MAYBE:
                if (customTypeName && customTypeName.length > 0) return "Maybe!(" ~ customTypeName ~ ")";
                return "Maybe!(" ~ toDTypeSimple(innerType) ~ ")";
            default:
                return "auto";
        }
    }

    /// Overload with defaults
    private string toDType(DuendeType type) {
        return toDType(type, null, DuendeType.VOID);
    }

    /**
     * Render a recursive Duende type, keeping nested generic arguments.
     * int is the signed 64-bit D long.
     */
    private string toDTypeNode(TypeNode node) {
        if (!node.present) return "auto";
        switch (node.base) {
            case DuendeType.INT: return "long";
            case DuendeType.FLOAT: return "double";
            case DuendeType.STRING: return "string";
            case DuendeType.BOOL: return "bool";
            case DuendeType.BYTES: return "ubyte[]";
            case DuendeType.VOID: return "void";
            case DuendeType.LIST:
                if (!node.args.length) return "string[]";
                return toDTypeNode(node.args[0]) ~ "[]";
            case DuendeType.DICT:
                if (node.args.length >= 2)
                    return toDTypeNode(node.args[1]) ~ "[" ~ toDTypeNode(node.args[0]) ~ "]";
                return "string[string]";
            case DuendeType.REGEX: return "auto";
            case DuendeType.DATE: return "SysTime";
            case DuendeType.AUTO: return "auto";
            case DuendeType.STRUCT:
            case DuendeType.FRAME:
            case DuendeType.ENUM:
            case DuendeType.PROTOCOL:
            case DuendeType.CUSTOM:
                return node.name.length ? node.name : "auto";
            case DuendeType.RESULT:
                return wrapNamedGeneric("Result", node);
            case DuendeType.MAYBE:
                return wrapNamedGeneric("Maybe", node);
            default:
                return "auto";
        }
    }

    private string wrapNamedGeneric(string ctor, TypeNode node) {
        string inner;
        if (node.args.length) inner = toDTypeNode(node.args[0]);
        else if (node.name.length) inner = node.name;
        else inner = "auto";
        if (!inner.length || inner == "auto" || inner == "void") return "auto";
        return ctor ~ "!(" ~ inner ~ ")";
    }

    /**
     * Convert a Duende type to a simple D type string without generics.
     * Used for inner types in Result/Maybe declarations.
     */
    private string toDTypeSimple(DuendeType type) {
    switch (type) {
            case DuendeType.INT: return "long";
            case DuendeType.FLOAT: return "double";
            case DuendeType.STRING: return "string";
            case DuendeType.BOOL: return "bool";
            case DuendeType.BYTES: return "ubyte[]";
            case DuendeType.VOID: return "void";
            case DuendeType.LIST: return "string[]"; // simple context lacks inner; keep legacy for nested
            case DuendeType.DICT: return "string[string]";
            case DuendeType.REGEX: return "auto";
            case DuendeType.DATE: return "SysTime";
            case DuendeType.AUTO: return "auto";
            case DuendeType.STRUCT: return "auto";
            case DuendeType.FRAME: return "auto";
            case DuendeType.ENUM: return "auto";
            case DuendeType.PROTOCOL: return "auto";
            case DuendeType.CUSTOM: return "auto";
            case DuendeType.RESULT: return "auto";
            case DuendeType.MAYBE: return "auto";
            default: return "auto";
        }
    }

    /**
     * Payload type of Result!(T) or Maybe!(T). Empty when expected is some other type.
     */
    private string wrapperInner(string expected, string ctor) {
        if (!expected.length) return "";
        string prefix = ctor ~ "!(";
        if (expected.length <= prefix.length + 1) return "";
        if (expected[0 .. prefix.length] != prefix) return "";
        if (expected[$-1] != ')') return "";
        string inner = expected[prefix.length .. $-1];
        if (!inner.length || inner == "auto" || inner == "void") return "";
        return inner;
    }

    /**
     * Type used for Ok/Error or Some/None.
     * The immediate expected type wins. A Result or Maybe function return is the backup
     * so an untyped constructor inside that function still matches the return.
     * With no context, Error is Result!(string) and None is Maybe!(string).
     */
    private string constructorPayload(string expected, string ctor) {
        string inner = wrapperInner(expected, ctor);
        if (!inner.length) inner = wrapperInner(currentFunctionReturnDType, ctor);
        return inner;
    }

    /**
     * Ok/Some with no surrounding wrapper type.
     * An int literal is Duende's signed 64-bit int, not D's 32-bit int.
     * Any other payload is evaluated once and the wrapper uses that value's type.
     */
    private string inferSuccessWrapper(string ctor, string factory, Expression value) {
        if (auto lit = cast(LiteralExpression)value) {
            if (lit.type == DuendeType.INT)
                return ctor ~ "!long." ~ factory ~ "(" ~ generateLiteral(lit) ~ ")";
            if (lit.type == DuendeType.FLOAT)
                return ctor ~ "!double." ~ factory ~ "(" ~ generateLiteral(lit) ~ ")";
        }
        string once = generateExpression(value);
        return "(() { auto __du_payload = " ~ once ~ "; return " ~ ctor ~ "!(typeof(__du_payload))." ~ factory ~ "(__du_payload); })()";
    }

    /**
     * Generate Result constructor expressions from the surrounding type.
     */
    private string generateResultConstructor(ResultConstructorExpression expr, string expected = "") {
        string payloadType = constructorPayload(expected, "Result");
        if (expr.isOk) {
            if (payloadType.length)
                return "Result!(" ~ payloadType ~ ").ok(" ~ generateExpected(payloadType, expr.value) ~ ")";
            return inferSuccessWrapper("Result", "ok", expr.value);
        }
        string err = generateExpression(expr.value);
        if (payloadType.length)
            return "Result!(" ~ payloadType ~ ").error(" ~ err ~ ")";
        return "Result!(string).error(" ~ err ~ ")";
    }

    /**
     * Generate Maybe constructor expressions from the surrounding type.
     */
    private string generateMaybeConstructor(MaybeConstructorExpression expr, string expected = "") {
        string payloadType = constructorPayload(expected, "Maybe");
        if (expr.isSome) {
            if (payloadType.length)
                return "Maybe!(" ~ payloadType ~ ").some(" ~ generateExpected(payloadType, expr.value) ~ ")";
            return inferSuccessWrapper("Maybe", "some", expr.value);
        }
        if (payloadType.length)
            return "Maybe!(" ~ payloadType ~ ").none()";
        return "Maybe!(string).none()";
    }

    /**
     * `subject ? else fallback`.
     * Subject runs once. Fallback is generated in the type expected of this expression
     * and is evaluated by duende_unwrap only on Error or None.
     */
    private string generateUnwrapExpression(UnwrapExpression expr, string expected = "") {
        string subject = generateExpression(expr.result);
        string fallback = generateExpected(expected, expr.defaultValue);
        return "duende_unwrap(" ~ subject ~ ", " ~ fallback ~ ")";
    }

    /**
     * Generate panic expressions for error conditions.
     * Used for unrecoverable errors.
     */
    private string generatePanicExpression(PanicExpression expr) {
        return "(() { assert(false, " ~ generateExpression(expr.message) ~ "); return 0; })()";
    }
}