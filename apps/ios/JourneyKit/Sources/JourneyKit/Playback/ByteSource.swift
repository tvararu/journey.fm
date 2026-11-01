import Foundation

public enum SourceError: Error {
    case cancelled
    case truncated
}

public final class ReadToken: @unchecked Sendable {
    let lock = NSLock()
    var flag = false

    public init() {}

    public var isCancelled: Bool { lock.withLock { flag } }

    func cancel() { lock.withLock { flag = true } }
}

public final class ByteSource: @unchecked Sendable {
    let condition = NSCondition()
    let reader: FileHandle
    var filled: [Range<Int64>] = []
    var length: Int64?
    var finished = false
    var failure: (any Error)?
    var wants: (@Sendable (Int64) -> Void)?

    init(writingTo file: URL) throws {
        FileManager.default.createFile(atPath: file.path(percentEncoded: false), contents: nil)
        reader = try FileHandle(forReadingFrom: file)
    }

    public init(complete file: URL) throws {
        reader = try FileHandle(forReadingFrom: file)
        let size = Int64(try reader.seekToEnd())
        filled = [0..<size]
        length = size
        finished = true
    }

    var isComplete: Bool {
        condition.withLock { finished && failure == nil && gap() == nil }
    }

    func begin(length: Int64?) {
        condition.withLock {
            if self.length == nil { self.length = length }
            condition.broadcast()
        }
    }

    func wrote(_ count: Int, at offset: Int64) {
        condition.withLock {
            var range = offset..<(offset + Int64(count))
            filled.removeAll { other in
                guard
                    other.overlaps(range) || other.upperBound == range.lowerBound
                        || other.lowerBound == range.upperBound
                else { return false }
                range =
                    min(
                        other.lowerBound, range.lowerBound)..<max(
                        other.upperBound, range.upperBound)
                return true
            }
            filled.insert(
                range, at: filled.firstIndex { $0.lowerBound > range.lowerBound } ?? filled.endIndex
            )
            condition.broadcast()
        }
    }

    func gap() -> Range<Int64>? {
        guard let length else { return nil }
        var start: Int64 = 0
        for range in filled {
            if range.lowerBound > start { return start..<range.lowerBound }
            start = max(start, range.upperBound)
        }
        return start < length ? start..<length : nil
    }

    func missing() -> Range<Int64>? {
        condition.withLock { gap() }
    }

    func finish(_ error: (any Error)?) {
        condition.withLock {
            guard !finished else { return }
            if let error {
                failure = error
            } else if length == nil {
                length = filled.last?.upperBound ?? 0
            }
            if failure == nil && gap() != nil { failure = SourceError.truncated }
            finished = true
            condition.broadcast()
        }
    }

    public func cancel(_ token: ReadToken) {
        token.cancel()
        condition.withLock { condition.broadcast() }
    }

    public func size(_ token: ReadToken) throws -> Int64 {
        try condition.withLock {
            while length == nil && !finished && !token.isCancelled { condition.wait() }
            if token.isCancelled { throw SourceError.cancelled }
            if let failure { throw failure }
            return length ?? 0
        }
    }

    public func read(
        at offset: Int64, count: Int, into buffer: UnsafeMutableRawPointer, _ token: ReadToken
    ) throws -> Int {
        condition.lock()
        defer { condition.unlock() }
        var asked = false
        while true {
            if token.isCancelled { throw SourceError.cancelled }
            let end = min(offset + Int64(count), length ?? .max)
            guard end > offset else { return 0 }
            let available = filled.first { $0.contains(offset) }.map { min($0.upperBound, end) }
            if let available, available == end || finished {
                try reader.seek(toOffset: UInt64(offset))
                let data = try reader.read(upToCount: Int(available - offset)) ?? Data()
                data.copyBytes(to: buffer.assumingMemoryBound(to: UInt8.self), count: data.count)
                return data.count
            }
            if finished { throw failure ?? SourceError.truncated }
            if available == nil && !asked, let wants {
                asked = true
                condition.unlock()
                wants(offset)
                condition.lock()
                continue
            }
            condition.wait()
        }
    }
}
