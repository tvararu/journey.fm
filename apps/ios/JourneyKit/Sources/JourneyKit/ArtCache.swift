import Foundation

public actor ArtCache {
    let directory: URL
    let client: JellyfinClient

    public init(directory: URL, client: JellyfinClient) {
        self.directory = directory
        self.client = client
    }

    public func image(itemId: String, tag: String, maxWidth: Int) async throws -> Data {
        let file = directory.appending(path: "\(itemId)-\(tag)-\(maxWidth).jpg")
        if let data = try? Data(contentsOf: file) { return data }
        let data = try await client.data(
            from: client.imageURL(itemId: itemId, tag: tag, maxWidth: maxWidth))
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        for stale in try manager.contentsOfDirectory(atPath: directory.path(percentEncoded: false))
        where stale.hasPrefix("\(itemId)-") && !stale.hasPrefix("\(itemId)-\(tag)-") {
            try? manager.removeItem(at: directory.appending(path: stale))
        }
        try data.write(to: file, options: .atomic)
        return data
    }

    public func clear() throws {
        try? FileManager.default.removeItem(at: directory)
    }
}
