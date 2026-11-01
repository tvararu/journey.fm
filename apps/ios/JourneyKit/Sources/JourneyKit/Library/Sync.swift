import Foundation
import GRDB

public protocol LibrarySource: Sendable {
    func artists() async throws -> [Artist]
    func albums(since: Date?) async throws -> [SyncedAlbum]
    func tracks(since: Date?) async throws -> [Track]
}

public struct SyncReport: Sendable, Equatable {
    public var full = false
    public var artists = 0
    public var albums = 0
    public var tracks = 0
    public var deleted = 0
    public var deferred = 0
}

public struct Sync: Sendable {
    public static let fullSyncInterval: TimeInterval = 24 * 60 * 60
    static let overlap: TimeInterval = 60 * 60

    let source: any LibrarySource
    let library: Library

    public init(source: any LibrarySource, library: Library) {
        self.source = source
        self.library = library
    }

    public func run(full forceFull: Bool = false, now: Date = .now) async throws -> SyncReport {
        let state = try await library.db.read { try SyncState.fetchOne($0) } ?? SyncState()
        let full =
            forceFull || state.lastSync == nil
            || state.lastFullSync.map { now.timeIntervalSince($0) > Self.fullSyncInterval } ?? true
        let since = full ? nil : state.lastSync?.addingTimeInterval(-Self.overlap)

        let artists = try await source.artists()
        let albums = try await source.albums(since: since)
        let tracks = try await source.tracks(since: since)

        let report = try await library.db.write { db in
            var report = SyncReport(
                full: full, artists: artists.count, albums: albums.count, tracks: tracks.count)

            for artist in artists { try artist.upsert(db) }
            for synced in albums {
                try synced.album.upsert(db)
                try AlbumArtist.filter(Column("albumId") == synced.album.id).deleteAll(db)
                for (position, artistId) in synced.artistIds.enumerated() {
                    try AlbumArtist(
                        albumId: synced.album.id, artistId: artistId, position: position
                    )
                    .insert(db)
                }
            }
            let albumIds = Set(try String.fetchAll(db, Album.select(Column("id"))))
            for track in tracks {
                if albumIds.contains(track.albumId) {
                    try track.upsert(db)
                } else {
                    report.deferred += 1
                }
            }
            if full {
                report.deleted += try Track.filter(!tracks.map(\.id).contains(Column("id")))
                    .deleteAll(db)
                report.deleted += try Album.filter(!albums.map(\.album.id).contains(Column("id")))
                    .deleteAll(db)
                report.deleted += try Artist.filter(!artists.map(\.id).contains(Column("id")))
                    .deleteAll(db)
            }

            try SyncState(lastSync: now, lastFullSync: full ? now : state.lastFullSync).upsert(db)
            return report
        }
        Log.sync.info(
            "\(full ? "full" : "delta", privacy: .public) sync: \(report.artists) artists, \(report.albums) albums, \(report.tracks) tracks, \(report.deleted) deleted, \(report.deferred) deferred"
        )
        return report
    }
}
