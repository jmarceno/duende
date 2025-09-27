module duende_packages.stdhash.duende_hash;

// Hashing helpers exposed to Duende as std.hash / std.digest
import std.digest.md : MD5;
import std.digest.sha : SHA1, SHA224, SHA256, SHA384, SHA512, SHA512_224, SHA512_256;
import std.digest.crc : CRC32, CRC64_ECMA;
import std.digest.murmurhash : murmurHash3_32;
import std.array : appender;
import std.format : formattedWrite;

// Utility: hex encode digest bytes to lowercase string
private string toHex(const(ubyte)[] data) {
    auto app = appender!string();
    foreach (b; data) {
        formattedWrite(app, "%02x", b);
    }
    return app.data;
}

// MD5 -> hex string
string md5(string s) {
    MD5 ctx; ctx.put(cast(ubyte[])s);
    auto dg = ctx.finish();
    return toHex(dg);
}

// CRC32 -> uint
uint crc32(string s) {
    CRC32 c; c.put(cast(ubyte[])s);
    return c.finish();
}

// CRC64 (ECMA) -> ulong
ulong crc64(string s) {
    CRC64_ECMA c; c.put(cast(ubyte[])s);
    return c.finish();
}

// SHA1..SHA512 family -> hex string
string sha1(string s) {
    SHA1 c; c.put(cast(ubyte[])s); return toHex(c.finish());
}

string sha224(string s) {
    SHA224 c; c.put(cast(ubyte[])s); return toHex(c.finish());
}

string sha256(string s) {
    SHA256 c; c.put(cast(ubyte[])s); return toHex(c.finish());
}

string sha384(string s) {
    SHA384 c; c.put(cast(ubyte[])s); return toHex(c.finish());
}

string sha512(string s) {
    SHA512 c; c.put(cast(ubyte[])s); return toHex(c.finish());
}

string sha512_224(string s) {
    SHA512_224 c; c.put(cast(ubyte[])s); return toHex(c.finish());
}

string sha512_256(string s) {
    SHA512_256 c; c.put(cast(ubyte[])s); return toHex(c.finish());
}

// MurmurHash3 x86 32-bit -> uint; accepts optional seed
uint murmurhash3(string s, uint seed = 0u) {
    return murmurHash3_32(cast(ubyte[])s, seed);
}
