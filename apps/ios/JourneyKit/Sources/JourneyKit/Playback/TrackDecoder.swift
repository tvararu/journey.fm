import AVFoundation
import AudioToolbox

public enum DecodeError: Error {
    case status(String, OSStatus)
}

final class SourceReader {
    let source: ByteSource
    let token = ReadToken()

    init(_ source: ByteSource) { self.source = source }
}

public final class TrackDecoder: @unchecked Sendable {
    let reader: SourceReader
    var audioFile: AudioFileID?
    var file: ExtAudioFileRef?
    public private(set) var format: AVAudioFormat
    public private(set) var length: AVAudioFramePosition = 0

    public init(source: ByteSource, typeHint: AudioFileTypeID = kAudioFileFLACType) throws {
        reader = SourceReader(source)
        format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        let client = Unmanaged.passUnretained(reader).toOpaque()
        try check("open") {
            AudioFileOpenWithCallbacks(
                client,
                { client, position, count, buffer, actual in
                    let reader = Unmanaged<SourceReader>.fromOpaque(client).takeUnretainedValue()
                    do {
                        actual.pointee = UInt32(
                            try reader.source.read(
                                at: position, count: Int(count), into: buffer, reader.token))
                        return noErr
                    } catch {
                        actual.pointee = 0
                        return kAudioFileUnspecifiedError
                    }
                }, nil,
                { client in
                    let reader = Unmanaged<SourceReader>.fromOpaque(client).takeUnretainedValue()
                    return (try? reader.source.size(reader.token)) ?? 0
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
