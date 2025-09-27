module duende_packages.stdnet.duende_net;

// Minimal networking helpers used by Duende examples
import std.socket; // use full module to access Socket, TcpSocket, UdpSocket, InternetAddress
import std.conv;
import std.string;
import std.array;
import std.stdio;
import core.thread;
import core.time;
version (Posix) {
    import core.sys.posix.sys.select;
    import core.sys.posix.sys.types;
}
version (Windows) {
    import core.sys.windows.winsock2;
}

struct TcpListener { Socket sock; }
struct TcpSocket { Socket sock; }
struct UdpSocket { UdpSocketD sock; }

alias UdpSocketD = std.socket.UdpSocket;
alias TcpSocketD = std.socket.TcpSocket;

// Internal: wait until a socket is readable or timeout
private bool waitReadable(Socket s, long timeoutMs) {
    version (Posix) {
        fd_set rfds;
        FD_ZERO(&rfds);
        FD_SET(cast(int)s.handle, &rfds);
        timeval tv;
        tv.tv_sec = cast(typeof(tv.tv_sec))(timeoutMs / 1000);
        tv.tv_usec = cast(typeof(tv.tv_usec))((timeoutMs % 1000) * 1000);
        auto n = select(cast(int)s.handle + 1, &rfds, null, null, &tv);
        return n > 0 && FD_ISSET(cast(int)s.handle, &rfds) != 0;
    } else version (Windows) {
        fd_set rfds;
        FD_ZERO(&rfds);
        FD_SET(cast(SOCKET)s.handle, &rfds);
        TIMEVAL tv;
        tv.tv_sec = cast(typeof(tv.tv_sec))(timeoutMs / 1000);
        tv.tv_usec = cast(typeof(tv.tv_usec))((timeoutMs % 1000) * 1000);
        auto n = select(0, &rfds, null, null, &tv);
        return n > 0 && FD_ISSET(cast(SOCKET)s.handle, &rfds) != 0;
    } else {
        // Fallback: simple sleep-based wait
        auto deadline = MonoTime.currTime + msecs(timeoutMs);
        while (MonoTime.currTime < deadline) { Thread.sleep(msecs(1)); }
        return true;
    }
}

TcpListener tcpListen(long port, string address = "127.0.0.1", int backlog = 10) {
    auto s = new TcpSocketD(AddressFamily.INET);
    s.setOption(SocketOptionLevel.SOCKET, SocketOption.REUSEADDR, 1);
    s.bind(new InternetAddress(address, cast(ushort)port));
    s.listen(backlog);
    return TcpListener(s);
}

TcpSocket tcpAccept(ref TcpListener listener) {
    auto s = listener.sock.accept();
    s.setOption(SocketOptionLevel.TCP, SocketOption.TCP_NODELAY, 1);
    return TcpSocket(s);
}

void tcpClose(ref TcpListener listener) {
    scope(exit) {} // keep signature; no-op wrapper
    if (listener.sock !is null) listener.sock.close();
}

void tcpClose(ref TcpSocket client) {
    scope(exit) {} // keep signature; no-op wrapper
    if (client.sock !is null) client.sock.close();
}

TcpSocket tcpConnect(string host, long port) {
    auto s = new TcpSocketD(AddressFamily.INET);
    s.setOption(SocketOptionLevel.TCP, SocketOption.TCP_NODELAY, 1);
    s.connect(new InternetAddress(host, cast(ushort)port));
    return TcpSocket(s);
}

// Send a full string with newline (optional)
long tcpSend(ref TcpSocket s, string data, bool addNewline = false) {
    auto buf = addNewline ? (data ~ "\n") : data;
    auto bytes = cast(const(ubyte)[])buf;
    long sent = 0;
    while (sent < bytes.length) {
        auto n = s.sock.send(bytes[sent .. $]);
        if (n <= 0) break;
        sent += n;
    }
    return sent;
}

// Receive a line terminated by \n (without trailing newline)
string tcpRecvLine(ref TcpSocket s) {
    ubyte[] buf;
    buf.reserve(256);
    ubyte[1] tmp;
    while (true) {
        auto r = s.sock.receive(tmp);
        if (r == 1) {
            if (tmp[0] == '\n') break;
            buf ~= tmp[0];
        } else if (r == 0) {
            // connection closed
            break;
        }
    }
    return cast(string)buf.idup;
}

// Receive a line with timeout in milliseconds; returns partial data if timeout elapses
string tcpRecvLineTimeout(ref TcpSocket s, long timeoutMs) {
    ubyte[] lbuf;
    lbuf.reserve(256);
    ubyte[1] btmp;
    long remainMs = timeoutMs;
    while (remainMs > 0) {
        long sliceMs = remainMs > 50 ? 50 : remainMs;
        if (!waitReadable(s.sock, sliceMs)) {
            remainMs -= sliceMs;
            continue;
        }
        auto r = s.sock.receive(btmp);
        if (r == 1) {
            if (btmp[0] == '\n') break;
            lbuf ~= btmp[0];
        } else if (r == 0) {
            break; // connection closed
        }
        // Don't decrement remain if we actually read; let next loop compute
    }
    return cast(string)lbuf.idup;
}

// Receive all currently available bytes (single blocking read)
string tcpRecvAll(ref TcpSocket s) {
    ubyte[] buf;
    ubyte[1024] tmp;
    // Single blocking read; read what's available up to buffer size
    auto n = s.sock.receive(tmp[]);
    if (n > 0) buf ~= tmp[0 .. n];
    return cast(string)buf.idup;
}

// Spawn a detached thread that accepts once from a listener, echoes back one line with prefix "echo:", and closes.
void spawnEchoOnce(ref TcpListener listener) {
    auto ls = listener; // copy struct (socket ref)
    auto th = new Thread({
        try {
            auto client = tcpAccept(ls);
            auto line = tcpRecvLine(client);
            auto _sent = tcpSend(client, "echo:" ~ line, true);
            cast(void)_sent; // ignore
            tcpClose(client);
        } catch (Exception e) {
            // swallow for demo
        }
    });
    th.isDaemon = true;
    th.start();
}

// Accept with a timeout; returns true on success and sets client
bool tcpAcceptTimeout(ref TcpListener listener, out TcpSocket client, long timeoutMs) {
    if (!waitReadable(listener.sock, timeoutMs)) {
        client = TcpSocket(null);
        return false;
    }
    auto s = listener.sock.accept();
    s.setOption(SocketOptionLevel.TCP, SocketOption.TCP_NODELAY, 1);
    client = TcpSocket(s);
    return true;
}

// UDP helpers
UdpSocket udpOpen(long port = 0, string address = "0.0.0.0") {
    auto s = new UdpSocketD(AddressFamily.INET);
    s.bind(new InternetAddress(address, cast(ushort)port));
    return UdpSocket(s);
}

long udpSendTo(ref UdpSocket s, string host, long port, string data) {
    auto addr = new InternetAddress(host, cast(ushort)port);
    auto bytes = cast(const(ubyte)[])data;
    return s.sock.sendTo(bytes, addr);
}

string udpRecvFrom(ref UdpSocket s, out string fromHost, out long fromPort) {
    ubyte[2048] buf;
    Address from;
    auto n = s.sock.receiveFrom(buf[], from);
    if (n > 0) {
        if (auto ia = cast(InternetAddress)from) {
            fromHost = ia.toAddrString();
            fromPort = ia.port;
        } else {
            fromHost = ""; fromPort = 0;
        }
        return cast(string)buf[0 .. n].idup;
    }
    fromHost = ""; fromPort = 0;
    return "";
}

// Receive a datagram with timeout; returns empty string on timeout
string udpRecv(ref UdpSocket s, long timeoutMs = 1000) {
    if (!waitReadable(s.sock, timeoutMs)) return "";
    ubyte[2048] ubuf;
    Address from;
    auto r = s.sock.receiveFrom(ubuf[], from);
    if (r > 0) return cast(string)ubuf[0 .. r].idup;
    return "";
}

// Get bound local port
long udpLocalPort(ref UdpSocket s) {
    auto a = s.sock.localAddress();
    if (auto ia = cast(InternetAddress)a) return cast(long)ia.port;
    return 0;
}

void udpClose(ref UdpSocket s) {
    if (s.sock !is null) s.sock.close();
}

// Spawn a detached UDP echo (single datagram) server on provided socket
void spawnUdpEchoOnce(ref UdpSocket sock) {
    auto us = sock;
    auto th = new Thread({
        try {
            if (!waitReadable(us.sock, 2000)) return;
            ubyte[2048] ubuf;
            Address from;
            auto n = us.sock.receiveFrom(ubuf[], from);
            if (n > 0) {
                if (auto ia = cast(InternetAddress)from) {
                    auto msg = cast(string)ubuf[0 .. n];
                    auto reply = "udp:" ~ msg;
                    auto bytes = cast(const(ubyte)[])reply;
                    us.sock.sendTo(bytes, ia);
                }
            }
        } catch (Exception) {}
    });
    th.isDaemon = true; th.start();
}
