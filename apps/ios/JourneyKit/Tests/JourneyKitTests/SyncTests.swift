import Foundation
import GRDB
import Synchronization
import Testing

@testable import JourneyKit

final class FakeSource: LibrarySource {
    struct State {
        var artists: [Artist] = []
        var albums: [SyncedAlbum] = []
        var tracks: [Track] = []
        var synced: [SyncedTrack] = []
        var since: [Date?] = []
    }

    let state = Mutex(State())

    func artists() async throws -> [Artist] { state.withLock { $0.artists } }

    func albums(since: Date?) async throws -> [SyncedAlbum] {
        state.withLock {
            $0.since.append(since)
            return $0.albums
        }
    }

    func tracks(since: Date?) async throws -> [SyncedTrack] {
        state.withLock { $0.tracks.map { SyncedTrack(track: $0) } + $0.synced }
    }
}

func album(_ id: String, artists: [String] = ["a1"]) -> SyncedAlbum {
    SyncedAlbum(
        album: Album(
            id: id, name: id, sortName: id, artistName: "Artist", year: 2002, genres: "",
            duration: 60, trackCount: 1, imageTag: nil, dateCreated: "2026-01-01T00:00:00Z"),
        artistIds: artists)
}

func track(_ id: String, album: String) -> Track {
    Track(
        id: id, albumId: album, name: id, artistName: "Artist", disc: 1, number: 1, duration: 60,
        container: "flac")
}

let artist = Artist(id: "a1", name: "Artist", sortName: "artist", imageTag: nil)
let start = Date(timeIntervalSince1970: 1_800_000_000)

@Test func fullSyncRemovesWhatTheServerNoLongerHas() async throws {
    let library = try Library()
    let source = FakeSource()
    source.state.withLock {
        $0.artists = [artist]
        $0.albums = [album("x"), album("y")]
        $0.tracks = [track("x1", album: "x"), track("y1", album: "y")]
    }
    _ = try await Sync(source: source, library: library).run(now: start)
    source.state.withLock {
        $0.albums = [album("x")]
        $0.tracks = [track("x1", album: "x")]
    }
    let report = try await Sync(source: source, library: library).run(full: true, now: start)
    let stats = try await library.stats()
    #expect(report.deleted == 2)
    #expect(stats.albums == 1 && stats.tracks == 1)
}

@Test func deltaSyncAsksForChangesSinceTheLastSyncAndKeepsTheRest() async throws {
    let library = try Library()
    let source = FakeSource()
    source.state.withLock {
        $0.albums = [album("x")]
        $0.tracks = [track("x1", album: "x")]
    }
    _ = try await Sync(source: source, library: library).run(now: start)
    source.state.withLock {
        $0.albums = [album("y")]
        $0.tracks = [track("y1", album: "y")]
    }
    let report = try await Sync(source: source, library: library)
        .run(now: start.addingTimeInterval(600))
    let stats = try await library.stats()
    #expect(!report.full)
    #expect(source.state.withLock { $0.since } == [nil, start.addingTimeInterval(-3600)])
    #expect(stats.albums == 2 && stats.tracks == 2)
}

@Test func fullSyncComesRoundAfterADay() async throws {
    let library = try Library()
    let source = FakeSource()
    _ = try await Sync(source: source, library: library).run(now: start)
    let report = try await Sync(source: source, library: library)
        .run(now: start.addingTimeInterval(Sync.fullSyncInterval + 1))
    #expect(report.full)
}

@Test func trackWithUnknownAlbumWaitsForTheNextSync() async throws {
    let library = try Library()
    let source = FakeSource()
    source.state.withLock { $0.tracks = [track("z1", album: "z")] }
    let first = try await Sync(source: source, library: library).run(now: start)
    #expect(first.deferred == 1)
    source.state.withLock { $0.albums = [album("z")] }
    _ = try await Sync(source: source, library: library).run(now: start.addingTimeInterval(60))
    #expect(try await library.stats().tracks == 1)
}

@Test func albumArtistsAreReplacedOnUpdate() async throws {
    let library = try Library()
    let source = FakeSource()
    source.state.withLock { $0.albums = [album("x", artists: ["a1", "a2"])] }
    _ = try await Sync(source: source, library: library).run(now: start)
    source.state.withLock { $0.albums = [album("x", artists: ["a3"])] }
    _ = try await Sync(source: source, library: library).run(now: start.addingTimeInterval(60))
    let links = try await library.db.read { try AlbumArtist.fetchAll($0) }
    #expect(links == [AlbumArtist(albumId: "x", artistId: "a3", position: 0)])
}

@Test func tagsGenresAndCreditsAreStoredAndReplaced() async throws {
    let library = try Library()
    let source = FakeSource()
    var x = album("x")
    x.tags = [Tag("DATE", "2004-03-23"), Tag("RYM_DESCRIPTORS", "playful")]
    x.genres = ["Abstract Hip Hop", "Jazz Rap"]
    let credit = { (name: String, kind: String, position: Int) in
        Credit(trackId: "x1", name: name, role: "", kind: kind, position: position)
    }
    source.state.withLock {
        $0.albums = [x]
        $0.synced = [
            SyncedTrack(
                track: track("x1", album: "x"), tags: [Tag("ISRC", "US1")],
                credits: [credit("Madlib", "Producer", 0), credit("MF DOOM", "Lyricist", 1)])
        ]
    }
    _ = try await Sync(source: source, library: library).run(now: start)
    x.tags = [Tag("DATE", "2004")]
    x.genres = ["Jazz Rap"]
    source.state.withLock {
        $0.albums = [x]
        $0.synced = [
            SyncedTrack(
                track: track("x1", album: "x"), tags: [], credits: [credit("Madlib", "Engineer", 0)]
            )
        ]
    }
    _ = try await Sync(source: source, library: library).run(now: start.addingTimeInterval(60))
    let (tags, genres, credits, trackTags) = try await library.db.read { db in
        (
            try AlbumTag.fetchAll(db).map { Tag($0.key, $0.value) },
            try AlbumGenre.fetchAll(db).map(\.name),
            try Credit.fetchAll(db),
            try TrackTag.fetchCount(db)
        )
    }
    #expect(tags == [Tag("DATE", "2004")])
    #expect(genres == ["Jazz Rap"])
    #expect(credits == [credit("Madlib", "Engineer", 0)])
    #expect(trackTags == 0)
}

@Test func theMetadataMigrationForcesAFullSync() throws {
    let queue = try DatabaseQueue()
    let migrator = Library.migrator
    try migrator.migrate(queue, upTo: "playLog")
    try queue.write { try SyncState(lastSync: start, lastFullSync: start).insert($0) }
    try migrator.migrate(queue)
    #expect(try queue.read { try SyncState.fetchOne($0) }?.lastFullSync == nil)
}

@Test func decodesJellyfinItems() throws {
    let url = try #require(
        Bundle.module.url(forResource: "items", withExtension: "json", subdirectory: "Fixtures"))
    let items = try JSONDecoder().decode(ItemsPage.self, from: Data(contentsOf: url)).items
    let synced = items[0].album
    #expect(synced.album.artistName == "Hermano")
    #expect(synced.album.genres == "Stoner, Desert, Doom")
    #expect(synced.album.trackCount == 12)
    #expect(synced.album.imageTag == "b0d07923eabbcc4310e0a929d8d1234e")
    #expect(synced.artistIds == ["313d9a8b16dac37f3e0b5b83068b7d9e"])
    let track = try #require(items[1].track?.track)
    #expect(track.albumId == "27f894018bc3ab93f92c732995a8fa52")
    #expect(track.disc == 1 && track.number == 0)
    #expect(abs(track.duration - 93.026667) < 0.001)
}

@Test func decodesCatalogueFields() throws {
    let json = """
        {"Items": [
          {"Id": "a", "Name": "Madvillainy", "AlbumArtist": "Madvillain", "CommunityRating": 8.64,
           "Studios": [{"Name": "Stones Throw Records", "Id": "s"}],
           "Genres": ["Abstract Hip Hop"],
           "Tags": ["ORIGINALDATE:2004-03-19", "REPLAYGAIN_ALBUM_GAIN:-7.01 dB",
                    "REPLAYGAIN_ALBUM_PEAK:1.00000000", "RYM_URL:https://rateyourmusic.com/x", "plain"]},
          {"Id": "t", "Name": "Accordion", "AlbumId": "a", "HasLyrics": true, "Etag": "e1",
           "People": [{"Name": "Madvillain", "Type": "AlbumArtist"}, {"Name": "Madvillain", "Type": "Artist"},
                      {"Name": "Otis Jackson Jr.", "Type": "Composer"}, {"Name": "Madlib", "Type": "Producer"}],
           "Tags": ["PERFORMER:MF DOOM (lead vocals)", "PERFORMER:Madlib", "REPLAYGAIN_TRACK_GAIN:-7.71 dB",
                    "REPLAYGAIN_TRACK_PEAK:0.94430542"]}
        ]}
        """
    let items = try JSONDecoder().decode(ItemsPage.self, from: Data(json.utf8)).items
    let synced = items[0].album
    #expect(synced.album.released == "2004-03-19")
    #expect(synced.album.rating == 8.64)
    #expect(synced.album.label == "Stones Throw Records")
    #expect(synced.album.gain == -7.01 && synced.album.peak == 1)
    #expect(synced.tags.first("RYM_URL") == "https://rateyourmusic.com/x")
    #expect(synced.tags.count == 4)
    #expect(synced.genres == ["Abstract Hip Hop"])
    let track = try #require(items[1].track)
    #expect(track.track.gain == -7.71 && track.track.peak == 0.94430542)
    #expect(track.track.hasLyrics == true && track.track.etag == "e1")
    #expect(
        track.credits.map { [$0.name, $0.role, $0.kind] } == [
            ["Otis Jackson Jr.", "", "Composer"], ["Madlib", "", "Producer"],
            ["MF DOOM", "lead vocals", "Performer"], ["Madlib", "", "Performer"],
        ])
    #expect(track.credits.map(\.position) == [0, 1, 2, 3])
}
