import Foundation
import Observation

public final class SavedFiles: @unchecked Sendable {
    public let directory: URL
    public let incoming: URL
    let library: Library
    let lock = NSLock()
    var adopted: (@Sendable (String) -> Void)?

    init(directory: URL, library: Library) {
        self.directory = directory
        incoming = directory.appendingPathExtension("incoming")
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

    func accept(_ file: URL) -> Bool {
        do {
            try prepare()
            try FileManager.default.moveItem(
                at: file, to: incoming.appending(path: UUID().uuidString + ".tar"))
            return true
        } catch {
            Log.audio.error("Keeping an archive failed: \(error, privacy: .public)")
            return false
        }
    }

    func archives() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: incoming, includingPropertiesForKeys: nil))?
            .sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []
    }

    func held() -> Set<String> {
        Set(archives().flatMap { (try? Tar.names($0)) ?? [] })
    }

    func unpackIncoming() -> Bool {
        let archives = archives()
        for archive in archives {
            unpack(archive)
            try? FileManager.default.removeItem(at: archive)
        }
        return !archives.isEmpty
    }

    func unpack(_ archive: URL) {
        let wanted = { [library] (id: String) in library.waitingFile(trackId: id) != nil }
        do {
            try Tar.unpack(archive, into: FileManager.default.temporaryDirectory, wanted: wanted) {
                id, file in
                if let name = library.waitingFile(trackId: id) {
                    _ = store(file, as: name, trackId: id)
                }
            }
        } catch {
            Log.audio.error("Unpacking an album failed: \(error, privacy: .public)")
        }
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
        for folder in [directory, incoming] {
            var folder = folder
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try folder.setResourceValues(values)
        }
    }

    static func name(_ track: Track) -> String { "\(track.id).\(track.container ?? "flac")" }
}

enum DownloadEvent: Sendable {
    case progress([String], Double)
    case done(
        String, url: URL?, task: Int, delivered: Bool, cancelled: Bool, resume: Data?)
    case finishedEvents
}

final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let files: SavedFiles
    let lock = NSLock()
    var sink: (@Sendable (DownloadEvent) -> Void)?
    var accepted: Set<Int> = []

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
        if files.accept(location) {
            lock.withLock { _ = accepted.insert(downloadTask.taskIdentifier) }
        }
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?
    ) {
        guard let batch = Downloads.parse(task) else { return }
        let delivered = lock.withLock { accepted.remove(task.taskIdentifier) != nil }
        let cancelled = (error as? URLError)?.code == .cancelled
        if let error, !cancelled {
            Log.audio.error(
                "Download of \(batch.map(\.id), privacy: .public) failed: \(error, privacy: .public)"
            )
        }
        let resume = (error as NSError?)?.userInfo[NSURLSessionDownloadTaskResumeData] as? Data
        send(
            .done(
                task.taskDescription ?? "", url: task.originalRequest?.url,
                task: task.taskIdentifier, delivered: delivered, cancelled: cancelled,
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
    @ObservationIgnored var client: JellyfinClient
    @ObservationIgnored let session: URLSession
    @ObservationIgnored let window: Int
    @ObservationIgnored var tasks: [String: URLSessionDownloadTask] = [:]
    @ObservationIgnored var watching: Task<Void, Never>?
    @ObservationIgnored var resuming: Task<Void, Never>?
    @ObservationIgnored var again = false
    @ObservationIgnored var invalidated = false
    @ObservationIgnored var failedAt: [String: Date] = [:]
    @ObservationIgnored var delivered: Set<String> = []
    @ObservationIgnored var unpacking: Task<Void, Never>?

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
        invalidated = true
        watching?.cancel()
        session.invalidateAndCancel()
        tasks = [:]
        progress = [:]
    }

    public func move(to client: JellyfinClient) {
        self.client = client
        Task { await resume() }
    }

    func run(_ change: @escaping () async throws -> Void) async {
        do {
            try await change()
        } catch {
            Log.audio.error("Changing downloads failed: \(error, privacy: .public)")
        }
        await resume()
    }

    func unpack() {
        guard unpacking == nil else { return }
        unpacking = Task {
            let found = await Task.detached(priority: .utility) { [files] in
                files.unpackIncoming()
            }.value
            unpacking = nil
            if found { await resume(retry: false) }
        }
    }

    func reconcile() async {
        guard !invalidated else { return }
        do {
            try files.prepare()
            unpack()
            let lost = try files.sweep().map(Self.trackId)
            if !lost.isEmpty { try await library.markUnsaved(trackIds: lost) }

            var live: [String: URLSessionDownloadTask] = [:]
            for case let task as URLSessionDownloadTask in await session.allTasks {
                guard let batch = Self.parse(task), task.state != .completed else { continue }
                if let url = (task.originalRequest ?? task.currentRequest)?.url,
                    !client.serves(url)
                {
                    task.cancel()
                    continue
                }
                if batch.contains(where: { live[$0.id] != nil }) {
                    task.cancel()
                    continue
                }
                for item in batch { live[item.id] = task }
            }
            let held = await Task.detached { [files] in files.held() }.value
            let pending = try await library.pendingDownloads()
            let resumes = try await library.resumes()
            for id in delivered { failedAt[id] = .now }
            delivered = []
            var running = [false: 0, true: 0]
            var kept = Set<Int>()
            tasks = tasks.filter { $0.value.state == .completed }
            for item in pending {
                guard let task = live[item.trackId], task.state != .completed else { continue }
                if !kept.contains(task.taskIdentifier) {
                    guard running[item.wifiOnly, default: 0] < window else { continue }
                    running[item.wifiOnly, default: 0] += 1
                    kept.insert(task.taskIdentifier)
                }
                tasks[item.trackId] = task
            }
            for task in live.values where !kept.contains(task.taskIdentifier) { task.cancel() }
            guard !paused, !invalidated else { return }
            let recent = Date.now.addingTimeInterval(-Self.backoff)
            let waiting = pending.filter {
                tasks[$0.trackId] == nil && !held.contains($0.trackId)
                    && failedAt[$0.trackId].map({ $0 < recent }) ?? true
            }
            let byId = Dictionary(waiting.map { ($0.trackId, $0) }) { first, _ in first }
            let wanted = Set(pending.map(\.trackId))
            var claimed = Set<String>()
            var resumable: [(StoredResume?, [PendingDownload])] = []
            for stored in resumes {
                let ids = Self.parse(stored.description).map(\.id)
                guard client.serves(stored.url), !ids.isEmpty, ids.allSatisfy(wanted.contains)
                else {
                    session.downloadTask(withResumeData: stored.data).cancel()
                    try await library.dropResume(description: stored.description)
                    continue
                }
                claimed.formUnion(ids)
                let batch = ids.compactMap { byId[$0] }
                if batch.count == ids.count { resumable.append((stored, batch)) }
            }
            let fresh = Self.batches(waiting.filter { !claimed.contains($0.trackId) })
            for (stored, batch) in resumable + fresh.map({ (nil, $0) }) {
                let wifiOnly = batch[0].wifiOnly
                guard running[wifiOnly, default: 0] < window else { continue }
                running[wifiOnly, default: 0] += 1
                let task: URLSessionDownloadTask
                if let stored {
                    task = session.downloadTask(withResumeData: stored.data)
                    task.taskDescription = stored.description
                } else {
                    var request = client.request(client.archiveURL(ids: Self.request(batch)))
                    request.allowsExpensiveNetworkAccess = !wifiOnly
                    request.allowsConstrainedNetworkAccess = !wifiOnly
                    task = session.downloadTask(with: request)
                    task.taskDescription = batch.map { "\($0.trackId)/\($0.file)" }.joined(
                        separator: ",")
                }
                task.priority = wifiOnly ? URLSessionTask.lowPriority : URLSessionTask.highPriority
                for item in batch { tasks[item.trackId] = task }
                task.resume()
                if let stored { try await library.dropResume(description: stored.description) }
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
        case .done(let description, let url, let task, let delivered, let cancelled, let partial):
            let ids = Self.parse(description).map(\.id)
            for id in ids where tasks[id].map({ $0.taskIdentifier == task }) ?? true {
                tasks[id] = nil
                progress[id] = nil
            }
            if delivered {
                self.delivered.formUnion(ids)
            } else if !cancelled && partial == nil {
                for id in ids { failedAt[id] = .now }
            }
            Task {
                if let partial, let url {
                    do {
                        try await library.keepResume(
                            description: description, url: url, data: partial)
                    } catch {
                        Log.audio.error("Keeping resume data failed: \(error, privacy: .public)")
                    }
                }
                await resume(retry: false)
            }
        case .finishedEvents:
            Task {
                await resume()
                await unpacking?.value
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
    nonisolated static let archiveAlbums = 20
    nonisolated static let archiveIds = 150

    nonisolated static func trackId(_ file: String) -> String {
        String(file.prefix { $0 != "." })
    }

    nonisolated static func parse(_ task: URLSessionTask) -> [(id: String, file: String)]? {
        let batch = parse(task.taskDescription ?? "")
        return batch.isEmpty ? nil : batch
    }

    nonisolated static func parse(_ description: String) -> [(id: String, file: String)] {
        description.split(separator: ",").compactMap { pair -> (id: String, file: String)? in
            let parts = pair.split(separator: "/")
            return parts.count == 2 ? (String(parts[0]), String(parts[1])) : nil
        }
    }

    nonisolated static func batches(_ items: [PendingDownload]) -> [[PendingDownload]] {
        var batches: [[PendingDownload]] = []
        for album in albums(items) {
            if let last = batches.last, last[0].wifiOnly == album[0].wifiOnly,
                albums(last).count < archiveAlbums, request(last + album).count <= archiveIds
            {
                batches[batches.count - 1] += album
            } else {
                batches.append(album)
            }
        }
        return batches
    }

    nonisolated static func request(_ batch: [PendingDownload]) -> [String] {
        albums(batch).flatMap {
            $0.count == $0[0].albumTracks ? [$0[0].album] : $0.map(\.trackId)
        }
    }

    nonisolated static func albums(_ items: [PendingDownload]) -> [[PendingDownload]] {
        var albums: [[PendingDownload]] = []
        for item in items {
            if let last = albums.last?.last, last.album == item.album,
                last.wifiOnly == item.wifiOnly
            {
                albums[albums.count - 1].append(item)
            } else {
                albums.append([item])
            }
        }
        return albums
    }
}

public enum DownloadState: Sendable, Equatable {
    case waiting
    case downloading(Double)
    case saved
}
