module duende.packages;

import std.file;
import std.path;
import std.array;
import std.string;
import std.stdio;
import std.process : environment;
import duende.builtins_packages;
import duende.pinned_versions;

struct ModuleMapEntry {
    string duendeModule;
    string[] dImports;
    string[string] aliases;
    string[] helpers;
    string[string] types;
    string[] reexports;
    string packageName;
    string pkgVersion;
    string[string] dubDeps;
    string[string] dubSubConfigs;
}

struct Provider {
    string packageName;
    string pkgVersion;
    ModuleMapEntry entry;
    string basePath;
}

class Packages {
    private string projectDir;
    private bool verbose;
    private Provider[][string] providersByModule;
    private Provider[string] used;

    this(string projectDir, bool verbose) {
        this.projectDir = projectDir;
        this.verbose = verbose;
        discover();
    }

    Provider* resolveModule(string duModule) {
        if (duModule in providersByModule) {
            auto lst = providersByModule[duModule];
            if (lst.length) { used[duModule] = lst[0]; return &used[duModule]; }
        }
        return null;
    }

    Provider[] usedProviders() {
        Provider[] acc;
        foreach (k, p; used) acc ~= p;
        return acc;
    }

    string[] collectHelperSources() {
        string[] acc;
        foreach (p; usedProviders()) {
            foreach (h; p.entry.helpers) {
                auto abs = isAbsolute(h) ? h : buildPath(p.basePath, h);
                if (abs.startsWith("builtin://")) {
                    // Materialize embedded helper to a temp file next to the executable build output
                    // Determine a writable temp dir: use projectDir/duende_build/helpers/<pkg>
                    string outRoot = buildPath(projectDir, "duende_build", "helpers", p.packageName.length ? p.packageName : "embedded");
                    if (!exists(outRoot)) mkdirRecurse(outRoot);
                    string rel = h; // helper path as given in manifest
                    string fname = baseName(rel);
                    string outPath = buildPath(outRoot, fname);
                    // Retrieve embedded contents by re-importing via builtins_packages import mechanism
                    // The EmbeddedProviderSpec stored baseRel and we can reconstruct a path to import content.
                    // However, we don't have raw strings here; so we rely on builtins stringImportPaths to read from duende_packages if present.
                    // As a fallback, we simply skip if file not found (shouldn't happen for embedded stddb).
                    try {
                        // Try to read from "duende_packages/<baseRel>/<helper>" if present (during dev build)
                        string exeDir; try { exeDir = dirName(thisExePath()); } catch (Exception) { exeDir = getcwd(); }
                        string devPath = buildPath(exeDir, "duende_packages", p.entry.packageName == "duende-std-database" ? "stddb" : p.entry.packageName, fname);
                        if (exists(devPath)) {
                            std.file.write(outPath, readText(devPath));
                            acc ~= outPath;
                            continue;
                        }
                    } catch (Exception) {}
                    // If we couldn't locate, skip; providers without helpers will still work.
                    continue;
                }
                if (exists(abs)) acc ~= abs;
            }
        }
        return acc;
    }

    string[string] collectDubDeps() {
        string[string] deps;
        foreach (p; usedProviders()) {
            foreach (k, v; p.entry.dubDeps) {
                if (k in PINNED_DUB_VERSIONS) {
                    deps[k] = PINNED_DUB_VERSIONS[k];
                } else if (k !in deps) {
                    deps[k] = v;
                }
            }
        }
        return deps;
    }

    string[string] collectDubSubConfigs() {
        string[string] sc;
        foreach (p; usedProviders()) {
            foreach (k, v; p.entry.dubSubConfigs) {
                if (k !in sc) sc[k] = v;
            }
        }
        return sc;
    }

    private void discover() {
        // 1) Load embedded providers compiled into the binary
        auto embedded = getEmbeddedProviders();
        foreach (spec; embedded) {
            // Parse manifest from embedded string
            try {
                auto pm = parsePackageTOML(spec.manifestToml);
                // If embedded helpers are present, materialize them to a writable path so they can be compiled
                string materializedBase = "";
                if (spec.helpers.length) {
                    materializedBase = buildPath(projectDir, "duende_build", "embedded_providers", spec.baseRel);
                    try { if (!exists(materializedBase)) mkdirRecurse(materializedBase); } catch (Exception) {}
                    foreach (rel, contents; spec.helpers) {
                        auto outPath = buildPath(materializedBase, rel);
                        try {
                            auto outDir = dirName(outPath);
                            if (!exists(outDir)) mkdirRecurse(outDir);
                            std.file.write(outPath, contents);
                        } catch (Exception we) {
                            if (verbose) writeln("[duende] Failed to write embedded helper ", rel, " for ", spec.baseRel, ": ", we.msg);
                        }
                    }
                }

                Provider p;
                p.packageName = pm.name.length ? pm.name : spec.name;
                p.pkgVersion = pm.pkgVersion;
                // Build providers for each module section
                foreach (duModule, sec; pm.modules) {
                    ModuleMapEntry e;
                    e.duendeModule = duModule;
                    e.dImports = sec.imports.dup;
                    e.aliases = sec.aliases.dup;
                    e.helpers = sec.helpers.dup;
                    e.types = sec.types.dup;
                    e.reexports = sec.reexports.dup;
                    e.packageName = p.packageName;
                    e.pkgVersion = p.pkgVersion;
                    e.dubDeps = pm.dubDependencies.dup;
                    e.dubSubConfigs = pm.dubSubConfigurations.dup;

                    Provider pp;
                    pp.packageName = p.packageName;
                    pp.pkgVersion = p.pkgVersion;
                    pp.entry = e;
                    // Point basePath to the materialized directory if present; otherwise mark as builtin
                    pp.basePath = materializedBase.length ? materializedBase : ("builtin://" ~ spec.baseRel);
                    auto arr = providersByModule.get(duModule, Provider[].init);
                    Provider[] merged; merged ~= pp; foreach (x; arr) merged ~= x;
                    providersByModule[duModule] = merged;
                }
            } catch (Exception e) {
                if (verbose) writeln("[duende] Warning: failed to load embedded provider ", spec.name, ": ", e.msg);
            }
        }

        // 2) Load providers from filesystem next to the executable, if present
        string exeDir;
        try { exeDir = dirName(thisExePath()); } catch (Exception) { exeDir = getcwd(); }
        auto root = buildPath(exeDir, "duende_packages");
        if (!exists(root) || !isDir(root)) return;
        foreach (de; dirEntries(root, SpanMode.shallow)) {
            if (!de.isDir) continue;
            auto manifest = buildPath(de.name, "duende-package.toml");
            if (exists(manifest)) loadManifest(manifest);
        }

        // Debug: list discovered providers when verbose
        if (verbose) {
            writeln("[duende] Providers discovered (modules):");
            foreach (k, v; providersByModule) {
                // Show first provider source (embedded vs filesystem)
                string src = v.length ? v[0].basePath : "";
                writeln("  ", k, " -> count=", v.length, " first.basePath=", src);
            }
        }
    }

    private void loadManifest(string manifestPath) {
        auto pm = parsePackageTOML(readText(manifestPath));
        if (!pm.name.length) { if (verbose) writeln("[duende] Warning: duende-package.toml missing name: ", manifestPath); return; }
        auto base = dirName(absolutePath(manifestPath));
        foreach (duModule, sec; pm.modules) {
            ModuleMapEntry e;
            e.duendeModule = duModule;
            e.dImports = sec.imports.dup;
            e.aliases = sec.aliases.dup;
            e.helpers = sec.helpers.dup;
            e.types = sec.types.dup;
            e.reexports = sec.reexports.dup;
            e.packageName = pm.name;
            e.pkgVersion = pm.pkgVersion;
            e.dubDeps = pm.dubDependencies.dup;
            e.dubSubConfigs = pm.dubSubConfigurations.dup;

            Provider p;
            p.packageName = pm.name;
            p.pkgVersion = pm.pkgVersion;
            p.entry = e;
            p.basePath = base;

            auto arr = providersByModule.get(duModule, Provider[].init);
            Provider[] merged; merged ~= p; foreach (x; arr) merged ~= x;
            providersByModule[duModule] = merged;
        }

        if (verbose) {
            writeln("[duende] Loaded manifest: ", manifestPath);
            foreach (duModule, _; pm.modules) {
                writeln("  provides module: ", duModule);
            }
        }
    }

    // Trace module resolution in verbose mode
    Provider* debugResolve(string duModule) {
        auto p = resolveModule(duModule);
        if (verbose) {
            if (p is null) {
                writeln("[duende] resolveModule('", duModule, "') -> NOT FOUND");
            } else {
                writeln("[duende] resolveModule('", duModule, "') -> ", p.packageName, " (basePath=", p.basePath, ")");
            }
        }
        return p;
    }
}

private struct PackageManifest {
    string name;
    string pkgVersion;
    string description;
    ModuleSection[string] modules;
    string[string] dubDependencies;
    string[string] dubSubConfigurations;
}

private struct ModuleSection {
    string[] imports;
    string[] helpers;
    string[string] aliases;
    string[string] types;
    string[] reexports;
}

private PackageManifest parsePackageTOML(string toml) {
    PackageManifest pm;
    string currentSection;
    string currentModuleKey;
    auto lines = toml.splitLines();

    // Helper: strip quotes from a string and check bracket/brace balance ignoring quoted text
    bool isBalanced(string s, dchar open, dchar close) {
        int bal = 0; bool inStr = false;
        foreach (dchar ch; s) {
            if (ch == '"') { inStr = !inStr; continue; }
            if (inStr) continue;
            if (ch == open) bal++;
            else if (ch == close) bal--;
        }
        return bal <= 0;
    }

    for (size_t i = 0; i < lines.length; ++i) {
        auto line = lines[i].strip();
        if (!line.length) continue;
        if (line[0] == '#') continue;
        if (line[0] == '[' && line[$-1] == ']') {
            currentSection = line[1 .. $-1].strip();
            if (currentSection.startsWith("modules.")) {
                currentModuleKey = currentSection["modules.".length .. $];
                if (!(currentModuleKey in pm.modules)) pm.modules[currentModuleKey] = ModuleSection.init;
            } else { currentModuleKey = null; }
            continue;
        }
        auto eq = indexOfChar(line, '=');
        if (eq < 0) continue;
        auto key = line[0 .. eq].strip();
        auto val = stripInlineComment(line[eq + 1 .. $]);

        if (!currentSection.length) {
            if (key == "name") pm.name = stripQuotes(val.strip());
            else if (key == "version") pm.pkgVersion = stripQuotes(val.strip());
            else if (key == "description") pm.description = stripQuotes(val.strip());
            continue;
        }

        // Collect multi-line arrays and inline tables
        auto collectBalanced = (ref size_t idx, string first, dchar open, dchar close) {
            string acc = first.strip();
            if (!(acc.length && acc[0] == open && acc[$-1] == close) && (acc.length && acc[0] == open)) {
                // Keep consuming lines until balance closes
                while (idx + 1 < lines.length) {
                    idx++;
                    string nxt = stripInlineComment(lines[idx]);
                    acc ~= " " ~ nxt.strip();
                    if (isBalanced(acc, open, close)) break;
                }
            }
            return acc;
        };

        if (currentSection.startsWith("modules.")) {
            auto m = pm.modules.get(currentModuleKey, ModuleSection.init);
            if (key == "imports" || key == "helpers" || key == "reexports") {
                auto acc = collectBalanced(i, val, '[', ']');
                auto arr = parseStringArray(acc);
                if (key == "imports") m.imports = arr;
                else if (key == "helpers") m.helpers = arr;
                else m.reexports = arr;
            } else if (key == "aliases" || key == "types") {
                auto acc = collectBalanced(i, val, '{', '}');
                auto mp = parseInlineTable(acc);
                if (key == "aliases") m.aliases = mp; else m.types = mp;
            } else {
                // Unknown key in module section: ignore
            }
            pm.modules[currentModuleKey] = m;
            continue;
        }
        if (currentSection == "dub") {
            if (key == "dependencies") {
                auto acc = collectBalanced(i, val, '{', '}');
                pm.dubDependencies = parseInlineTable(acc);
            } else if (key == "subConfigurations") {
                auto acc = collectBalanced(i, val, '{', '}');
                pm.dubSubConfigurations = parseInlineTable(acc);
            }
            continue;
        }
    }
    return pm;
}

private int indexOfChar(string s, char c) { foreach (i, ch; s) if (ch == c) return cast(int)i; return -1; }
private string stripInlineComment(string s) {
    bool inStr = false; foreach (i, ch; s) { if (ch == '"') inStr = !inStr; if (!inStr && ch == '#') return s[0 .. i].strip(); } return s.strip();
}
private string stripQuotes(string s) { auto v = s.strip(); if (v.length >= 2 && v[0] == '"' && v[$-1] == '"') return v[1 .. $-1]; return v; }
private string[] parseStringArray(string v) {
    auto s = v.strip(); string[] arr; if (!(s.length >= 2 && s[0] == '[' && s[$-1] == ']')) return arr; s = s[1 .. $-1];
    foreach (part; s.split(',')) { auto p = stripQuotes(part.strip()); if (p.length) arr ~= p; } return arr;
}
private string[string] parseInlineTable(string v) {
    auto s = v.strip(); string[string] map; if (!(s.length >= 2 && s[0] == '{' && s[$-1] == '}')) return map; s = s[1 .. $-1];
    foreach (pair; s.split(',')) { auto p = pair.strip(); if (!p.length) continue; auto eq = indexOfChar(p, '='); if (eq < 0) eq = indexOfChar(p, ':'); if (eq < 0) continue; auto k = stripQuotes(p[0 .. eq].strip()); auto val = stripQuotes(p[eq + 1 .. $].strip()); if (k.length) map[k] = val; } return map;
}

