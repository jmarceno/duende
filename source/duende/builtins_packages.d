module duende.builtins_packages;

// Embed provider manifests present under duende_packages at compiler build time.
// We use D's string import feature (dub stringImportPaths) to include files as
// strings in the binary so the compiler can register them even when moved.

struct EmbeddedProviderSpec {
    string name;          // logical package name (folder name)
    string baseRel;       // relative base path under duende_packages (same as name)
    string manifestToml;  // contents of duende-package.toml
    string[string] helpers; // optional helper files: relative path -> contents
}

EmbeddedProviderSpec[] getEmbeddedProviders() {
    EmbeddedProviderSpec[] specs;

    // terminal
    static if (__traits(compiles, { enum s = import("terminal/duende-package.toml"); })) {
        enum termManifest = import("terminal/duende-package.toml");
        specs ~= EmbeddedProviderSpec(
            "duende-arsd-terminal",
            "terminal",
            termManifest,
            null
        );
    }

    // simple
    static if (__traits(compiles, { enum s = import("simple/duende-package.toml"); })) {
        enum simpleManifest = import("simple/duende-package.toml");
        specs ~= EmbeddedProviderSpec(
            "simple",
            "simple",
            simpleManifest,
            null
        );
    }

    // stdcsv
    static if (__traits(compiles, { enum s = import("stdcsv/duende-package.toml"); })) {
        enum stdcsvManifest = import("stdcsv/duende-package.toml");
        specs ~= EmbeddedProviderSpec(
            "stdcsv",
            "stdcsv",
            stdcsvManifest,
            null
        );
    }

    // stdjson
    static if (__traits(compiles, { enum s = import("stdjson/duende-package.toml"); })) {
        enum stdjsonManifest = import("stdjson/duende-package.toml");
        specs ~= EmbeddedProviderSpec(
            "stdjson",
            "stdjson",
            stdjsonManifest,
            null
        );
    }

    // stdnet (manifest only; helper on disk)
    static if (__traits(compiles, { enum s = import("stdnet/duende-package.toml"); })) {
        enum stdnetManifest = import("stdnet/duende-package.toml");
        specs ~= EmbeddedProviderSpec(
            "stdnet",
            "stdnet",
            stdnetManifest,
            null
        );
    }

    // stdprocess (manifest only; helper on disk)
    static if (__traits(compiles, { enum s = import("stdprocess/duende-package.toml"); })) {
        enum stdprocManifest = import("stdprocess/duende-package.toml");
        specs ~= EmbeddedProviderSpec(
            "stdprocess",
            "stdprocess",
            stdprocManifest,
            null
        );
    }

    // stdencoding (manifest only; helper on disk)
    static if (__traits(compiles, { enum s = import("stdencoding/duende-package.toml"); })) {
        enum stdencManifest = import("stdencoding/duende-package.toml");
        specs ~= EmbeddedProviderSpec(
            "stdencoding",
            "stdencoding",
            stdencManifest,
            null
        );
    }

    return specs;
}
