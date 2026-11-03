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
    public var overview: String?
    public var albumCount: Int
    public var firstYear: Int?
    public var lastYear: Int?
}

public struct AlbumDetail: Sendable, Equatable {
    public var album: Album
    public var artists: [Artist]
    public var tracks: [Track]
    public var more: [Album]
    public var tags: [Tag] = []
    public var genres: [String] = []
    public var credits: [Credit] = []
}

public struct ArtistDetail: Sendable, Equatable {
    public var artist: ArtistSummary
    public var albums: [Album]
}

public struct GenreSummary: Codable, Sendable, Hashable, Identifiable, FetchableRecord {
    public var name: String
    public var albumCount: Int
    public var id: String { name }
}

public struct TrackCredits: Sendable, Equatable {
    public var credits: [Credit]
    public var isrc: [String]

    public init(credits: [Credit], isrc: [String]) {
        self.credits = credits
        self.isrc = isrc
    }
}

public struct TrackHit: Sendable, Equatable, Identifiable {
    public var track: Track
    public var album: Album
    public var id: String { track.id }

    public init(track: Track, album: Album) {
        self.track = track
        self.album = album
    }
}

public struct CreditHit: Sendable, Equatable, Identifiable {
    public var album: Album
    public var name: String
    public var reads: String
    public var id: String { "\(album.id)\u{0}\(name)" }
}

public struct LyricHit: Sendable, Equatable, Identifiable {
    public var hit: TrackHit
    public var line: String
    public var id: String { hit.id }
}

public struct SearchResults: Sendable, Equatable {
    public var artists: [ArtistSummary] = []
    public var albums: [Album] = []
    public var tracks: [TrackHit] = []
    public var credits: [CreditHit] = []
    public var lyrics: [LyricHit] = []

    public init() {}

    public var isEmpty: Bool {
        artists.isEmpty && albums.isEmpty && tracks.isEmpty && credits.isEmpty && lyrics.isEmpty
    }
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
            let tags = try AlbumTag.filter(Column("albumId") == id).order(Column("position"))
                .fetchAll(db).map { Tag($0.key, $0.value) }
            let genres = try String.fetchAll(
                db, sql: "SELECT name FROM albumGenre WHERE albumId = ? ORDER BY position",
                arguments: [id])
            let credits = try Credit.fetchAll(
                db,
                sql: """
                    SELECT credit.* FROM credit JOIN track ON track.id = credit.trackId
                    WHERE track.albumId = ?
                    """, arguments: [id])
            return AlbumDetail(
                album: album, artists: artists, tracks: tracks, more: more ?? [], tags: tags,
                genres: genres, credits: credits)
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

    public func observeGenres() -> AsyncValueObservation<[GenreSummary]> {
        ValueObservation.tracking { db in
            try GenreSummary.fetchAll(
                db,
                sql: """
                    SELECT name, count(DISTINCT albumId) AS albumCount FROM albumGenre
                    GROUP BY name ORDER BY lower(name)
                    """)
        }.values(in: db)
    }

    public func observeGenre(name: String) -> AsyncValueObservation<[Album]> {
        ValueObservation.tracking { db in
            try Album.fetchAll(
                db,
                sql: """
                    SELECT DISTINCT album.* FROM album
                    JOIN albumGenre ON albumGenre.albumId = album.id
                    WHERE albumGenre.name = ?
                    ORDER BY album.artistSortName, album.year, album.sortName
                    """, arguments: [name])
        }.values(in: db)
    }

    public func trackCredits(trackId: String) async throws -> TrackCredits {
        try await db.read { db in
            let credits = try Credit.filter(Column("trackId") == trackId)
                .order(Column("position")).fetchAll(db)
            let isrc = try String.fetchAll(
                db,
                sql: """
                    SELECT value FROM trackTag WHERE trackId = ?1 AND key = 'ISRC'
                    UNION ALL
                    SELECT value FROM albumTag WHERE key = 'ISRC'
                        AND albumId = (SELECT albumId FROM track WHERE id = ?1)
                    """, arguments: [trackId])
            return TrackCredits(credits: credits, isrc: isrc)
        }
    }

    public func randomAlbums(limit: Int) async throws -> [Album] {
        try await db.read { try Album.order(sql: "random()").limit(limit).fetchAll($0) }
    }

    public func search(_ text: String) async throws -> SearchResults {
        guard let pattern = FTS5Pattern(matchingAllPrefixesIn: text) else { return SearchResults() }
        let query = text.trimmingCharacters(in: .whitespaces)
        return try await db.read { db in
            var results = SearchResults()
            results.artists = try ArtistSummary.fetchAll(
                db,
                sql: Self.artistSummary + """
                     WHERE artist.rowid IN
                        (SELECT rowid FROM artistSearch WHERE artistSearch MATCH ?)
                    GROUP BY artist.id
                    ORDER BY instr(lower(artist.name), lower(?)) = 1 DESC, artist.sortName
                    """, arguments: [pattern, query])
            results.albums = try Album.fetchAll(
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
            let credits = try Row.fetchAll(
                db,
                sql: """
                    SELECT credit.name, credit.role, credit.kind, track.albumId FROM credit
                    JOIN creditSearch ON creditSearch.rowid = credit.rowid
                    JOIN track ON track.id = credit.trackId
                    WHERE creditSearch MATCH ?
                    ORDER BY instr(lower(credit.name), lower(?)) = 1 DESC, credit.name,
                        track.albumId, track.disc, track.number, credit.position
                    """, arguments: [pattern, query])
            let lyrics = try Row.fetchAll(
                db,
                sql: """
                    SELECT track.*, lyrics.text AS lyricText FROM lyrics
                    JOIN lyricsSearch ON lyricsSearch.rowid = lyrics.rowid
                    JOIN track ON track.id = lyrics.trackId
                    WHERE lyricsSearch MATCH ?
                    ORDER BY lyricsSearch.rank LIMIT 200
                    """, arguments: [pattern])
            let lyricTracks = try lyrics.map { try Track(row: $0) }
            let albumIds = Set(
                tracks.map(\.albumId) + lyricTracks.map(\.albumId)
                    + credits.map { $0["albumId"] as String })
            let byId = Dictionary(
                uniqueKeysWithValues: try Album.fetchAll(db, keys: albumIds).map { ($0.id, $0) })
            results.tracks = tracks.compactMap { track in
                byId[track.albumId].map { TrackHit(track: track, album: $0) }
            }
            var creditHits: [CreditHit] = []
            var index: [String: Int] = [:]
            for row in credits {
                let albumId: String = row["albumId"]
                guard let album = byId[albumId] else { continue }
                let credit = Credit(
                    trackId: "", name: row["name"], role: row["role"], kind: row["kind"],
                    position: 0)
                let key = "\(albumId)\u{0}\(credit.name)"
                if let i = index[key] {
                    if !creditHits[i].reads.components(separatedBy: ", ").contains(credit.reads) {
                        creditHits[i].reads += ", \(credit.reads)"
                    }
                } else {
                    index[key] = creditHits.count
                    creditHits.append(
                        CreditHit(album: album, name: credit.name, reads: credit.reads))
                }
            }
            results.credits = creditHits
            results.lyrics = zip(lyrics, lyricTracks).compactMap { row, track in
                byId[track.albumId].map {
                    LyricHit(
                        hit: TrackHit(track: track, album: $0),
                        line: matchingLine(row["lyricText"], query: query))
                }
            }
            return results
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

func matchingLine(_ text: String, query: String) -> String {
    let fold = { (s: Substring) in
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
    let wanted = query.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(fold)
    let lines = text.split(separator: "\n").filter {
        !$0.trimmingCharacters(in: .whitespaces).isEmpty
    }
    var best: (line: Substring, score: Int)?
    for line in lines {
        let words = line.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(fold)
        let score = wanted.filter { want in words.contains { $0.hasPrefix(want) } }.count
        if score > best?.score ?? 0 { best = (line, score) }
        if score == wanted.count { break }
    }
    return String(best?.line ?? lines.first ?? "")
}
