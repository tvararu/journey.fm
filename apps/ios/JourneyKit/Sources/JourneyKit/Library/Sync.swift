import Foundation
import GRDB

public protocol LibrarySource: Sendable {
    func artists() async throws -> [Artist]
    func albums(since: Date?) async throws -> [SyncedAlbum]
    func tracks(since: Date?) async throws -> [SyncedTrack]
}

public struct SyncReport: Sendable, Equatable {
    public var full = false
    public var artists = 0
    public var albums = 0
    public var tracks = 0
    public var deleted = 0
    public var deferred = 0
}

public struct SyncProgress: Sendable, Equatable {
    public var artists: Int?
    public var albums: Int?
    public var tracks: Int?

    public init() {}
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

    public func run(
        full forceFull: Bool = false, now: Date = .now,
        progress: @Sendable (SyncProgress) -> Void = { _ in }
    ) async throws -> SyncReport {
        let state = try await library.db.read { try SyncState.fetchOne($0) } ?? SyncState()
        let full =
            forceFull || state.lastSync == nil
            || state.lastFullSync.map { now.timeIntervalSince($0) > Self.fullSyncInterval } ?? true
        let since = full ? nil : state.lastSync?.addingTimeInterval(-Self.overlap)

        var step = SyncProgress()
        progress(step)
        let artists = try await source.artists()
        step.artists = artists.count
        progress(step)
        let albums = try await source.albums(since: since)
        step.albums = albums.count
        progress(step)
        let tracks = try await source.tracks(since: since)
        step.tracks = tracks.count
        progress(step)

        let report = try await library.db.write { db in
            var report = SyncReport(
                full: full, artists: artists.count, albums: albums.count, tracks: tracks.count)

            for artist in artists { try artist.upsert(db) }
            for synced in albums {
                let id = synced.album.id
                try synced.album.upsert(db)
                try AlbumArtist.filter(Column("albumId") == id).deleteAll(db)
                var seen = Set<String>()
                let artistIds = synced.artistIds.filter { seen.insert($0).inserted }
                for (position, artistId) in artistIds.enumerated() {
                    try AlbumArtist(albumId: id, artistId: artistId, position: position).insert(db)
                }
                try AlbumTag.filter(Column("albumId") == id).deleteAll(db)
                for (position, tag) in synced.tags.enumerated() {
                    try AlbumTag(albumId: id, key: tag.key, value: tag.value, position: position)
                        .insert(db)
                }
                try AlbumGenre.filter(Column("albumId") == id).deleteAll(db)
                for (position, name) in synced.genres.enumerated() {
                    try AlbumGenre(albumId: id, name: name, position: position).insert(db)
                }
            }
            let albumIds = Set(try String.fetchAll(db, Album.select(Column("id"))))
            for synced in tracks {
                let id = synced.track.id
                guard albumIds.contains(synced.track.albumId) else {
                    report.deferred += 1
                    continue
                }
                try synced.track.upsert(db)
                try TrackTag.filter(Column("trackId") == id).deleteAll(db)
                for (position, tag) in synced.tags.enumerated() {
                    try TrackTag(trackId: id, key: tag.key, value: tag.value, position: position)
                        .insert(db)
                }
                try Credit.filter(Column("trackId") == id).deleteAll(db)
                for credit in synced.credits { try credit.insert(db) }
            }
            if full {
                report.deleted += try Track.filter(!tracks.map(\.track.id).contains(Column("id")))
                    .deleteAll(db)
                report.deleted += try Album.filter(!albums.map(\.album.id).contains(Column("id")))
                    .deleteAll(db)
                report.deleted += try Artist.filter(!artists.map(\.id).contains(Column("id")))
                    .deleteAll(db)
            }

            try Library.refreshDerived(db)
            try SyncState(lastSync: now, lastFullSync: full ? now : state.lastFullSync).upsert(db)
            return report
        }
        Log.sync.info(
            "\(full ? "full" : "delta", privacy: .public) sync: \(report.artists) artists, \(report.albums) albums, \(report.tracks) tracks, \(report.deleted) deleted, \(report.deferred) deferred"
        )
        return report
    }
}
