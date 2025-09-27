module duende.codegen.d.helpers;

import std.array;
import std.string;

/**
 * Helper functions and runtime support for generated D code.
 * This module contains helper functions that are embedded in the generated
 * D code to support Duende language features.
 */
mixin template DHelpersMixin() {
    /** Generate system helper runtime. Provides osName, osVersion, cpuArch and argv exposure. */
    private string generateSystemHelpers() {
        return q"[
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
]";
    }
    /**
     * Generate date/time helper functions if needed.
     * These are embedded in the generated D code when date/time operations are used.
     */
    private string generateDateTimeHelpers() {
        return q"[
// Simple date formatting helper supporting a subset of strftime-like tokens
string duende_formatDate(SysTime dt, string fmt) {
    import std.array : appender;
    auto buf = appender!string();
    for (size_t i = 0; i < fmt.length; ++i) {
        auto ch = fmt[i];
        if (ch == '%') {
            if (i + 1 >= fmt.length) { buf.put('%'); break; }
            auto t = fmt[++i];
            switch (t) {
                case 'Y': { // year 4-digit, sign if BC
                    buf.put(format("%04d", cast(int)dt.year)); break; }
                case 'm': { // month 01-12
                    buf.put(format("%02d", cast(int)dt.month)); break; }
                case 'd': { // day 01-31
                    buf.put(format("%02d", cast(int)dt.day)); break; }
                case 'H': { // hour 00-23
                    buf.put(format("%02d", cast(int)dt.hour)); break; }
                case 'M': { // minute 00-59
                    buf.put(format("%02d", cast(int)dt.minute)); break; }
                case 'S': { // second 00-59
                    buf.put(format("%02d", cast(int)dt.second)); break; }
                case 'F': { // %Y-%m-%d
                    buf.put(format("%04d-%02d-%02d", cast(int)dt.year, cast(int)dt.month, cast(int)dt.day)); break; }
                case 'T': { // %H:%M:%S
                    buf.put(format("%02d:%02d:%02d", cast(int)dt.hour, cast(int)dt.minute, cast(int)dt.second)); break; }
                case 'z': { // +HH:MM or -HH:MM
                    auto off = dt.utcOffset; // Duration
                    import core.time : dur, hours, minutes;
                    long totalMinutes = off.total!"minutes";
                    char sign = totalMinutes < 0 ? '-' : '+';
                    long absMin = totalMinutes < 0 ? -totalMinutes : totalMinutes;
                    long hh = absMin / 60;
                    long mm = absMin % 60;
                    buf.put(format("%c%02d:%02d", sign, cast(int)hh, cast(int)mm));
                    break; }
                case 'Z': { // 'Z' for UTC else +HH:MM
                    import std.datetime.timezone : UTC;
                    if (dt.timezone is UTC()) {
                        buf.put("Z");
                    } else {
                        auto off = dt.utcOffset;
                        import core.time : dur, hours, minutes;
                        long totalMinutes = off.total!"minutes";
                        char sign = totalMinutes < 0 ? '-' : '+';
                        long absMin = totalMinutes < 0 ? -totalMinutes : totalMinutes;
                        long hh = absMin / 60;
                        long mm = absMin % 60;
                        buf.put(format("%c%02d:%02d", sign, cast(int)hh, cast(int)mm));
                    }
                    break; }
                default: { buf.put('%'); buf.put(t); break; }
            }
        } else {
            buf.put(ch);
        }
    }
    return buf.data;
}

// Days between (a - b) in whole days
long duende_daysBetween(SysTime a, SysTime b) {
    import core.time : days;
    auto diff = a - b; // Duration
    return diff.total!"days";
}
]";
    }

    /**
     * Generate dictionary helper functions if needed.
     * These provide additional dictionary operations for generated D code.
     */
    private string generateDictHelpers() {
        return q"[
struct DictEntry { string key; string value; }
DictEntry[] duende_dict_items(string[string] dict) {
    DictEntry[] result;
    foreach (k, v; dict) {
        result ~= DictEntry(k, v);
    }
    return result;
}
]";
    }

    /**
     * Generate std.math-style helpers that are not directly in D's std.math.
     * Exposed as free functions: toRadians, toDegrees, sinDeg, cosDeg, tanDeg,
     * roundTo, formatFloat.
     */
    private string generateStdMathHelpers() {
        return q"[
// Degree/radian conversion
double toRadians(double deg) { import std.math : PI; return deg * PI / 180.0; }
double toDegrees(double rad) { import std.math : PI; return rad * 180.0 / PI; }

// Trigonometry in degrees
double sinDeg(double deg) { import std.math : sin, PI; return sin(deg * PI / 180.0); }
double cosDeg(double deg) { import std.math : cos, PI; return cos(deg * PI / 180.0); }
double tanDeg(double deg) { import std.math : tan, PI; return tan(deg * PI / 180.0); }

// Round to N decimals
double roundTo(double x, long n) {
    import std.math : pow, round;
    auto s = pow(10.0, cast(double)n);
    return round(x * s) / s;
}

// Format float to N decimals
string formatFloat(double x, long n) {
    import std.format : format;
    return format("%.*f", cast(int)n, x);
}
]";
    }

    /**
     * Generate expression evaluation helper.
     * This handles automatic printing of expression results in the REPL-style environment.
     */
    private string generateEvalHelper() {
        return q"[
void duende_eval(T)(T value) {
    static if (__traits(hasMember, T, "isOk")) {
        if (value.isOk) writeln(value.value); else writeln(value.errorMessage);
    } else static if (__traits(hasMember, T, "isSome")) {
        if (value.isSome) writeln(value.value); else {}
    } else {
        // No-op for other types; keep side-effects if any
    }
}
]";
    }
}