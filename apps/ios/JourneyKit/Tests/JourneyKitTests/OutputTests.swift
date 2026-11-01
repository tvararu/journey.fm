import AVFoundation
import Foundation
import Testing

@testable import JourneyKit

let rate = 44100.0

func flac(value: Float, frames: AVAudioFrameCount) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID()).flac")
    let file = try AVAudioFile(
        forWriting: url,
        settings: [
            AVFormatIDKey: kAudioFormatFLAC, AVSampleRateKey: rate, AVNumberOfChannelsKey: 2,
            AVEncoderBitDepthHintKey: 16,
        ], commonFormat: .pcmFormatFloat32, interleaved: false)
    let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames)!
    buffer.frameLength = frames
    for channel in 0..<2 {
        buffer.floatChannelData![channel].update(repeating: value, count: Int(frames))
    }
    try file.write(from: buffer)
    file.close()
    return url
}

func offlineOutput() throws -> Output {
    let engine = AVAudioEngine()
    try engine.enableManualRenderingMode(
        .offline, format: AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2)!,
        maximumFrameCount: 4096)
    return Output(engine: engine)
}

func render(_ output: Output, frames: Int) throws -> [Float] {
    var samples: [Float] = []
    let engine = output.engine
    while samples.count < frames {
        let buffer = AVAudioPCMBuffer(
            pcmFormat: engine.manualRenderingFormat, frameCapacity: 4096)!
        _ = try engine.renderOffline(4096, to: buffer)
        samples += UnsafeBufferPointer(
            start: buffer.floatChannelData![0], count: Int(buffer.frameLength))
    }
    return samples
}

func untilScheduled(_ output: Output) async throws {
    for _ in 0..<500 where !(output.isFullyScheduled && output.node.isPlaying) {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(output.isFullyScheduled && output.node.isPlaying)
}

@Test func theNextTrackStartsOnTheSampleAfterTheLastOne() async throws {
    let first: AVAudioFrameCount = 13_331
    let second: AVAudioFrameCount = 9_007
    let a = UUID()
    let b = UUID()
    let output = try offlineOutput()
    try output.start(
        .init(entry: a, source: try ByteSource(complete: flac(value: 0.25, frames: first))), at: 0,
        following: .init(
            entry: b, source: try ByteSource(complete: flac(value: 0.5, frames: second))),
        play: true)
    try await untilScheduled(output)
    let samples = try render(output, frames: Int(first + second) + 8192)
    let start = try #require(samples.firstIndex { $0 != 0 })
    let middle = start + Int(first)
    let end = middle + Int(second)
    #expect(samples[start..<middle].allSatisfy { abs($0 - 0.25) < 1e-4 })
    #expect(samples[middle..<end].allSatisfy { abs($0 - 0.5) < 1e-4 })
    #expect(samples[end...].allSatisfy { $0 == 0 })
    #expect(output.poll().events == [.started(b), .ended])
}

@Test func startingPartWayReportsThePositionFromThatPoint() async throws {
    let a = UUID()
    let output = try offlineOutput()
    try output.start(
        .init(entry: a, source: try ByteSource(complete: flac(value: 0.25, frames: 44_100))),
        at: 0.5, following: nil, play: true)
    try await untilScheduled(output)
    let early = try render(output, frames: 8192)
    let position = try #require(output.poll().position)
    #expect(abs(position - (0.5 + 8192 / rate)) < 0.01)
    let rest = try render(output, frames: 22_050)
    #expect((early + rest).filter { $0 != 0 }.count == 22_050)
}

@Test func aSourceStillDownloadingDecodesEveryFrame() async throws {
    let url = try flac(value: 0.25, frames: 100_000)
    let bytes = try Data(contentsOf: url)
    let partial = FileManager.default.temporaryDirectory.appending(path: "\(UUID()).part")
    let source = try ByteSource(writingTo: partial)
    let writer = try FileHandle(forWritingTo: partial)
    source.begin(length: Int64(bytes.count))
    let feeding = Task.detached {
        for offset in stride(from: 0, to: bytes.count, by: 4096) {
            let piece = bytes[offset..<min(offset + 4096, bytes.count)]
            try writer.write(contentsOf: piece)
            source.wrote(piece.count, at: Int64(offset))
            try await Task.sleep(for: .milliseconds(1))
        }
        source.finish(nil)
    }
    let decoder = try TrackDecoder(source: source)
    let buffer = AVAudioPCMBuffer(pcmFormat: decoder.format, frameCapacity: 8192)!
    var frames = 0
    while try decoder.read(into: buffer) { frames += Int(buffer.frameLength) }
    try await feeding.value
    #expect(decoder.length == 100_000)
    #expect(frames == 100_000)
}
