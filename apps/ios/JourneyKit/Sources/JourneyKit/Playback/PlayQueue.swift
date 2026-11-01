import Foundation

public enum RepeatMode: String, Codable, Sendable, CaseIterable {
    case off, all, one
}

public struct QueueEntry: Codable, Sendable, Equatable, Identifiable {
    public var id = UUID()
    public var track: Track
    public var album: Album
    public var playNext = false
    public var started = false

    public init(_ hit: TrackHit, playNext: Bool = false) {
        track = hit.track
        album = hit.album
        self.playNext = playNext
    }
}

public struct PlayQueue: Codable, Sendable, Equatable {
    public private(set) var entries: [QueueEntry] = []
    public private(set) var index = 0
    public private(set) var shuffle = false
    public var repeatMode = RepeatMode.off
    var original: [UUID]?

    public init() {}

    public var current: QueueEntry? { entries.indices.contains(index) ? entries[index] : nil }
    public var upNext: ArraySlice<QueueEntry> {
        entries.isEmpty ? [] : entries[(index + 1)...]
    }
    public var played: Set<String> {
        Set(entries.prefix(index).filter(\.started).map(\.track.id))
    }
    public var isEmpty: Bool { entries.isEmpty }

    public var following: QueueEntry? {
        if repeatMode == .one { return current }
        if index + 1 < entries.count { return entries[index + 1] }
        return repeatMode == .all ? entries.first : nil
    }

    public mutating func play(
        _ hits: [TrackHit], from start: Int? = nil, shuffled: Bool = false,
        using generator: inout some RandomNumberGenerator
    ) {
        guard !hits.isEmpty else { return }
        entries = hits.map { QueueEntry($0) }
        original = nil
        shuffle = false
        index = start ?? 0
        if shuffled {
            original = entries.map(\.id)
            let first = entries.remove(
                at: start ?? Int.random(in: entries.indices, using: &generator))
            entries.shuffle(using: &generator)
            entries.insert(first, at: 0)
            index = 0
            shuffle = true
        }
        settle()
    }

    public mutating func play(_ hits: [TrackHit], from start: Int? = nil, shuffled: Bool = false) {
        var generator = SystemRandomNumberGenerator()
        play(hits, from: start, shuffled: shuffled, using: &generator)
    }

    public mutating func playNext(_ hits: [TrackHit]) {
        guard !entries.isEmpty else { return play(hits) }
        let added = hits.map { QueueEntry($0, playNext: true) }
        var position = index + 1
        while position < entries.count && entries[position].playNext { position += 1 }
        entries.insert(contentsOf: added, at: position)
        if var original, let anchor = original.firstIndex(of: entries[position - 1].id) {
            original.insert(contentsOf: added.map(\.id), at: anchor + 1)
            self.original = original
        }
    }

    public mutating func add(_ hits: [TrackHit]) {
        guard !entries.isEmpty else { return play(hits) }
        let added = hits.map { QueueEntry($0) }
        entries.append(contentsOf: added)
        original?.append(contentsOf: added.map(\.id))
    }

    @discardableResult
    public mutating func advance() -> Bool {
        if repeatMode == .one { return !entries.isEmpty }
        return skip()
    }

    @discardableResult
    public mutating func skip() -> Bool {
        if index + 1 < entries.count {
            index += 1
            settle()
            return true
        }
        guard repeatMode != .off, !entries.isEmpty else { return false }
        index = 0
        settle()
        return true
    }

    @discardableResult
    public mutating func back() -> Bool {
        if index > 0 {
            index -= 1
            settle()
            return true
        }
        guard repeatMode != .off, !entries.isEmpty else { return false }
        index = entries.count - 1
        settle()
        return true
    }

    public mutating func rewind() {
        index = 0
        settle()
    }

    public mutating func jump(to id: UUID) {
        guard let position = entries.firstIndex(where: { $0.id == id }) else { return }
        index = position
        settle()
    }

    public mutating func removeUpNext(atOffsets offsets: IndexSet) {
        let ids = Set(offsets.map { upNext[upNext.startIndex + $0].id })
        entries.removeAll { ids.contains($0.id) }
        original?.removeAll { ids.contains($0) }
    }

    public mutating func moveUpNext(fromOffsets source: IndexSet, toOffset destination: Int) {
        guard !entries.isEmpty else { return }
        let next = Array(upNext)
        let moving = source.map { next[$0] }
        var rest = next.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        rest.insert(contentsOf: moving, at: destination - source.count { $0 < destination })
        entries.replaceSubrange((index + 1)..., with: rest)
    }

    public mutating func clearUpNext() {
        guard !entries.isEmpty else { return }
        let ids = Set(upNext.map(\.id))
        entries.removeSubrange((index + 1)...)
        original?.removeAll { ids.contains($0) }
    }

    public mutating func setShuffle(_ on: Bool, using generator: inout some RandomNumberGenerator) {
        guard !entries.isEmpty else { return }
        if on {
            if !shuffle { original = entries.map(\.id) }
            entries[(index + 1)...].shuffle(using: &generator)
        } else if shuffle, let original {
            let order = Dictionary(uniqueKeysWithValues: original.enumerated().map { ($1, $0) })
            let currentId = entries[index].id
            entries.sort { (order[$0.id] ?? .max) < (order[$1.id] ?? .max) }
            index = entries.firstIndex { $0.id == currentId } ?? 0
            self.original = nil
        }
        shuffle = on
    }

    public mutating func setShuffle(_ on: Bool) {
        var generator = SystemRandomNumberGenerator()
        setShuffle(on, using: &generator)
    }

    mutating func settle() {
        guard entries.indices.contains(index) else { return }
        entries[index].playNext = false
        entries[index].started = true
    }
}
