module duende.compiler;

import std.stdio;
import std.getopt;
import std.file;
import std.path;
import std.process;
import std.string;
import std.algorithm;
import std.array;
import std.range;

import duende.lexer;
import duende.parser;
import duende.ast;
import duende.codegen_package;
import duende.dub_integration;
import duende.packages;
import duende.buildinfo;
import duende.semantic : analyzeModule, SemanticError, SemanticErrorCollector;
import std.datetime.stopwatch;
import core.time : Duration; // for timing values
import std.conv : to;

// Terminal coloring for CLI output
static import arsd.terminal;

private class TermUI {
    arsd.terminal.Terminal* term;
    bool isTty;

    this() {
        if (arsd.terminal.Terminal.stdoutIsTerminal()) {
            auto t = new arsd.terminal.Terminal(arsd.terminal.ConsoleOutputType.linear);
            this.term = t;
            this.isTty = true;
        } else {
            this.term = null;
            this.isTty = false;
        }
    }

    void plain(string msg) { writeln(msg); }
    void info(string msg) {
        if (!isTty) { writeln(msg); return; }
        term.color(arsd.terminal.Color.DEFAULT, arsd.terminal.Color.DEFAULT);
        term.writeln(msg);
        term.flush();
    }
    void success(string msg) {
        if (!isTty) { writeln(msg); return; }
        term.color(arsd.terminal.Color.green, arsd.terminal.Color.DEFAULT);
        term.writeln(msg);
        term.color(arsd.terminal.Color.DEFAULT, arsd.terminal.Color.DEFAULT);
        term.flush();
    }
    void warn(string msg) {
        if (!isTty) { writeln(msg); return; }
        term.color(arsd.terminal.Color.yellow, arsd.terminal.Color.DEFAULT);
        term.writeln(msg);
        term.color(arsd.terminal.Color.DEFAULT, arsd.terminal.Color.DEFAULT);
        term.flush();
    }
    void error(string msg) {
        if (!isTty) { writeln(msg); return; }
        term.color(arsd.terminal.Color.red, arsd.terminal.Color.DEFAULT);
        term.writeln(msg);
        term.color(arsd.terminal.Color.DEFAULT, arsd.terminal.Color.DEFAULT);
        term.flush();
    }
    void header(string msg) {
        if (!isTty) { writeln(msg); return; }
        term.bold(true);
        term.writeln(msg);
        term.bold(false);
        term.flush();
    }
}

class CompilerError : Exception {
    this(string msg, string file = __FILE__, size_t line = __LINE__) {
        super(msg, file, line);
    }
}

// Semantic error types are imported from duende.semantic

void main(string[] args) {
    bool verbose = false;
    bool printAst = false;
    bool printTokens = false;
    bool runAfterCompile = false;
    bool optimize = false;
    bool emitD = false;
    string outputFile = "";
    string targetLang = "d";
    string compilerChoice = "dmd"; // dmd (default) or ldc

    // Preserve original argv for manual scans because getopt mutates args
    auto argv = args.dup;

    auto helpInfo = getopt(
        args,
        "verbose|v", "Enable verbose output", &verbose,
        "ast", "Print AST and exit", &printAst,
        "tokens", "Print tokens and exit", &printTokens,
        "run|r", "Compile and run the executable", &runAfterCompile,
        "optimize|O", "Enable optimization (-O2 for dmd)", &optimize,
        "output|o", "Output file name", &outputFile,
        "target|t", "Target language (d)", &targetLang,
        "compiler", "D compiler to use: dmd (default) or ldc", &compilerChoice,
        "emit-d", "Generate D code and print module mappings, then exit", &emitD
    );

    if (helpInfo.helpWanted) {
        defaultGetoptPrinter("Duende Compiler", helpInfo.options);
        return;
    }

    // Fallback parse for -o/--output regardless of position using the original argv
    if (!outputFile.length) {
        foreach (i; 1 .. argv.length) {
            auto a = argv[i];
            if (a == "-o" || a == "--output") {
                if (i + 1 < argv.length) {
                    outputFile = argv[i + 1];
                }
                break;
            }
            // Support --output=NAME form
            if (a.startsWith("--output=") && a.length > 9) {
                outputFile = a[9 .. $];
                break;
            }
            // Support -oNAME short form
            if (a.length > 2 && a[0] == '-' && a[1] == 'o') {
                outputFile = a[2 .. $];
                break;
            }
        }
    }

    // Determine source file: first positional ending with .du or .duende
    string sourceFile = "";
    foreach (i; 1 .. args.length) {
        auto a = args[i];
        if (a.length && a[0] != '-') {
            if (a.endsWith(".du") || a.endsWith(".duende")) {
                sourceFile = a;
                break;
            }
        }
    }
    if (!sourceFile.length) {
        if (args.length >= 2) sourceFile = args[1];
    }
    if (!sourceFile.length) {
        writeln("Usage: duende [options] <source-file>");
        writeln("Use --help for more options");
        return;
    }

    if (!exists(sourceFile)) {
        writefln("Error: Source file '%s' not found", sourceFile);
        return;
    }

    auto ui = new TermUI();
    try {
        // Normalize compiler choice
        compilerChoice = compilerChoice.strip.toLower();
        if (compilerChoice != "dmd" && compilerChoice != "ldc") {
            throw new CompilerError("Invalid --compiler value: '" ~ compilerChoice ~ "'. Expected 'dmd' or 'ldc'.");
        }

        // Build the module graph and compile all modules together
        string absSource = absolutePath(sourceFile);
        // Build output next to the entry source file (what tests expect)
        string buildBaseDir = dirName(absSource);
    string outputDir = buildPath(buildBaseDir, "duende_build");
        if (!exists(outputDir)) mkdirRecurse(outputDir);

        // Determine module root: if compiling something under an 'examples' tree,
        // treat that 'examples' dir as the project root so absolute imports like
        // 'imports_cases.wildcard.a' resolve from there. Otherwise, default to
        // the directory of the entry source file.
        string projectDir = buildBaseDir;
        {
            string cur = buildBaseDir;
            while (cur.length && cur != dirName(cur)) {
                if (baseName(cur) == "examples") { projectDir = cur; break; }
                cur = dirName(cur);
            }
        }

    // Initialize packages discovery for external providers (std/third-party)
    auto packages = new Packages(projectDir, verbose);
    auto graph = new ModuleGraph(projectDir, outputDir, verbose, packages);
        auto swTranspile = StopWatch(AutoStart.yes);
    auto entry = graph.addEntry(sourceFile);
    graph.resolveAll();

        // Perform semantic validation on all modules
        auto semanticErrors = new SemanticErrorCollector();
        foreach (mod; graph.order) {
            auto info = graph.modules[mod];
            // Set file path in source positions for this module
            string currentFile = info.sourcePath;
            
            validateModuleSemantics(info, semanticErrors);
        }
        
        // If there are semantic errors, report them and exit
        if (semanticErrors.hasErrors()) {
            semanticErrors.reportAll();            
            throw new CompilerError("Semantic validation failed: " ~ semanticErrors.errors.length.to!string ~ " error(s)");
        }

        // Optional debug outputs
        if (printTokens || printAst) {
            // Re-lex/parse the entry file and print
            auto code = std.file.readText(sourceFile);
            auto lx = new Lexer(code);
            auto toks = lx.tokenize();
            if (printTokens) {
                foreach (t; toks) {
                    writeln(t.line, ":", t.column, " ", t.type, " ", t.value);
                }
                return;
            }
            if (printAst) {
                auto ps2 = new Parser(toks);
                auto prog2 = ps2.parse();
                printProgram(prog2);
                return;
            }
        }

        // Generate D sources for each module
        string[string] moduleDPaths; // moduleName -> path
        foreach (mod; graph.order) {
            auto info = graph.modules[mod];
            auto code = graph.generateModuleD(info);
            // Write under directory structure matching the module name
            auto parts = info.moduleName.split(".");
            string modDir = outputDir;
            if (parts.length > 1) {
                modDir = buildPath(outputDir, buildPath(parts[0 .. $-1]));
                if (!exists(modDir)) mkdirRecurse(modDir);
            }
            string dFile = parts[$-1] ~ ".d";
            string dPath = buildPath(modDir, dFile);
            std.file.write(dPath, code);
            moduleDPaths[info.moduleName] = dPath;
            if (verbose) writefln("Generated %s -> %s", info.moduleName, dPath);
        }
    swTranspile.stop();
    auto transpileDur = swTranspile.peek;

        // Handle --emit-d flag: print module mappings and exit
        if (emitD) {
            foreach (moduleName, dPath; moduleDPaths) {
                writefln("%s => %s", moduleName, dPath);
            }
            return;
        }

        // Decide build path: if providers declare dub deps, synthesize a temp dub project; else compile directly with dmd
        string exeStem = stripExtension(baseName(sourceFile));
        // Determine final executable output path according to -o rules
        // Rules:
        // - default: build to outputDir/<exeStem>
        // - -o .   : place the executable next to the duende compiler binary
        // - -o <dir>: if path looks like a directory (absolute or contains a path sep), place <exeStem> inside it
        // - -o <name>: treat as filename inside outputDir
        string executablePath;
        if (outputFile.length) {
            bool looksLikeDir = outputFile.canFind("/");
            string exeDir;
            if (outputFile == ".") {
                // Same directory as the duende compiler
                try {
                    exeDir = dirName(thisExePath());
                } catch (Exception) {
                    exeDir = getcwd();
                }
                if (!exists(exeDir)) mkdirRecurse(exeDir);
                executablePath = buildPath(exeDir, exeStem);
            } else if (isAbsolute(outputFile) || looksLikeDir || (exists(outputFile) && isDir(outputFile))) {
                // Treat as a directory path
                string dirPath = isAbsolute(outputFile) ? outputFile : buildPath(getcwd(), outputFile);
                if (!exists(dirPath)) mkdirRecurse(dirPath);
                executablePath = buildPath(dirPath, exeStem);
            } else {
                // Treat as a filename inside default outputDir
                if (!exists(outputDir)) mkdirRecurse(outputDir);
                executablePath = buildPath(outputDir, outputFile);
            }
        } else {
            executablePath = buildPath(outputDir, exeStem);
        }
    auto helperSources = packages.collectHelperSources();
    auto providerDubDeps = packages.collectDubDeps();
    auto providerDubSubCfgs = packages.collectDubSubConfigs();
    // Allow overriding ddbc subConfiguration via env var for easy driver selection
    try {
        import std.process : environment;
        string overrideCfg = environment.get("DUENDE_DDBC_SUBCONFIG", "");
        if (overrideCfg.length) {
            providerDubSubCfgs["ddbc"] = overrideCfg;
        }
    } catch (Exception) {
        // ignore env issues
    }
    // Detect if the user's project has a dub.sdl/json next to the entry source
    bool userHasDub = DubIntegration.hasDubFile(buildBaseDir);

        Duration compileDuration;
        if (userHasDub) {
            if (verbose) {
                ui.info("[duende] Found user's dub configuration; building via dub (with merged provider deps if any)...");
            }
            auto swCompile = StopWatch(AutoStart.yes);
            string exe = DubIntegration.buildTempDubFromUserConfig(
                outputDir,
                exeStem,
                moduleDPaths.values,
                helperSources,
                buildBaseDir,
                providerDubDeps,
                providerDubSubCfgs,
                optimize,
                compilerChoice
            );
            compileDuration = swCompile.peek;
            if (exists(executablePath)) remove(executablePath);
            copy(exe, executablePath);
            version (Posix) {
                import core.sys.posix.sys.stat; 
                import std.string : toStringz;
                stat_t st;
                if (stat(executablePath.toStringz, &st) == 0) {
                    mode_t newMode = st.st_mode | S_IXUSR;
                    chmod(executablePath.toStringz, newMode);
                } else {
                    execute(["chmod", "+x", executablePath]);
                }
            }
        } else if (providerDubDeps.length) {
            if (verbose) {
                ui.info("[duende] Building via dub due to provider dependencies...");
                foreach (k, v; providerDubDeps) ui.info("  dub dep " ~ k ~ " = " ~ v);
            }
            // Build a temp dub project including generated files and helper sources
            auto swCompile = StopWatch(AutoStart.yes);
            string exe = DubIntegration.buildTempDubWithSources(
                outputDir,
                exeStem,
                moduleDPaths.values,
                helperSources,
                providerDubDeps,
                providerDubSubCfgs,
                optimize,
                compilerChoice
            );
            compileDuration = swCompile.peek;
            // Copy/move the built exe next to expected path for tests
            if (exists(executablePath)) remove(executablePath);
            copy(exe, executablePath);
            version (Posix) {
                import core.sys.posix.sys.stat; // brings in stat_t, mode_t, S_IXUSR, stat, chmod
                import std.string : toStringz;
                // Read current mode and set owner-executable bit
                stat_t st;
                if (stat(executablePath.toStringz, &st) == 0) {
                    mode_t newMode = st.st_mode | S_IXUSR;
                    chmod(executablePath.toStringz, newMode);
                } else {
                    // Fallback
                    execute(["chmod", "+x", executablePath]);
                }
            }
        } else {
            string compilerExe = (compilerChoice == "ldc") ? "ldc2" : "dmd";
            if (verbose) ui.info("Compiling with " ~ compilerExe ~ "...");
            string[] ccArgs;
            if (compilerExe == "dmd") {
                ccArgs = [compilerExe, "-of" ~ executablePath];
                if (optimize) ccArgs ~= ["-O", "-release", "-inline"];
            } else {
                // ldc2
                ccArgs = [compilerExe, "-of=" ~ executablePath];
                if (optimize) ccArgs ~= ["-O3", "-release", "-enable-inlining"];
            }
            foreach (path; moduleDPaths.values) ccArgs ~= path;
            foreach (hs; helperSources) ccArgs ~= hs;
            auto swCompile = StopWatch(AutoStart.yes);
            auto result = execute(ccArgs);
            auto swc = swCompile.peek; compileDuration = swc;
            if (result.status != 0) throw new CompilerError((compilerExe ~ " compilation failed:\n") ~ result.output);
        }

        // Stats and summary
    ulong binSize = 0;
        try { binSize = cast(ulong) std.file.getSize(executablePath); } catch (Exception) {}
    // Use microseconds and round up to the nearest millisecond to avoid showing 0 on tiny runs
    auto transpileUs = transpileDur.total!"usecs";
    auto compileUs = compileDuration.total!"usecs";
    long transpileMs = cast(long)((transpileUs + 999) / 1000); // ceil division to ms
    if (transpileMs == 0 && moduleDPaths.length) {
        // If we generated at least one module but timer resolution yielded 0, show 1 ms
        transpileMs = 1;
    }
    long compileMs = cast(long)((compileUs + 999) / 1000);
    string transpileStr = transpileMs > 0 ? (to!string(transpileMs) ~ " ms") : (to!string(transpileUs) ~ " µs");
    string compileStr = compileMs > 0 ? (to!string(compileMs) ~ " ms") : (to!string(compileUs) ~ " µs");

        if (verbose) {
            writefln("Executable: %s", executablePath);
            ui.success("Compilation successful!");
        }
        if (!runAfterCompile) {
            // Always print a concise summary instead of plain OK
            // Format:
            // duende vX.Y.Z | transpile: Xms | compile: Yms | binary: <path> (Z bytes)
            string summary = "duende v" ~ DUENDE_VERSION ~
                "\n | transpile: " ~ transpileStr ~
                "\n | compile: " ~ compileStr ~
                "\n | binary: " ~ absolutePath(executablePath) ~
                "\n | (" ~ to!string(binSize) ~ " bytes)";
            writeln(summary);
        }

        if (runAfterCompile) {
            if (verbose) {
                writeln("Running executable...");
                writeln("====================");
            }

            auto runResult = execute([executablePath]);

            if (runResult.output.length > 0) {
                write(runResult.output);
            }

            if (runResult.status != 0 && verbose) {
                writefln("Program exited with code: %d", runResult.status);
            }
        }

    } catch (CompilerError e) {
        ui.error("Error: " ~ e.msg);
    } catch (Exception e) {
        ui.error("Internal error: " ~ e.msg);
        if (verbose) {
            ui.warn(e.toString());
        }
    }
}

// ---------------- Module system -----------------

class ModuleGraph {
    string projectDir;
    string outputDir;
    bool verbose;
    Packages packages;
    string[string] pathCache;            // moduleName -> resolved source path
    Program[string] astCache;            // sourcePath -> parsed Program
    ModuleInfo[string] modules;          // moduleName -> info
    string[] order;                      // topological or discovery order

    this(string projectDir, string outputDir, bool verbose, Packages packages) {
        this.projectDir = projectDir;
        this.outputDir = outputDir;
        this.verbose = verbose;
        this.packages = packages;
    }

    string addEntry(string sourceFile) {
        string modName = computeModuleName(sourceFile);
        if (modName !in modules) {
            auto info = parseModuleFromFile(sourceFile, modName);
            modules[modName] = info;
            order ~= modName;
            if (verbose) {
                writefln("[duende] addEntry %s imports=%s", modName, info.imports.length);
                foreach (imp; info.imports) {
                    writefln("  import %s", imp.modulePath.join("."));
                }
            }
        }
        return modName;
    }

    void resolveAll() {
        // DFS to resolve imports; handle cycles via existing entries
        foreach (mod; order.dup) {
            resolveImports(mod);
            if (verbose) {
                auto info = modules[mod];
                writefln("[duende] Generating module %s imports=%s", info.moduleName, info.imports.length);
                foreach (imp; info.imports) writeln("  import ", imp.modulePath.join("."));
            }
        }
    }

    private void resolveImports(string modName) {
        auto info = modules[modName];
        foreach (imp; info.imports) {
            string depName = imp.modulePath.join(".");
            // If this is std.* or user import that doesn't resolve to a file, try external providers
            bool isStdPref = (imp.modulePath.length && imp.modulePath[0] == "std");

            if (depName in modules) continue;

            string baseDir = dirName(info.sourcePath);
            string resolved = resolveModulePath(baseDir, imp.modulePath);
            if (!resolved.length) {
                    // Attempt resolve via external provider
                if (verbose) writeln("[duende] resolveImports: trying provider for ", depName, " (std? ", isStdPref, ")");
                auto prov = packages.debugResolve(depName);
                if (prov !is null) {
                    // Record provider on this module for codegen
                    info.externalProviders[depName] = *prov;
                    if (verbose) writeln("[duende] resolveImports: attached provider for ", depName, " -> ", prov.packageName);
                    modules[modName] = info; // write back
                    continue; // do not try to parse a .du file for this import
                }
                // Build richer message: show candidates searched
                    // If this is a std.* import with no provider, allow it silently;
                    // built-in codegen handles std modules like std.math.
                    if (isStdPref) {
                        if (verbose) writeln("[duende] resolveImports: no provider found for ", depName, ", allowing std builtin");
                        modules[modName] = info; // persist any changes
                        continue;
                    }
                auto tried = attemptedModulePaths(baseDir, imp.modulePath);
                string[] roots;
                // Only exe-local packages next to the compiler binary
                string exeDir;
                try { exeDir = dirName(thisExePath()); } catch (Exception) { exeDir = getcwd(); }
                roots ~= buildPath(exeDir, "duende_packages");
                if (verbose) {
                    writeln("[duende] Import not found: ", depName, " from ", info.sourcePath);
                    writeln("[duende] Tried files:");
                    foreach (t; tried) writeln("  ", t);
                    writeln("[duende] Checked package roots:");
                    foreach (r; roots) writeln("  ", r);
                }
                string msg = "Import not found: " ~ depName ~ " (from " ~ info.sourcePath ~ ")\n" ~
                             "Tried files:\n  " ~ join(tried, "\n  ") ~ "\n" ~
                             "Package root:\n  " ~ join(roots, "\n  ") ~ "\n" ~
                             "Hint: add a Duende package providing this module under duende_packages/ next to the duende executable.";
                throw new CompilerError(msg);
            }

            auto depInfo = parseModuleFromFile(resolved, computeModuleName(resolved));
            modules[depInfo.moduleName] = depInfo;
            order ~= depInfo.moduleName;
            // Recurse for newly added module
            resolveImports(depInfo.moduleName);
        }
    }

    private string resolveModulePath(string baseDir, string[] path) {
        // Cache by module logical name
        string modName = path.join(".");
        auto cached = pathCache.get(modName, "");
        if (cached.length && exists(cached)) return cached;

        string subdir = joinPathParts(path.length > 1 ? path[0 .. $-1] : []);
        string fnameDU = path[$-1] ~ ".du";
        string fnameDE = path[$-1] ~ ".duende";
    // Try from project root first (treat dotted names as absolute modules under projectDir)
        string pr1 = subdir.length ? buildPath(projectDir, buildPath(subdir, fnameDU)) : buildPath(projectDir, fnameDU);
        if (exists(pr1)) { pathCache[modName] = pr1; return pr1; }
        string pr2 = subdir.length ? buildPath(projectDir, buildPath(subdir, fnameDE)) : buildPath(projectDir, fnameDE);
        if (exists(pr2)) { pathCache[modName] = pr2; return pr2; }
    // Then try relative to the importer file
    string rel1 = subdir.length ? buildPath(baseDir, buildPath(subdir, fnameDU)) : buildPath(baseDir, fnameDU);
    if (exists(rel1)) { pathCache[modName] = rel1; return rel1; }
    string rel2 = subdir.length ? buildPath(baseDir, buildPath(subdir, fnameDE)) : buildPath(baseDir, fnameDE);
    if (exists(rel2)) { pathCache[modName] = rel2; return rel2; }
        return "";
    }

    private ModuleInfo parseModuleFromFile(string path, string modName) {
        // Avoid re-lex/parse for the same file in a run
        if (path in astCache) {
            auto cachedProg = astCache[path];
            // We still need to collect imports from cached program
            ImportDeclaration[] cachedImports;
            foreach (s; cachedProg.statements) {
                if (auto imp = cast(ImportDeclaration)s) cachedImports ~= imp;
            }
            return ModuleInfo(modName, path, cachedProg, cachedImports);
        }

        string sourceCode = readText(path);
        auto lx = new Lexer(sourceCode);
        auto toks = lx.tokenize();
        auto ps = new Parser(toks);
        auto prog = ps.parse();
        astCache[path] = prog;
        // Collect import declarations at top-level
        ImportDeclaration[] imports;
        foreach (s; prog.statements) {
            if (auto imp = cast(ImportDeclaration)s) imports ~= imp;
        }
        return ModuleInfo(modName, path, prog, imports);
    }

    private string computeModuleName(string path) {
        // Module name is relative path from projectDir without extension, dots as separators
        string abs = absolutePath(path);
        string rel = abs.startsWith(projectDir) ? abs[projectDir.length + 1 .. $] : baseName(abs);
        // strip extension
        rel = stripExtension(rel);
        // replace separators with dots
        return rel.replace("/", ".").replace("\\", ".");
    }

    private string joinPathParts(string[] parts) {
        string acc = "";
        foreach (p; parts) {
            acc = acc.length ? buildPath(acc, p) : p;
        }
        return acc;
    }

    private string[] attemptedModulePaths(string baseDir, string[] path) {
        string[] tried;
        string subdir = joinPathParts(path.length > 1 ? path[0 .. $-1] : []);
        string fnameDU = path[$-1] ~ ".du";
        string fnameDE = path[$-1] ~ ".duende";
        string rel1 = subdir.length ? buildPath(baseDir, buildPath(subdir, fnameDU)) : buildPath(baseDir, fnameDU);
        string rel2 = subdir.length ? buildPath(baseDir, buildPath(subdir, fnameDE)) : buildPath(baseDir, fnameDE);
        string pr1 = subdir.length ? buildPath(projectDir, buildPath(subdir, fnameDU)) : buildPath(projectDir, fnameDU);
        string pr2 = subdir.length ? buildPath(projectDir, buildPath(subdir, fnameDE)) : buildPath(projectDir, fnameDE);
        tried ~= rel1; tried ~= rel2; tried ~= pr1; tried ~= pr2;
        return tried;
    }

    // Per-module D code generation
    string generateModuleD(ModuleInfo info) {
    auto gen = new DCodeGenerator();
    gen.moduleName = info.moduleName;
    // Entry module is the first in graph.order
    bool isEntry = (order.length > 0 && order[0] == info.moduleName);
    gen.isLibraryModule = !isEntry;

        // Determine if this module explicitly imports std.math
        bool hasStdMathImport = false;
        foreach (imp; info.imports) {
            if (imp.modulePath.length >= 2 && imp.modulePath[0] == "std" && imp.modulePath[1] == "math") {
                hasStdMathImport = true;
                break;
            }
        }

        // Validate: using any math functionality requires `import std.math` in this module
        {
            bool[string] names;
            foreach (s; info.program.statements) collectCallNames(s, names);
            string[] mathNames = [
                "abs","min","max","floor","ceil","round","sqrt","pow","log","exp",
                "sin","cos","tan","sinDeg","cosDeg","tanDeg",
                "toRadians","toDegrees","roundTo","formatFloat"
            ];
            bool usesMath = false;
            foreach (mn; mathNames) { if (mn in names) { usesMath = true; break; } }
            if (usesMath && !hasStdMathImport) {
                string msg = "Math functions require 'import std.math' in module '" ~ info.moduleName ~ "' (" ~ info.sourcePath ~ ").";
                throw new CompilerError(msg);
            }
        }

        // Only include std.math helpers if the module explicitly imports it
        gen.includeStdMathHelpers = hasStdMathImport;

        // Determine if this module explicitly imports std.hash or std.digest
        bool hasStdHashImport = false;
        foreach (imp; info.imports) {
            if (imp.modulePath.length >= 2 && imp.modulePath[0] == "std") {
                auto m1 = imp.modulePath[1];
                if (m1 == "hash" || m1 == "digest") { hasStdHashImport = true; break; }
            }
        }

        // Validate: using any hash/digest functionality requires an explicit import
        {
            bool[string] names;
            foreach (s; info.program.statements) collectCallNames(s, names);
            string[] hashNames = [
                "md5","crc32","crc64",
                "sha1","sha224","sha256","sha384","sha512","sha512_224","sha512_256",
                "murmurhash3"
            ];
            bool usesHash = false;
            foreach (hn; hashNames) { if (hn in names) { usesHash = true; break; } }
            if (usesHash && !hasStdHashImport) {
                string msg = "Hash and digest functions require 'import std.hash' or 'import std.digest' in module '" ~ info.moduleName ~ "' (" ~ info.sourcePath ~ ").";
                throw new CompilerError(msg);
            }
        }

        // Ensure external providers are recorded for std.* imports (e.g., std.encoding)
        foreach (imp; info.imports) {
            if (imp.modulePath.length && imp.modulePath[0] == "std") {
                auto dep = imp.modulePath.join(".");
                if (!(dep in info.externalProviders)) {
                    // Use verbose-aware resolution to aid debugging when -v is enabled
                    auto prov = packages.debugResolve(dep);
                    if (prov !is null) {
                        info.externalProviders[dep] = *prov;
                        if (verbose) writeln("[duende] codegen: injecting provider for ", dep, " -> ", prov.packageName);
                    }
                }
            }
        }

        // Build user import lines for this module (including external providers)
        string[] lines;
        string[] aliasLines;
        if (verbose) {
            writeln("[duende] codegen: externalProviders for ", info.moduleName, ": ");
            foreach (k, p; info.externalProviders) writeln("  ", k, " from ", p.packageName);
        }
        // First, append provider D imports and aliases if any
        foreach (k, prov; info.externalProviders) {
            foreach (di; prov.entry.dImports) {
                lines ~= "import " ~ di ~ ";";
            }
            foreach (an, target; prov.entry.aliases) {
                aliasLines ~= "alias " ~ an ~ " = " ~ target ~ ";";
            }
        }
        foreach (imp; info.imports) {
            // Skip std.* explicit imports; handled by providers if present
            if (imp.modulePath.length && imp.modulePath[0] == "std") {
                // Still allow selective aliases if provider declared them; already added above.
                // If not already attached on this module, try resolving provider now and inject its imports/aliases.
                string depStd = imp.modulePath.join(".");
                if (!(depStd in info.externalProviders)) {
                    auto provNow = packages.debugResolve(depStd);
                    if (provNow !is null) {
                        foreach (di; provNow.entry.dImports) lines ~= "import " ~ di ~ ";";
                        foreach (an, target; provNow.entry.aliases) aliasLines ~= "alias " ~ an ~ " = " ~ target ~ ";";
                    }
                }
                continue;
            }
            // If this import is provided externally, do not emit a D import for the Duende module name
            string depNameCheck = imp.modulePath.join(".");
            if (depNameCheck in info.externalProviders) {
                continue;
            }
            string mod = imp.modulePath.join(".");

            // Resolve relative module names against current module's parent namespace
            if (!(mod in modules)) {
                auto parts = info.moduleName.split(".");
                if (parts.length > 1) {
                    string parent = parts[0 .. $-1].join(".");
                    string candidate = parent.length ? (parent ~ "." ~ mod) : mod;
                    if (candidate in modules) {
                        mod = candidate;
                    }
                }
            }

            string impKw = imp.isPublic ? "public import " : "import ";

            // Always import the module with a short alias to allow 'foo.bar' usage
            string shortName = imp.moduleAlias.length ? imp.moduleAlias : imp.modulePath[$-1];
            lines ~= impKw ~ shortName ~ " = " ~ mod ~ ";";

            // Handle selective or wildcard
            if (imp.items.length) {
                foreach (it; imp.items) {
                    string local = it.localAlias.length ? it.localAlias : it.name;
                    string modRef = shortName ~ "." ~ it.name;
                    aliasLines ~= "alias " ~ local ~ " = " ~ modRef ~ ";";
                }
            } else if (imp.isWildcard) {
                // Expand wildcard using the target module's exported symbols
                string depName = mod;
                if (depName in modules) {
                    auto ex = exportedSymbolsFrom(modules[depName].program);
                    if (ex.length) {
                        foreach (n; ex) {
                            aliasLines ~= "alias " ~ n ~ " = " ~ shortName ~ "." ~ n ~ ";";
                        }
                    }
                }
            }

            // If the imported module re-exports other modules publicly, bridge their
            // aliases into this module so `mod1` can be referenced directly if
            // `mod2` does `public import mod1`.
            if (mod in modules) {
                foreach (reimp; modules[mod].imports) {
                    if (reimp.isPublic) {
                        string childShort = reimp.moduleAlias.length ? reimp.moduleAlias : reimp.modulePath[$-1];
                        aliasLines ~= "alias " ~ childShort ~ " = " ~ shortName ~ "." ~ childShort ~ ";";
                    }
                }
            }
        }
        if (verbose) {
            writeln("[duende] codegen: provider import lines: ", lines.length);
            foreach (l; lines) writeln("    ", l);
            writeln("[duende] codegen: provider alias lines: ", aliasLines.length);
            foreach (a; aliasLines) writeln("    ", a);
        }
        gen.userModuleImports = lines;
        gen.userAliasLines = aliasLines;

        return gen.generate(info.program);
    }
}

struct ModuleInfo {
    string moduleName;
    string sourcePath;
    Program program;
    ImportDeclaration[] imports;
    Provider[string] externalProviders; // duModule -> provider used by this module
}

private string[] exportedSymbolsFrom(Program prog) {
    string[] syms;
    foreach (s; prog.statements) {
        if (auto f = cast(FunctionDeclaration)s) syms ~= f.name;
        else if (auto st = cast(StructDeclaration)s) syms ~= st.name;
        else if (auto fr = cast(FrameDeclaration)s) syms ~= fr.name;
        else if (auto en = cast(EnumDeclaration)s) syms ~= en.name;
        else if (auto pr = cast(ProtocolDeclaration)s) syms ~= pr.name;
    }
    return syms;
}

private string joinList(string[] xs) {
    import std.array : appender;
    auto buf = appender!string();
    foreach (i, x; xs) { if (i) buf ~= ", "; buf ~= x; }
    return buf.data;
}

// Walk statements/expressions to collect call names used
private void collectCallNames(Statement s, ref bool[string] names) {
    import std.algorithm : canFind;
    void visitExpr(Expression e) {
        if (e is null) return;
        if (auto ce = cast(CallExpression)e) {
            names[ce.name] = true;
            foreach (a; ce.arguments) visitExpr(a);
        } else if (auto be = cast(BinaryExpression)e) {
            visitExpr(be.left); visitExpr(be.right);
        } else if (auto ue = cast(UnaryExpression)e) {
            visitExpr(ue.operand);
        } else if (auto me = cast(MethodCallExpression)e) {
            visitExpr(me.object); foreach (a; me.arguments) visitExpr(a);
        } else if (auto ie = cast(IndexExpression)e) {
            visitExpr(ie.object); visitExpr(ie.index);
        } else if (auto pe = cast(PropertyExpression)e) {
            visitExpr(pe.object);
        } else if (auto le = cast(ListLiteralExpression)e) {
            foreach (el; le.elements) visitExpr(el);
        } else if (auto de = cast(DictLiteralExpression)e) {
            foreach (i, k; de.keys) { visitExpr(k); visitExpr(de.values[i]); }
        } else if (auto se = cast(StringInterpolationExpression)e) {
            foreach (ex; se.expressions) visitExpr(ex);
        } else if (auto rc = cast(ResultConstructorExpression)e) {
            visitExpr(rc.value);
        } else if (auto mc = cast(MaybeConstructorExpression)e) {
            visitExpr(mc.value);
        } else if (auto ue2 = cast(UnwrapExpression)e) {
            visitExpr(ue2.result); visitExpr(ue2.defaultValue);
        } else if (auto te = cast(TryBlockExpression)e) {
            foreach (st; te.statements) collectCallNames(st, names);
        } else if (auto me2 = cast(MatchExpression)e) {
            visitExpr(me2.subject); foreach (c; me2.cases) { visitExpr(c.value); }
        }
    }
    if (auto f = cast(FunctionDeclaration)s) { foreach (st; f.body) collectCallNames(st, names); }
    else if (auto m = cast(MethodDeclaration)s) { foreach (st; m.body) collectCallNames(st, names); }
    else if (auto fs = cast(ForStatement)s) { visitExpr(fs.start); visitExpr(fs.end); foreach (st; fs.body) collectCallNames(st, names); }
    else if (auto fi = cast(ForInStatement)s) { visitExpr(fi.iterable); foreach (st; fi.body) collectCallNames(st, names); }
    else if (auto ws = cast(WhileStatement)s) { visitExpr(ws.condition); foreach (st; ws.body) collectCallNames(st, names); }
    else if (auto es = cast(ExpressionStatement)s) { visitExpr(es.expression); }
    else if (auto rs = cast(ReturnStatement)s) { visitExpr(rs.value); }
    else if (auto ifs = cast(IfStatement)s) {
        visitExpr(ifs.condition);
        foreach (st; ifs.thenBranch) collectCallNames(st, names);
        foreach (st; ifs.elseBranch) collectCallNames(st, names);
    }
    else if (auto ms = cast(MatchStatement)s) {
        visitExpr(ms.subject);
        foreach (c; ms.cases) {
            foreach (st; c.body) collectCallNames(st, names);
        }
    }
}

// ---------------- Semantic validation -----------------

private void validateModuleSemantics(ModuleInfo info, SemanticErrorCollector errorCollector) {
    // Run modular analyzer (undefined vars, function calls, types)
    analyzeModule(info.program, info.moduleName, info.sourcePath, errorCollector);
    // Run legacy checks preserved here
    validateBreakContinueUsage(info.program, info.moduleName, info.sourcePath, errorCollector);
    validateImportRequirements(info.program, info.moduleName, info.sourcePath, errorCollector);
    validateDefaultParameters(info.program, info.sourcePath, errorCollector);
}

// -------- Default parameter validation --------
private void validateDefaultParameters(Program program, string sourcePath, SemanticErrorCollector errorCollector) {
    // Helpers
    bool isConstExpr(Expression e) {
        if (e is null) return false;
        if (cast(LiteralExpression)e !is null) return true;
        if (auto s = cast(StringInterpolationExpression)e) {
            // Interpolations may contain expressions; only allow no expressions
            return s.expressions.length == 0; // should be a plain string literal if allowed
        }
        if (cast(BytesLiteralExpression)e !is null) return true;
        if (auto u = cast(UnaryExpression)e) {
            // Allow unary +/- on const numeric
            if (u.operator == "+" || u.operator == "-") return isConstExpr(u.operand);
            return false;
        }
        if (auto b = cast(BinaryExpression)e) {
            // Allow arithmetic on consts
            immutable allowedOps = ["+","-","*","/","%"];
            foreach (op; allowedOps) if (b.operator == op) {
                return isConstExpr(b.left) && isConstExpr(b.right);
            }
            return false;
        }
        if (auto c = cast(CastExpression)e) {
            return isConstExpr(c.value);
        }
        // Disallow calls, variables, method calls, list/dict/regex, match/try, result/maybe, etc.
        return false;
    }

    DuendeType exprType(Expression e) {
        if (e is null) return DuendeType.VOID;
        if (auto lit = cast(LiteralExpression)e) return lit.type;
        if (cast(BytesLiteralExpression)e !is null) return DuendeType.BYTES;
        if (cast(StringInterpolationExpression)e !is null) return DuendeType.STRING; // only literal allowed by isConstExpr
        if (auto u = cast(UnaryExpression)e) return exprType(u.operand);
        if (auto b = cast(BinaryExpression)e) {
            auto lt = exprType(b.left);
            auto rt = exprType(b.right);
            if ((lt == DuendeType.FLOAT) || (rt == DuendeType.FLOAT)) return DuendeType.FLOAT;
            return DuendeType.INT;
        }
        if (auto c = cast(CastExpression)e) return c.targetType;
        return DuendeType.VOID; // unknown
    }

    bool isTypeCompatible(DuendeType paramType, DuendeType exprT) {
        if (paramType == exprT) return true;
        // Allow numeric widening
        if (paramType == DuendeType.FLOAT && exprT == DuendeType.INT) return true;
        // Disallow others for now
        return false;
    }

    void checkParams(Parameter[] params, string whereName) {
        bool seenDefault = false;
        foreach (i, p; params) {
            if (p.defaultValue !is null) {
                // Mark we saw a default; subsequent non-defaults are errors
                seenDefault = true;
                // Must be const expr
                if (!isConstExpr(p.defaultValue)) {
                    string msg = "Default value for parameter '" ~ p.name ~ "' in " ~ whereName ~ " must be a compile-time constant expression (no function calls or non-constant variables).";
                    errorCollector.addError(msg, sourcePath, 1, 1);
                } else {
                    // Type-check
                    auto et = exprType(p.defaultValue);
                    if (!isTypeCompatible(p.type, et)) {
                        string msg = "Default value for parameter '" ~ p.name ~ "' in " ~ whereName ~ " has incompatible type.";
                        errorCollector.addError(msg, sourcePath, 1, 1);
                    }
                }
            } else if (seenDefault) {
                string msg = "Non-default parameter '" ~ p.name ~ "' cannot follow a parameter with a default value in " ~ whereName ~ ".";
                errorCollector.addError(msg, sourcePath, 1, 1);
            }
        }
    }

    foreach (s; program.statements) {
        if (auto f = cast(FunctionDeclaration)s) {
            checkParams(f.parameters, "function '" ~ f.name ~ "'");
        } else if (auto m = cast(MethodDeclaration)s) {
            checkParams(m.parameters, "method '" ~ m.name ~ "'");
        } else if (auto pr = cast(ProtocolDeclaration)s) {
            foreach (ms; pr.methods) {
                checkParams(ms.parameters, "protocol method '" ~ ms.name ~ "'");
            }
        } else if (auto st = cast(StructDeclaration)s) {
            foreach (md; st.methods) checkParams(md.parameters, "struct method '" ~ md.name ~ "'");
        } else if (auto fr = cast(FrameDeclaration)s) {
            foreach (md; fr.methods) checkParams(md.parameters, "frame method '" ~ md.name ~ "'");
        }
    }
}

private void validateBreakContinueUsage(Program program, string moduleName, string sourcePath, SemanticErrorCollector errorCollector) {
    void visitStmt(Statement s, int loopDepth) {
        if (auto f = cast(FunctionDeclaration)s) {
            // Nested function is its own control-flow context; loopDepth resets
            foreach (st; f.body) visitStmt(st, 0);
            return;
        }
        if (auto m = cast(MethodDeclaration)s) {
            foreach (st; m.body) visitStmt(st, 0);
            return;
        }
        if (auto fs = cast(ForStatement)s) {
            foreach (st; fs.body) visitStmt(st, loopDepth + 1);
            return;
        }
        if (auto fi = cast(ForInStatement)s) {
            foreach (st; fi.body) visitStmt(st, loopDepth + 1);
            return;
        }
        if (auto ws = cast(WhileStatement)s) {
            foreach (st; ws.body) visitStmt(st, loopDepth + 1);
            return;
        }
        if (auto es = cast(ExpressionStatement)s) {
            // Only TryBlockExpression contains nested statements we must analyze
            if (auto te = cast(TryBlockExpression)es.expression) {
                foreach (st; te.statements) visitStmt(st, loopDepth);
            }
            return;
        }
        if (auto ifs = cast(IfStatement)s) {
            foreach (st; ifs.thenBranch) visitStmt(st, loopDepth);
            foreach (st; ifs.elseBranch) visitStmt(st, loopDepth);
            return;
        }
        if (auto ms = cast(MatchStatement)s) {
            foreach (c; ms.cases) {
                foreach (st; c.body) visitStmt(st, loopDepth);
            }
            return;
        }
        if (auto breakStmt = cast(BreakStatement)s) {
            if (loopDepth <= 0) {
                string msg = "Invalid use of 'break' outside of a loop";
                auto pos = breakStmt.position;
                if (pos.file.length == 0) {
                    pos.file = sourcePath;
                }
                errorCollector.addError(msg, pos);
            }
            return;
        }
        if (auto continueStmt = cast(ContinueStatement)s) {
            if (loopDepth <= 0) {
                string msg = "Invalid use of 'continue' outside of a loop";
                auto pos = continueStmt.position;
                if (pos.file.length == 0) {
                    pos.file = sourcePath;
                }
                errorCollector.addError(msg, pos);
            }
            return;
        }
        // Other statements: ok
    }

    foreach (s; program.statements) visitStmt(s, 0);
}

private void validateImportRequirements(Program program, string moduleName, string sourcePath, SemanticErrorCollector errorCollector) {
    // Determine if this module explicitly imports std.math
    bool hasStdMathImport = false;
    bool hasStdHashImport = false;
    
    // Check imports (this logic is similar to what's in generateModuleD)
    foreach (s; program.statements) {
        if (auto imp = cast(ImportDeclaration)s) {
            if (imp.modulePath.length >= 2 && imp.modulePath[0] == "std" && imp.modulePath[1] == "math") {
                hasStdMathImport = true;
            }
            if (imp.modulePath.length >= 2 && imp.modulePath[0] == "std") {
                auto m1 = imp.modulePath[1];
                if (m1 == "hash" || m1 == "digest") { 
                    hasStdHashImport = true; 
                }
            }
        }
    }
    
    // Collect function calls from all statements
    bool[string] functionCalls;
    foreach (s; program.statements) {
        collectCallNames(s, functionCalls);
    }
    
    // Validate math function usage
    string[] mathNames = [
        "abs","min","max","floor","ceil","round","sqrt","pow","log","exp",
        "sin","cos","tan","sinDeg","cosDeg","tanDeg",
        "toRadians","toDegrees","roundTo","formatFloat"
    ];
    foreach (mathFunc; mathNames) {
        if (mathFunc in functionCalls && !hasStdMathImport) {
            string msg = "Math functions require 'import std.math' in module '" ~ moduleName ~ "'";
            // For now, use a default position since we don't track call positions yet
            errorCollector.addError(msg, sourcePath, 1, 1);
            break; // Only report once per module
        }
    }
    
    // Validate hash function usage
    string[] hashNames = [
        "hash",  // generic hash function
        "md5","crc32","crc64",
        "sha1","sha224","sha256","sha384","sha512","sha512_224","sha512_256",
        "murmurhash3"
    ];
    foreach (hashFunc; hashNames) {
        if (hashFunc in functionCalls && !hasStdHashImport) {
            string msg = "Hash and digest functions require 'import std.hash' or 'import std.digest' in module '" ~ moduleName ~ "'";
            // For now, use a default position since we don't track call positions yet
            errorCollector.addError(msg, sourcePath, 1, 1);
            break; // Only report once per module
        }
    }
}

// (no out-of-class definitions)

void printProgram(Program program, int indent = 0) {
    string indentStr = "  ".replicate(indent);
    writefln("%sProgram:", indentStr);

    foreach (stmt; program.statements) {
        printStatement(stmt, indent + 1);
    }
}

void printStatement(Statement stmt, int indent = 0) {
    string indentStr = "  ".replicate(indent);

    if (auto varDecl = cast(VariableDeclaration)stmt) {
        writefln("%sVariableDeclaration: %s %s %s", indentStr,
                varDecl.isMutable ? "var" : "let", varDecl.type, varDecl.name);
        if (varDecl.initializer) {
            printExpression(varDecl.initializer, indent + 1);
        }
    } else if (auto funcDecl = cast(FunctionDeclaration)stmt) {
        writefln("%sFunctionDeclaration: %s %s", indentStr, funcDecl.returnType, funcDecl.name);
        foreach (param; funcDecl.parameters) {
            writefln("%s  Parameter: %s %s", indentStr, param.type, param.name);
        }
        foreach (bodyStmt; funcDecl.body) {
            printStatement(bodyStmt, indent + 1);
        }
    } else if (auto exprStmt = cast(ExpressionStatement)stmt) {
        writefln("%sExpressionStatement:", indentStr);
        printExpression(exprStmt.expression, indent + 1);
    } else if (auto retStmt = cast(ReturnStatement)stmt) {
        writefln("%sReturnStatement:", indentStr);
        if (retStmt.value) {
            printExpression(retStmt.value, indent + 1);
        }
    } else if (auto structDecl = cast(StructDeclaration)stmt) {
        writefln("%sStructDeclaration: %s", indentStr, structDecl.name);
        foreach (field; structDecl.fields) {
            writefln("%s  Field: %s %s", indentStr, field.type, field.name);
        }
        foreach (method; structDecl.methods) {
            printStatement(method, indent + 1);
        }
    } else if (auto frameDecl = cast(FrameDeclaration)stmt) {
        writefln("%sFrameDeclaration: %s", indentStr, frameDecl.name);
        foreach (field; frameDecl.fields) {
            printStatement(field, indent + 1);
        }
        foreach (method; frameDecl.methods) {
            printStatement(method, indent + 1);
        }
    } else if (auto enumDecl = cast(EnumDeclaration)stmt) {
        writefln("%sEnumDeclaration: %s", indentStr, enumDecl.name);
        foreach (value; enumDecl.values) {
            writefln("%s  Value: %s", indentStr, value);
        }
    } else if (auto methodDecl = cast(MethodDeclaration)stmt) {
        writefln("%sMethodDeclaration: %s %s", indentStr, methodDecl.returnType, methodDecl.name);
        foreach (param; methodDecl.parameters) {
            writefln("%s  Parameter: %s %s", indentStr, param.type, param.name);
        }
        foreach (bodyStmt; methodDecl.body) {
            printStatement(bodyStmt, indent + 1);
        }
    } else if (auto ifStmt = cast(IfStatement)stmt) {
        writefln("%sIfStatement:", indentStr);
        writefln("%s  Condition:", indentStr);
        printExpression(ifStmt.condition, indent + 2);
        writefln("%s  Then:", indentStr);
        foreach (thenStmt; ifStmt.thenBranch) {
            printStatement(thenStmt, indent + 2);
        }
        if (ifStmt.elseBranch && ifStmt.elseBranch.length > 0) {
            writefln("%s  Else:", indentStr);
            foreach (elseStmt; ifStmt.elseBranch) {
                printStatement(elseStmt, indent + 2);
            }
        }
    } else if (auto matchStmt = cast(MatchStatement)stmt) {
        writefln("%sMatchStatement:", indentStr);
        writefln("%s  Subject:", indentStr);
        printExpression(matchStmt.subject, indent + 2);
        foreach (c; matchStmt.cases) {
            writefln("%s  Case:", indentStr);
            // Not expanding patterns in debug to keep simple
            foreach (s; c.body) printStatement(s, indent + 2);
        }
    }
}

void printExpression(Expression expr, int indent = 0) {
    string indentStr = "  ".replicate(indent);

    if (auto literal = cast(LiteralExpression)expr) {
        writefln("%sLiteral: %s (%s)", indentStr, literal.value, literal.type);
    } else if (auto variable = cast(VariableExpression)expr) {
        writefln("%sVariable: %s", indentStr, variable.name);
    } else if (auto binary = cast(BinaryExpression)expr) {
        writefln("%sBinaryExpression: %s", indentStr, binary.operator);
        writefln("%s  Left:", indentStr);
        printExpression(binary.left, indent + 2);
        writefln("%s  Right:", indentStr);
        printExpression(binary.right, indent + 2);
    } else if (auto call = cast(CallExpression)expr) {
        writefln("%sCallExpression: %s", indentStr, call.name);
        foreach (i, arg; call.arguments) {
            writefln("%s  Arg %d:", indentStr, i);
            printExpression(arg, indent + 2);
        }
    } else if (auto constructor = cast(ConstructorCallExpression)expr) {
        writefln("%sConstructorCall: %s", indentStr, constructor.typeName);
        foreach (i, arg; constructor.arguments) {
            writefln("%s  Arg %d:", indentStr, i);
            printExpression(arg, indent + 2);
        }
    } else if (auto property = cast(PropertyExpression)expr) {
        writefln("%sPropertyExpression: %s", indentStr, property.property);
        writefln("%s  Object:", indentStr);
        printExpression(property.object, indent + 2);
    } else if (auto propAssignment = cast(PropertyAssignmentExpression)expr) {
        writefln("%sPropertyAssignmentExpression: %s", indentStr, propAssignment.property);
        writefln("%s  Object:", indentStr);
        printExpression(propAssignment.object, indent + 2);
        writefln("%s  Value:", indentStr);
        printExpression(propAssignment.value, indent + 2);
    } else if (auto matchExpr = cast(MatchExpression)expr) {
        writefln("%sMatchExpression:", indentStr);
        writefln("%s  Subject:", indentStr);
        printExpression(matchExpr.subject, indent + 2);
    }
}
