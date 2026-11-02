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

    public func recordPlay(_ play: CountedPlay) async throws {
        try await db.write { db in
            try db.execute(
                sql: "INSERT INTO play (entryId, trackId, albumId, playedAt) VALUES (?, ?, ?, ?)",
                arguments: [play.entryId.uuidString, play.trackId, play.albumId, play.startedAt])
        }
    }

    public func clearHistory(at date: Date = .now) async throws {
        try await db.write { db in
            try db.execute(
                sql: "INSERT OR REPLACE INTO history (id, clearedAt) VALUES (1, ?)",
                arguments: [date])
        }
    }

    public func observeRecentlyPlayed(limit: Int) -> AsyncValueObservation<[Album]> {
        ValueObservation.tracking { db in
            try Album.fetchAll(
                db,
                sql: """
                    SELECT album.* FROM album
                    JOIN (SELECT albumId, max(playedAt) AS last FROM play GROUP BY albumId) p
                        ON p.albumId = album.id
                    ORDER BY p.last DESC LIMIT ?
                    """, arguments: [limit])
        }.values(in: db)
    }

    public func observeHistory(excluding entryId: UUID?, limit: Int = 100)
        -> AsyncValueObservation<[TrackHit]>
    {
        ValueObservation.tracking { db in
            let tracks = try Track.fetchAll(
                db,
                sql: """
                    SELECT track.* FROM track
                    JOIN (
                        SELECT trackId, max(playedAt) AS last FROM play
                        WHERE playedAt > coalesce((SELECT clearedAt FROM history), '')
                            AND entryId IS NOT ?
                        GROUP BY trackId ORDER BY last DESC LIMIT ?
                    ) p ON p.trackId = track.id
                    ORDER BY p.last
                    """, arguments: [entryId?.uuidString, limit])
            let albums = try Album.fetchAll(db, keys: Set(tracks.map(\.albumId)))
            let byId = Dictionary(uniqueKeysWithValues: albums.map { ($0.id, $0) })
            return tracks.compactMap { track in
                byId[track.albumId].map { TrackHit(track: track, album: $0) }
            }
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
