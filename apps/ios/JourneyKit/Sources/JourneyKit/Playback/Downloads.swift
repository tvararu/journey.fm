import Foundation
import Observation

public final class SavedFiles: Sendable {
    public let directory: URL
    let library: Library

    init(directory: URL, library: Library) {
        self.directory = directory
        self.library = library
    }

    public func file(for track: Track) -> URL? {
        let url = directory.appending(path: Self.name(track))
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) ? url : nil
    }

    func adopt(_ track: Track, from file: URL) -> Bool {
        library.isWaiting(trackId: track.id) && store(file, as: Self.name(track), trackId: track.id)
    }

    func store(_ file: URL, as name: String, trackId: String) -> Bool {
        let manager = FileManager.default
        let destination = directory.appending(path: name)
        do {
            try prepare()
            try? manager.removeItem(at: destination)
            try manager.moveItem(at: file, to: destination)
            let size = try destination.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            if try library.markSaved(trackId: trackId, bytes: Int64(size)) { return true }
            try? manager.removeItem(at: destination)
        } catch {
            Log.audio.error(
                "Saving \(trackId, privacy: .public) failed: \(error, privacy: .public)")
        }
        return false
    }

    func prepare() throws {
        var directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
    }

    static func name(_ track: Track) -> String { "\(track.id).\(track.container ?? "flac")" }
}

enum DownloadEvent: Sendable {
    case progress(String, Double)
    case done(String, saved: Bool)
    case finishedEvents
}

final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let files: SavedFiles
    let lock = NSLock()
    var sink: (@Sendable (DownloadEvent) -> Void)?
    var stored = Set<Int>()

    init(files: SavedFiles) {
        self.files = files
    }

    func send(_ event: DownloadEvent) {
        lock.withLock { sink }?(event)
    }

    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData _: Int64,
        totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
    ) {
        guard let (id, _) = Downloads.parse(downloadTask), totalBytesExpectedToWrite > 0 else {
            return
        }
        send(.progress(id, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
    }

    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let (id, name) = Downloads.parse(downloadTask) else { return }
        guard let response = downloadTask.response, (try? JellyfinClient.check(response)) != nil
        else {
            Log.audio.error(
                "Download of \(id, privacy: .public) failed: \(String(describing: downloadTask.response), privacy: .public)"
            )
            return
        }
        if files.store(location, as: name, trackId: id) {
            lock.withLock { _ = stored.insert(downloadTask.taskIdentifier) }
        }
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?
    ) {
        guard let (id, _) = Downloads.parse(task) else { return }
        let saved = lock.withLock { stored.remove(task.taskIdentifier) != nil }
        if let error, (error as? URLError)?.code != .cancelled {
            Log.audio.error(
                "Download of \(id, privacy: .public) failed: \(error, privacy: .public)")
        }
        send(.done(id, saved: saved))
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        send(.finishedEvents)
    }
}

@MainActor
@Observable
public final class Downloads {
    public private(set) var summary = DownloadSummary()
    public private(set) var progress: [String: Double] = [:]
    public var paused = false

    @ObservationIgnored public let files: SavedFiles
    @ObservationIgnored public var finishedEvents: (() -> Void)?
    @ObservationIgnored public var changed: (DownloadSummary) -> Void = { _ in }
    @ObservationIgnored let library: Library
    @ObservationIgnored let client: JellyfinClient
    @ObservationIgnored let session: URLSession
    @ObservationIgnored var tasks: [String: URLSessionDownloadTask] = [:]
    @ObservationIgnored var watching: Task<Void, Never>?
    @ObservationIgnored var resuming: Task<Void, Never>?
    @ObservationIgnored var again = false

    public init(
        library: Library, client: JellyfinClient, directory: URL,
        configuration: URLSessionConfiguration
    ) {
        self.library = library
        self.client = client
        let files = SavedFiles(directory: directory, library: library)
        self.files = files
        let delegate = DownloadDelegate(files: files)
        session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        delegate.lock.withLock {
            delegate.sink = { [weak self] event in
                Task { @MainActor in self?.handle(event) }
            }
        }
        watching = Task { [weak self, library] in
            do {
                for try await summary in library.observeDownloads() {
                    guard let self else { return }
                    self.summary = summary
                    self.dropFinished()
                    self.changed(summary)
                }
            } catch {
                Log.audio.error("Watching downloads failed: \(error, privacy: .public)")
            }
        }
    }

    public func state(of trackId: String) -> DownloadState? {
        if summary.saved.contains(trackId) { return .saved }
        guard summary.waiting.contains(trackId) else { return nil }
        return progress[trackId].map(DownloadState.downloading) ?? .waiting
    }

    public func albumProgress(_ trackIds: [String]) -> Double? {
        let wanted = trackIds.filter { summary.saved.contains($0) || summary.waiting.contains($0) }
        guard !wanted.isEmpty, wanted.contains(where: { !summary.saved.contains($0) }) else {
            return nil
        }
        let done = wanted.reduce(0.0) {
            $0 + (summary.saved.contains($1) ? 1 : progress[$1] ?? 0)
        }
        return done / Double(wanted.count)
    }

    public func save(trackIds: [String]) async {
        await run { try await self.library.want(trackIds: trackIds) }
    }

    public func save(albumIds: [String]) async {
        await run { try await self.library.want(albumIds: albumIds) }
    }

    public func saveEverything(createdAfter: String? = nil) async {
        await run { try await self.library.wantEverything(createdAfter: createdAfter) }
    }

    public func remove(trackIds: [String]? = nil, albumIds: [String]? = nil) async {
        await run {
            let files = try await self.library.removeDownloads(
                trackIds: trackIds, albumIds: albumIds)
            self.delete(files)
        }
    }

    public func removeAll() async {
        await remove()
    }

    public func resume() async {
        guard resuming == nil else {
            again = true
            while let resuming { await resuming.value }
            return
        }
        repeat {
            again = false
            let task = Task { await reconcile() }
            resuming = task
            await task.value
        } while again
        resuming = nil
    }

    public func invalidate() {
        watching?.cancel()
        session.invalidateAndCancel()
        tasks = [:]
        progress = [:]
    }

    func run(_ change: @escaping () async throws -> Void) async {
        do {
            try await change()
        } catch {
            Log.audio.error("Changing downloads failed: \(error, privacy: .public)")
        }
        await resume()
    }

    func reconcile() async {
        do {
            try files.prepare()
            let saved = try await library.savedFiles()
            let present = Set(
                (try? FileManager.default.contentsOfDirectory(
                    atPath: files.directory.path(percentEncoded: false)))
                    ?? [])
            delete(Array(present.subtracting(saved)))
            let lost = saved.subtracting(present).map(Self.trackId)
            if !lost.isEmpty { try await library.markUnsaved(trackIds: lost) }

            let pending = try await library.pendingDownloads()
            let wanted = Set(pending.map(\.trackId))
            tasks = [:]
            for case let task as URLSessionDownloadTask in await session.allTasks {
                guard let (id, _) = Self.parse(task), task.state != .completed else { continue }
                if wanted.contains(id) && tasks[id] == nil {
                    tasks[id] = task
                } else {
                    task.cancel()
                }
            }
            guard !paused else { return }
            for item in pending where tasks[item.trackId] == nil {
                var request = client.request(client.audioURL(trackId: item.trackId))
                request.allowsExpensiveNetworkAccess = !item.wifiOnly
                request.allowsConstrainedNetworkAccess = !item.wifiOnly
                let task = session.downloadTask(with: request)
                task.taskDescription = "\(item.trackId)/\(item.file)"
                task.priority =
                    item.wifiOnly ? URLSessionTask.lowPriority : URLSessionTask.defaultPriority
                tasks[item.trackId] = task
                task.resume()
            }
        } catch {
            Log.audio.error("Resuming downloads failed: \(error, privacy: .public)")
        }
    }

    func handle(_ event: DownloadEvent) {
        switch event {
        case .progress(let id, let fraction):
            guard tasks[id] != nil, abs((progress[id] ?? 0) - fraction) >= 0.01 || fraction == 1
            else { return }
            progress[id] = fraction
        case .done(let id, _):
            tasks[id] = nil
            progress[id] = nil
        case .finishedEvents:
            finishedEvents?()
            finishedEvents = nil
        }
    }

    func dropFinished() {
        for (id, task) in tasks where summary.saved.contains(id) {
            task.cancel()
            tasks[id] = nil
            progress[id] = nil
        }
    }

    func delete(_ names: [String]) {
        for name in names {
            try? FileManager.default.removeItem(at: files.directory.appending(path: name))
            let id = Self.trackId(name)
            tasks.removeValue(forKey: id)?.cancel()
            progress[id] = nil
        }
    }

    nonisolated static func trackId(_ file: String) -> String {
        String(file.prefix { $0 != "." })
    }

    nonisolated static func parse(_ task: URLSessionTask) -> (String, String)? {
        guard let parts = task.taskDescription?.split(separator: "/"), parts.count == 2 else {
            return nil
        }
        return (String(parts[0]), String(parts[1]))
    }
}

public enum DownloadState: Sendable, Equatable {
    case waiting
    case downloading(Double)
    case saved
}
