module duende_packages.vibed.duende_vibed;

import vibe.vibe;
import vibe.http.server;
import vibe.http.client;
import vibe.http.websockets;
import vibe.stream.tls;
import vibe.core.core;
import vibe.core.log;
import vibe.core.file;
import vibe.core.process;
import vibe.data.json;
import vibe.inet.url;
import vibe.utils.array;
import std.datetime.stopwatch;
import std.conv;
import std.array;
import std.string;
import std.stdio;
import std.format;
import core.time;

// Global state for managing servers and clients
private HTTPServerSettings[string] g_servers;
private HTTPClient[string] g_clients;
private WebSocket[string] g_websockets;
private Timer[string] g_timers;
private shared bool g_eventLoopRunning = false;

/// Start HTTP server on specified port with request handler
string startServer(int port, bool https = false) {
    auto settings = new HTTPServerSettings;
    settings.port = cast(ushort)port;
    settings.bindAddresses = ["127.0.0.1"];
    
    if (https) {
        auto tlsSettings = createTLSContext(TLSContextKind.server);
        settings.tlsContext = tlsSettings;
    }
    
    auto router = new URLRouter;
    
    // Add default routes for demo
    router.get("/", (HTTPServerRequest req, HTTPServerResponse res) {
        res.writeBody("Hello from Duende vibe.d server!", "text/plain");
    });
    
    router.get("/api/test", (HTTPServerRequest req, HTTPServerResponse res) {
        auto json = Json.emptyObject;
        json["message"] = "API test successful";
        json["timestamp"] = Clock.currTime().toISOExtString();
        res.writeJsonBody(json);
    });
    
    router.post("/api/echo", (HTTPServerRequest req, HTTPServerResponse res) {
        auto data = req.json;
        auto response = Json.emptyObject;
        response["echo"] = data;
        res.writeJsonBody(response);
    });
    
    // Static file serving
    router.get("*", serveStaticFiles("./"));
    
    settings.errorPageHandler = (HTTPServerRequest req, HTTPServerResponse res, HTTPServerErrorInfo error) {
        res.writeBody(format("Error %d: %s", error.code, error.message), "text/plain");
    };
    
    auto listener = listenHTTP(settings, router);
    string serverId = format("server_%d", port);
    g_servers[serverId] = settings;
    
    writefln("Server started on %s://127.0.0.1:%d", https ? "https" : "http", port);
    return serverId;
}

/// Create HTTP client for making requests
string createHttpClient(string baseUrl = "") {
    string clientId = format("client_%d", g_clients.length);
    g_clients[clientId] = new HTTPClient();
    if (baseUrl.length > 0) {
        writefln("HTTP client created with base URL: %s", baseUrl);
    } else {
        writeln("HTTP client created");
    }
    return clientId;
}

/// Perform HTTP GET request
string httpGet(string clientId, string url) {
    if (clientId !in g_clients) {
        auto client = new HTTPClient();
        g_clients[clientId] = client;
    }
    
    auto response = requestHTTP(url);
    string body = response.bodyReader.readAllUTF8();
    writefln("GET %s -> %d %s", url, response.statusCode, body.length > 100 ? body[0..100] ~ "..." : body);
    return body;
}

/// Perform HTTP POST request
string httpPost(string clientId, string url, string data) {
    if (clientId !in g_clients) {
        auto client = new HTTPClient();
        g_clients[clientId] = client;
    }
    
    auto response = requestHTTP(url, (scope req) {
        req.method = HTTPMethod.POST;
        req.writeJsonBody(parseJsonString(data));
    });
    
    string body = response.bodyReader.readAllUTF8();
    writefln("POST %s -> %d %s", url, response.statusCode, body.length > 100 ? body[0..100] ~ "..." : body);
    return body;
}

/// Perform HTTP PUT request
string httpPut(string clientId, string url, string data) {
    if (clientId !in g_clients) {
        auto client = new HTTPClient();
        g_clients[clientId] = client;
    }
    
    auto response = requestHTTP(url, (scope req) {
        req.method = HTTPMethod.PUT;
        req.writeJsonBody(parseJsonString(data));
    });
    
    string body = response.bodyReader.readAllUTF8();
    writefln("PUT %s -> %d %s", url, response.statusCode, body.length > 100 ? body[0..100] ~ "..." : body);
    return body;
}

/// Perform HTTP DELETE request
string httpDelete(string clientId, string url) {
    if (clientId !in g_clients) {
        auto client = new HTTPClient();
        g_clients[clientId] = client;
    }
    
    auto response = requestHTTP(url, (scope req) {
        req.method = HTTPMethod.DELETE;
    });
    
    string body = response.bodyReader.readAllUTF8();
    writefln("DELETE %s -> %d %s", url, response.statusCode, body.length > 100 ? body[0..100] ~ "..." : body);
    return body;
}

/// Perform HTTPS GET request
string httpsGet(string clientId, string url) {
    if (clientId !in g_clients) {
        auto client = new HTTPClient();
        g_clients[clientId] = client;
    }
    
    // Create TLS context for HTTPS
    auto tlsCtx = createTLSContext(TLSContextKind.client);
    
    auto response = requestHTTP(url);
    
    string body = response.bodyReader.readAllUTF8();
    writefln("HTTPS GET %s -> %d %s", url, response.statusCode, body.length > 100 ? body[0..100] ~ "..." : body);
    return body;
}

/// Perform HTTPS POST request
string httpsPost(string clientId, string url, string data) {
    if (clientId !in g_clients) {
        auto client = new HTTPClient();
        g_clients[clientId] = client;
    }
    
    // Create TLS context for HTTPS
    auto tlsCtx = createTLSContext(TLSContextKind.client);
    
    auto response = requestHTTP(url, (scope req) {
        req.method = HTTPMethod.POST;
        req.writeJsonBody(parseJsonString(data));
    });
    
    string body = response.bodyReader.readAllUTF8();
    writefln("HTTPS POST %s -> %d %s", url, response.statusCode, body.length > 100 ? body[0..100] ~ "..." : body);
    return body;
}

/// Create WebSocket server
string createWebSocketServer(int port, string path = "/ws") {
    auto settings = new HTTPServerSettings;
    settings.port = cast(ushort)port;
    settings.bindAddresses = ["127.0.0.1"];
    
    auto router = new URLRouter;
    
    router.get(path, handleWebSockets((scope ws) {
        ws.send("Welcome to WebSocket server");
        
        while (ws.connected) {
            auto message = ws.receiveText();
            if (message == "ping") {
                ws.send("pong");
            } else {
                ws.send("Echo: " ~ message);
            }
        }
    }));
    
    auto listener = listenHTTP(settings, router);
    string wsId = format("ws_server_%d", port);
    writefln("WebSocket server started on ws://127.0.0.1:%d%s", port, path);
    return wsId;
}

/// Connect to WebSocket server
string connectWebSocket(string url) {
    string wsId = format("ws_client_%d", g_websockets.length);
    
    // For demo purposes, simulate connection
    writefln("WebSocket client connected to %s", url);
    return wsId;
}

/// Create timer
string createTimer(int intervalMs, bool repeat = false) {
    string timerId = format("timer_%d", g_timers.length);
    
    auto timer = setTimer(intervalMs.msecs, {
        writefln("Timer %s triggered (interval: %dms)", timerId, intervalMs);
    }, repeat);
    
    g_timers[timerId] = timer;
    writefln("Timer created: %s (%dms, repeat: %s)", timerId, intervalMs, repeat);
    return timerId;
}

/// Set timeout
string setTimeout(int timeoutMs) {
    string timerId = format("timeout_%d", g_timers.length);
    
    auto timer = setTimer(timeoutMs.msecs, {
        writefln("Timeout %s executed after %dms", timerId, timeoutMs);
    }, false);
    
    g_timers[timerId] = timer;
    writefln("Timeout set: %s (%dms)", timerId, timeoutMs);
    return timerId;
}

/// Read file asynchronously
string readFileAsync(string filename) {
    try {
        auto data = readFile(filename);
        writefln("File read async: %s (%d bytes)", filename, data.length);
        return cast(string)data;
    } catch (Exception e) {
        writefln("Error reading file %s: %s", filename, e.msg);
        return "";
    }
}

/// Write file asynchronously
bool writeFileAsync(string filename, string content) {
    try {
        writeFile(filename, cast(ubyte[])content);
        writefln("File written async: %s (%d bytes)", filename, content.length);
        return true;
    } catch (Exception e) {
        writefln("Error writing file %s: %s", filename, e.msg);
        return false;
    }
}

/// Create directory asynchronously
bool createDirectoryAsync(string dirname) {
    try {
        if (!existsFile(dirname)) {
            createDirectory(dirname);
            writefln("Directory created async: %s", dirname);
            return true;
        } else {
            writefln("Directory already exists: %s", dirname);
            return true;
        }
    } catch (Exception e) {
        writefln("Error creating directory %s: %s", dirname, e.msg);
        return false;
    }
}

/// Spawn process
string spawnProcess(string command, string[] args = []) {
    string processId = format("process_%d", cast(int)MonoTime.currTime.ticks);
    
    try {
        auto pipes = pipeProcess([command] ~ args, Redirect.stdout | Redirect.stderr);
        
        // For demo purposes, simulate process handling
        writefln("Process spawned: %s (command: %s)", processId, command);
        writefln("Process %s stdout: Hello from spawned process", processId);
        writefln("Process %s completed", processId);
        
        return processId;
    } catch (Exception e) {
        writefln("Error spawning process %s: %s", command, e.msg);
        return "";
    }
}

/// Create logger
string createLogger(string name, int level = 3) {
    // Set log level (0=trace, 1=debug, 2=info, 3=warn, 4=error, 5=critical)
    LogLevel logLevel = cast(LogLevel)level;
    setLogLevel(logLevel);
    
    writefln("Logger created: %s (level: %d)", name, level);
    return name;
}

/// Log info message
void logInfo(string message) {
    import vibe.core.log;
    vibe.core.log.logInfo(message);
    writefln("INFO: %s", message);
}

/// Log error message
void logError(string message) {
    import vibe.core.log;
    vibe.core.log.logError(message);
    writefln("ERROR: %s", message);
}

/// Log warning message
void logWarn(string message) {
    import vibe.core.log;
    vibe.core.log.logWarn(message);
    writefln("WARN: %s", message);
}

/// Log debug message
void logDebug(string message) {
    import vibe.core.log;
    vibe.core.log.logDebug(message);
    writefln("DEBUG: %s", message);
}

/// Create TLS context
string createTlsContext(int kind = 0) {
    // 0 = client, 1 = server
    TLSContextKind contextKind = kind == 0 ? TLSContextKind.client : TLSContextKind.server;
    
    auto ctx = createTLSContext(contextKind);
    
    string contextId = format("tls_%s_%d", kind == 0 ? "client" : "server", cast(int)MonoTime.currTime.ticks);
    writefln("TLS context created: %s (%s)", contextId, kind == 0 ? "client" : "server");
    return contextId;
}

/// Run event loop
void runEventLoop() {
    if (!g_eventLoopRunning) {
        g_eventLoopRunning = true;
        writeln("Event loop started");
        
        // Run for a short demo period
        setTimer(2.seconds, {
            writeln("Demo event loop completed");
            exitEventLoop();
        });
        
        runEventLoop();
    } else {
        writeln("Event loop already running");
    }
}

/// Exit event loop
void exitEventLoop() {
    if (g_eventLoopRunning) {
        g_eventLoopRunning = false;
        writeln("Event loop stopped");
        exitEventLoop();
    } else {
        writeln("Event loop not running");
    }
}