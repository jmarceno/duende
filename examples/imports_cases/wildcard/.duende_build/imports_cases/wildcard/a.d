module imports_cases.wildcard.a;

import std.stdio;
import std.format;


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


// ========= Duende System Helpers =========
// Captured command-line arguments (excluding program name)
__gshared string[] DUENDE_ARGS;

// OS name based on version identifiers
string duende_osName() {
    version(Windows) return "windows";
    version(OSX) return "macos";
    version(iOS) return "ios";
    version(Android) return "android";
    version(linux) return "linux";
    version(FreeBSD) return "freebsd";
    version(OpenBSD) return "openbsd";
    version(NetBSD) return "netbsd";
    version(Posix) return "posix";
    return "unknown";
}

// Try to get a human-friendly OS version string.
string duende_osVersion() {
    import std.string : strip, chomp;
    import std.process : execute;
    version(Windows) {
        auto r = execute(["cmd", "/c", "ver"]); return r.output.chomp.strip();
    }
    version(linux) {
    import std.file : readText;
    import std.string : splitLines, startsWith;
    string osv;
        try {
            auto txt = readText("/etc/os-release");
            foreach (line; splitLines(txt)) {
                if (startsWith(line, "PRETTY_NAME=")) {
                    auto val = line["PRETTY_NAME=".length .. $];
                    if (val.length && val[0] == '"' && val[$-1] == '"') {
                        val = val[1 .. $-1];
                    }
                    osv = val.strip();
                    break;
                }
            }
        } catch (Exception) {
            // ignore and fallback
        }
        if (!osv.length) {
            auto r = execute(["uname", "-sr"]);
            osv = r.output.chomp.strip();
        }
        return osv;
    }
    version(OSX) {
        auto r = execute(["/usr/bin/sw_vers"]); return r.output.chomp.strip();
    }
    version(Posix) {
        auto r = execute(["/bin/sh", "-c", "uname -sr"]); return r.output.chomp.strip();
    }
    return "";
}

// CPU architecture
string duende_cpuArch() {
    version(X86_64) return "x86_64";
    version(X86) return "x86";
    version(AArch64) return "aarch64";
    version(ARM) return "arm";
    version(PPC) return "ppc";
    version(RISCV64) return "riscv64";
    return "unknown";
}
// Expose args as a copy of DUENDE_ARGS
string[] duende_args() {
    return DUENDE_ARGS.dup;
}
// =========================================

void duende_eval(T)(T value) {
    static if (__traits(hasMember, T, "isOk")) {
        if (value.isOk) writeln(value.value); else writeln(value.errorMessage);
    } else static if (__traits(hasMember, T, "isSome")) {
        if (value.isSome) writeln(value.value); else {}
    } else {
        // No-op for other types; keep side-effects if any
    }
}

long foo() {
    return 1;
}

long bar() {
    return 2;
}

