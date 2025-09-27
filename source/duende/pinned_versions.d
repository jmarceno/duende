module duende.pinned_versions;

/// Centralized pinning of dub dependency versions used by embedded providers.
/// Keys must match the dependency name in provider manifests (e.g., "arsd-official:terminal").
/// Values are exact versions tested with the compiler.
immutable string[string] PINNED_DUB_VERSIONS = [
    // arsd-official umbrella is versioned together; 12.0.0 is what tests use now
    "arsd-official:terminal": "==12.0.0",
    "arsd-official:core": "==12.0.0",
    // Database connector
    "ddbc": "==0.7.0",
    // Vibe.d web framework
    "vibe-d": "==0.10.0",
];
