module builtins_packages;

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

    // (simple) intentionally not embedded; used only for tests

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

    // stddb (std.database)
    static if (__traits(compiles, { enum s = import("stddb/duende-package.toml"); })) {
        enum stddbManifest = import("stddb/duende-package.toml");
        // Try to embed helper source if available
        static if (__traits(compiles, { enum h = import("stddb/duende_db.d"); })) {
            enum stddbHelper = import("stddb/duende_db.d");
            string[string] stddbHelpers;
            stddbHelpers["duende_db.d"] = stddbHelper;
            specs ~= EmbeddedProviderSpec(
                "stddb",
                "stddb",
                stddbManifest,
                stddbHelpers
            );
        } else {
            specs ~= EmbeddedProviderSpec(
                "stddb",
                "stddb",
                stddbManifest,
                null
            );
        }
    }

    // stdasync
    static if (__traits(compiles, { enum s = import("stdasync/duende-package.toml"); })) {
        enum stdasyncManifest = import("stdasync/duende-package.toml");
        static if (__traits(compiles, { enum h = import("stdasync/duende_async.d"); })) {
            enum stdasyncHelper = import("stdasync/duende_async.d");
            string[string] stdasyncHelpers; stdasyncHelpers["duende_async.d"] = stdasyncHelper;
            specs ~= EmbeddedProviderSpec("stdasync", "stdasync", stdasyncManifest, stdasyncHelpers);
        } else {
            specs ~= EmbeddedProviderSpec("stdasync", "stdasync", stdasyncManifest, null);
        }
    }

    // stdencoding
    static if (__traits(compiles, { enum s = import("stdencoding/duende-package.toml"); })) {
        enum stdencManifest = import("stdencoding/duende-package.toml");
        static if (__traits(compiles, { enum h = import("stdencoding/duende_encoding.d"); })) {
            enum stdencHelper = import("stdencoding/duende_encoding.d");
            string[string] stdencHelpers; stdencHelpers["duende_encoding.d"] = stdencHelper;
            specs ~= EmbeddedProviderSpec("stdencoding", "stdencoding", stdencManifest, stdencHelpers);
        } else {
            specs ~= EmbeddedProviderSpec("stdencoding", "stdencoding", stdencManifest, null);
        }
    }

    // stdhash (includes std.digest)
    static if (__traits(compiles, { enum s = import("stdhash/duende-package.toml"); })) {
        enum stdhashManifest = import("stdhash/duende-package.toml");
        static if (__traits(compiles, { enum h = import("stdhash/duende_hash.d"); })) {
            enum stdhashHelper = import("stdhash/duende_hash.d");
            string[string] stdhashHelpers; stdhashHelpers["duende_hash.d"] = stdhashHelper;
            specs ~= EmbeddedProviderSpec("stdhash", "stdhash", stdhashManifest, stdhashHelpers);
        } else {
            specs ~= EmbeddedProviderSpec("stdhash", "stdhash", stdhashManifest, null);
        }
    }

    // stdnet
    static if (__traits(compiles, { enum s = import("stdnet/duende-package.toml"); })) {
        enum stdnetManifest = import("stdnet/duende-package.toml");
        static if (__traits(compiles, { enum h = import("stdnet/duende_net.d"); })) {
            enum stdnetHelper = import("stdnet/duende_net.d");
            string[string] stdnetHelpers; stdnetHelpers["duende_net.d"] = stdnetHelper;
            specs ~= EmbeddedProviderSpec("stdnet", "stdnet", stdnetManifest, stdnetHelpers);
        } else {
            specs ~= EmbeddedProviderSpec("stdnet", "stdnet", stdnetManifest, null);
        }
    }

    // stdprocess
    static if (__traits(compiles, { enum s = import("stdprocess/duende-package.toml"); })) {
        enum stdprocManifest = import("stdprocess/duende-package.toml");
        static if (__traits(compiles, { enum h = import("stdprocess/duende_process.d"); })) {
            enum stdprocHelper = import("stdprocess/duende_process.d");
            string[string] stdprocHelpers; stdprocHelpers["duende_process.d"] = stdprocHelper;
            specs ~= EmbeddedProviderSpec("stdprocess", "stdprocess", stdprocManifest, stdprocHelpers);
        } else {
            specs ~= EmbeddedProviderSpec("stdprocess", "stdprocess", stdprocManifest, null);
        }
    }

    // stdxml
    static if (__traits(compiles, { enum s = import("stdxml/duende-package.toml"); })) {
        enum stdxmlManifest = import("stdxml/duende-package.toml");
        static if (__traits(compiles, { enum h = import("stdxml/duende_xml.d"); })) {
            enum stdxmlHelper = import("stdxml/duende_xml.d");
            string[string] stdxmlHelpers; stdxmlHelpers["duende_xml.d"] = stdxmlHelper;
            specs ~= EmbeddedProviderSpec("stdxml", "stdxml", stdxmlManifest, stdxmlHelpers);
        } else {
            specs ~= EmbeddedProviderSpec("stdxml", "stdxml", stdxmlManifest, null);
        }
    }

    // vibed
    static if (__traits(compiles, { enum s = import("vibed/duende-package.toml"); })) {
        enum vibedManifest = import("vibed/duende-package.toml");
        static if (__traits(compiles, { enum h = import("vibed/duende_vibed.d"); })) {
            enum vibedHelper = import("vibed/duende_vibed.d");
            string[string] vibedHelpers; vibedHelpers["duende_vibed.d"] = vibedHelper;
            specs ~= EmbeddedProviderSpec("vibed", "vibed", vibedManifest, vibedHelpers);
        } else {
            specs ~= EmbeddedProviderSpec("vibed", "vibed", vibedManifest, null);
        }
    }

    return specs;
}
