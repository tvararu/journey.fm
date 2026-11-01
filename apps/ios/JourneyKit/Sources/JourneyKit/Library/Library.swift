import Foundation
import GRDB

public struct LibraryStats: Sendable, Equatable {
    public var albums = 0
    public var artists = 0
    public var tracks = 0
    public var lastSync: Date?

    public init(albums: Int = 0, artists: Int = 0, tracks: Int = 0, lastSync: Date? = nil) {
        self.albums = albums
        self.artists = artists
        self.tracks = tracks
        self.lastSync = lastSync
    }
}

public final class Library: Sendable {
    let db: any DatabaseWriter

    public init(path: String) throws {
        try FileManager.default.createDirectory(
            at: URL(filePath: path).deletingLastPathComponent(), withIntermediateDirectories: true)
        db = try DatabasePool(path: path)
        try Self.migrator.migrate(db)
    }

    public init() throws {
        db = try DatabaseQueue()
        try Self.migrator.migrate(db)
    }

    public func stats() async throws -> LibraryStats {
        try await db.read(Self.stats)
    }

    public func album(id: String) async throws -> Album? {
        try await db.read { try Album.fetchOne($0, key: id) }
    }

    public func observeStats() -> AsyncValueObservation<LibraryStats> {
        ValueObservation.tracking(Self.stats).values(in: db)
    }

    public func observeRecentAlbums(limit: Int) -> AsyncValueObservation<[Album]> {
        ValueObservation.tracking { db in
            try Album.order(Column("dateCreated").desc).limit(limit).fetchAll(db)
        }.values(in: db)
    }

    public func erase() async throws {
        try await db.write { db in
            try Album.deleteAll(db)
            try Artist.deleteAll(db)
            try SyncState.deleteAll(db)
        }
    }

    static func stats(_ db: Database) throws -> LibraryStats {
        LibraryStats(
            albums: try Album.fetchCount(db),
            artists: try Artist.fetchCount(db),
            tracks: try Track.fetchCount(db),
            lastSync: try SyncState.fetchOne(db)?.lastSync
        )
    }

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("library") { db in
            try db.create(table: "artist") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("sortName", .text).notNull()
                t.column("imageTag", .text)
            }
            try db.create(table: "album") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("sortName", .text).notNull()
                t.column("artistName", .text).notNull()
                t.column("year", .integer)
                t.column("genres", .text).notNull()
                t.column("duration", .double).notNull()
                t.column("trackCount", .integer).notNull()
                t.column("imageTag", .text)
                t.column("dateCreated", .text).notNull().indexed()
            }
            try db.create(table: "albumArtist") { t in
                t.column("albumId", .text).notNull().references("album", onDelete: .cascade)
                t.column("artistId", .text).notNull().indexed()
                t.column("position", .integer).notNull()
                t.primaryKey(["albumId", "position"])
            }
            try db.create(table: "track") { t in
                t.primaryKey("id", .text)
                t.column("albumId", .text).notNull().indexed().references(
                    "album", onDelete: .cascade)
                t.column("name", .text).notNull()
                t.column("artistName", .text).notNull()
                t.column("disc", .integer)
                t.column("number", .integer)
                t.column("duration", .double).notNull()
                t.column("container", .text)
            }
            try db.create(table: "syncState") { t in
                t.primaryKey("id", .integer)
                t.column("lastSync", .datetime)
                t.column("lastFullSync", .datetime)
            }
        }
        return migrator
    }
}
