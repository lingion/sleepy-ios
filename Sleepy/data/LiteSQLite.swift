#if WIDGET_EXT || WATCH_APP || DEBUG
import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum LiteSQLiteError: Error, LocalizedError {
    case open(String)
    case prepare(String)
    case step(String)

    var errorDescription: String? {
        switch self {
        case .open(let m), .prepare(let m), .step(let m): return m
        }
    }
}

enum LiteBindValue {
    case null
    case int(Int)
    case int64(Int64)
    case double(Double)
    case bool(Bool)
    case text(String)
}

final class LiteStatement {
    let stmt: OpaquePointer?

    init(_ db: OpaquePointer?, sql: String) throws {
        var pointer: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &pointer, nil) != SQLITE_OK {
            let msg = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "prepare failed"
            throw LiteSQLiteError.prepare("\(msg): \(sql)")
        }
        self.stmt = pointer
    }

    deinit {
        if let stmt { sqlite3_finalize(stmt) }
    }

    func bind(_ values: [LiteBindValue]) {
        for (idx, val) in values.enumerated() {
            let pos = Int32(idx + 1)
            switch val {
            case .null:
                sqlite3_bind_null(stmt, pos)
            case .int(let v):
                sqlite3_bind_int64(stmt, pos, sqlite3_int64(v))
            case .int64(let v):
                sqlite3_bind_int64(stmt, pos, v)
            case .double(let v):
                sqlite3_bind_double(stmt, pos, v)
            case .bool(let v):
                sqlite3_bind_int64(stmt, pos, v ? 1 : 0)
            case .text(let s):
                sqlite3_bind_text(stmt, pos, s, -1, SQLITE_TRANSIENT)
            }
        }
    }

    func nextRow() -> Bool { sqlite3_step(stmt) == SQLITE_ROW }

    func colInt64(_ idx: Int32) -> Int64 { sqlite3_column_int64(stmt, idx) }
    func colInt(_ idx: Int32) -> Int { Int(sqlite3_column_int64(stmt, idx)) }
    func colDouble(_ idx: Int32) -> Double { sqlite3_column_double(stmt, idx) }
    func colBool(_ idx: Int32) -> Bool { sqlite3_column_int64(stmt, idx) != 0 }
    func colString(_ idx: Int32) -> String {
        guard let c = sqlite3_column_text(stmt, idx) else { return "" }
        return String(cString: c)
    }
    func colOptString(_ idx: Int32) -> String? {
        sqlite3_column_type(stmt, idx) == SQLITE_NULL ? nil : colString(idx)
    }
    func colOptInt64(_ idx: Int32) -> Int64? {
        sqlite3_column_type(stmt, idx) == SQLITE_NULL ? nil : sqlite3_column_int64(stmt, idx)
    }
    func colOptBool(_ idx: Int32) -> Bool? {
        sqlite3_column_type(stmt, idx) == SQLITE_NULL ? nil : (sqlite3_column_int64(stmt, idx) != 0)
    }
}

final class LiteDatabase {
    private var db: OpaquePointer?
    private let lock = NSRecursiveLock()

    init(path: String, createSchema: Bool = true) throws {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        if sqlite3_open_v2(path, &handle, flags, nil) != SQLITE_OK {
            let msg = handle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
            if let handle { sqlite3_close(handle) }
            throw LiteSQLiteError.open(msg)
        }
        self.db = handle
        sqlite3_busy_timeout(handle, 5000)
        // Run connection-level PRAGMAs outside any transaction: SQLite rejects
        // `PRAGMA journal_mode = WAL` inside a transaction and treats
        // `PRAGMA foreign_keys = ON` as a no-op until outside a transaction.
        let bootstrapConn = Connection(db: handle)
        try bootstrapConn.execute("PRAGMA foreign_keys = ON;")
        let currentJournal = try? bootstrapConn.fetchOne("PRAGMA journal_mode;") {
            $0.colString(0).lowercased()
        }
        if currentJournal != "wal" {
            try? bootstrapConn.execute("PRAGMA journal_mode = WAL;")
        }
        // Only the process that owns the GRDB migrations may create tables (see AppDatabase).
        if createSchema { try ensureSchema() }
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    struct Connection {
        let db: OpaquePointer?

        func execute(_ sql: String, arguments: [LiteBindValue] = []) throws {
            let s = try LiteStatement(db, sql: sql)
            s.bind(arguments)
            let rc = sqlite3_step(s.stmt)
            if rc != SQLITE_DONE && rc != SQLITE_ROW {
                let msg = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "step failed"
                throw LiteSQLiteError.step("\(msg): \(sql)")
            }
        }

        func fetchAll<T>(_ sql: String, arguments: [LiteBindValue] = [], map: (LiteStatement) -> T) throws -> [T] {
            let s = try LiteStatement(db, sql: sql)
            s.bind(arguments)
            var items: [T] = []
            while s.nextRow() { items.append(map(s)) }
            return items
        }

        func fetchOne<T>(_ sql: String, arguments: [LiteBindValue] = [], map: (LiteStatement) -> T) throws -> T? {
            let s = try LiteStatement(db, sql: sql)
            s.bind(arguments)
            return s.nextRow() ? map(s) : nil
        }

        var lastInsertRowId: Int64 { sqlite3_last_insert_rowid(db) }
    }

    func read<T>(_ block: (Connection) throws -> T) throws -> T {
        lock.lock(); defer { lock.unlock() }
        return try block(Connection(db: db))
    }

    func write<T>(_ block: (Connection) throws -> T) throws -> T {
        lock.lock(); defer { lock.unlock() }
        let conn = Connection(db: db)
        try conn.execute("BEGIN IMMEDIATE TRANSACTION;")
        do {
            let result = try block(conn)
            try conn.execute("COMMIT;")
            return result
        } catch {
            try? conn.execute("ROLLBACK;")
            throw error
        }
    }

    private func hasCurrentSchema(_ conn: Connection) throws -> Bool {
        let requiredColumns: [(String, [String])] = [
            ("time_tables", [
                "periodTableId", "preBindSnapshotJson", "reminderEnabled",
                "reminderOverride", "importSourceJson", "jwSchoolSourceJson",
                "jwSchoolSourceVerified",
            ]),
            ("courses", [
                "colorMode", "isIrregularNode", "isIrregularTime", "alias", "fixedDate",
            ]),
            ("period_tables", ["comboScheduleJson"]),
            ("course_colors", ["tableKey", "groupId", "hue"]),
        ]
        for (table, columns) in requiredColumns {
            let existing = Set(try conn.fetchAll("PRAGMA table_info(\(table));") { $0.colString(1) })
            if existing.isEmpty { return false }
            for column in columns where !existing.contains(column) {
                return false
            }
        }
        return true
    }

    private func ensureSchema() throws {
        let alreadyCurrent = try read { conn in
            try hasCurrentSchema(conn)
        }
        if alreadyCurrent { return }
        try write { conn in
            try conn.execute("""
                CREATE TABLE IF NOT EXISTS time_tables (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    name TEXT NOT NULL,
                    startDate TEXT NOT NULL,
                    maxWeek INTEGER NOT NULL,
                    nodesPerDay INTEGER NOT NULL,
                    timeJson TEXT NOT NULL,
                    color TEXT NOT NULL,
                    isDefault INTEGER NOT NULL,
                    smartConfigJson TEXT NOT NULL,
                    createdAt INTEGER NOT NULL,
                    periodTableId INTEGER,
                    preBindSnapshotJson TEXT NOT NULL DEFAULT '',
                    reminderEnabled INTEGER NOT NULL DEFAULT 1,
                    reminderOverride INTEGER DEFAULT NULL,
                    importSourceJson TEXT NOT NULL DEFAULT '',
                    jwSchoolSourceJson TEXT NOT NULL DEFAULT '',
                    jwSchoolSourceVerified INTEGER NOT NULL DEFAULT 0
                );
            """)
            try conn.execute("""
                CREATE TABLE IF NOT EXISTS courses (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    groupId TEXT NOT NULL,
                    tableId INTEGER NOT NULL REFERENCES time_tables(id) ON DELETE CASCADE,
                    courseName TEXT NOT NULL,
                    teacher TEXT NOT NULL,
                    room TEXT NOT NULL,
                    note TEXT NOT NULL,
                    day INTEGER NOT NULL,
                    startNode INTEGER NOT NULL,
                    step INTEGER NOT NULL,
                    startWeek INTEGER NOT NULL,
                    endWeek INTEGER NOT NULL,
                    type INTEGER NOT NULL,
                    color TEXT NOT NULL,
                    ownTime INTEGER NOT NULL,
                    startTime TEXT NOT NULL,
                    endTime TEXT NOT NULL,
                    credit REAL NOT NULL,
                    level INTEGER NOT NULL,
                    colorMode INTEGER NOT NULL DEFAULT 0,
                    isIrregularNode INTEGER NOT NULL DEFAULT 0,
                    isIrregularTime INTEGER NOT NULL DEFAULT 0,
                    alias TEXT NOT NULL DEFAULT '',
                    fixedDate TEXT DEFAULT NULL
                );
            """)
            try conn.execute("""
                CREATE TABLE IF NOT EXISTS period_tables (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    name TEXT NOT NULL,
                    nodesPerDay INTEGER NOT NULL,
                    timeJson TEXT NOT NULL,
                    smartConfigJson TEXT NOT NULL,
                    createdAt INTEGER NOT NULL,
                    updatedAt INTEGER NOT NULL,
                    comboScheduleJson TEXT NOT NULL DEFAULT ''
                );
            """)
            try conn.execute("""
                CREATE TABLE IF NOT EXISTS course_colors (
                    tableKey TEXT NOT NULL,
                    groupId TEXT NOT NULL,
                    hue REAL NOT NULL,
                    PRIMARY KEY (tableKey, groupId)
                );
            """)
            try addMissingColumns(conn, table: "time_tables", columns: [
                ("periodTableId", "INTEGER"),
                ("preBindSnapshotJson", "TEXT NOT NULL DEFAULT ''"),
                ("reminderEnabled", "INTEGER NOT NULL DEFAULT 1"),
                ("reminderOverride", "INTEGER DEFAULT NULL"),
                ("importSourceJson", "TEXT NOT NULL DEFAULT ''"),
                ("jwSchoolSourceJson", "TEXT NOT NULL DEFAULT ''"),
                ("jwSchoolSourceVerified", "INTEGER NOT NULL DEFAULT 0"),
            ])
            try addMissingColumns(conn, table: "courses", columns: [
                ("colorMode", "INTEGER NOT NULL DEFAULT 0"),
                ("isIrregularNode", "INTEGER NOT NULL DEFAULT 0"),
                ("isIrregularTime", "INTEGER NOT NULL DEFAULT 0"),
                ("alias", "TEXT NOT NULL DEFAULT ''"),
                ("fixedDate", "TEXT DEFAULT NULL"),
            ])
            try addMissingColumns(conn, table: "period_tables", columns: [
                ("comboScheduleJson", "TEXT NOT NULL DEFAULT ''"),
            ])
        }
    }

    private func addMissingColumns(_ conn: Connection, table: String, columns: [(String, String)]) throws {
        let existing = Set(try conn.fetchAll("PRAGMA table_info(\(table));") { $0.colString(1) })
        for (name, def) in columns where !existing.contains(name) {
            try conn.execute("ALTER TABLE \(table) ADD COLUMN \(name) \(def);")
        }
    }
}
#endif
