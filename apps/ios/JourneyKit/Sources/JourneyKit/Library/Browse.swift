import Foundation
import GRDB

public enum AlbumSort: String, CaseIterable, Sendable {
    case title, artist, year, added
}

public struct ArtistSummary: Codable, Sendable, Hashable, Identifiable, FetchableRecord {
    public var id: String
    public var name: String
    public var sortName: String
    public var imageTag: String?
    public var albumCount: Int
    public var firstYear: Int?
    public var lastYear: Int?
}

public struct AlbumDetail: Sendable, Equatable {
    public var album: Album
    public var artists: [Artist]
    public var tracks: [Track]
    public var more: [Album]
}

public struct ArtistDetail: Sendable, Equatable {
    public var artist: ArtistSummary
    public var albums: [Album]
}

public struct TrackHit: Sendable, Equatable, Identifiable {
    public var track: Track
    public var album: Album
    public var id: String { track.id }
}

public struct SearchResults: Sendable, Equatable {
    public var artists: [ArtistSummary] = []
    public var albums: [Album] = []
    public var tracks: [TrackHit] = []

    public init() {}

    init(artists: [ArtistSummary], albums: [Album], tracks: [TrackHit]) {
        self.artists = artists
        self.albums = albums
        self.tracks = tracks
    }

    public var isEmpty: Bool { artists.isEmpty && albums.isEmpty && tracks.isEmpty }
}

extension Library {
    static let artistSummary = """
        SELECT artist.*, count(*) AS albumCount,
            min(album.year) AS firstYear, max(album.year) AS lastYear
        FROM artist
        JOIN albumArtist ON albumArtist.artistId = artist.id
        JOIN album ON album.id = albumArtist.albumId
        """

    public func observeAlbums(sort: AlbumSort) -> AsyncValueObservation<[Album]> {
        ValueObservation.tracking { db in
            try Album.order(Self.ordering(sort)).fetchAll(db)
        }.values(in: db)
    }

    public func observeArtists() -> AsyncValueObservation<[ArtistSummary]> {
        ValueObservation.tracking { db in
            try ArtistSummary.fetchAll(
                db, sql: Self.artistSummary + " GROUP BY artist.id ORDER BY artist.sortName")
        }.values(in: db)
    }

    public func observeAlbum(id: String) -> AsyncValueObservation<AlbumDetail?> {
        ValueObservation.tracking { db -> AlbumDetail? in
            guard let album = try Album.fetchOne(db, key: id) else { return nil }
            let artists = try Artist.fetchAll(
                db,
                sql: """
                    SELECT artist.* FROM artist
                    JOIN albumArtist ON albumArtist.artistId = artist.id
                    WHERE albumArtist.albumId = ? ORDER BY albumArtist.position
                    """, arguments: [id])
            let tracks = try Track.filter(Column("albumId") == id)
                .order(Column("disc"), Column("number"), Column("name"))
                .fetchAll(db)
            let more = try artists.first.map { artist in
                try Self.albums(db, artistId: artist.id).filter { $0.id != id }
            }
            return AlbumDetail(album: album, artists: artists, tracks: tracks, more: more ?? [])
        }.values(in: db)
    }

    public func observeArtist(id: String) -> AsyncValueObservation<ArtistDetail?> {
        ValueObservation.tracking { db -> ArtistDetail? in
            guard
                let artist = try ArtistSummary.fetchOne(
                    db, sql: Self.artistSummary + " WHERE artist.id = ? GROUP BY artist.id",
                    arguments: [id])
            else { return nil }
            return ArtistDetail(artist: artist, albums: try Self.albums(db, artistId: id))
        }.values(in: db)
    }

    public func randomAlbums(limit: Int) async throws -> [Album] {
        try await db.read { try Album.order(sql: "random()").limit(limit).fetchAll($0) }
    }

    public func search(_ text: String) async throws -> SearchResults {
        guard let pattern = FTS5Pattern(matchingAllPrefixesIn: text) else { return SearchResults() }
        let query = text.trimmingCharacters(in: .whitespaces)
        return try await db.read { db in
            let artists = try ArtistSummary.fetchAll(
                db,
                sql: Self.artistSummary + """
                     WHERE artist.rowid IN
                        (SELECT rowid FROM artistSearch WHERE artistSearch MATCH ?)
                    GROUP BY artist.id
                    ORDER BY instr(lower(artist.name), lower(?)) = 1 DESC, artist.sortName
                    """, arguments: [pattern, query])
            let albums = try Album.fetchAll(
                db,
                sql: """
                    SELECT album.* FROM album
                    JOIN albumSearch ON albumSearch.rowid = album.rowid
                    WHERE albumSearch MATCH ?
                    ORDER BY instr(lower(album.name), lower(?)) = 1 DESC, albumSearch.rank
                    """, arguments: [pattern, query])
            let tracks = try Track.fetchAll(
                db,
                sql: """
                    SELECT track.* FROM track
                    JOIN trackSearch ON trackSearch.rowid = track.rowid
                    WHERE trackSearch MATCH ?
                    ORDER BY instr(lower(track.name), lower(?)) = 1 DESC, trackSearch.rank
                    """, arguments: [pattern, query])
            let trackAlbums = try Album.fetchAll(db, keys: Set(tracks.map(\.albumId)))
            let byId = Dictionary(uniqueKeysWithValues: trackAlbums.map { ($0.id, $0) })
            return SearchResults(
                artists: artists, albums: albums,
                tracks: tracks.compactMap { track in
                    byId[track.albumId].map { TrackHit(track: track, album: $0) }
                })
        }
    }

    public func artItems() async throws -> [ArtItem] {
        try await db.read { db in
            try ArtItem.fetchAll(
                db,
                sql: """
                    SELECT id, imageTag AS tag FROM album WHERE imageTag IS NOT NULL
                    UNION ALL
                    SELECT id, imageTag FROM artist WHERE imageTag IS NOT NULL
                        AND id IN (SELECT artistId FROM albumArtist)
                    """)
        }
    }

    static func albums(_ db: Database, artistId: String) throws -> [Album] {
        try Album.fetchAll(
            db,
            sql: """
                SELECT album.* FROM album
                JOIN albumArtist ON albumArtist.albumId = album.id
                WHERE albumArtist.artistId = ? ORDER BY album.year, album.sortName
                """, arguments: [artistId])
    }

    static func ordering(_ sort: AlbumSort) -> [any SQLOrderingTerm] {
        switch sort {
        case .title: [Column("sortName"), Column("artistSortName")]
        case .artist: [Column("artistSortName"), Column("year"), Column("sortName")]
        case .year: [Column("year"), Column("artistSortName"), Column("sortName")]
        case .added: [Column("dateCreated").desc]
        }
    }
}
