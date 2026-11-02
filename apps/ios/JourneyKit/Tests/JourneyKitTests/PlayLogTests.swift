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
