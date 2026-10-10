import Foundation
import GRDB

enum AppDatabase {
    /// Open (or create) the per-account ciphertext DB under Application Support.
    static func open(userId: String) throws -> DatabaseQueue {
        let root = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("Dayrule", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let safe = userId.replacingOccurrences(of: "/", with: "_")
        let url = root.appendingPathComponent("data-\(safe).sqlite")
        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        let dbQueue = try DatabaseQueue(path: url.path, configuration: config)
        try migrator.migrate(dbQueue)
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
        return migrator
    }
}
