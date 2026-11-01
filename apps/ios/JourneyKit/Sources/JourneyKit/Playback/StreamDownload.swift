import Foundation

final class StreamDownload: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    let source: ByteSource
    let partial: URL
    let destination: URL
    let writer: FileHandle
    var task: URLSessionDataTask?
    let done: @Sendable (Bool) -> Void

    init(
        request: URLRequest, partial: URL, destination: URL, session: URLSession,
        done: @escaping @Sendable (Bool) -> Void
    ) throws {
        self.partial = partial
        self.destination = destination
        self.done = done
        source = try ByteSource(writingTo: partial)
        writer = try FileHandle(forWritingTo: partial)
        super.init()
        let task = session.dataTask(with: request)
        task.delegate = self
        self.task = task
        task.resume()
    }

    func cancel() {
        task?.cancel()
    }

    func urlSession(
        _ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse
    ) async -> URLSession.ResponseDisposition {
        do {
            try JellyfinClient.check(response)
        } catch {
            source.finish(error)
            return .cancel
        }
        source.begin(
            length: response.expectedContentLength >= 0 ? response.expectedContentLength : nil)
        return .allow
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        do {
            try writer.write(contentsOf: data)
            source.wrote(data.count)
        } catch {
            dataTask.cancel()
            source.finish(error)
        }
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?
    ) {
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
