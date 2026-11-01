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
    var written: Int64 = 0
    var length: Int64?
    var finished = false
    var failure: (any Error)?

    init(writingTo file: URL) throws {
        FileManager.default.createFile(atPath: file.path(percentEncoded: false), contents: nil)
        reader = try FileHandle(forReadingFrom: file)
    }

    public init(complete file: URL) throws {
        reader = try FileHandle(forReadingFrom: file)
        written = Int64(try reader.seekToEnd())
        length = written
        finished = true
    }

    var isComplete: Bool {
        condition.withLock { finished && failure == nil && written == length }
    }

    func begin(length: Int64?) {
        condition.withLock {
            self.length = length
            condition.broadcast()
        }
    }

    func wrote(_ count: Int) {
        condition.withLock {
            written += Int64(count)
            condition.broadcast()
        }
    }

    func finish(_ error: (any Error)?) {
        condition.withLock {
            guard !finished else { return }
            if let error {
                failure = error
            } else if let length, written != length {
                failure = SourceError.truncated
            } else {
                length = written
            }
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
            return length ?? written
        }
    }

    public func read(
        at offset: Int64, count: Int, into buffer: UnsafeMutableRawPointer, _ token: ReadToken
    ) throws -> Int {
        try condition.withLock {
            while written < offset + Int64(count) && !finished && !token.isCancelled {
                condition.wait()
            }
            if token.isCancelled { throw SourceError.cancelled }
            if written < offset + Int64(count), let failure { throw failure }
            let end = min(written, offset + Int64(count))
            guard end > offset else { return 0 }
            try reader.seek(toOffset: UInt64(offset))
            let data = try reader.read(upToCount: Int(end - offset)) ?? Data()
            data.copyBytes(to: buffer.assumingMemoryBound(to: UInt8.self), count: data.count)
            return data.count
        }
    }
}
