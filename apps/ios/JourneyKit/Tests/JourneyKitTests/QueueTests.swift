import Foundation
import Testing

@testable import JourneyKit

let paranoid = SyncedAlbum(
    album: Album(
        id: "p", name: "Paranoid", sortName: "paranoid", artistName: "Black Sabbath", year: 1970,
        genres: "", duration: 0, trackCount: 4, imageTag: nil, dateCreated: "2026-01-01T00:00:00Z"),
    artistIds: ["bs"])

func hits(_ names: String...) -> [TrackHit] {
    names.map { TrackHit(track: song($0, $0, album: "p"), album: paranoid.album) }
}

extension PlayQueue {
    var names: [String] { entries.map(\.track.id) }
    var upNextNames: [String] { upNext.map(\.track.id) }
}

struct Seeded: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state
    }
}

@Test func playingFromATrackQueuesTheRestAndMarksOnlyStartedTracksPlayed() {
    var queue = PlayQueue()
    queue.play(hits("a", "b", "c", "d"), from: 2)
    #expect(queue.current?.track.id == "c")
    #expect(queue.upNextNames == ["d"])
    #expect(queue.played.isEmpty)
    queue.skip()
    #expect(queue.played == ["c"])
    queue.back()
    queue.back()
    #expect(queue.played.isEmpty)
    queue.jump(to: queue.entries[3].id)
    #expect(queue.played == ["b", "c"])
}

@Test func shuffleKeepsTheChosenTrackFirstAndOffRestoresTheOrder() {
    var generator = Seeded(state: 7)
    var queue = PlayQueue()
    queue.play(hits("a", "b", "c", "d", "e", "f"), from: 3, shuffled: true, using: &generator)
    #expect(queue.current?.track.id == "d")
    #expect(queue.played.isEmpty)
    #expect(Set(queue.upNextNames) == ["a", "b", "c", "e", "f"])
    #expect(queue.upNextNames != ["a", "b", "c", "e", "f"])
    queue.skip()
    let second = queue.current?.track.id
    queue.setShuffle(false, using: &generator)
    #expect(queue.names == ["a", "b", "c", "d", "e", "f"])
    #expect(queue.current?.track.id == second)
}

@Test func shufflingMidwayLeavesPlayedTracksAlone() {
    var generator = Seeded(state: 3)
    var queue = PlayQueue()
    queue.play(hits("a", "b", "c", "d", "e", "f"), from: 2)
    queue.setShuffle(true, using: &generator)
    #expect(Array(queue.names.prefix(3)) == ["a", "b", "c"])
    #expect(queue.current?.track.id == "c")
    #expect(Set(queue.upNextNames) == ["d", "e", "f"])
}

@Test func playNextGoesAfterTheCurrentTrackAndAfterEarlierPlayNexts() {
    var queue = PlayQueue()
    queue.play(hits("a", "b", "c"))
    queue.playNext(hits("x"))
    queue.playNext(hits("y", "z"))
    #expect(queue.upNextNames == ["x", "y", "z", "b", "c"])
    #expect(queue.upNext.map(\.playNext) == [true, true, true, false, false])
    queue.skip()
    #expect(queue.current?.track.id == "x")
    #expect(queue.current?.playNext == false)
    queue.playNext(hits("w"))
    #expect(queue.upNextNames == ["y", "z", "w", "b", "c"])
}

@Test func addToQueueAppendsAndStartsAnEmptyQueue() {
    var queue = PlayQueue()
    queue.add(hits("a"))
    #expect(queue.current?.track.id == "a")
    queue.add(hits("b", "c"))
    #expect(queue.upNextNames == ["b", "c"])
    #expect(queue.upNext.allSatisfy { !$0.playNext })
}

@Test func addingWhileShuffledSurvivesTurningShuffleOff() {
    var generator = Seeded(state: 11)
    var queue = PlayQueue()
    queue.play(hits("a", "b", "c"), from: 0, shuffled: true, using: &generator)
    queue.add(hits("z"))
    queue.playNext(hits("n"))
    queue.setShuffle(false, using: &generator)
    #expect(queue.names == ["a", "n", "b", "c", "z"])
}

@Test func skipAndBackFollowTheRepeatMode() {
    var queue = PlayQueue()
    queue.play(hits("a", "b"), from: 1)
    var moved = queue.skip()
    #expect(!moved)
    #expect(queue.following == nil)
    queue.repeatMode = .all
    #expect(queue.following?.track.id == "a")
    moved = queue.skip()
    #expect(moved && queue.current?.track.id == "a")
    moved = queue.back()
    #expect(moved && queue.current?.track.id == "b")
    queue.repeatMode = .one
    #expect(queue.following?.track.id == "b")
    moved = queue.advance()
    #expect(moved && queue.current?.track.id == "b")
    moved = queue.skip()
    #expect(moved && queue.current?.track.id == "a")
    queue.repeatMode = .off
    moved = queue.back()
    #expect(!moved && queue.current?.track.id == "a")
}

@Test func offlineTheQueueSkipsAndMarksTracksThatAreNotOnThePhone() {
    let onPhone: Set<String> = ["a", "d"]
    let available = { (track: Track) in onPhone.contains(track.id) }
    var queue = PlayQueue()
    queue.play(hits("a", "b", "c", "d", "e"))
    #expect(queue.following(where: available)?.track.id == "d")

    let d = queue.entries[3].id
    queue.markMissing(before: d)
    queue.jump(to: d)
    #expect(queue.entries.filter(\.missing).map(\.track.id) == ["b", "c"])
    #expect(queue.played == ["a"])
    #expect(queue.following(where: available) == nil)

    queue.skip()
    let landed = queue.skipUnavailable(available)
    #expect(!landed)
    #expect(queue.entries.filter(\.missing).map(\.track.id) == ["b", "c", "e"])

    queue.repeatMode = .all
    queue.jump(to: queue.entries[1].id)
    let wrapped = queue.skipUnavailable(available)
    #expect(wrapped)
    #expect(queue.current?.track.id == "d")
    #expect(queue.following(where: available)?.track.id == "a")
}

@Test func upNextCanBeRemovedReorderedAndCleared() {
    var queue = PlayQueue()
    queue.play(hits("a", "b", "c", "d", "e"), from: 1)
    queue.removeUpNext(atOffsets: [1])
    #expect(queue.upNextNames == ["c", "e"])
    queue.moveUpNext(fromOffsets: [1], toOffset: 0)
    #expect(queue.upNextNames == ["e", "c"])
    queue.clearUpNext()
    #expect(queue.names == ["a", "b"])
    #expect(queue.current?.track.id == "b")
}

@Test func clearingHistoryKeepsTheCurrentTrackAndWhatFollows() {
    var queue = PlayQueue()
    queue.play(hits("a", "b", "c", "d"), from: 2)
    queue.setShuffle(true)
    queue.skip()
    let current = queue.current?.track.id
    let upNext = queue.upNextNames
    queue.clearHistory()
    #expect(queue.history.isEmpty)
    #expect(queue.current?.track.id == current)
    #expect(queue.upNextNames == upNext)
    queue.setShuffle(false)
    #expect(queue.current?.track.id == current)
    #expect(queue.names.count == 1 + upNext.count)
}

@Test func playbackResumesFromTheSavedQueueAndPosition() async throws {
    let path = FileManager.default.temporaryDirectory.appending(path: "\(UUID()).sqlite")
        .path(percentEncoded: false)
    var queue = PlayQueue()
    queue.play(hits("a", "b", "c"), from: 1)
    queue.playNext(hits("x"))
    queue.repeatMode = .all
    try await Library(path: path).savePlayback(queue, position: 83.5)
    let saved = try #require(try await Library(path: path).savedPlayback())
    #expect(saved.queue == queue)
    #expect(saved.position == 83.5)
}

@Test func playNowPlaysTheTrackAndKeepsUpNext() {
    var queue = PlayQueue()
    queue.play(hits("a", "b", "c"))
    queue.playNow(hits("x")[0])
    #expect(queue.current?.track.id == "x")
    #expect(queue.upNextNames == ["b", "c"])

    var generator = Seeded(state: 5)
    queue.play(hits("a", "b", "c", "d"))
    queue.setShuffle(true, using: &generator)
    let upNext = queue.upNextNames
    queue.playNow(hits("x")[0])
    #expect(queue.current?.track.id == "x")
    #expect(queue.upNextNames == upNext)
    queue.setShuffle(false, using: &generator)
    #expect(queue.names == ["a", "x", "b", "c", "d"])
    #expect(queue.current?.track.id == "x")
}
