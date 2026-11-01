import Foundation
import GRDB

public struct SavedPlayback: Sendable, Equatable {
    public var queue: PlayQueue
    public var position: Double
}

extension Library {
    public func savePlayback(_ queue: PlayQueue, position: Double) async throws {
        let data = try JSONEncoder().encode(queue)
        try await db.write { db in
            try db.execute(
                sql: "INSERT OR REPLACE INTO playback (id, queue, position) VALUES (1, ?, ?)",
                arguments: [data, position])
        }
    }

    public func savedPlayback() async throws -> SavedPlayback? {
        try await db.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT queue, position FROM playback")
            else { return nil }
            let queue = try JSONDecoder().decode(PlayQueue.self, from: row["queue"] as Data)
            return SavedPlayback(queue: queue, position: row["position"])
        }
    }

    public func recordPlay(albumId: String, at date: Date = .now) async throws {
        try await db.write { db in
            try db.execute(
                sql: "INSERT OR REPLACE INTO played (albumId, playedAt) VALUES (?, ?)",
                arguments: [albumId, date])
        }
    }

    public func observeRecentlyPlayed(limit: Int) -> AsyncValueObservation<[Album]> {
        ValueObservation.tracking { db in
            try Album.fetchAll(
                db,
                sql: """
                    SELECT album.* FROM album JOIN played ON played.albumId = album.id
                    ORDER BY played.playedAt DESC LIMIT ?
                    """, arguments: [limit])
        }.values(in: db)
    }

    public func tracks(albumIds: [String]) async throws -> [TrackHit] {
        try await db.read { db in
            let albums = try Album.fetchAll(db, keys: albumIds)
            let byId = Dictionary(uniqueKeysWithValues: albums.map { ($0.id, $0) })
            return try albumIds.flatMap { id -> [TrackHit] in
                guard let album = byId[id] else { return [] }
                return try Track.filter(Column("albumId") == id)
                    .order(Column("disc"), Column("number"), Column("name"))
                    .fetchAll(db)
                    .map { TrackHit(track: $0, album: album) }
            }
        }
    }
}
