import Foundation
import Synchronization
import Testing

@testable import JourneyKit

final class FakeSource: LibrarySource {
    struct State {
        var artists: [Artist] = []
        var albums: [SyncedAlbum] = []
        var tracks: [Track] = []
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

    func tracks(since: Date?) async throws -> [Track] { state.withLock { $0.tracks } }
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
    let track = try #require(items[1].track)
    #expect(track.albumId == "27f894018bc3ab93f92c732995a8fa52")
    #expect(track.disc == 1 && track.number == 0)
    #expect(abs(track.duration - 93.026667) < 0.001)
}
