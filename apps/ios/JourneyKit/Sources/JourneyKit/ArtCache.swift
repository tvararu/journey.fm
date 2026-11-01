import Foundation
import GRDB

public struct ArtItem: Codable, Sendable, Hashable, FetchableRecord {
    public var id: String
    public var tag: String

    public init(id: String, tag: String) {
        self.id = id
        self.tag = tag
    }
}

public actor ArtCache {
    public static let width = 600
    static let downloads = 4

    nonisolated let directory: URL
    let client: JellyfinClient

    public init(directory: URL, client: JellyfinClient) {
        self.directory = directory
        self.client = client
    }

    public nonisolated func cached(_ item: ArtItem) -> Data? {
        try? Data(contentsOf: file(item))
    }

    public func image(_ item: ArtItem) async throws -> Data {
        if let data = cached(item) { return data }
        let data = try await client.data(
            from: client.imageURL(itemId: item.id, tag: item.tag, maxWidth: Self.width))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: file(item), options: .atomic)
        return data
    }

    public func prefetch(
        _ items: [ArtItem], progress: @Sendable (_ done: Int, _ total: Int) -> Void = { _, _ in }
    ) async -> Int {
        let manager = FileManager.default
        let wanted = Set(items.map { file($0).lastPathComponent })
        let existing = Set(
            (try? manager.contentsOfDirectory(atPath: directory.path(percentEncoded: false))) ?? [])
        for stale in existing.subtracting(wanted) {
            try? manager.removeItem(at: directory.appending(path: stale))
        }
        let missing = items.filter { !existing.contains(file($0).lastPathComponent) }
        var done = 0
        var failed = 0
        await withTaskGroup(of: Bool.self) { group in
            var queue = missing.makeIterator()
            for _ in 0..<Self.downloads {
                guard let item = queue.next() else { break }
                group.addTask { (try? await self.image(item)) != nil }
            }
            for await ok in group {
                done += 1
                if !ok { failed += 1 }
                progress(done, missing.count)
                if let item = queue.next() {
                    group.addTask { (try? await self.image(item)) != nil }
                }
            }
        }
        Log.art.info(
            "Prefetched \(missing.count - failed) of \(missing.count) missing covers; \(failed) failed"
        )
        return failed
    }

    public func clear() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    nonisolated func file(_ item: ArtItem) -> URL {
        directory.appending(path: "\(item.id)-\(item.tag).jpg")
    }
}
