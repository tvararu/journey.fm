import Foundation

final class StreamDownload: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    static let ahead: Int64 = 512 * 1024

    let source: ByteSource
    let partial: URL
    let destination: URL
    let writer: FileHandle
    let session: URLSession
    let request: URLRequest
    let done: @Sendable (Bool) -> Void
    let lock = NSLock()
    var task: URLSessionDataTask?
    var cursor: Int64 = 0
    var stopped = false

    init(
        request: URLRequest, partial: URL, destination: URL, session: URLSession,
        done: @escaping @Sendable (Bool) -> Void
    ) throws {
        self.partial = partial
        self.destination = destination
        self.session = session
        self.request = request
        self.done = done
        source = try ByteSource(writingTo: partial)
        writer = try FileHandle(forWritingTo: partial)
        super.init()
        source.wants = { [weak self] offset in self?.want(offset) }
        lock.withLock { fetch(nil) }
    }

    func cancel() {
        let task = lock.withLock {
            stopped = true
            return self.task
        }
        if let task {
            task.cancel()
        } else {
            complete(SourceError.cancelled)
        }
    }

    func want(_ offset: Int64) {
        lock.withLock {
            guard !stopped, task != nil, offset < cursor || offset > cursor + Self.ahead else {
                return
            }
            Log.audio.info(
                "Jumping to byte \(offset) of \(self.destination.lastPathComponent, privacy: .public)"
            )
            fetch(offset..<(source.condition.withLock { source.length } ?? .max))
        }
    }

    func fetch(_ range: Range<Int64>?) {
        task?.cancel()
        var request = request
        if let range {
            let end = range.upperBound == .max ? "" : String(range.upperBound - 1)
            request.setValue("bytes=\(range.lowerBound)-\(end)", forHTTPHeaderField: "Range")
        }
        let task = session.dataTask(with: request)
        task.delegate = self
        self.task = task
        cursor = range?.lowerBound ?? 0
        task.resume()
    }

    func current(_ task: URLSessionTask) -> Bool {
        lock.withLock { task === self.task }
    }

    func urlSession(
        _ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse
    ) async -> URLSession.ResponseDisposition {
        guard current(dataTask) else { return .cancel }
        do {
            try JellyfinClient.check(response)
        } catch {
            fail(error)
            return .cancel
        }
        let http = response as? HTTPURLResponse
        if http?.statusCode == 206 {
            let total = http?.value(forHTTPHeaderField: "Content-Range")?.split(separator: "/").last
            source.begin(length: total.flatMap { Int64($0) })
        } else {
            lock.withLock { if task === dataTask { cursor = 0 } }
            source.begin(
                length: response.expectedContentLength >= 0 ? response.expectedContentLength : nil)
        }
        return .allow
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.withLock {
            guard dataTask === task else { return }
            do {
                try writer.seek(toOffset: UInt64(cursor))
                try writer.write(contentsOf: data)
                source.wrote(data.count, at: cursor)
                cursor += Int64(data.count)
            } catch {
                dataTask.cancel()
                stopped = true
            }
        }
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?
    ) {
        let next: Next = lock.withLock {
            guard task === self.task else { return .ignore }
            self.task = nil
            if let error { return .finish(error) }
            if stopped { return .finish(SourceError.cancelled) }
            if let gap = source.missing() {
                fetch(gap)
                return .ignore
            }
            return .finish(nil)
        }
        if case .finish(let error) = next { complete(error) }
    }

    enum Next {
        case ignore
        case finish((any Error)?)
    }

    func fail(_ error: any Error) {
        lock.withLock { stopped = true }
        source.finish(error)
    }

    func complete(_ error: (any Error)?) {
        try? writer.close()
        source.finish(error)
        let complete = source.isComplete
        if complete {
            try? FileManager.default.removeItem(at: destination)
            try? FileManager.default.moveItem(at: partial, to: destination)
        } else {
            try? FileManager.default.removeItem(at: partial)
        }
        done(complete)
    }
}
