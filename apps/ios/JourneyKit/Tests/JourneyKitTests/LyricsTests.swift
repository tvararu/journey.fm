import Foundation
import GRDB
import Synchronization
import Testing

@testable import JourneyKit

final class FakeLyrics: LyricsSource {
    let answers: [String: Result<[LyricLine], JellyfinError>]
    let asked = Mutex<[String]>([])

    init(_ answers: [String: Result<[LyricLine], JellyfinError>]) { self.answers = answers }

    func lyrics(trackId: String) async throws -> [LyricLine] {
        asked.withLock { $0.append(trackId) }
        return try (answers[trackId] ?? .success([])).get()
    }
}

func lyricTrack(_ id: String, lyrics: Bool, etag: String = "e1") -> Track {
    var track = track(id, album: "x")
    track.hasLyrics = lyrics
    track.etag = etag
    return track
}

func libraryWith(_ tracks: [Track]) async throws -> Library {
    let library = try Library()
    let source = FakeSource()
    source.state.withLock {
        $0.albums = [album("x")]
        $0.tracks = tracks
    }
    _ = try await Sync(source: source, library: library).run(now: start)
    return library
}

@Test func onlyMissingOrChangedLyricsAreFetched() async throws {
    let library = try await libraryWith([
        lyricTrack("a", lyrics: true), lyricTrack("b", lyrics: true),
        lyricTrack("c", lyrics: false),
    ])
    let synced = [LyricLine(text: "one", time: 1.5), LyricLine(text: "two", time: 3)]
    let first = FakeLyrics(["a": .success(synced), "b": .success([LyricLine(text: "plain")])])
    #expect(try await LyricsSync(source: first, library: library).run() == 2)
    #expect(Set(first.asked.withLock { $0 }) == ["a", "b"])

    let again = FakeLyrics([:])
    try await LyricsSync(source: again, library: library).run()
    #expect(again.asked.withLock { $0 }.isEmpty)

    let lyrics = try #require(try await library.lyrics(trackId: "a"))
    #expect(lyrics.synced && lyrics.lines == synced)
    #expect(lyrics.current(at: 2) == 0 && lyrics.current(at: 0.5) == nil)
    #expect(try await library.lyrics(trackId: "b")?.synced == false)
}

@Test func aChangedEtagFetchesAgainAndLostLyricsAreRemoved() async throws {
    let library = try await libraryWith([
        lyricTrack("a", lyrics: true), lyricTrack("b", lyrics: true),
    ])
    try await LyricsSync(source: FakeLyrics([:]), library: library).run()
    let source = FakeSource()
    source.state.withLock {
        $0.albums = [album("x")]
        $0.tracks = [lyricTrack("a", lyrics: true, etag: "e2"), lyricTrack("b", lyrics: false)]
    }
    _ = try await Sync(source: source, library: library).run(now: start.addingTimeInterval(60))
    let lyrics = FakeLyrics(["a": .success([LyricLine(text: "new")])])
    try await LyricsSync(source: lyrics, library: library).run()
    #expect(lyrics.asked.withLock { $0 } == ["a"])
    #expect(try await library.lyrics(trackId: "a")?.lines == [LyricLine(text: "new")])
    #expect(try await library.db.read { try LyricsRow.fetchCount($0) } == 1)
}

@Test func noLyricsIsRememberedAndAFailureIsRetried() async throws {
    let library = try await libraryWith([
        lyricTrack("a", lyrics: true), lyricTrack("b", lyrics: true),
    ])
    let first = FakeLyrics(["a": .success([]), "b": .failure(.status(500))])
    #expect(try await LyricsSync(source: first, library: library).run() == 1)
    #expect(try await library.lyrics(trackId: "a") == nil)
    let second = FakeLyrics([:])
    try await LyricsSync(source: second, library: library).run()
    #expect(second.asked.withLock { $0 } == ["b"])
}

@Test func signingOutStopsTheLyrics() async throws {
    let library = try await libraryWith([lyricTrack("a", lyrics: true)])
    await #expect(throws: JellyfinError.unauthorized) {
        try await LyricsSync(source: FakeLyrics(["a": .failure(.unauthorized)]), library: library)
            .run()
    }
}

@Test func lyricsTimesAreTicks() throws {
    let json =
        #"{"Metadata":{},"Lyrics":[{"Text":"Living off borrowed time","Start":191100000},{"Text":"plain"}]}"#
    let lines = try JSONDecoder().decode(LyricsResponse.self, from: Data(json.utf8)).lines
    #expect(
        lines == [
            LyricLine(text: "Living off borrowed time", time: 19.11), LyricLine(text: "plain"),
        ])
}
