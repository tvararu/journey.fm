import AVFoundation
import AudioToolbox

public enum DecodeError: Error {
    case status(String, OSStatus)
}

final class SourceReader {
    let source: ByteSource
    let token = ReadToken()
    var header = Int64.max
    var skip: Int64 = 0

    init(_ source: ByteSource) { self.source = source }

    func size() throws -> Int64 {
        try source.size(token) - skip
    }

    func read(at position: Int64, count: Int, into buffer: UnsafeMutableRawPointer) throws -> Int {
        var done = 0
        while done < count {
            let at = position + Int64(done)
            let limit = at < header ? min(count - done, Int(header - at)) : count - done
            let got = try source.read(
                at: at < header ? at : at + skip, count: limit, into: buffer + done, token)
            if got == 0 { break }
            done += got
        }
        return done
    }

    func bytes(at position: Int64, count: Int) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: count)
        let got = try bytes.withUnsafeMutableBytes {
            try source.read(at: position, count: count, into: $0.baseAddress!, token)
        }
        guard got == count else { throw SourceError.truncated }
        return bytes
    }

    func seekPoint(for seconds: Double) throws -> (header: Int64, sample: Int64, offset: Int64)? {
        guard try bytes(at: 0, count: 4) == Array("fLaC".utf8) else { return nil }
        var position: Int64 = 4
        var rate = 0
        var points: [(sample: UInt64, offset: UInt64)] = []
        while true {
            let block = try bytes(at: position, count: 4)
            let length = Int(block[1]) << 16 | Int(block[2]) << 8 | Int(block[3])
            switch block[0] & 0x7f {
            case 0:
                let info = try bytes(at: position + 4, count: 18)
                rate = Int(info[10]) << 12 | Int(info[11]) << 4 | Int(info[12]) >> 4
            case 3:
                let table = try bytes(at: position + 4, count: length)
                points = stride(from: 0, to: length - 17, by: 18).map { start in
                    let value = { (from: Int) in
                        table[from..<(from + 8)].reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
                    }
                    return (value(start), value(start + 8))
                }
            default:
                break
            }
            position += 4 + Int64(length)
            if block[0] & 0x80 != 0 { break }
        }
        let target = UInt64(seconds * Double(rate))
        guard rate > 0,
            let point = points.last(where: { $0.sample <= target && $0.sample != .max }),
            point.sample > 0
        else { return nil }
        return (position, Int64(point.sample), Int64(point.offset))
    }
}

public final class TrackDecoder: @unchecked Sendable {
    let reader: SourceReader
    var audioFile: AudioFileID?
    var file: ExtAudioFileRef?
    public private(set) var format: AVAudioFormat
    public private(set) var length: AVAudioFramePosition = 0

    public init(
        source: ByteSource, from seconds: Double = 0,
        typeHint: AudioFileTypeID = kAudioFileFLACType
    ) throws {
        reader = SourceReader(source)
        format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        var base: AVAudioFramePosition = 0
        if seconds > 0, typeHint == kAudioFileFLACType,
            let point = try reader.seekPoint(for: seconds)
        {
            reader.header = point.header
            reader.skip = point.offset
            base = point.sample
        }
        let client = Unmanaged.passUnretained(reader).toOpaque()
        try check("open") {
            AudioFileOpenWithCallbacks(
                client,
                { client, position, count, buffer, actual in
                    let reader = Unmanaged<SourceReader>.fromOpaque(client).takeUnretainedValue()
                    do {
                        actual.pointee = UInt32(
                            try reader.read(at: position, count: Int(count), into: buffer))
                        return noErr
                    } catch {
                        actual.pointee = 0
                        return kAudioFileUnspecifiedError
                    }
                }, nil,
                { client in
                    let reader = Unmanaged<SourceReader>.fromOpaque(client).takeUnretainedValue()
                    return (try? reader.size()) ?? 0
                }, nil, typeHint, &audioFile)
        }
        try check("wrap") { ExtAudioFileWrapAudioFileID(audioFile!, false, &file) }
        var description = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        try check("format") {
            ExtAudioFileGetProperty(
                file!, kExtAudioFileProperty_FileDataFormat, &size, &description)
        }
        guard
            let format = AVAudioFormat(
                standardFormatWithSampleRate: description.mSampleRate,
                channels: description.mChannelsPerFrame)
        else { throw DecodeError.status("channels", -1) }
        self.format = format
        size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        try check("client format") {
            ExtAudioFileSetProperty(
                file!, kExtAudioFileProperty_ClientDataFormat, size, format.streamDescription)
        }
        var frames: Int64 = 0
        size = UInt32(MemoryLayout<Int64>.size)
        try check("length") {
            ExtAudioFileGetProperty(file!, kExtAudioFileProperty_FileLengthFrames, &size, &frames)
        }
        length = frames
        let start = AVAudioFramePosition(seconds * format.sampleRate)
        if start > base { try seek(to: start - base) }
    }

    deinit {
        if let file { ExtAudioFileDispose(file) }
        if let audioFile { AudioFileClose(audioFile) }
    }

    public func cancel() {
        reader.source.cancel(reader.token)
    }

    public func read(into buffer: AVAudioPCMBuffer) throws -> Bool {
        buffer.frameLength = buffer.frameCapacity
        let list = buffer.mutableAudioBufferList
        var frames = buffer.frameCapacity
        try check("read") { ExtAudioFileRead(file!, &frames, list) }
        buffer.frameLength = frames
        return frames > 0
    }

    public func seek(to frame: AVAudioFramePosition) throws {
        try check("seek") { ExtAudioFileSeek(file!, frame) }
    }

    func check(_ step: String, _ call: () -> OSStatus) throws {
        if reader.token.isCancelled { throw SourceError.cancelled }
        let status = call()
        if reader.token.isCancelled { throw SourceError.cancelled }
        if status != noErr { throw DecodeError.status(step, status) }
    }
}
