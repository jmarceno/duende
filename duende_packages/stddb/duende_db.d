module duende_packages.stddb.duende_db;

// Thin wrappers around ddbc to provide a stable API for Duende programs.
// We keep types simple and stringly-typed where possible for portability.

import ddbc;
import std.stdio;
import std.string;
import std.conv;
import std.array;

struct DBConn { Connection conn; }
struct DBStmt { PreparedStatement stmt; }

// Connect using ddbc connection string.
// Examples:
//   "ddbc:sqlite::memory:" or "sqlite::memory:" for in-memory SQLite
//   "ddbc:sqlite:my.db" for file-based SQLite
// Other databases depend on client libs being installed.
DBConn dbConnect(string url) {
    auto u = url;
    // Allow omitting ddbc: prefix
    if (!u.startsWith("ddbc:")) {
        u = "ddbc:" ~ u;
    }
    auto c = createConnection(u);
    return DBConn(c);
}

void dbClose(ref DBConn dbc) {
    if (dbc.conn !is null) {
        dbc.conn.close();
    }
}

// Transaction helpers
void dbBegin(ref DBConn dbc) { auto s = dbc.conn.createStatement(); scope(exit) s.close(); s.executeUpdate("BEGIN"); }
void dbCommit(ref DBConn dbc) { auto s = dbc.conn.createStatement(); scope(exit) s.close(); s.executeUpdate("COMMIT"); }
void dbRollback(ref DBConn dbc) { auto s = dbc.conn.createStatement(); scope(exit) s.close(); s.executeUpdate("ROLLBACK"); }

// Execute a non-query (DDL/DML). Returns affected rows if supported, else 0.
long dbExecute(ref DBConn dbc, string sql) {
    auto s = dbc.conn.createStatement();
    scope(exit) s.close();
    return cast(long)s.executeUpdate(sql);
}

// Run a SELECT expected to return a single scalar value (first row, first column). Returns empty string if no rows.
string dbQueryScalar(ref DBConn dbc, string sql) {
    auto s = dbc.conn.createStatement();
    scope(exit) s.close();
    auto rs = s.executeQuery(sql);
    if (rs.next()) {
        // Convert any type to string via ddbc getters; prefer getString when possible
        auto v = rs.getString(1);
        return v is null ? "" : v;
    }
    return "";
}

// Run a SELECT and materialize to string[][], converting each column to string with getString.
string[][] dbQueryAll(ref DBConn dbc, string sql) {
    auto s = dbc.conn.createStatement();
    scope(exit) s.close();
    auto rs = s.executeQuery(sql);
    string[][] rows;
    auto meta = rs.getMetaData();
    long cols = cast(long)meta.getColumnCount();
    while (rs.next()) {
        string[] row;
        foreach (i; 1 .. cols + 1) {
            auto v = rs.getString(cast(int)i);
            row ~= (v is null ? "" : v);
        }
        rows ~= row;
    }
    return rows;
}

// Prepared statements API
DBStmt dbPrepare(ref DBConn dbc, string sql) {
    auto ps = dbc.conn.prepareStatement(sql);
    return DBStmt(cast(PreparedStatement)ps);
}

void dbCloseStmt(ref DBStmt st) {
    if (st.stmt !is null) st.stmt.close();
}

void dbCloseStmtTry(ref DBStmt st) {
    if (st.stmt is null) return;
    try {
        st.stmt.close();
    } catch (Exception) {
        // ignore
    }
}

void dbBindString(ref DBStmt st, long idx, string value) { st.stmt.setString(cast(int)idx, value); }

void dbBindInt(ref DBStmt st, long idx, long value) { st.stmt.setLong(cast(int)idx, value); }
// Bind a floating-point value (double)
void dbBindFloat(ref DBStmt st, long idx, double value) { st.stmt.setDouble(cast(int)idx, value); }
// Bind raw bytes (blob). Duende's `bytes` maps to D ubyte[]; ddbc expects byte[]
void dbBindBytes(ref DBStmt st, long idx, ubyte[] value) {
    st.stmt.setBytes(cast(int)idx, cast(byte[])value);
}

long dbExecPrepared(ref DBStmt st) { return cast(long)st.stmt.executeUpdate(); }

// Safe variants that catch exceptions and return -1 on error
long dbExecuteTry(ref DBConn dbc, string sql) {
    auto s = dbc.conn.createStatement();
    scope(exit) s.close();
    try {
        return cast(long)s.executeUpdate(sql);
    } catch (Exception) {
        return -1;
    }
}

long dbExecPreparedTry(ref DBStmt st) {
    try {
        return cast(long)st.stmt.executeUpdate();
    } catch (Exception) {
        return -1;
    }
}
