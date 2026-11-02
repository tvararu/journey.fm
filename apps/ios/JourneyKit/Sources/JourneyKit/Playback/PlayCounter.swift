import Foundation

public struct CountedPlay: Sendable, Equatable {
    public var entryId: UUID
    public var trackId: String
    public var albumId: String
    public var startedAt: Date
}

struct PlayCounter {
    private var entry: QueueEntry?
    private var startedAt = Date.distantPast
    private var sampled = 0.0
    private var heard = 0.0
    private var counted = false

    static func threshold(for duration: Double) -> Double? {
        duration < 30 ? nil : min(duration / 2, 240)
    }

    mutating func start(_ entry: QueueEntry, at position: Double, now: Date = .now) {
        self.entry = entry
        startedAt = now
        sampled = position
        heard = 0
        counted = false
    }

    mutating func rebase(to position: Double) {
        sampled = position
    }

    mutating func advance(
        _ entry: QueueEntry, to position: Double, playing: Bool, now: Date = .now
    ) -> CountedPlay? {
        guard entry.id == self.entry?.id else {
            if playing { start(entry, at: position, now: now) }
            return nil
        }
        let step = position - sampled
        sampled = position
        guard playing, !counted, step > 0, step <= 2 else { return nil }
        heard += step
        guard let threshold = Self.threshold(for: entry.track.duration), heard >= threshold
        else { return nil }
        counted = true
        return CountedPlay(
            entryId: entry.id, trackId: entry.track.id, albumId: entry.album.id,
            startedAt: startedAt)
    }
}
