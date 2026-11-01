import Foundation

@testable import JourneyKit

final class Stub: @unchecked Sendable {
    static let registry = NSLock()
    nonisolated(unsafe) static var stubs: [String: Stub] = [:]

    let host = "\(UUID().uuidString.lowercased()).test"
    let lock = NSLock()
    var body: Data
    var status = 200
    var chunk = Int.max
    var delay: TimeInterval = 0
    var ranges: [String?] = []
    var active = 0
    var mostActive = 0

    init(body: Data) {
        self.body = body
        Self.registry.withLock { Self.stubs[host] = self }
    }

    var client: JellyfinClient {
        JellyfinClient(
            session: Session(
                server: URL(string: "https://\(host)")!, userId: "u", token: "t", deviceId: "d",
                deviceName: "test"))
    }

    var configuration: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return configuration
    }

    var requestedRanges: [String?] { lock.withLock { ranges } }

    static func find(_ request: URLRequest) -> Stub? {
        registry.withLock { request.url?.host().flatMap { stubs[$0] } }
    }
}

final class StubProtocol: URLProtocol, @unchecked Sendable {
    var timer: Timer?
    var remaining = Data()
    var stub: Stub?
    var ended = false

    func end() {
        guard !ended, let stub else { return }
        ended = true
        stub.lock.withLock { stub.active -= 1 }
    }

    override class func canInit(with request: URLRequest) -> Bool { Stub.find(request) != nil }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let stub = Stub.find(request), let url = request.url else { return }
        let range = request.value(forHTTPHeaderField: "Range")
        self.stub = stub
        let (body, status, chunk, delay) = stub.lock.withLock {
            stub.active += 1
            stub.mostActive = max(stub.mostActive, stub.active)
            stub.ranges.append(range)
            return (stub.body, stub.status, stub.chunk, stub.delay)
        }
        var headers = ["Content-Length": String(body.count), "Accept-Ranges": "bytes"]
        var code = status
        remaining = body
        if status == 200, let range, let spec = range.split(separator: "=").last {
            let bounds = spec.split(separator: "-", omittingEmptySubsequences: false)
            let start = Int(bounds[0]) ?? 0
            let end = bounds.count > 1 && !bounds[1].isEmpty ? Int(bounds[1])! : body.count - 1
            remaining = body.subdata(in: start..<(end + 1))
            code = 206
            headers["Content-Length"] = String(remaining.count)
            headers["Content-Range"] = "bytes \(start)-\(end)/\(body.count)"
        }
        client?.urlProtocol(
            self,
            didReceive: HTTPURLResponse(
                url: url, statusCode: code, httpVersion: "HTTP/1.1", headerFields: headers)!,
            cacheStoragePolicy: .notAllowed)
        guard delay > 0 else {
            client?.urlProtocol(self, didLoad: remaining)
            end()
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        let timer = Timer(timeInterval: delay, repeats: true) { [weak self] timer in
            guard let self else { return timer.invalidate() }
            let piece = self.remaining.prefix(chunk)
            self.remaining = self.remaining.dropFirst(piece.count)
            self.client?.urlProtocol(self, didLoad: Data(piece))
            if self.remaining.isEmpty {
                timer.invalidate()
                self.end()
                self.client?.urlProtocolDidFinishLoading(self)
            }
        }
        self.timer = timer
        RunLoop.current.add(timer, forMode: .common)
    }

    override func stopLoading() {
        timer?.invalidate()
        timer = nil
        end()
    }
}

func pattern(_ count: Int) -> Data {
    Data((0..<count).map { UInt8(truncatingIfNeeded: $0 &* 7 &+ $0 >> 8) })
}

func eventually(
    _ seconds: Double = 5, _ condition: @MainActor () -> Bool
) async -> Bool {
    let deadline = Date.now.addingTimeInterval(seconds)
    while Date.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return await condition()
}
