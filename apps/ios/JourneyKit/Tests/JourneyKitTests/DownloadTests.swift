import Foundation
import Testing

@testable import JourneyKit

@MainActor
struct DownloadTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)

    func setUp(_ stub: Stub, tracks: [Track]) async throws -> (Library, Downloads) {
        let albums = Dictionary(grouping: tracks, by: \.albumId).mapValues { $0.map(\.id) }
        stub.lock.withLock { stub.albums = albums }
        let library = try await librarySynced(
            artists: [], albums: Set(albums.keys + ["x", "y"]).sorted().map { album($0) },
            tracks: tracks)
        let downloads = Downloads(
            library: library, client: stub.client, directory: directory,
            configuration: stub.configuration)
        return (library, downloads)
    }

    func files() -> Set<String> {
        Set(
            (try? FileManager.default.contentsOfDirectory(
                atPath: directory.path(percentEncoded: false))) ?? [])
    }

    @Test func savingAnAlbumStoresEveryTrackAndRemovingDeletesThem() async throws {
        let stub = Stub(body: pattern(3000))
        let (_, downloads) = try await setUp(
            stub,
            tracks: [track("x1", album: "x"), track("x2", album: "x"), track("y1", album: "y")])

        await downloads.save(albumIds: ["x"])
        #expect(await eventually { downloads.summary.saved == ["x1", "x2"] })
        #expect(downloads.summary.completeAlbums == ["x"])
        #expect(downloads.summary.bytes == 6000)
        #expect(downloads.state(of: "x1") == .saved)
        #expect(downloads.state(of: "y1") == nil)
        #expect(files() == ["x1.flac", "x2.flac"])
        #expect(try Data(contentsOf: directory.appending(path: "x1.flac")) == pattern(3000))

        await downloads.remove(trackIds: ["x2"])
        #expect(await eventually { downloads.summary.saved == ["x1"] })
        #expect(downloads.summary.completeAlbums.isEmpty)
        #expect(files() == ["x1.flac"])

        await downloads.removeAll()
        #expect(await eventually { downloads.summary.wanted == 0 })
        #expect(files().isEmpty)
    }

    @Test func aFailedResponseIsNotSavedAndStaysWaiting() async throws {
        let stub = Stub(body: Data("Internal error".utf8))
        stub.status = 500
        let (_, downloads) = try await setUp(stub, tracks: [track("x1", album: "x")])

        await downloads.save(trackIds: ["x1"])
        #expect(await eventually { downloads.summary.waiting == ["x1"] && downloads.tasks.isEmpty })
        #expect(downloads.summary.saved.isEmpty)
        #expect(files().isEmpty)

        stub.lock.withLock { stub.status = 200 }
        await downloads.resume()
        #expect(await eventually { downloads.summary.saved == ["x1"] })
    }

    @Test func aTrackWhoseAudioChangedIsDownloadedAgain() async throws {
        let stub = Stub(body: pattern(1000))
        let (library, downloads) = try await setUp(stub, tracks: [track("x1", album: "x")])
        await downloads.save(trackIds: ["x1"])
        #expect(await eventually { downloads.summary.saved == ["x1"] })

        stub.lock.withLock { stub.body = pattern(1500) }
        var changed = track("x1", album: "x")
        changed.duration = 61
        try await library.db.write { [changed] in try changed.upsert($0) }
        await downloads.resume()
        #expect(
            await eventually {
                downloads.summary.saved == ["x1"] && downloads.summary.bytes == 1500
            })
        #expect(stub.requestedRanges.count == 2)
    }

    @Test func aStreamedTrackWaitingToBeSavedIsSavedWhenItFinishes() async throws {
        let stub = Stub(body: pattern(256 * 1024))
        stub.chunk = 64 * 1024
        stub.delay = 0.02
        let (_, downloads) = try await setUp(stub, tracks: [track("x1", album: "x")])
        downloads.paused = true
        await downloads.save(trackIds: ["x1"])
        let cache = AudioCache(
            directory: directory.appending(path: "cache"), client: stub.client,
            saved: downloads.files, configuration: stub.configuration)
        let source = try cache.source(for: track("x1", album: "x"))
        let token = ReadToken()
        #expect(try source.size(token) == 256 * 1024)
        #expect(await eventually { downloads.summary.saved == ["x1"] })
        #expect(stub.requestedRanges.count == 1)
        #expect(downloads.files.file(for: track("x1", album: "x")) != nil)
        #expect(cache.isOnPhone(track("x1", album: "x")))
    }

    @Test func downloadEverythingFetchesTwentyAlbumsPerArchiveWithinTheWindow() async throws {
        let stub = Stub(body: pattern(16 * 1024))
        stub.chunk = 4 * 1024
        stub.delay = 0.01
        let albums = (1...21).map { String(format: "a%02d", $0) }
        let tracks = albums.map { track("\($0)t", album: $0) }
        let (_, downloads) = try await setUp(stub, tracks: tracks)
        let windowed = Downloads(
            library: downloads.library, client: stub.client, directory: directory,
            configuration: stub.configuration, window: 1)
        downloads.invalidate()

        await windowed.saveEverything()
        #expect(windowed.tasks.count == 20)
        #expect(await eventually(10) { windowed.summary.saved.count == 21 })
        #expect(windowed.summary.everything)
        #expect(files().count == 21)
        #expect(stub.lock.withLock { stub.requested } == [Array(albums.prefix(20)), ["a21"]])
        #expect(stub.lock.withLock { stub.mostActive } == 1)
    }

    @Test func anArchiveNamesWholeAlbumsAndOnlyTheMissingTracksOfOthers() {
        func pending(_ id: String, _ album: String, of count: Int) -> PendingDownload {
            PendingDownload(
                trackId: id, file: "\(id).flac", wifiOnly: true, album: album, albumTracks: count)
        }
        let batch = [
            pending("x1", "x", of: 2), pending("x2", "x", of: 2), pending("y2", "y", of: 3),
        ]
        #expect(Downloads.request(batch) == ["x", "y2"])
    }

    @Test func removingATrackLeavesTheRestOfItsAlbumDownloading() async throws {
        let stub = Stub(body: pattern(64 * 1024))
        stub.chunk = 16 * 1024
        stub.delay = 0.02
        let (_, downloads) = try await setUp(
            stub, tracks: [track("x1", album: "x"), track("x2", album: "x")])

        await downloads.save(albumIds: ["x"])
        await downloads.remove(trackIds: ["x2"])
        #expect(await eventually { downloads.summary.saved == ["x1"] })
        #expect(files() == ["x1.flac"])
        #expect(stub.requestedRanges.count == 1)
    }

    @Test func downloadNewAlbumsOnlyWantsAlbumsAddedAfterTheCutoff() async throws {
        let stub = Stub(body: pattern(100))
        let (library, downloads) = try await setUp(
            stub, tracks: [track("x1", album: "x"), track("y1", album: "y")])
        downloads.paused = true
        try await library.db.write { db in
            try db.execute(
                sql: "UPDATE album SET dateCreated = '2026-10-01T00:00:00.0000000Z' WHERE id = 'x'")
            try db.execute(
                sql: "UPDATE album SET dateCreated = '2026-11-01T12:00:00.0000000Z' WHERE id = 'y'")
        }
        await downloads.saveEverything(createdAfter: "2026-11-01T00:00:00Z")
        #expect(await eventually { downloads.summary.waiting == ["y1"] })
    }
}
