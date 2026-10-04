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
     * Generate the Result and Maybe type definitions for D code.
     * These are generic types used for error handling and null safety.
     */
    private string generateResultAndMaybeTypes() {
        return q"[
// Result type for error handling
struct Result(T) {
    private bool _isOk;
    private T _value;
    private string _errorMsg;

    static Result!T ok(T value) {
        Result!T result;
        result._isOk = true;
        result._value = value;
        return result;
    }

    static Result!T error(string err) {
        Result!T result;
        result._isOk = false;
        result._errorMsg = err;
        return result;
    }

    @property bool isOk() const { return _isOk; }
    @property bool isError() const { return !_isOk; }
    @property inout(T) value() inout { return _value; }
    @property string errorMessage() const { return _errorMsg; }
}

// Maybe type for null safety
struct Maybe(T) {
    private bool _isSome;
    private T _value;

    static Maybe!T some(T value) {
        Maybe!T result;
        result._isSome = true;
        result._value = value;
        return result;
    }

    static Maybe!T none() {
        Maybe!T result;
        result._isSome = false;
        return result;
    }

    @property bool isSome() const { return _isSome; }
    @property bool isNone() const { return !_isSome; }
    @property T value() const { return _value; }
}

// Helper functions for creating Results
auto duende_ok(T)(T value) {
    return Result!T.ok(value);
}

auto duende_error(T)(string err) {
    return Result!T.error(err);
}

// Helper template for unwrapping values: returns the same type as the default value
auto unwrapValue(R, T)(R result, T defaultValue) {
    static if (__traits(hasMember, R, "isOk")) {
        return result.isOk ? result.value.to!T : defaultValue;
    } else static if (__traits(hasMember, R, "isSome")) {
        return result.isSome ? result.value.to!T : defaultValue;
    } else {
        return defaultValue;
    }
}
]";
    }

    /**
     * Generate Result constructor expressions.
     * Handles both ok and error cases, with context-aware type inference.
     */
    private string generateResultConstructor(ResultConstructorExpression expr) {
        if (expr.isOk) {
            return "Result!(typeof(" ~ generateExpression(expr.value) ~ ")).ok(" ~ generateExpression(expr.value) ~ ")";
        } else {
            // Use the current function's return type context
            if (currentFunctionReturnType == DuendeType.RESULT) {
                string innerTypeName;
                if (currentFunctionReturnNode.present && currentFunctionReturnNode.args.length)
                    innerTypeName = toDTypeNode(currentFunctionReturnNode.args[0]);
                else if (currentFunctionReturnCustomTypeName && currentFunctionReturnCustomTypeName.length)
                    innerTypeName = currentFunctionReturnCustomTypeName;
                else
                    innerTypeName = toDTypeSimple(currentFunctionReturnInnerType);
                return "Result!(" ~ innerTypeName ~ ").error(" ~ generateExpression(expr.value) ~ ")";
            } else {
                // Fallback to string for non-function contexts
                return "Result!(string).error(" ~ generateExpression(expr.value) ~ ")";
            }
        }
    }

    /**
     * Generate Maybe constructor expressions.
     * Handles both Some and None cases, with context-aware type inference.
     */
    private string generateMaybeConstructor(MaybeConstructorExpression expr) {
        if (expr.isSome) {
            return "Maybe!(typeof(" ~ generateExpression(expr.value) ~ ")).some(" ~ 
                   generateExpression(expr.value) ~ ")";
        } else {
            // Use the current function's return type context for None
            if (currentFunctionReturnType == DuendeType.MAYBE) {
                string innerTypeName;
                if (currentFunctionReturnNode.present && currentFunctionReturnNode.args.length)
                    innerTypeName = toDTypeNode(currentFunctionReturnNode.args[0]);
                else if (currentFunctionReturnCustomTypeName && currentFunctionReturnCustomTypeName.length)
                    innerTypeName = currentFunctionReturnCustomTypeName;
                else
                    innerTypeName = toDTypeSimple(currentFunctionReturnInnerType);
                return "Maybe!(" ~ innerTypeName ~ ").none()";
            } else {
                return "Maybe!string.none()";
            }
        }
    }

    /**
     * Generate unwrap expressions for Result/Maybe types.
     * Provides safe access to wrapped values with defaults.
     */
    private string generateUnwrapExpression(UnwrapExpression expr) {
        return "unwrapValue(" ~ generateExpression(expr.result) ~ ", " ~ 
               generateExpression(expr.defaultValue) ~ ")";
    }

    /**
     * Generate panic expressions for error conditions.
     * Used for unrecoverable errors.
     */
    private string generatePanicExpression(PanicExpression expr) {
        return "(() { assert(false, " ~ generateExpression(expr.message) ~ "); return 0; })()";
    }
}