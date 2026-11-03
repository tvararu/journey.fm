import Foundation
import Testing

@testable import JourneyKit

@MainActor
struct DownloadTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)

    func setUp(_ stub: Stub, tracks: [Track]) async throws -> (Library, Downloads) {
        let library = try await librarySynced(
            artists: [], albums: [album("x"), album("y")], tracks: tracks)
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

    @Test func downloadEverythingKeepsOnlyAWindowOfRequestsOpen() async throws {
        let stub = Stub(body: pattern(64 * 1024))
        stub.chunk = 16 * 1024
        stub.delay = 0.01
        let tracks = (1...6).map { track("x\($0)", album: "x") } + [track("y1", album: "y")]
        let (_, downloads) = try await setUp(stub, tracks: tracks)
        let windowed = Downloads(
            library: downloads.library, client: stub.client, directory: directory,
            configuration: stub.configuration, window: 2)
        downloads.invalidate()

        await windowed.saveEverything()
        #expect(windowed.tasks.count == 2)
        await windowed.save(trackIds: ["y1"])
        #expect(windowed.tasks.count == 3)
        #expect(await eventually(10) { windowed.summary.saved.count == 7 })
        #expect(windowed.summary.everything)
        #expect(stub.lock.withLock { stub.mostActive } <= 3)
    }

    @Test func onlyAsManyTracksAsFitInTheRoomAreQueued() async throws {
        let stub = Stub(body: pattern(64 * 1024))
        stub.delay = 5
        let tracks = (1...6).map { track("x\($0)", album: "x") }
        let (_, downloads) = try await setUp(stub, tracks: tracks)
        let size = Downloads.estimate(
            PendingDownload(trackId: "x1", file: "x1.flac", wifiOnly: true, duration: 60))
        downloads.room = size * 2 + size / 2

        await downloads.saveEverything()
        #expect(downloads.tasks.count == 2)
        downloads.room = size * 5
        await downloads.resume()
        #expect(downloads.tasks.count == 5)
        downloads.invalidate()
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
