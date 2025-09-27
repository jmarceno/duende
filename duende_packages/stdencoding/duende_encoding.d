module duende_packages.stdencoding.duende_encoding;

// Unified encoding helpers exposed to Duende as std.encoding
import std.base64 : Base64;
import std.utf : toUTF8, toUTF16, UTFException;
import std.string : representation, fromStringz, format, strip, toLower;
import std.array : appender, array, join;
import std.conv : to;
import std.algorithm : map, each;
import std.range : chunks;

// Types exposed to Duende runtime: use native D aliases
alias Bytes = immutable(ubyte)[];

// UTF-8
Bytes utf8Encode(string s) {
    // D strings are UTF-8 already; return raw bytes
    return cast(Bytes) (cast(ubyte[]) s.dup);
}

string utf8Decode(Bytes b) {
    // D strings are UTF-8; we assume data is valid UTF-8 and return as string
    return cast(string) b.idup;
}

// UTF-16 Little Endian
Bytes utf16LEEncode(string s) {
    auto w = toUTF16(s); // native endianness
    // Force LE byte order explicitly
    import core.stdc.stdint : uint16_t;
    ubyte[] buf;
    buf.reserve(w.length * 2);
    foreach (wc; w) {
        ushort v = wc;
        ubyte lo = cast(ubyte)(v & 0xFF);
        ubyte hi = cast(ubyte)((v >> 8) & 0xFF);
        buf ~= lo; buf ~= hi; // LE
    }
    return cast(Bytes)buf.idup;
}

string utf16LEDecode(Bytes b) {
    import std.utf : toUTF8;
    // Read pairs as LE
    const size_t n = b.length / 2;
    wchar[] w; w.reserve(n);
    for (size_t i = 0; i + 1 < b.length; i += 2) {
        ushort v = cast(ushort)(b[i] | (b[i+1] << 8));
        w ~= cast(wchar)v;
    }
    return to!string(w);
}

// UTF-16 Big Endian
Bytes utf16BEEncode(string s) {
    auto w = toUTF16(s);
    ubyte[] buf; buf.reserve(w.length * 2);
    foreach (wc; w) {
        ushort v = wc;
        ubyte hi = cast(ubyte)((v >> 8) & 0xFF);
        ubyte lo = cast(ubyte)(v & 0xFF);
        buf ~= hi; buf ~= lo; // BE
    }
    return cast(Bytes)buf.idup;
}

string utf16BEDecode(Bytes b) {
    const size_t n = b.length / 2;
    wchar[] w; w.reserve(n);
    for (size_t i = 0; i + 1 < b.length; i += 2) {
        ushort v = cast(ushort)((b[i] << 8) | b[i+1]);
        w ~= cast(wchar)v;
    }
    return to!string(w);
}

// Base64
string base64Encode(Bytes b) {
    auto enc = Base64.encode(cast(const(ubyte)[])b);
    return cast(string) enc.idup;
}

Bytes base64Decode(string s) {
    auto dec = Base64.decode(cast(const(char)[])s);
    return cast(Bytes) dec.idup;
}

// Hex (lowercase)
string hexEncode(Bytes b) {
    import std.format : format;
    auto buf = appender!string();
    foreach (ubyte x; b) {
        buf.put(format("%02x", x));
    }
    return buf.data;
}

Bytes hexDecode(string s) {
    import std.ascii : isHexDigit, toLower;
    auto clean = s.strip();
    if (clean.length % 2 == 1) {
        // If odd, prefix a 0
        clean = "0" ~ clean;
    }
    ubyte[] buf; buf.reserve(clean.length / 2);
    for (size_t i = 0; i + 1 < clean.length; i += 2) {
        ubyte hi = hexVal(clean[i]);
        ubyte lo = hexVal(clean[i+1]);
        buf ~= cast(ubyte)((hi << 4) | lo);
    }
    return cast(Bytes)buf.idup;
}

private ubyte hexVal(dchar c) {
    import std.ascii : toLower;
    dchar x = toLower(c);
    if (x >= '0' && x <= '9') return cast(ubyte)(x - '0');
    if (x >= 'a' && x <= 'f') return cast(ubyte)(10 + (x - 'a'));
    return 0; // forgiving
}

// Generic conversions
// Convert encoded data (as bytes) from a given encoding label to a string
string convertToString(string encoding, Bytes data) {
    auto e = encoding.toLower();
    if (e == "utf-8" || e == "utf8") return utf8Decode(data);
    if (e == "utf-16le" || e == "utf16le") return utf16LEDecode(data);
    if (e == "utf-16be" || e == "utf16be") return utf16BEDecode(data);
    if (e == "base64" || e == "b64") {
        // Treat bytes as ASCII text
        string txt = cast(string)(cast(char[])data.dup);
        return utf8Decode(base64Decode(txt));
    }
    if (e == "hex") {
        string txt = cast(string)(cast(char[])data.dup);
        return utf8Decode(hexDecode(txt));
    }
    // default: interpret as utf-8
    return utf8Decode(data);
}

// Convert a string to a target encoding and return bytes
Bytes convertToBytes(string encoding, string s) {
    auto e = encoding.toLower();
    if (e == "utf-8" || e == "utf8") return utf8Encode(s);
    if (e == "utf-16le" || e == "utf16le") return utf16LEEncode(s);
    if (e == "utf-16be" || e == "utf16be") return utf16BEEncode(s);
    if (e == "base64" || e == "b64") return cast(Bytes) base64Encode(utf8Encode(s));
    if (e == "hex") return cast(Bytes) hexEncode(utf8Encode(s));
    return utf8Encode(s);
}
