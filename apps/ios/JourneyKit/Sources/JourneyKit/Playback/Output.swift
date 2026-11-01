import AVFoundation

public final class Output: @unchecked Sendable {
    public enum Event: Sendable, Equatable {
        case started(UUID)
        case failed(UUID)
        case ended
        case reset
    }

    public struct Item: Sendable {
        public var entry: UUID
        public var source: ByteSource

        public init(entry: UUID, source: ByteSource) {
            self.entry = entry
            self.source = source
        }
    }

    final class Segment {
        let item: Item
        let startTime: Double
        var decoder: TrackDecoder?
        var converter: AVAudioConverter?
        var startFrame: AVAudioFramePosition = 0
        var base: AVAudioFramePosition?
        var end: AVAudioFramePosition?
        var failed = false

        init(_ item: Item, startTime: Double) {
            self.item = item
            self.startTime = startTime
        }

        var done: Bool { end != nil }
    }

    public let engine: AVAudioEngine
    let node = AVAudioPlayerNode()
    let state = NSCondition()
    let ahead: Double
    let prebuffer: Double
    let chunk: AVAudioFrameCount = 8192
    var segments: [Segment] = []
    var scheduled: AVAudioFramePosition = 0
    var lastSample: AVAudioFramePosition = 0
    var wantsPlay = false
    var events: [Event] = []
    var format: AVAudioFormat
    var generation = 0
    var observer: (any NSObjectProtocol)?

    public init(engine: AVAudioEngine = AVAudioEngine(), ahead: Double = 5, prebuffer: Double = 0.5)
    {
        self.engine = engine
        self.ahead = ahead
        self.prebuffer = prebuffer
        format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        observer = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            state.withLock {
                if !segments.isEmpty { events.append(.reset) }
            }
        }
        let thread = Thread { [weak self] in
            while let output = self { if !output.feed() { break } }
        }
        thread.name = "fm.journey.feed"
        thread.qualityOfService = .userInitiated
        thread.start()
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        state.withLock {
            generation = -1
            for segment in segments { segment.decoder?.cancel() }
            state.broadcast()
        }
    }

    public func start(_ item: Item, at time: Double, following: Item?, play: Bool) throws {
        try state.withLock {
            clear()
            segments =
                [Segment(item, startTime: time)]
                + (following.map { [Segment($0, startTime: 0)] } ?? [])
            wantsPlay = play
            if !engine.isRunning {
                engine.prepare()
                try engine.start()
            }
            state.broadcast()
        }
    }

    public func stop() {
        state.withLock {
            clear()
            wantsPlay = false
            engine.pause()
        }
    }

    @discardableResult
    public func setFollowing(_ item: Item?) -> Bool {
        state.withLock {
            guard !segments.isEmpty else { return true }
            let old = segments.count > 1 ? segments[1] : nil
            if old?.item.entry == item?.entry { return true }
            if old?.base != nil { return false }
            old?.decoder?.cancel()
            segments = [segments[0]] + (item.map { [Segment($0, startTime: 0)] } ?? [])
            state.broadcast()
            return true
        }
    }

    public func pause() {
        state.withLock {
            wantsPlay = false
            sample()
            node.pause()
            engine.pause()
        }
    }

    public func resume() throws {
        try state.withLock {
            wantsPlay = true
            if !engine.isRunning {
                engine.prepare()
                try engine.start()
            }
            state.broadcast()
        }
    }

    public func poll() -> (events: [Event], position: Double?) {
        state.withLock {
            let now = sample()
            var found = events
            events = []
            while let current = segments.first {
                if current.failed && current.base == nil {
                    found.append(.failed(current.item.entry))
                    clear()
                    wantsPlay = false
                    break
                }
                if segments.count > 1, let next = segments[1].base, now >= next {
                    segments.removeFirst()
                    found.append(.started(segments[0].item.entry))
                    continue
                }
                if let end = current.end, now >= end, segments.count == 1 || segments[1].done {
                    if current.failed {
                        found.append(.failed(current.item.entry))
                    } else if segments.count > 1 {
                        found.append(.failed(segments[1].item.entry))
                    } else {
                        found.append(.ended)
                    }
                    clear()
                    wantsPlay = false
                }
                break
            }
            guard let current = segments.first else { return (found, nil) }
            guard let base = current.base else { return (found, current.startTime) }
            return (found, max(0, Double(now - base) / format.sampleRate))
        }
    }

    var isFullyScheduled: Bool {
        state.withLock { segments.allSatisfy(\.done) }
    }

    @discardableResult
    func sample() -> AVAudioFramePosition {
        if node.isPlaying, let render = node.lastRenderTime,
            render.isSampleTimeValid || render.isHostTimeValid,
            let time = node.playerTime(forNodeTime: render)
        {
            lastSample = time.sampleTime
        }
        return lastSample
    }

    func clear() {
        generation += 1
        for segment in segments { segment.decoder?.cancel() }
        segments = []
        node.stop()
        scheduled = 0
        lastSample = 0
    }

    func feed() -> Bool {
        state.lock()
        guard generation >= 0 else {
            state.unlock()
            return false
        }
        let now = sample()
        if node.isPlaying && now >= scheduled && segments.contains(where: { !$0.done }) {
            node.pause()
            for segment in segments {
                segment.base = segment.base.map { $0 + now - scheduled }
            }
            scheduled = now
        }
        let buffered = Double(scheduled - now) / format.sampleRate
        if wantsPlay && !node.isPlaying && engine.isRunning
            && (buffered >= prebuffer || (!segments.isEmpty && segments.allSatisfy(\.done)))
            && scheduled > now
        {
            node.play()
        }
        guard buffered < ahead, let segment = segments.first(where: { !$0.done }) else {
            state.wait(until: .now.addingTimeInterval(0.1))
            state.unlock()
            return true
        }
        let generation = generation
        let fresh = scheduled == 0 && segment === segments.first
        state.unlock()

        do {
            if segment.decoder == nil {
                let decoder = try TrackDecoder(source: segment.item.source)
                let startFrame = AVAudioFramePosition(segment.startTime * decoder.format.sampleRate)
                if startFrame > 0 { try decoder.seek(to: startFrame) }
                state.withLock {
                    guard generation == self.generation else { return decoder.cancel() }
                    if fresh && !decoder.format.isEqual(format) {
                        format = decoder.format
                        let running = engine.isRunning
                        if running { engine.stop() }
                        engine.connect(node, to: engine.mainMixerNode, format: format)
                        if running {
                            engine.prepare()
                            try? engine.start()
                        }
                    }
                    if !decoder.format.isEqual(format) {
                        segment.converter = AVAudioConverter(from: decoder.format, to: format)
                    }
                    segment.startFrame = AVAudioFramePosition(
                        Double(startFrame) * format.sampleRate / decoder.format.sampleRate)
                    segment.decoder = decoder
                }
                return true
            }
            guard let decoder = segment.decoder,
                let buffer = AVAudioPCMBuffer(pcmFormat: decoder.format, frameCapacity: chunk)
            else { return true }
            let more = try decoder.read(into: buffer)
            let output = more ? try convert(buffer, segment.converter) : nil
            state.withLock {
                guard generation == self.generation else { return }
                if segment.base == nil { segment.base = scheduled - segment.startFrame }
                if let output, output.frameLength > 0 {
                    node.scheduleBuffer(output)
                    scheduled += AVAudioFramePosition(output.frameLength)
                }
                if !more { segment.end = scheduled }
            }
        } catch {
            state.withLock {
                guard generation == self.generation else { return }
                if case SourceError.cancelled = error { return }
                Log.audio.error(
                    "Playback of \(segment.item.entry, privacy: .public) failed: \(String(describing: error), privacy: .public)"
                )
                segment.failed = true
                segment.end = scheduled
            }
        }
        return true
    }

    func convert(_ buffer: AVAudioPCMBuffer, _ converter: AVAudioConverter?) throws
        -> AVAudioPCMBuffer
    {
        guard let converter else { return buffer }
        let capacity =
            AVAudioFrameCount(
                Double(buffer.frameLength) * converter.outputFormat.sampleRate
                    / converter.inputFormat.sampleRate) + 64
        guard
            let output = AVAudioPCMBuffer(
                pcmFormat: converter.outputFormat, frameCapacity: capacity)
        else { return buffer }
        nonisolated(unsafe) var given = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if given {
                status.pointee = .noDataNow
                return nil
            }
            given = true
            status.pointee = .haveData
            return buffer
        }
        if let error { throw error }
        return output
    }
}
