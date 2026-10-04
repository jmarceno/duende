module duende_runtime;

import std.conv : to;
import std.stdio : writeln;

// String addition is concatenation; numeric addition keeps D's native result type.
auto duende_add(L, R)(L left, R right) {
    static if (is(L : const(char)[]) && is(R : const(char)[]))
        return left ~ right;
    else static if (is(L : const(ubyte)[]) && is(R : const(ubyte)[]))
        return left ~ right;
    else
        return left + right;
}

// A character here is a one-byte string slice. Evaluate the index only once.
string duende_char_at(string text, long index) {
    auto start = cast(size_t) index;
    return text[start .. start + 1];
}

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

// One entry from dict.items(). key and value keep the dictionary's types.
struct DictEntry(K, V) {
    K key;
    V value;
}

DictEntry!(K, V)[] duende_dict_items(K, V)(V[K] dict) {
    DictEntry!(K, V)[] result;
    foreach (k, v; dict) {
        result ~= DictEntry!(K, V)(k, v);
    }
    return result;
}

// Missing list elements are None. A stored value, including -1, is Some.
Maybe!(T) duende_list_first(T)(T[] xs) {
    if (xs.length == 0) return Maybe!(T).none();
    return Maybe!(T).some(xs[0]);
}

Maybe!(T) duende_list_last(T)(T[] xs) {
    if (xs.length == 0) return Maybe!(T).none();
    return Maybe!(T).some(xs[$-1]);
}

// A missing dictionary key is None. Indexing that key still aborts.
Maybe!(V) duende_dict_get(K, V)(V[K] dict, K key) {
    auto found = key in dict;
    if (found is null) return Maybe!(V).none();
    return Maybe!(V).some(*found);
}

// Replace one list element. Structs with let fields have no assignment, so those move into the slot.
void duende_list_put(T)(T[] xs, long index, T value) {
    static if (__traits(compiles, { T[] sample = [T.init]; sample[0] = T.init; })) {
        xs[cast(size_t)index] = value;
    } else {
        import core.lifetime : moveEmplace;
        moveEmplace(value, xs[cast(size_t)index]);
    }
}

// Insert or replace one dictionary entry, including structs with let fields.
void duende_dict_put(K, V)(V[K] dict, K key, V value) {
    static if (__traits(compiles, { V[K] sample; sample[K.init] = V.init; })) {
        dict[key] = value;
    } else {
        dict.remove(key);
        static if (__VERSION__ >= 2112) {
            update(dict, key, delegate V() { return value; }, delegate void(ref V slot) {});
        } else {
            // Before 2.112, druntime's update assigns into the new slot, which
            // const members forbid. Ask the runtime for the slot and build it in place.
            import core.lifetime : moveEmplace;
            bool found;
            auto slot = cast(V*) _aaGetX(cast(void**) &dict, typeid(V[K]), V.sizeof, &key, found);
            moveEmplace(value, *slot);
        }
    }
}

static if (__VERSION__ < 2112) {
    private extern (C) void* _aaGetX(void** paa, const TypeInfo_AssociativeArray ti,
        const size_t valsz, const scope void* pkey, out bool found) pure nothrow;
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
