module duende.binding;

import duende.ast;

/**
 * Argument binding for calls to Duende functions.
 *
 * This is the single place that decides which supplied argument feeds which
 * parameter. Semantic analysis reports its errors; code generation consumes
 * its mapping, so the two can never disagree.
 *
 * Rules:
 *   - Named arguments bind to the parameter with that name.
 *   - Positional arguments then fill the remaining parameters left to right.
 *   - Unfilled parameters use their default value; a parameter without a
 *     default must be supplied.
 *   - Every supplied argument must bind to exactly one parameter: unknown
 *     names, a name used twice, and surplus positional arguments are errors.
 */
struct ArgumentBindingError {
    string message;
    // Index of the offending argument in the call, or -1 when the error is about the call as a whole
    long argIndex = -1;
}

struct ArgumentBinding {
    // For each parameter, the index of the supplied argument bound to it, or -1 when its default is used
    long[] argForParam;
    ArgumentBindingError[] errors;

    bool ok() const { return errors.length == 0; }
}

ArgumentBinding bindArguments(string callee, const Parameter[] params, size_t argCount, const string[] argNames) {
    ArgumentBinding b;
    b.argForParam = new long[params.length];
    b.argForParam[] = -1;

    string nameOf(size_t i) { return i < argNames.length ? argNames[i] : ""; }

    // Named arguments first
    foreach (i; 0 .. argCount) {
        auto name = nameOf(i);
        if (!name.length) continue;
        long pi = -1;
        foreach (j, p; params) { if (p.name == name) { pi = cast(long)j; break; } }
        if (pi < 0) {
            b.errors ~= ArgumentBindingError("Unknown named parameter '" ~ name ~ "' for function '" ~ callee ~ "'", cast(long)i);
            continue;
        }
        if (b.argForParam[pi] >= 0) {
            b.errors ~= ArgumentBindingError("Duplicate argument for parameter '" ~ name ~ "' in call to '" ~ callee ~ "'", cast(long)i);
            continue;
        }
        b.argForParam[pi] = cast(long)i;
    }

    // Positional arguments fill the remaining parameters left to right
    size_t slot = 0;
    foreach (i; 0 .. argCount) {
        if (nameOf(i).length) continue;
        while (slot < params.length && b.argForParam[slot] >= 0) slot++;
        if (slot >= params.length) {
            b.errors ~= ArgumentBindingError("Too many arguments in call to '" ~ callee ~ "'", cast(long)i);
            continue;
        }
        b.argForParam[slot++] = cast(long)i;
    }

    foreach (j, p; params) {
        if (b.argForParam[j] < 0 && p.defaultValue is null) {
            b.errors ~= ArgumentBindingError("Missing argument for parameter '" ~ p.name ~ "' in call to '" ~ callee ~ "'", -1);
        }
    }
    return b;
}
