import Foundation
import GRDB

public struct DownloadSummary: Sendable, Equatable {
    public var saved: Set<String> = []
    public var waiting: Set<String> = []
    public var completeAlbums: Set<String> = []
    public var albums: Set<String> = []
    public var bytes: Int64 = 0
    public var tracks = 0

    public init() {}

    public var wanted: Int { saved.count + waiting.count }
    public var everything: Bool { tracks > 0 && saved.count == tracks }
}

public struct PendingDownload: Sendable, Equatable {
    public var trackId: String
    public var file: String
    public var wifiOnly: Bool
    public var album: String
    public var albumTracks: Int
}

extension Library {
    static let version = "coalesce(track.container, '') || ':' || track.duration"
    static let file = "track.id || '.' || coalesce(track.container, 'flac')"

    public func want(trackIds: [String], wifiOnly: Bool = false) async throws {
        try await db.write { db in
            try db.execute(
                sql: """
                    INSERT INTO download (trackId, albumId, version, wifiOnly)
                    SELECT id, albumId, \(Self.version), ? FROM track
                    WHERE id IN (\(databaseQuestionMarks(count: trackIds.count)))
                    ON CONFLICT (trackId) DO UPDATE SET wifiOnly = wifiOnly AND excluded.wifiOnly
                    """, arguments: StatementArguments([wifiOnly] + trackIds))
        }
    }

    public func want(albumIds: [String], wifiOnly: Bool = false) async throws {
        let ids = try await db.read { db in
            try String.fetchAll(
                db, Track.select(Column("id")).filter(albumIds.contains(Column("albumId"))))
        }
        try await want(trackIds: ids, wifiOnly: wifiOnly)
    }

    public func wantEverything(createdAfter: String? = nil) async throws {
        try await db.write { db in
            try db.execute(
                sql: """
                    INSERT OR IGNORE INTO download (trackId, albumId, version, wifiOnly)
                    SELECT track.id, track.albumId, \(Self.version), 1 FROM track
                    JOIN album ON album.id = track.albumId WHERE album.dateCreated > ?
                    """, arguments: [createdAfter ?? ""])
        }
    }

    @discardableResult
    public func removeDownloads(trackIds: [String]? = nil, albumIds: [String]? = nil) async throws
        -> [String]
    {
        try await db.write { db in
            let (column, ids) =
                if let trackIds { ("trackId", trackIds) } else { ("albumId", albumIds ?? []) }
            let filter =
                trackIds == nil && albumIds == nil
                ? "1" : "download.\(column) IN (\(databaseQuestionMarks(count: ids.count)))"
            let arguments = StatementArguments(trackIds == nil && albumIds == nil ? [] : ids)
            let files = try String.fetchAll(
                db,
                sql: """
                    SELECT \(Self.file) FROM download JOIN track ON track.id = download.trackId
                    WHERE \(filter)
                    """, arguments: arguments)
            try db.execute(sql: "DELETE FROM download WHERE \(filter)", arguments: arguments)
            return files
        }
    }

    public func pendingDownloads() async throws -> [PendingDownload] {
        try await db.write { db in
            try db.execute(
                sql: """
                    UPDATE download SET savedAt = NULL, bytes = NULL WHERE savedAt IS NOT NULL
                    AND version != (SELECT \(Self.version) FROM track WHERE track.id = download.trackId)
                    """)
            return try Row.fetchAll(
                db,
                sql: """
                    SELECT download.trackId, \(Self.file) AS file, download.wifiOnly,
                        track.albumId,
                        (SELECT COUNT(*) FROM track AS t WHERE t.albumId = track.albumId)
                            AS albumTracks
                    FROM download
                    JOIN track ON track.id = download.trackId WHERE download.savedAt IS NULL
                    ORDER BY download.wifiOnly, track.albumId, track.disc, track.number
                    """
            ).map {
                PendingDownload(
                    trackId: $0["trackId"], file: $0["file"], wifiOnly: $0["wifiOnly"],
                    album: $0["albumId"], albumTracks: $0["albumTracks"])
            }
        }
    }

    func savedFiles() throws -> Set<String> {
        try db.read { db in
            Set(
                try String.fetchAll(
                    db,
                    sql: """
                        SELECT \(Self.file) FROM download JOIN track ON track.id = download.trackId
                        WHERE download.savedAt IS NOT NULL
                        """))
        }
    }

    public func markUnsaved(trackIds: [String]) async throws {
        try await db.write { db in
            try db.execute(
                sql: """
                    UPDATE download SET savedAt = NULL, bytes = NULL
                    WHERE trackId IN (\(databaseQuestionMarks(count: trackIds.count)))
                    """, arguments: StatementArguments(trackIds))
        }
    }

    func markSaved(trackId: String, bytes: Int64) throws -> Bool {
        try db.write { db in
            try db.execute(
                sql: """
                    UPDATE download SET savedAt = ?, bytes = ?, version =
                        (SELECT \(Self.version) FROM track WHERE track.id = download.trackId)
                    WHERE trackId = ?
                    """, arguments: [Date.now, bytes, trackId])
            return db.changesCount > 0
        }
    }

    func isWaiting(trackId: String) -> Bool {
        (try? db.read { db in
            try Bool.fetchOne(
                db, sql: "SELECT savedAt IS NULL FROM download WHERE trackId = ?",
                arguments: [trackId])
        }) == true
    }

    public func observeDownloads() -> AsyncValueObservation<DownloadSummary> {
        ValueObservation.tracking { db in
            var summary = DownloadSummary()
            for row in try Row.fetchAll(
                db, sql: "SELECT trackId, albumId, savedAt, bytes FROM download")
            {
                let id: String = row["trackId"]
                summary.albums.insert(row["albumId"])
                if row["savedAt"] as Date? == nil {
                    summary.waiting.insert(id)
                } else {
                    summary.saved.insert(id)
                    summary.bytes += row["bytes"] ?? 0
                }
            }
            summary.completeAlbums = Set(
                try String.fetchAll(
                    db,
                    sql: """
                        SELECT download.albumId FROM download
                        JOIN album ON album.id = download.albumId
                        WHERE download.savedAt IS NOT NULL
                        GROUP BY download.albumId HAVING count(*) = max(album.trackCount)
                        """))
            summary.tracks = try Track.fetchCount(db)
            return summary
        }.values(in: db)
    }
}
