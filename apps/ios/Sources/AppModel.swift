import JourneyKit
import Observation
import UIKit
import os

struct CoverProgress: Equatable {
    var done: Int
    var total: Int
}

@MainActor
@Observable
final class AppModel {
    var session: Session?
    var stats = LibraryStats()
    var statsLoaded = false
    var syncing = false
    var syncProgress = SyncProgress()
    var covers: CoverProgress?
    var syncError: String?
    var offline = false
    var error: String?
    var clock = Date.now
    private(set) var art: ArtCache?
    let library: Library

    init() {
        let path = URL.applicationSupportDirectory.appending(path: "library.sqlite")
        do {
            library = try Library(path: path.path(percentEncoded: false))
        } catch {
            fatalError("Cannot open the library database: \(error)")
        }
        session = SessionStore.load()
        art = session.map(Self.artCache)
    }

    var needsFirstSync: Bool { statsLoaded && stats.lastSync == nil }

    var syncStatus: String {
        if syncing { return "Syncing…" }
        let synced =
            stats.lastSync.map {
                "Synced \(Self.relative.localizedString(for: $0, relativeTo: max(clock, $0)))"
            } ?? "Never synced"
        if offline { return "Offline · \(synced)" }
        if syncError != nil { return "Couldn't sync · \(synced)" }
        return synced
    }

    func tick() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(30))
            clock = .now
        }
    }

    func signIn(server: String, username: String, password: String) async {
        guard let url = URL(string: server.trimmingCharacters(in: .whitespaces)), url.host() != nil
        else {
            error = "That server address isn't a URL."
            return
        }
        do {
            let session = try await JellyfinClient.signIn(
                server: url, username: username, password: password,
                deviceName: UIDevice.current.name, deviceId: SessionStore.deviceId())
            try SessionStore.save(session)
            Log.session.info("Signed in to \(url.absoluteString, privacy: .public)")
            error = nil
            art = Self.artCache(session)
            self.session = session
        } catch {
            Log.session.error("Sign-in failed: \(String(describing: error), privacy: .public)")
            self.error = error.localizedDescription
        }
    }

    #if DEBUG
        func signInFromLaunchEnvironment() async {
            let environment = ProcessInfo.processInfo.environment
            guard session == nil, let server = environment["JELLYFIN_URL"],
                let username = environment["JELLYFIN_USERNAME"],
                let password = environment["JELLYFIN_PASSWORD"]
            else { return }
            await signIn(server: server, username: username, password: password)
        }
    #endif

    func sync() async {
        guard let session, let art, !syncing else { return }
        guard await runSync(JellyfinClient(session: session)) else { return }
        await fetchCovers(art)
    }

    private func runSync(_ client: JellyfinClient) async -> Bool {
        syncing = true
        syncProgress = SyncProgress()
        defer { syncing = false }
        do {
            _ = try await Sync(source: client, library: library).run { progress in
                Task { @MainActor in
                    if self.syncing { self.syncProgress = progress }
                }
            }
            syncError = nil
            offline = false
            return true
        } catch JellyfinError.unauthorized {
            Log.session.error("The server rejected the token; signing out")
            await signOut()
            error = "The server signed this phone out. Sign in again."
        } catch let error as URLError where Self.offlineCodes.contains(error.code) {
            Log.sync.error("Sync failed offline: \(String(describing: error), privacy: .public)")
            offline = true
            syncError = error.localizedDescription
        } catch {
            Log.sync.error("Sync failed: \(String(describing: error), privacy: .public)")
            offline = false
            syncError = error.localizedDescription
        }
        return false
    }

    private func fetchCovers(_ art: ArtCache) async {
        guard covers == nil else { return }
        covers = CoverProgress(done: 0, total: 0)
        defer { covers = nil }
        do {
            _ = await art.prefetch(try await library.artItems()) { done, total in
                Task { @MainActor in
                    if self.covers != nil { self.covers = CoverProgress(done: done, total: total) }
                }
            }
        } catch {
            Log.art.error("Listing covers failed: \(String(describing: error), privacy: .public)")
        }
    }

    func signOut() async {
        SessionStore.clear()
        try? await art?.clear()
        try? await library.erase()
        art = nil
        syncError = nil
        offline = false
        session = nil
    }

    func watchStats() async {
        do {
            for try await stats in library.observeStats() {
                self.stats = stats
                statsLoaded = true
            }
        } catch {
            Log.sync.error(
                "Watching the library failed: \(String(describing: error), privacy: .public)")
        }
    }

    private static let offlineCodes: Set<URLError.Code> = [
        .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost,
        .dnsLookupFailed, .timedOut,
    ]

    private static let relative = {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        return formatter
    }()

    private static func artCache(_ session: Session) -> ArtCache {
        ArtCache(
            directory: .applicationSupportDirectory.appending(path: "art"),
            client: JellyfinClient(session: session))
    }
}
