import Foundation
import Observation

public final class SavedFiles: @unchecked Sendable {
    public let directory: URL
    let library: Library
    let lock = NSLock()
    var adopted: (@Sendable (String) -> Void)?

    init(directory: URL, library: Library) {
        self.directory = directory
        self.library = library
    }

    public func file(for track: Track) -> URL? {
        let url = directory.appending(path: Self.name(track))
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) ? url : nil
    }

    func adopt(_ track: Track, from file: URL) -> Bool {
        guard library.isWaiting(trackId: track.id),
            store(file, as: Self.name(track), trackId: track.id)
        else { return false }
        lock.withLock { adopted }?(track.id)
        return true
    }

    func store(_ file: URL, as name: String, trackId: String) -> Bool {
        lock.withLock {
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
    }

    func unpack(_ archive: URL, _ batch: [(id: String, file: String)]) -> Set<String> {
        let names = Dictionary(batch.map { ($0.id, $0.file) }) { first, _ in first }
        var saved = Set<String>()
        do {
            try Tar.unpack(archive, into: FileManager.default.temporaryDirectory) { id, file in
                guard let name = names[id], library.isWaiting(trackId: id),
                    store(file, as: name, trackId: id)
                else { return }
                saved.insert(id)
            }
        } catch {
            Log.audio.error("Unpacking an album failed: \(error, privacy: .public)")
        }
        return saved
    }

    func sweep() throws -> Set<String> {
        try lock.withLock {
            let manager = FileManager.default
            let saved = try library.savedFiles()
            let present = Set(
                (try? manager.contentsOfDirectory(atPath: directory.path(percentEncoded: false)))
                    ?? [])
            for name in present.subtracting(saved) {
                try? manager.removeItem(at: directory.appending(path: name))
            }
            return saved.subtracting(present)
        }
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
    case progress([String], Double)
    case done([String], task: Int, saved: Set<String>, cancelled: Bool, resume: Data?)
    case finishedEvents
}

final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let files: SavedFiles
    let lock = NSLock()
    var sink: (@Sendable (DownloadEvent) -> Void)?
    var stored: [Int: Set<String>] = [:]

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
        guard let batch = Downloads.parse(downloadTask), totalBytesExpectedToWrite > 0 else {
            return
        }
        send(
            .progress(
                batch.map(\.id), Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
    }

    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let batch = Downloads.parse(downloadTask) else { return }
        guard let response = downloadTask.response, (try? JellyfinClient.check(response)) != nil
        else {
            Log.audio.error(
                "Download of \(batch.map(\.id), privacy: .public) failed: \(String(describing: downloadTask.response), privacy: .public)"
            )
            return
        }
        let saved = files.unpack(location, batch)
        lock.withLock { stored[downloadTask.taskIdentifier] = saved }
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?
    ) {
        guard let batch = Downloads.parse(task) else { return }
        let saved = lock.withLock { stored.removeValue(forKey: task.taskIdentifier) } ?? []
        let cancelled = (error as? URLError)?.code == .cancelled
        if let error, !cancelled {
            Log.audio.error(
                "Download of \(batch.map(\.id), privacy: .public) failed: \(error, privacy: .public)"
            )
        }
        let resume = (error as NSError?)?.userInfo[NSURLSessionDownloadTaskResumeData] as? Data
        send(
            .done(
                batch.map(\.id), task: task.taskIdentifier, saved: saved, cancelled: cancelled,
                resume: resume))
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
    @ObservationIgnored let window: Int
    @ObservationIgnored var tasks: [String: URLSessionDownloadTask] = [:]
    @ObservationIgnored var watching: Task<Void, Never>?
    @ObservationIgnored var resuming: Task<Void, Never>?
    @ObservationIgnored var again = false
    @ObservationIgnored var failedAt: [String: Date] = [:]
    @ObservationIgnored var resumeData: [String: Data] = [:]

    public init(
        library: Library, client: JellyfinClient, directory: URL,
        configuration: URLSessionConfiguration, window: Int = 4
    ) {
        self.window = window
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
        files.lock.withLock {
            files.adopted = { [weak self] id in
                Task { @MainActor in
                    self?.drop(id)
                }
            }
        }
        watching = Task { [weak self, library] in
            do {
                for try await summary in library.observeDownloads() {
                    guard let self else { return }
                    self.summary = summary
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

    public func resume(retry: Bool = true) async {
        if retry { failedAt = [:] }
        if let resuming {
            again = true
            return await resuming.value
        }
        let task = Task {
            repeat {
                again = false
                await reconcile()
            } while again
            resuming = nil
        }
        resuming = task
        await task.value
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
            let lost = try files.sweep().map(Self.trackId)
            if !lost.isEmpty { try await library.markUnsaved(trackIds: lost) }

            var live: [String: URLSessionDownloadTask] = [:]
            for case let task as URLSessionDownloadTask in await session.allTasks {
                guard let batch = Self.parse(task), task.state != .completed else { continue }
                if batch.contains(where: { live[$0.id] != nil }) {
                    task.cancel()
                    continue
                }
                for item in batch { live[item.id] = task }
            }
            let pending = try await library.pendingDownloads()
            var running = [false: 0, true: 0]
            var kept = Set<Int>()
            tasks = [:]
            for item in pending {
                guard let task = live[item.trackId] else { continue }
                if !kept.contains(task.taskIdentifier) {
                    guard running[item.wifiOnly, default: 0] < window else { continue }
                    running[item.wifiOnly, default: 0] += 1
                    kept.insert(task.taskIdentifier)
                }
                tasks[item.trackId] = task
            }
            for task in live.values where !kept.contains(task.taskIdentifier) { task.cancel() }
            guard !paused else { return }
            let recent = Date.now.addingTimeInterval(-Self.backoff)
            let waiting = pending.filter {
                tasks[$0.trackId] == nil && failedAt[$0.trackId].map({ $0 < recent }) ?? true
            }
            for batch in Self.batches(waiting) {
                let wifiOnly = batch[0].wifiOnly
                guard running[wifiOnly, default: 0] < window else { continue }
                running[wifiOnly, default: 0] += 1
                var request = client.request(client.archiveURL(trackIds: batch.map(\.trackId)))
                request.allowsExpensiveNetworkAccess = !wifiOnly
                request.allowsConstrainedNetworkAccess = !wifiOnly
                let task =
                    resumeData.removeValue(forKey: batch.map(\.trackId).joined(separator: ","))
                    .map { session.downloadTask(withResumeData: $0) }
                    ?? session.downloadTask(with: request)
                task.taskDescription = batch.map { "\($0.trackId)/\($0.file)" }.joined(
                    separator: ",")
                task.priority =
                    wifiOnly ? URLSessionTask.lowPriority : URLSessionTask.defaultPriority
                for item in batch { tasks[item.trackId] = task }
                task.resume()
            }
        } catch {
            Log.audio.error("Resuming downloads failed: \(error, privacy: .public)")
        }
    }

    func handle(_ event: DownloadEvent) {
        switch event {
        case .progress(let ids, let fraction):
            for id in ids
            where tasks[id] != nil && (abs((progress[id] ?? 0) - fraction) >= 0.01 || fraction == 1)
            {
                progress[id] = fraction
            }
        case .done(let ids, let task, let saved, let cancelled, let partial):
            for id in ids {
                if tasks[id].map({ $0.taskIdentifier == task }) ?? true {
                    tasks[id] = nil
                    progress[id] = nil
                }
                if !cancelled && !saved.contains(id) && partial == nil { failedAt[id] = .now }
            }
            if let partial { resumeData[ids.joined(separator: ",")] = partial }
            Task { await resume(retry: false) }
        case .finishedEvents:
            Task {
                await resume()
                finishedEvents?()
                finishedEvents = nil
            }
        }
    }

    func delete(_ names: [String]) {
        for name in names {
            try? FileManager.default.removeItem(at: files.directory.appending(path: name))
            drop(Self.trackId(name))
        }
    }

    func drop(_ id: String) {
        progress[id] = nil
        guard let task = tasks.removeValue(forKey: id),
            !tasks.values.contains(where: { $0 === task })
        else { return }
        task.cancel()
    }

    static let backoff: TimeInterval = 5 * 60
    nonisolated static let batch = 50

    nonisolated static func trackId(_ file: String) -> String {
        String(file.prefix { $0 != "." })
    }

    nonisolated static func parse(_ task: URLSessionTask) -> [(id: String, file: String)]? {
        let batch = (task.taskDescription ?? "").split(separator: ",").compactMap {
            pair -> (id: String, file: String)? in
            let parts = pair.split(separator: "/")
            return parts.count == 2 ? (String(parts[0]), String(parts[1])) : nil
        }
        return batch.isEmpty ? nil : batch
    }

    nonisolated static func batches(_ items: [PendingDownload]) -> [[PendingDownload]] {
        var batches: [[PendingDownload]] = []
        for item in items {
            if let last = batches.last, last.count < batch, last[0].album == item.album,
                last[0].wifiOnly == item.wifiOnly
            {
                batches[batches.count - 1].append(item)
            } else {
                batches.append([item])
            }
        }
        return batches
    }
}

public enum DownloadState: Sendable, Equatable {
    case waiting
    case downloading(Double)
    case saved
}
