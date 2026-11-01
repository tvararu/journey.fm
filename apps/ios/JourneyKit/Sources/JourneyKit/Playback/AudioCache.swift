import Foundation

public final class AudioCache: @unchecked Sendable {
    let directory: URL
    let client: JellyfinClient
    let keep: Int
    let saved: SavedFiles?
    let session: URLSession
    let lock = NSLock()
    var downloads: [String: StreamDownload] = [:]

    public init(
        directory: URL, client: JellyfinClient, keep: Int = 30, saved: SavedFiles? = nil,
        configuration: URLSessionConfiguration = .default
    ) {
        self.directory = directory
        self.client = client
        self.keep = keep
        self.saved = saved
        session = URLSession(configuration: configuration)
    }

    public func isOnPhone(_ track: Track) -> Bool {
        saved?.file(for: track) != nil
            || FileManager.default.fileExists(atPath: cached(track).path(percentEncoded: false))
    }

    func cached(_ track: Track) -> URL {
        directory.appending(path: SavedFiles.name(track))
    }

    public func source(for track: Track) throws -> ByteSource {
        try lock.withLock {
            if let download = downloads[track.id] { return download.source }
            if let file = saved?.file(for: track) { return try ByteSource(complete: file) }
            let manager = FileManager.default
            let destination = cached(track)
            if manager.fileExists(atPath: destination.path(percentEncoded: false)) {
                try? manager.setAttributes(
                    [.modificationDate: Date.now],
                    ofItemAtPath: destination.path(percentEncoded: false))
                return try ByteSource(complete: destination)
            }
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            let start = Date.now
            let download = try StreamDownload(
                request: client.request(client.audioURL(trackId: track.id)),
                partial: directory.appending(path: "\(track.id).part"),
                destination: destination, session: session
            ) { [weak self] complete in
                Log.audio.info(
                    "Fetch of \(track.id, privacy: .public) \(complete ? "finished" : "stopped") after \(start.distance(to: .now), format: .fixed(precision: 1)) s"
                )
                if complete, let saved = self?.saved { _ = saved.adopt(track, from: destination) }
                self?.finished(track.id)
            }
            downloads[track.id] = download
            return download.source
        }
    }

    public func cancel(except wanted: Set<String>) {
        lock.withLock {
            for (id, download) in downloads where !wanted.contains(id) { download.cancel() }
        }
    }

    public func clear() {
        lock.withLock {
            for download in downloads.values { download.cancel() }
            try? FileManager.default.removeItem(at: directory)
        }
    }

    func finished(_ id: String) {
        lock.withLock {
            downloads[id] = nil
            prune()
        }
    }

    func prune() {
        let manager = FileManager.default
        guard
            let files = try? manager.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
        else { return }
        let complete = files.filter { $0.pathExtension != "part" }.map { url in
            (
                url,
                (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
            )
        }
        for (url, _) in complete.sorted(by: { $0.1 > $1.1 }).dropFirst(keep) {
            try? manager.removeItem(at: url)
        }
    }
}
