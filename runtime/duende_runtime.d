module duende_runtime;

import std.conv : to;
import std.stdio : writeln;

// One Result and one Maybe for every generated module.
// Importing this module is what keeps wrapper values the same type across source files.

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
    @property inout(T) value() inout { return _value; }
}

// `subject ? else fallback`
// The expression type is the type of the fallback.
// A successful payload is converted to that type with std.conv.to.
// The fallback expression runs only for Error or None, and only once.
// The caller evaluates subject once before entering this template.
auto duende_unwrap(R, T)(R subject, lazy T fallback) {
    static if (__traits(hasMember, R, "isOk")) {
        if (subject.isOk) return subject.value.to!T;
        return fallback;
    } else static if (__traits(hasMember, R, "isSome")) {
        if (subject.isSome) return subject.value.to!T;
        return fallback;
    } else {
        return fallback;
    }
}

void duende_eval(T)(T value) {
    static if (__traits(hasMember, T, "isOk")) {
        if (value.isOk) writeln(value.value); else writeln(value.errorMessage);
    } else static if (__traits(hasMember, T, "isSome")) {
        if (value.isSome) writeln(value.value); else {}
    } else {
    }
}
