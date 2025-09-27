module duende.dub_integration;

import std.file;
import std.path;
import std.string;
import std.process;
import std.stdio;
import std.json;
import std.conv : to;
import std.datetime : Clock, UTC;

class DubIntegration {
    static bool hasDubFile(string directory) {
        string dubSdl = buildPath(directory, "dub.sdl");
        string dubJson = buildPath(directory, "dub.json");

        return exists(dubSdl) || exists(dubJson);
    }

    static string[] buildDubProject(string sourceFile, string outputDir, bool optimize = false) {
        string sourceDir = dirName(absolutePath(sourceFile));

        if (!hasDubFile(sourceDir)) {
            return [sourceFile];
        }

    // Building with user's dub configuration; keep quiet by default

        string tempDir = buildPath(outputDir, "temp_dub");
        if (!exists(tempDir)) {
            mkdirRecurse(tempDir);
        }

        string dubFile = buildPath(sourceDir, "dub.sdl");
        if (!exists(dubFile)) {
            dubFile = buildPath(sourceDir, "dub.json");
        }

        copyDubConfig(sourceDir, tempDir);

        string mainFile = buildPath(tempDir, "app.d");
        string sourceContent = readText(sourceFile);
        std.file.write(mainFile, sourceContent);

        string[] dubArgs = ["dub", "build"];
        if (optimize) {
            dubArgs ~= ["--build=release-opt", "--compiler=dmd"];
        } else {
            dubArgs ~= ["--build=release"];
        }
        dubArgs ~= ["--root=" ~ tempDir];

        auto result = execute(dubArgs);
        if (result.status != 0) {
            throw new Exception("Dub build failed: " ~ result.output);
        }

        string[] builtFiles;
        string executableName = getProjectName(dubFile);
        string executablePath = buildPath(tempDir, executableName);

        if (exists(executablePath)) {
            builtFiles ~= executablePath;
        }

        return builtFiles;
    }

    // Build a temporary dub project including generated D files, extra helper sources, and explicit dub deps.
    // Returns the path to the built executable.
    static string buildTempDubWithSources(
        string outputDir,
        string exeName,
        string[] dSources,
        string[] helperSources,
        string[string] dubDependencies,
        string[string] dubSubConfigurations,
        bool optimize = false,
        string compilerChoice = "dmd"
    ) {
        // Use a unique temp dir per build to avoid parallel build races
        string uniq = exeName ~ "_" ~ to!string(thisProcessID()) ~ "_" ~ to!string(Clock.currTime(UTC()).stdTime);
        string tempDir = buildPath(outputDir, "duende_temp_dub_" ~ uniq);
        mkdirRecurse(tempDir);

        // Create minimal dub.sdl
        string dubSdl = buildPath(tempDir, "dub.sdl");
        string sdl;
        sdl ~= "name \"" ~ exeName ~ "\"\n";
        sdl ~= "targetType \"executable\"\n";
        if (dubDependencies.length) {
            foreach (k, v; dubDependencies) {
                sdl ~= "dependency \"" ~ k ~ "\" version=\"" ~ v ~ "\"\n";
            }
        }
        if (dubSubConfigurations.length) {
            foreach (k, v; dubSubConfigurations) {
                sdl ~= "subConfiguration \"" ~ k ~ "\" \"" ~ v ~ "\"\n";
            }
        }
        std.file.write(dubSdl, sdl);

        // Copy sources into source/
        string srcDir = buildPath(tempDir, "source");
        mkdirRecurse(srcDir);
        foreach (src; dSources ~ helperSources) {
            string target = buildPath(srcDir, baseName(src));
            copy(src, target);
        }

        // Simple main that just imports all units to ensure linking; the real entry is one of the generated units
        // We'll assume the first dSources contains main.
        // Dub will build all modules in source/ as part of the project.

    string[] args = ["dub", "build", "--root=" ~ tempDir];
    if (optimize) args ~= ["--build=release"]; // keep default release
    // Pass through compiler choice
    string cc = (compilerChoice == "ldc") ? "ldc2" : "dmd";
    args ~= ["--compiler=" ~ cc];

        auto res = execute(args);
        if (res.status != 0) {
            throw new Exception("Dub build failed: " ~ res.output);
        }

        string exePath = buildPath(tempDir, exeName);
        if (!exists(exePath)) {
            // Try typical platform suffix
            string alt = exePath ~ ".exe";
            if (exists(alt)) exePath = alt; else throw new Exception("Dub did not produce executable: " ~ exePath);
        }
        return exePath;
    }

    // Build using a user-provided dub.sdl/json found in sourceRoot.
    // We copy their config into a temp project, add our generated sources into source/,
    // and merge in any additional provider dependencies.
    static string buildTempDubFromUserConfig(
        string outputDir,
        string exeName,
        string[] dSources,
        string[] helperSources,
        string sourceRoot,
        string[string] extraDubDependencies, // from providers
        string[string] extraDubSubConfigurations, // from providers
        bool optimize = false,
        string compilerChoice = "dmd"
    ) {
        string uniq = exeName ~ "_user_" ~ to!string(thisProcessID()) ~ "_" ~ to!string(Clock.currTime(UTC()).stdTime);
        string tempDir = buildPath(outputDir, "duende_temp_dub_" ~ uniq);
        mkdirRecurse(tempDir);

        // Copy user's dub file
        string srcSdl = buildPath(sourceRoot, "dub.sdl");
        string srcJson = buildPath(sourceRoot, "dub.json");
        string mode = exists(srcSdl) ? "sdl" : (exists(srcJson) ? "json" : "none");
        if (mode == "none") {
            // Fallback to our minimal dub
            return buildTempDubWithSources(outputDir, exeName, dSources, helperSources, extraDubDependencies, extraDubSubConfigurations, optimize, compilerChoice);
        }

        string dstDub = buildPath(tempDir, mode == "sdl" ? "dub.sdl" : "dub.json");
        copy(mode == "sdl" ? srcSdl : srcJson, dstDub);

        // Merge provider dependencies
        if (extraDubDependencies.length) {
            if (mode == "sdl") {
                // Append dependency lines
                auto content = readText(dstDub);
                foreach (k, v; extraDubDependencies) {
                    content ~= "\ndependency \"" ~ k ~ "\" version=\"" ~ v ~ "\"\n";
                }
                foreach (k, v; extraDubSubConfigurations) {
                    content ~= "\nsubConfiguration \"" ~ k ~ "\" \"" ~ v ~ "\"\n";
                }
                std.file.write(dstDub, content);
            } else {
                // JSON: merge dependencies object
                try {
                    auto content = readText(dstDub);
                    JSONValue json = parseJSON(content);
                    if (!("dependencies" in json)) {
                        JSONValue deps;
                        deps.object = JSONValue.init.object; // initialize as object
                        json["dependencies"] = deps;
                    }
                    foreach (k, v; extraDubDependencies) {
                        json["dependencies"][k] = v;
                    }
                    std.file.write(dstDub, json.toString());
                } catch (Exception e) {
                    // If merge fails, fall back to appending an SDL alongside; dub ignores extra files but we can try
                    auto extra = buildPath(tempDir, "duende_deps.sdl");
                    string s;
                    foreach (k, v; extraDubDependencies) s ~= "dependency \"" ~ k ~ "\" version=\"" ~ v ~ "\"\n";
                    foreach (k, v; extraDubSubConfigurations) s ~= "subConfiguration \"" ~ k ~ "\" \"" ~ v ~ "\"\n";
                    std.file.write(extra, s);
                }
            }
        }
        // If JSON mode and we could parse it successfully above, we still want to add subConfigurations.
        if (mode == "json" && extraDubSubConfigurations.length) {
            // Append an extra SDL file that dub will pick up
            auto sc = buildPath(tempDir, "duende_subconfigs.sdl");
            string s;
            foreach (k, v; extraDubSubConfigurations) s ~= "subConfiguration \"" ~ k ~ "\" \"" ~ v ~ "\"\n";
            std.file.write(sc, s);
        }

        // Put all generated/helper sources into source/
        string srcDir = buildPath(tempDir, "source");
        mkdirRecurse(srcDir);
        foreach (src; dSources ~ helperSources) {
            string target = buildPath(srcDir, baseName(src));
            copy(src, target);
        }

        string[] args = ["dub", "build", "--root=" ~ tempDir];
        if (optimize) args ~= ["--build=release"]; // default release
        string cc = (compilerChoice == "ldc") ? "ldc2" : "dmd";
        args ~= ["--compiler=" ~ cc];

        auto res = execute(args);
        if (res.status != 0) {
            throw new Exception("Dub build (user config) failed: " ~ res.output);
        }

        string exePath = buildPath(tempDir, exeName);
        if (!exists(exePath)) {
            string alt = exePath ~ ".exe";
            if (exists(alt)) exePath = alt; else throw new Exception("Dub (user config) did not produce executable: " ~ exePath);
        }
        return exePath;
    }

    static string[] getDubDependencies(string sourceFile) {
        string sourceDir = dirName(absolutePath(sourceFile));

        if (!hasDubFile(sourceDir)) {
            return [];
        }

        string dubFile = buildPath(sourceDir, "dub.sdl");
        if (!exists(dubFile)) {
            dubFile = buildPath(sourceDir, "dub.json");
        }

        return parseDubDependencies(dubFile);
    }

    private static void copyDubConfig(string sourceDir, string targetDir) {
        string[] configFiles = ["dub.sdl", "dub.json"];

        foreach (configFile; configFiles) {
            string sourcePath = buildPath(sourceDir, configFile);
            if (exists(sourcePath)) {
                string targetPath = buildPath(targetDir, configFile);
                copy(sourcePath, targetPath);
            }
        }

        string sourceSubDir = buildPath(sourceDir, "source");
        if (exists(sourceSubDir) && isDir(sourceSubDir)) {
            string targetSubDir = buildPath(targetDir, "source");
            if (!exists(targetSubDir)) {
                mkdirRecurse(targetSubDir);
            }
        }
    }

    private static string getProjectName(string dubFile) {
        try {
            if (dubFile.endsWith(".json")) {
                string content = readText(dubFile);
                JSONValue json = parseJSON(content);
                if ("name" in json) {
                    return json["name"].str;
                }
            } else if (dubFile.endsWith(".sdl")) {
                string content = readText(dubFile);
                foreach (line; content.splitLines()) {
                    line = line.strip();
                    if (line.startsWith("name ")) {
                        string nameValue = line[5..$].strip();
                        if (nameValue.startsWith("\"") && nameValue.endsWith("\"")) {
                            return nameValue[1..$-1];
                        }
                        return nameValue;
                    }
                }
            }
        } catch (Exception e) {
            writeln("Warning: Could not parse dub file: ", e.msg);
        }

        return "app";
    }

    private static string[] parseDubDependencies(string dubFile) {
        string[] dependencies;

        try {
            if (dubFile.endsWith(".json")) {
                string content = readText(dubFile);
                JSONValue json = parseJSON(content);
                if ("dependencies" in json) {
                    foreach (key, value; json["dependencies"].object) {
                        dependencies ~= key;
                    }
                }
            } else if (dubFile.endsWith(".sdl")) {
                string content = readText(dubFile);
                foreach (line; content.splitLines()) {
                    line = line.strip();
                    if (line.startsWith("dependency ")) {
                        string[] parts = line.split();
                        if (parts.length >= 2) {
                            string depName = parts[1];
                            if (depName.startsWith("\"") && depName.endsWith("\"")) {
                                depName = depName[1..$-1];
                            }
                            dependencies ~= depName;
                        }
                    }
                }
            }
        } catch (Exception e) {
            writeln("Warning: Could not parse dependencies: ", e.msg);
        }

        return dependencies;
    }
}