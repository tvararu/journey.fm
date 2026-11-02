import Foundation
import Observation

@MainActor
@Observable
public final class Player {
    public private(set) var queue = PlayQueue()
    public private(set) var isPlaying = false
    public private(set) var position: Double = 0
    public private(set) var failure: String?
    public var offline = false

    @ObservationIgnored public var activate: () -> Void = {}
    @ObservationIgnored public var changed: () -> Void = {}
    @ObservationIgnored let output: Output
    @ObservationIgnored let library: Library
    @ObservationIgnored var cache: AudioCache?
    @ObservationIgnored var prepared = false
    @ObservationIgnored var loop: Task<Void, Never>?
    @ObservationIgnored var savedAt = Date.distantPast
    @ObservationIgnored var counter = PlayCounter()

    public init(library: Library, output: Output = Output()) {
        self.library = library
        self.output = output
    }

    public var current: QueueEntry? { queue.current }
    public var duration: Double { queue.current?.track.duration ?? 0 }

    public func connect(_ cache: AudioCache?) {
        self.cache = cache
        if cache == nil { reset() }
    }

    public func restore() async {
        guard queue.isEmpty, let saved = try? await library.savedPlayback() else { return }
        queue = saved.queue
        position = saved.position
        changed()
    }

    public func reset() {
        output.stop()
        loop?.cancel()
        loop = nil
        queue = PlayQueue()
        isPlaying = false
        prepared = false
        position = 0
        failure = nil
        changed()
    }

    public func play(_ hits: [TrackHit], from start: Int? = nil, shuffled: Bool = false) {
        queue.play(hits, from: start, shuffled: shuffled)
        begin(at: 0, play: true)
    }

    public func playNext(_ hits: [TrackHit]) {
        let wasEmpty = queue.isEmpty
        queue.playNext(hits)
        wasEmpty ? begin(at: 0, play: true) : edited()
    }

    public func add(_ hits: [TrackHit]) {
        let wasEmpty = queue.isEmpty
        queue.add(hits)
        wasEmpty ? begin(at: 0, play: true) : edited()
    }

    public func playNow(_ hit: TrackHit) {
        queue.playNow(hit)
        begin(at: 0, play: true)
    }

    public func toggle() {
        isPlaying ? pause() : resume()
    }

    public func pause() {
        guard isPlaying else { return }
        output.pause()
        isPlaying = false
        _ = tick()
        loop?.cancel()
        loop = nil
        save(force: true)
        changed()
    }

    public func resume() {
        guard !isPlaying, queue.current != nil else { return }
        guard prepared else { return begin(at: position, play: true) }
        activate()
        do {
            try output.resume()
            isPlaying = true
            failure = nil
            startLoop()
        } catch {
            fail(error)
        }
        changed()
    }

    public func next() {
        if queue.skip() {
            begin(at: 0, play: isPlaying || !prepared)
        } else {
            finish()
        }
    }

    public func previous() {
        if position > 3 || !queue.back() {
            seek(to: 0)
        } else {
            begin(at: 0, play: isPlaying || !prepared)
        }
    }

    public func seek(to time: Double) {
        guard queue.current != nil else { return }
        begin(at: max(0, min(time, duration)), play: isPlaying, session: false)
    }

    public func jump(to id: UUID) {
        queue.jump(to: id)
        begin(at: 0, play: true)
    }

    public func removeUpNext(atOffsets offsets: IndexSet) {
        queue.removeUpNext(atOffsets: offsets)
        edited()
    }

    public func moveUpNext(fromOffsets source: IndexSet, toOffset destination: Int) {
        queue.moveUpNext(fromOffsets: source, toOffset: destination)
        edited()
    }

    public func clearUpNext() {
        queue.clearUpNext()
        edited()
    }

    public func clearHistory() {
        let at = queue.current.flatMap { counter.sessionStart(of: $0.id) } ?? .now
        let library = library
        Task { try? await library.clearHistory(at: at) }
    }

    public func setShuffle(_ on: Bool) {
        queue.setShuffle(on)
        edited()
    }

    public func cycleRepeat() {
        let modes = RepeatMode.allCases
        queue.repeatMode = modes[(modes.firstIndex(of: queue.repeatMode)! + 1) % modes.count]
        edited()
    }

    func begin(at time: Double, play: Bool, session: Bool = true) {
        guard let cache, !queue.isEmpty else { return }
        guard queue.skipUnavailable(available()) else {
            output.stop()
            isPlaying = false
            prepared = false
            failure = "Nothing left in the queue is on this iPhone."
            save(force: true)
            changed()
            return
        }
        guard let entry = queue.current else { return }
        if play { activate() }
        position = time
        failure = nil
        do {
            try output.start(
                Output.Item(
                    entry: entry.id, source: cache.source(for: entry.track),
                    gain: playbackGain(album: entry.album, track: entry.track)), at: time,
                following: following(), play: play)
            prepared = true
            isPlaying = play
            cache.cancel(except: wanted(entry))
            if !session {
                counter.rebase(to: time)
            } else if play {
                counter.start(entry, at: time)
            }
            startLoop()
        } catch {
            fail(error)
        }
        save(force: true)
        changed()
    }

    func edited() {
        if prepared, !output.setFollowing(following()) {
            begin(at: position, play: isPlaying, session: false)
            return
        }
        if let cache, let entry = queue.current {
            cache.cancel(except: wanted(entry))
        }
        save(force: true)
        changed()
    }

    func following() -> Output.Item? {
        guard let entry = queue.following(where: available()), let cache,
            let source = try? cache.source(for: entry.track)
        else { return nil }
        return Output.Item(
            entry: entry.id, source: source,
            gain: playbackGain(album: entry.album, track: entry.track))
    }

    func available() -> (Track) -> Bool {
        let cache = cache
        let offline = offline
        return { !offline || cache?.isOnPhone($0) == true }
    }

    func wanted(_ entry: QueueEntry) -> Set<String> {
        Set([entry.track.id, queue.following(where: available())?.track.id].compactMap { $0 })
    }

    func finish() {
        output.stop()
        queue.rewind()
        isPlaying = false
        prepared = false
        position = 0
        save(force: true)
        changed()
    }

    func fail(_ error: (any Error)?) {
        if let error {
            Log.audio.error("Playback failed: \(String(describing: error), privacy: .public)")
        }
        output.stop()
        isPlaying = false
        prepared = false
        failure = "Couldn't play \(queue.current?.track.name ?? "this track")."
    }

    func startLoop() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.tick() else { return }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    func tick() -> Bool {
        let (events, time) = output.poll()
        if let time { position = time }
        for event in events {
            switch event {
            case .started(let id):
                if id != queue.current?.id {
                    queue.markMissing(before: id)
                    queue.jump(to: id)
                }
                if let entry = queue.current { counter.start(entry, at: position) }
                edited()
            case .ended:
                finish()
            case .failed(let id):
                queue.jump(to: id)
                fail(nil)
                position = 0
                save(force: true)
                changed()
            case .reset:
                begin(at: position, play: isPlaying, session: false)
            }
        }
        if let entry = queue.current,
            let play = counter.advance(entry, to: position, playing: isPlaying)
        {
            let library = library
            Task { try? await library.recordPlay(play) }
        }
        save()
        if !isPlaying && events.isEmpty {
            loop = nil
            return false
        }
        return true
    }

    func save(force: Bool = false) {
        guard force || Date.now.timeIntervalSince(savedAt) > 10 else { return }
        savedAt = .now
        let library = library
        let queue = queue
        let position = position
        Task { try? await library.savePlayback(queue, position: position) }
    }
}
