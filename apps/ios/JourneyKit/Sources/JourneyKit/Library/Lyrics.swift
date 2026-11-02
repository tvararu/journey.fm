import Foundation
import GRDB

public struct LyricLine: Codable, Sendable, Equatable {
    public var text: String
    public var time: Double?

    public init(text: String, time: Double? = nil) {
        self.text = text
        self.time = time
    }
}

public struct Lyrics: Sendable, Equatable {
    public var lines: [LyricLine]

    public var synced: Bool { !lines.isEmpty && lines.allSatisfy { $0.time != nil } }

    public func current(at position: Double) -> Int? {
        guard synced else { return nil }
        return lines.lastIndex { ($0.time ?? 0) <= position }
    }
}

struct LyricsRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "lyrics"

    var trackId: String
    var etag: String?
    var synced: Bool
    var lines: String
    var text: String

    init(trackId: String, etag: String?, lines: [LyricLine]) {
        self.trackId = trackId
        self.etag = etag
        let lyrics = Lyrics(lines: lines)
        synced = lyrics.synced
        self.lines = String(
            decoding: (try? JSONEncoder().encode(lines)) ?? Data("[]".utf8), as: UTF8.self)
        text = lines.map(\.text).joined(separator: "\n")
    }

    var lyrics: Lyrics? {
        guard let decoded = try? JSONDecoder().decode([LyricLine].self, from: Data(lines.utf8)),
            !decoded.isEmpty
        else { return nil }
        return Lyrics(lines: decoded)
    }
}

public protocol LyricsSource: Sendable {
    func lyrics(trackId: String) async throws -> [LyricLine]
}

extension JellyfinClient: LyricsSource {}

public struct LyricsSync: Sendable {
    static let concurrency = 8

    let source: any LyricsSource
    let library: Library

    public init(source: any LyricsSource, library: Library) {
        self.source = source
        self.library = library
    }

    @discardableResult
    public func run(progress: @Sendable (Int, Int) -> Void = { _, _ in }) async throws -> Int {
        let wanted = try await library.db.write { db in
            try db.execute(
                sql:
                    "DELETE FROM lyrics WHERE trackId IN (SELECT id FROM track WHERE hasLyrics IS NOT 1)"
            )
            return try Row.fetchAll(
                db,
                sql: """
                    SELECT id, etag FROM track WHERE hasLyrics = 1 AND NOT EXISTS
                        (SELECT 1 FROM lyrics WHERE lyrics.trackId = track.id AND lyrics.etag IS track.etag)
                    """
            ).map { (id: $0["id"] as String, etag: $0["etag"] as String?) }
        }
        let total = wanted.count
        progress(0, total)
        guard total > 0 else { return 0 }
        let source = source
        var done = 0
        var saved = 0
        try await withThrowingTaskGroup(of: (String, String?, [LyricLine]?).self) { group in
            var pending = wanted.makeIterator()
            func next() {
                guard let (id, etag) = pending.next() else { return }
                group.addTask {
                    do {
                        return (id, etag, try await source.lyrics(trackId: id))
                    } catch let error as JellyfinError where error == .unauthorized {
                        throw error
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        Log.sync.error(
                            "Lyrics for \(id, privacy: .public) failed: \(String(describing: error), privacy: .public)"
                        )
                        return (id, etag, nil)
                    }
                }
            }
            for _ in 0..<Self.concurrency { next() }
            while let (id, etag, lines) = try await group.next() {
                done += 1
                if let lines {
                    try await library.db.write { db in
                        guard try Track.exists(db, key: id) else { return }
                        try LyricsRow(trackId: id, etag: etag, lines: lines).upsert(db)
                    }
                    saved += 1
                }
                progress(done, total)
                next()
            }
        }
        Log.sync.info("lyrics: \(saved) of \(total) saved")
        return saved
    }
}

extension Library {
    public func observeLyrics(trackId: String) -> AsyncValueObservation<Lyrics?> {
        ValueObservation.tracking { db in
            try LyricsRow.fetchOne(db, key: trackId)?.lyrics
        }.values(in: db)
    }

    public func lyrics(trackId: String) async throws -> Lyrics? {
        try await db.read { try LyricsRow.fetchOne($0, key: trackId)?.lyrics }
    }
}
