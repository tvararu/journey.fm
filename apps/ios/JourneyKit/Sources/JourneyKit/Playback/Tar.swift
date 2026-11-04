import Foundation

enum Tar {
    struct Truncated: Error {}

    static func unpack(_ archive: URL, into directory: URL, _ entry: (String, URL) -> Void) throws {
        let input = try FileHandle(forReadingFrom: archive)
        defer { try? input.close() }
        while let block = try input.read(upToCount: 512), block.count == 512 {
            let header = [UInt8](block)
            guard header.contains(where: { $0 != 0 }) else { return }
            let name = String(decoding: header[0..<100].prefix { $0 != 0 }, as: UTF8.self)
            let digits = header[124..<136].filter { (48...55).contains($0) }
            let size = UInt64(String(decoding: digits, as: UTF8.self), radix: 8) ?? 0
            let padding = (512 - size % 512) % 512
            guard header[156] == 48 || header[156] == 0 else {
                try input.seek(toOffset: input.offsetInFile + size + padding)
                continue
            }
            let file = directory.appending(path: UUID().uuidString)
            FileManager.default.createFile(atPath: file.path(percentEncoded: false), contents: nil)
            defer { try? FileManager.default.removeItem(at: file) }
            let output = try FileHandle(forWritingTo: file)
            var left = size
            while left > 0 {
                let copied = try autoreleasepool {
                    guard let chunk = try input.read(upToCount: Int(min(left, 1 << 20))),
                        !chunk.isEmpty
                    else { return 0 }
                    try output.write(contentsOf: chunk)
                    return chunk.count
                }
                guard copied > 0 else {
                    try? output.close()
                    throw Truncated()
                }
                left -= UInt64(copied)
            }
            try output.close()
            try input.seek(toOffset: input.offsetInFile + padding)
            entry(name, file)
        }
    }
}
