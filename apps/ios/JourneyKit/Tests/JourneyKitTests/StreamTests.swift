import Foundation
import Testing

@testable import JourneyKit

@Test func aReadFarAheadFetchesThatRangeAtOnceAndTheGapAfterwards() async throws {
    let size = 4 * 1024 * 1024
    let stub = Stub(body: pattern(size))
    stub.chunk = 32 * 1024
    stub.delay = 0.05
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let cache = AudioCache(
        directory: directory, client: stub.client, configuration: stub.configuration)
    let track = track("t1", album: "x")
    let source = try cache.source(for: track)
    let token = ReadToken()
    #expect(try source.size(token) == Int64(size))

    let offset = 3_000_000
    let started = Date.now
    var buffer = [UInt8](repeating: 0, count: 4096)
    let count = try buffer.withUnsafeMutableBytes {
        try source.read(at: Int64(offset), count: 4096, into: $0.baseAddress!, token)
    }
    #expect(Date.now.timeIntervalSince(started) < 1)
    #expect(Data(buffer.prefix(count)) == pattern(size).subdata(in: offset..<(offset + count)))
    #expect(stub.requestedRanges.contains { $0?.hasPrefix("bytes=\(offset)-") == true })

    #expect(await eventually(20) { cache.isOnPhone(track) })
    #expect(try Data(contentsOf: directory.appending(path: "t1.flac")) == pattern(size))
    let gaps = stub.requestedRanges.filter { $0?.hasSuffix("-\(offset - 1)") == true }
    #expect(gaps.count == 1)
}
