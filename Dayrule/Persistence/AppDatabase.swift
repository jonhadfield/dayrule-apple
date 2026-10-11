import Foundation
import GRDB

enum AppDatabase {
    /// Open (or create) the per-account ciphertext DB under Application Support.
    static func open(userId: String) throws -> DatabaseQueue {
        try FileManager.default.createDirectory(at: directoryURL(), withIntermediateDirectories: true)
        return try open(at: databaseURL(userId: userId))
    }

    /// Remove the per-account ciphertext DB (and sidecars) after account deletion.
    static func remove(userId: String) throws {
        let url = try databaseURL(userId: userId)
        let fm = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            let path = url.path + suffix
            if fm.fileExists(atPath: path) {
                try fm.removeItem(atPath: path)
            }
        }
    }

    private static func directoryURL() throws -> URL {
        try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("Dayrule", isDirectory: true)
    }

    private static func databaseURL(userId: String) throws -> URL {
        let safe = userId.replacingOccurrences(of: "/", with: "_")
        return try directoryURL().appendingPathComponent("data-\(safe).sqlite")
    }

    /// Open (or create) a ciphertext DB at an explicit path (tests / custom roots).
    static func open(at url: URL) throws -> DatabaseQueue {
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        let dbQueue = try DatabaseQueue(path: url.path, configuration: config)
        try migrator.migrate(dbQueue)
        FileProtection.protectCiphertextFile(at: url)
        return dbQueue
    }

    static func openInMemory() throws -> DatabaseQueue {
        let dbQueue = try DatabaseQueue()
        try migrator.migrate(dbQueue)
        return dbQueue
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_ciphertext") { db in
            try db.create(table: "records") { t in
                t.column("id", .text).primaryKey()
                t.column("alg", .integer).notNull()
                t.column("keyId", .integer).notNull()
                t.column("nonce", .text).notNull()
                t.column("ciphertext", .text).notNull()
            }
            try db.create(table: "outbox") { t in
                t.column("key", .text).primaryKey()
                t.column("rev", .integer).notNull()
            }
            try db.create(table: "syncmeta") { t in
                t.column("key", .text).primaryKey()
                t.column("seq", .integer).notNull()
            }
            try db.create(table: "tombstones") { t in
                t.column("key", .text).primaryKey()
                t.column("hlc", .text).notNull()
            }
            try db.create(table: "state") { t in
                t.column("k", .text).primaryKey()
                t.column("v", .text).notNull() // JSON
            }
        }
        // Unknown-alg wire records kept untouched until the client upgrades (PLAN §10.2).
        migrator.registerMigration("v2_opaque_records") { db in
            try db.create(table: "opaque_records") { t in
                t.column("id", .text).primaryKey()
                t.column("seq", .integer).notNull()
                t.column("alg", .integer).notNull()
                t.column("keyId", .integer).notNull()
                t.column("nonce", .text).notNull()
                t.column("ciphertext", .text).notNull()
                t.column("tombstone", .integer).notNull().defaults(to: 0)
            }
        }
        return migrator
    }
}
