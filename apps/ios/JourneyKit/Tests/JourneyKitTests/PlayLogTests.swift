import Foundation
import Testing

@testable import JourneyKit

func entry(_ id: String, seconds: Double) -> QueueEntry {
    var track = song(id, id, album: "p")
    track.duration = seconds
    return QueueEntry(TrackHit(track: track, album: paranoid.album))
}

extension PlayCounter {
    mutating func play(_ entry: QueueEntry, from: Double, to: Double) -> [CountedPlay] {
        var counted: [CountedPlay] = []
        var position = from
        while position < to {
            position = min(position + 0.25, to)
            if let play = advance(entry, to: position, playing: true, now: JourneyKitTests.start) {
                counted.append(play)
            }
        }
        return counted
    }
}

@Test func aTrackCountsAtHalfItsLengthOrFourMinutes() {
    let short = entry("a", seconds: 180)
    var counter = PlayCounter()
    counter.start(short, at: 0, now: start)
    #expect(counter.play(short, from: 0, to: 89.75).isEmpty)
    #expect(
        counter.play(short, from: 89.75, to: 90)
            == [CountedPlay(entryId: short.id, trackId: "a", albumId: "p", startedAt: start)])

    let long = entry("b", seconds: 600)
    counter.start(long, at: 0, now: start)
    #expect(counter.play(long, from: 0, to: 239.75).isEmpty)
    #expect(counter.play(long, from: 239.75, to: 240).count == 1)
}

@Test func tracksUnderThirtySecondsNeverCount() {
    let jingle = entry("a", seconds: 20)
    var counter = PlayCounter()
    counter.start(jingle, at: 0, now: start)
    #expect(counter.play(jingle, from: 0, to: 20).isEmpty)
}

@Test func seeksAndPausesAddNothingAndKeepWhatWasHeard() {
    let track = entry("a", seconds: 180)
    var counter = PlayCounter()
    counter.start(track, at: 0, now: start)
    #expect(counter.play(track, from: 0, to: 60).isEmpty)
    counter.rebase(to: 61.5)
    #expect(counter.advance(track, to: 63, playing: false, now: start) == nil)
    #expect(counter.advance(track, to: 64, playing: true, now: start) == nil)
    #expect(counter.play(track, from: 64, to: 92.75).isEmpty)
    #expect(counter.play(track, from: 92.75, to: 93).count == 1)
}

@Test func aSessionCountsOnceAndANewOneCountsAgain() {
    let track = entry("a", seconds: 60)
    var counter = PlayCounter()
    counter.start(track, at: 0, now: start)
    #expect(counter.play(track, from: 0, to: 60).count == 1)
    counter.start(track, at: 0, now: start)
    #expect(counter.play(track, from: 0, to: 60).count == 1)
}

@Test func aNewEntryStartsASessionAtItsFirstPlayingSample() {
    let first = entry("a", seconds: 60)
    let second = entry("b", seconds: 60)
    var counter = PlayCounter()
    counter.start(first, at: 0, now: start)
    #expect(counter.play(first, from: 0, to: 10).isEmpty)
    #expect(counter.advance(second, to: 0, playing: false, now: start) == nil)
    let later = start.addingTimeInterval(30)
    #expect(counter.advance(second, to: 0, playing: true, now: later) == nil)
    var counted: [CountedPlay] = []
    var position = 0.0
    while position < 30 {
        position += 0.25
        if let play = counter.advance(second, to: position, playing: true, now: later) {
            counted.append(play)
        }
    }
    #expect(
        counted == [CountedPlay(entryId: second.id, trackId: "b", albumId: "p", startedAt: later)])
}

func logged(_ track: String, album: String = "p", at seconds: Double, entry: UUID = UUID())
    -> CountedPlay
{
    CountedPlay(
        entryId: entry, trackId: track, albumId: album,
        startedAt: start.addingTimeInterval(seconds))
}

func paranoidWith(_ ids: [String]) async throws -> Library {
    let other = synced("v", name: "Vol. 4", artist: sabbath)
    return try await librarySynced(
        artists: [sabbath], albums: [paranoid, other],
        tracks: ids.map { song($0, $0, album: "p") } + [song("v1", "v1", album: "v")])
}

@Test func recentlyPlayedOrdersAlbumsByTheirLatestPlay() async throws {
    let library = try await paranoidWith(["a"])
    try await library.recordPlay(logged("a", at: 0))
    try await library.recordPlay(logged("v1", album: "v", at: 60))
    try await library.recordPlay(logged("a", at: 120))
    var recent = library.observeRecentlyPlayed(limit: 10).makeAsyncIterator()
    #expect(try await recent.next()?.map(\.id) == ["p", "v"])
}

@Test func historyListsEachTrackOnceOldestFirst() async throws {
    let library = try await paranoidWith(["a", "b"])
    try await library.recordPlay(logged("a", at: 0))
    try await library.recordPlay(logged("b", at: 60))
    try await library.recordPlay(logged("a", at: 120))
    try await library.recordPlay(logged("gone", at: 180))
    var history = library.observeHistory(excluding: nil).makeAsyncIterator()
    #expect(try await history.next()?.map(\.track.id) == ["b", "a"])
}

@Test func historyHidesClearedPlaysAndTheCurrentEntry() async throws {
    let library = try await paranoidWith(["a", "b", "c"])
    let current = UUID()
    try await library.recordPlay(logged("a", at: 0))
    try await library.clearHistory(at: start.addingTimeInterval(30))
    try await library.recordPlay(logged("b", at: 60))
    try await library.recordPlay(logged("c", at: 120, entry: current))
    var history = library.observeHistory(excluding: current).makeAsyncIterator()
    #expect(try await history.next()?.map(\.track.id) == ["b"])
    var recent = library.observeRecentlyPlayed(limit: 10).makeAsyncIterator()
    #expect(try await recent.next()?.map(\.id) == ["p"])
}

@Test func clearingAtThePlayingTrackStartKeepsItInHistory() async throws {
    let library = try await paranoidWith(["a", "b"])
    try await library.recordPlay(logged("a", at: 0))
    try await library.clearHistory(at: start.addingTimeInterval(60))
    try await library.recordPlay(logged("b", at: 60))
    var history = library.observeHistory(excluding: nil).makeAsyncIterator()
    #expect(try await history.next()?.map(\.track.id) == ["b"])
}

@Test func historyKeepsTheLatestHundredTracks() async throws {
    let ids = (0..<101).map { "t\($0)" }
    let library = try await paranoidWith(ids)
    for (offset, id) in ids.enumerated() {
        try await library.recordPlay(logged(id, at: Double(offset)))
    }
    var history = library.observeHistory(excluding: nil).makeAsyncIterator()
    let tracks = try #require(try await history.next()).map(\.track.id)
    #expect(tracks == Array(ids.dropFirst()))
}
