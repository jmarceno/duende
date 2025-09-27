module duende_packages.stdasync.duende_async;

// A tiny cooperative scheduler built on D fibers to support async-style code.
// This module aims to be cross-platform and work together with Duende's stdnet.

import core.thread;
import core.time;
import core.thread.fiber;
import std.datetime.stopwatch;
import std.exception;
import std.stdio;
import std.array;
import std.algorithm;
import std.conv;
import std.typecons;
import std.variant;
import std.functional;
import std.string;
import std.traits;

version (Posix) {
    import core.sys.posix.sys.select; // for FD_SET and select
    import core.sys.posix.sys.types;
}
version (Windows) {
    import core.sys.windows.winsock2;
}

// Task represents a scheduled fiber with an optional wake time
private struct Task {
    Fiber fiber;
    MonoTime wakeAt; // ready when MonoTime.currTime >= wakeAt; init == MonoTime.init means runnable now
    bool waitingIO;
    size_t ioHandle; // OS handle for socket-like readiness waiting (cast to size_t)
}

// Very small global scheduler (single thread, cooperative)
private __gshared Task[] gQueue;
private __gshared bool gRunning;

// Internal: schedule a fiber now
private void scheduleNow(Fiber f) {
    Task t; t.fiber = f; t.wakeAt = MonoTime.init; t.waitingIO = false; t.ioHandle = 0; gQueue ~= t;
}

// Internal: schedule after ms
private void scheduleAfter(Fiber f, long ms) {
    Task t; t.fiber = f; t.wakeAt = MonoTime.currTime + msecs(ms); t.waitingIO = false; t.ioHandle = 0; gQueue ~= t;
}

// Internal: schedule when handle readable
private void scheduleOnReadable(Fiber f, size_t handle) {
    Task t; t.fiber = f; t.wakeAt = MonoTime.init; t.waitingIO = true; t.ioHandle = handle; gQueue ~= t;
}

// Yield current fiber back to scheduler cooperatively
void yieldNow() {
    auto cur = Fiber.getThis();
    enforce(cur !is null, "yieldNow must be called from within a fiber spawned by std.async");
    // Reschedule immediately to the back of the queue
    scheduleNow(cur);
    cur.yield();
}

// Sleep for a number of milliseconds cooperatively (does not block thread)
void sleepAsync(long ms) {
    auto cur = Fiber.getThis();
    if (cur is null) {
        // If called outside fiber, fall back to blocking sleep
        Thread.sleep(msecs(ms));
        return;
    }
    scheduleAfter(cur, ms);
    cur.yield();
}

// Await until a raw socket handle is readable (best-effort, cross-platform)
// handle should be an OS descriptor integer. Duende's stdnet exposes s.sock.handle.
void awaitReadable(size_t handle, long timeoutMs = 0) {
    auto cur = Fiber.getThis();
    if (cur is null) {
        // Fallback to blocking poll
        version (Posix) {
            fd_set rfds; FD_ZERO(&rfds); FD_SET(cast(int)handle, &rfds);
            timeval tv; tv.tv_sec = cast(typeof(tv.tv_sec))(timeoutMs / 1000);
            tv.tv_usec = cast(typeof(tv.tv_usec))((timeoutMs % 1000) * 1000);
            auto n = select(cast(int)handle + 1, &rfds, null, null, (timeoutMs > 0 ? &tv : null));
            // ignore result
        } else version (Windows) {
            fd_set rfds; FD_ZERO(&rfds); FD_SET(cast(SOCKET)handle, &rfds);
            TIMEVAL tv; tv.tv_sec = cast(typeof(tv.tv_sec))(timeoutMs / 1000);
            tv.tv_usec = cast(typeof(tv.tv_usec))((timeoutMs % 1000) * 1000);
            auto n = select(0, &rfds, null, null, (timeoutMs > 0 ? &tv : null));
        } else {
            if (timeoutMs > 0) Thread.sleep(msecs(timeoutMs));
        }
        return;
    }
    scheduleOnReadable(cur, handle);
    cur.yield();
}

// Spawn a new fiber running f; returns immediately
void spawn(void delegate() f) {
    auto fb = new Fiber({ f(); });
    scheduleNow(fb);
}

// Overload: accept a delegate(long)->long to match Duende lambda codegen.
// The argument is ignored and the return value is discarded.
void spawn(long delegate(long) f) {
    auto fb = new Fiber({ f(0); });
    scheduleNow(fb);
}

// Simple event loop: runs until the queue is empty
void run() {
    gRunning = true;
    scope(exit) gRunning = false;
    while (gQueue.length) {
        // Select next ready task
        size_t idx = size_t.max;
        MonoTime now = MonoTime.currTime;

        // First pass: find runnable now (no wakeAt or waitingIO already ready)
        foreach (i, t; gQueue) {
            if (t.waitingIO) continue; // handle in IO pass
            if (t.wakeAt == MonoTime.init || now >= t.wakeAt) { idx = i; break; }
        }

        if (idx == size_t.max) {
            // IO readiness or sleep wait; compute min sleep
            long minSleepMs = long.max;
            bool hasIO = false;
            // Determine earliest wake and if any IO waits exist
            foreach (t; gQueue) {
                if (t.waitingIO) hasIO = true;
                else if (t.wakeAt != MonoTime.init) {
                    auto diff = t.wakeAt - now;
                    auto ms = diff.total!"msecs";
                    if (ms < minSleepMs) minSleepMs = ms;
                }
            }

            // If there's IO, poll with select for readiness, else sleep
            if (hasIO) {
                // Build fd_sets
                version (Posix) {
                    fd_set rfds; FD_ZERO(&rfds);
                    int maxfd = -1;
                    foreach (t; gQueue) if (t.waitingIO) { FD_SET(cast(int)t.ioHandle, &rfds); if (cast(int)t.ioHandle > maxfd) maxfd = cast(int)t.ioHandle; }
                    timeval tv; timeval* ptv = null;
                    if (minSleepMs != long.max) { tv.tv_sec = cast(typeof(tv.tv_sec))(minSleepMs / 1000); tv.tv_usec = cast(typeof(tv.tv_usec))((minSleepMs % 1000) * 1000); ptv = &tv; }
                    auto n = select(maxfd + 1, &rfds, null, null, ptv);
                    // Mark those fibers runnable now
                    foreach (i, ref t; gQueue) {
                        if (t.waitingIO) {
                            if (n > 0 && FD_ISSET(cast(int)t.ioHandle, &rfds)) { t.waitingIO = false; t.wakeAt = MonoTime.init; }
                        }
                    }
                } else version (Windows) {
                    fd_set rfds; FD_ZERO(&rfds);
                    foreach (t; gQueue) if (t.waitingIO) { FD_SET(cast(SOCKET)t.ioHandle, &rfds); }
                    TIMEVAL tv; TIMEVAL* ptv = null;
                    if (minSleepMs != long.max) { tv.tv_sec = cast(typeof(tv.tv_sec))(minSleepMs / 1000); tv.tv_usec = cast(typeof(tv.tv_usec))((minSleepMs % 1000) * 1000); ptv = &tv; }
                    auto n = select(0, &rfds, null, null, ptv);
                    foreach (i, ref t; gQueue) {
                        if (t.waitingIO) {
                            if (n > 0 && FD_ISSET(cast(SOCKET)t.ioHandle, &rfds)) { t.waitingIO = false; t.wakeAt = MonoTime.init; }
                        }
                    }
                } else {
                    // No select: coarse sleep
                    if (minSleepMs == long.max) minSleepMs = 1;
                    Thread.sleep(msecs(minSleepMs));
                }

                // After polling, pick any now-runnable task
                foreach (i, t; gQueue) {
                    if (!t.waitingIO && (t.wakeAt == MonoTime.init || MonoTime.currTime >= t.wakeAt)) { idx = i; break; }
                }
            } else {
                // Only sleeps scheduled
                if (minSleepMs == long.max) minSleepMs = 1; // avoid busy loop
                Thread.sleep(msecs(minSleepMs));
                foreach (i, t; gQueue) {
                    if (t.wakeAt == MonoTime.init || MonoTime.currTime >= t.wakeAt) { idx = i; break; }
                }
            }
        }

        if (idx == size_t.max) {
            // Nothing to run yet; avoid tight spin
            Thread.sleep(msecs(1));
            continue;
        }

        // Pop selected task
        auto task = gQueue[idx];
        gQueue = gQueue[0 .. idx] ~ gQueue[idx + 1 .. $];

        // Switch to fiber; it must reschedule itself when yielding
        try {
            task.fiber.call();
        } catch (Exception) {
            // Swallow to keep scheduler running; user code can handle errors
        }

        // If finished, fiber state is TERM and will not be rescheduled unless the function did so.
    }
}
