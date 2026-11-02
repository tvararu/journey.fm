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
            try db.execute(
                sql:
                    "DELETE FROM playback; DELETE FROM play; DELETE FROM history; DELETE FROM download"
            )
        }
    }

    static func stats(_ db: Database) throws -> LibraryStats {
        LibraryStats(
            albums: try Album.fetchCount(db),
            artists: try Artist.filter(sql: "id IN (SELECT artistId FROM albumArtist)")
                .fetchCount(db),
            tracks: try Track.fetchCount(db),
            lastSync: try SyncState.fetchOne(db)?.lastSync
        )
    }

    static func refreshDerived(_ db: Database) throws {
        try db.execute(
            sql: """
                UPDATE album SET
                    trackCount = (SELECT count(*) FROM track WHERE albumId = album.id),
                    duration = (SELECT total(duration) FROM track WHERE albumId = album.id)
                WHERE EXISTS (SELECT 1 FROM track WHERE albumId = album.id);
                UPDATE album SET artistId =
                    (SELECT artist.id FROM albumArtist
                     JOIN artist ON artist.id = albumArtist.artistId
                     WHERE albumArtist.albumId = album.id ORDER BY position LIMIT 1);
                UPDATE album SET artistSortName = coalesce(
                    (SELECT sortName FROM artist WHERE id = album.artistId), lower(artistName));
                """)
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
        migrator.registerMigration("browse") { db in
            try db.alter(table: "album") { t in
                t.add(column: "artistSortName", .text).notNull().defaults(to: "")
                t.add(column: "artistId", .text).indexed()
            }
            try refreshDerived(db)
            for (table, columns) in [
                ("artist", ["name"]), ("album", ["name", "artistName"]),
                ("track", ["name", "artistName"]),
            ] {
                try db.create(virtualTable: "\(table)Search", using: FTS5()) { t in
                    t.synchronize(withTable: table)
                    t.tokenizer = .unicode61()
                    for column in columns { t.column(column) }
                }
            }
        }
        migrator.registerMigration("uniqueAlbumArtists") { db in
            try db.execute(
                sql: """
                    DELETE FROM albumArtist WHERE rowid NOT IN
                        (SELECT min(rowid) FROM albumArtist GROUP BY albumId, artistId)
                    """)
        }
        migrator.registerMigration("playback") { db in
            try db.create(table: "playback") { t in
                t.primaryKey("id", .integer)
                t.column("queue", .blob).notNull()
                t.column("position", .double).notNull()
            }
            try db.create(table: "played") { t in
                t.primaryKey("albumId", .text)
                t.column("playedAt", .datetime).notNull().indexed()
            }
        }
        migrator.registerMigration("downloads") { db in
            try db.create(table: "download") { t in
                t.primaryKey("trackId", .text).references("track", onDelete: .cascade)
                t.column("albumId", .text).notNull().indexed()
                t.column("version", .text).notNull()
                t.column("wifiOnly", .boolean).notNull()
                t.column("bytes", .integer)
                t.column("savedAt", .datetime)
            }
        }
        migrator.registerMigration("playLog") { db in
            try db.drop(table: "played")
            try db.create(table: "play") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("entryId", .text).notNull()
                t.column("trackId", .text).notNull().indexed()
                t.column("albumId", .text).notNull().indexed()
                t.column("playedAt", .datetime).notNull().indexed()
            }
            try db.create(table: "history") { t in
                t.primaryKey("id", .integer)
                t.column("clearedAt", .datetime)
            }
        }
        return migrator
    }
}
