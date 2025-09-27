module duende_packages.stdprocess.duende_process;

import std.process;
import std.stdio;
import std.array;
import std.string;
import core.thread; // for Thread.join

struct ExecResult {
    int status;
    string stdout;
    string stderr;
}

// Read entire File to string safely
private string readAll(File f) {
    auto buf = appender!string();
    foreach (line; f.byLineCopy) {
        buf.put(cast(string)line);
        buf.put('\n');
    }
    return buf.data;
}

// Convenience: read all stdout from ProcessPipes
string readAllStdout(ref ProcessPipes p) {
    return readAll(p.stdout);
}

// Convenience: read all stderr from ProcessPipes
string readAllStderr(ref ProcessPipes p) {
    return readAll(p.stderr);
}

// Execute argv, capturing stdout and stderr separately
ExecResult execute(scope const(char[])[] args, const string[string] env = null, Config config = Config.none, scope const(char)[] workDir = null) {
    auto pipes = pipeProcess(args, Redirect.stdout | Redirect.stderr, env, config, workDir);
    scope(exit) {}

    string outData;
    string errData;

    // Read concurrently to avoid pipe deadlocks for large outputs
    auto tOut = new Thread({ outData = readAll(pipes.stdout); });
    auto tErr = new Thread({ errData = readAll(pipes.stderr); });
    tOut.isDaemon = true; tErr.isDaemon = true;
    tOut.start(); tErr.start();

    auto status = wait(pipes.pid);
    tOut.join(); tErr.join();

    // Normalize CRLF to LF for deterministic testing
    outData = outData.replace("\r\n", "\n");
    errData = errData.replace("\r\n", "\n");
    return ExecResult(status, outData, errData);
}

// Execute shell command string
ExecResult executeShell(scope const(char)[] command, const string[string] env = null, Config config = Config.none, scope const(char)[] workDir = null, string shellPath = nativeShell) {
    auto pipes = pipeShell(command, Redirect.stdout | Redirect.stderr, env, config, workDir, shellPath);
    scope(exit) {}

    string outData;
    string errData;
    auto tOut = new Thread({ outData = readAll(pipes.stdout); });
    auto tErr = new Thread({ errData = readAll(pipes.stderr); });
    tOut.isDaemon = true; tErr.isDaemon = true;
    tOut.start(); tErr.start();

    auto status = wait(pipes.pid);
    tOut.join(); tErr.join();
    outData = outData.replace("\r\n", "\n");
    errData = errData.replace("\r\n", "\n");
    return ExecResult(status, outData, errData);
}
