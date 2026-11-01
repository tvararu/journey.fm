import JourneyKit
import Network
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
    var error: String?
    var clock = Date.now
    var syncOffline = false { didSet { player.offline = offline } }
    var network = NWPath.Status.satisfied { didSet { player.offline = offline } }
    var expensiveNetwork = false
    var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    var freeSpace: Int64?
    var downloadingEverything = UserDefaults.standard.bool(forKey: "downloadingEverything") {
        didSet { UserDefaults.standard.set(downloadingEverything, forKey: "downloadingEverything") }
    }
    var downloadNew = UserDefaults.standard.bool(forKey: "downloadNew") {
        didSet {
            UserDefaults.standard.set(downloadNew, forKey: "downloadNew")
            if downloadNew && !oldValue {
                UserDefaults.standard.set(Date.now.ISO8601Format(), forKey: "downloadNewSince")
            }
        }
    }
    private(set) var art: ArtCache?
    private(set) var downloads: Downloads?
    private var audio: AudioCache?
    let library: Library
    let player: Player
    private var system: SystemAudio?
    private let monitor = NWPathMonitor()
    #if DEBUG
        private let forcedOffline = ProcessInfo.processInfo.environment["JOURNEY_OFFLINE"] == "1"
    #else
        private let forcedOffline = false
    #endif

    init() {
        let path = URL.applicationSupportDirectory.appending(path: "library.sqlite")
        do {
            library = try Library(path: path.path(percentEncoded: false))
        } catch {
            fatalError("Cannot open the library database: \(error)")
        }
        player = Player(library: library)
        session = SessionStore.load()
        art = session.map(Self.artCache)
        connectAudio()
        system = SystemAudio(player: player) { [weak self] in self?.art }
        player.offline = offline
        watchDevice()
        Task { await player.restore() }
    }

    var offline: Bool { forcedOffline || syncOffline || network != .satisfied }

    func isOnPhone(_ track: Track) -> Bool {
        audio?.isOnPhone(track) ?? false
    }

    var downloadPause: String? {
        if downloads?.paused == true { return "Paused: this iPhone is out of space." }
        if network != .satisfied { return "Waiting for a network connection." }
        if expensiveNetwork { return "Waiting for Wi-Fi." }
        if lowPower { return "Paused for Low Power Mode." }
        return nil
    }

    func downloadEverything() async {
        downloadingEverything = true
        await downloads?.saveEverything()
    }

    func removeAllDownloads() async {
        downloadingEverything = false
        downloadNew = false
        await downloads?.removeAll()
    }

    private func watchDevice() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in self?.update(path) }
        }
        monitor.start(queue: .main)
        NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled }
        }
    }

    private func update(_ path: NWPath) {
        let wasUp = network == .satisfied
        network = path.status
        expensiveNetwork = path.isExpensive || path.isConstrained
        if !wasUp && path.status == .satisfied {
            Task {
                await sync()
                await downloads?.resume()
            }
        }
    }

    private func downloadsChanged(_ summary: DownloadSummary) {
        checkSpace()
        if downloadingEverything && summary.everything {
            downloadingEverything = false
            downloadNew = true
        }
    }

    func checkSpace() {
        let values = try? URL.applicationSupportDirectory.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey
        ])
        freeSpace = values?.volumeAvailableCapacityForImportantUsage
        guard let downloads, let freeSpace else { return }
        let full = freeSpace < Self.reserve
        if downloads.paused != full {
            downloads.paused = full
            if !full { Task { await downloads.resume() } }
        }
    }

    private static let reserve: Int64 = 2_000_000_000

    func albumTracks(_ albumIds: [String]) async -> [TrackHit] {
        (try? await library.tracks(albumIds: albumIds)) ?? []
    }

    private func connectAudio() {
        downloads?.invalidate()
        downloads = session.map {
            let configuration = URLSessionConfiguration.background(
                withIdentifier: "fm.journey.app.downloads")
            configuration.sessionSendsLaunchEvents = true
            configuration.isDiscretionary = false
            configuration.httpMaximumConnectionsPerHost = 4
            return Downloads(
                library: library, client: JellyfinClient(session: $0),
                directory: Self.downloadsDirectory, configuration: configuration)
        }
        downloads?.changed = { [weak self] in self?.downloadsChanged($0) }
        audio = session.map {
            AudioCache(
                directory: .cachesDirectory.appending(path: "audio"),
                client: JellyfinClient(session: $0), keep: 10, saved: downloads?.files)
        }
        player.connect(audio)
        checkSpace()
        if let downloads { Task { await downloads.resume() } }
    }

    private static let downloadsDirectory = URL.applicationSupportDirectory.appending(path: "audio")

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
            connectAudio()
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
        if downloadNew, let downloads,
            let since = UserDefaults.standard.string(forKey: "downloadNewSince")
        {
            UserDefaults.standard.set(Date.now.ISO8601Format(), forKey: "downloadNewSince")
            await downloads.saveEverything(createdAfter: since)
        } else {
            await downloads?.resume()
        }
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
            syncOffline = false
            return true
        } catch JellyfinError.unauthorized {
            Log.session.error("The server rejected the token; signing out")
            await signOut()
            error = "The server signed this phone out. Sign in again."
        } catch let error as URLError where Self.offlineCodes.contains(error.code) {
            Log.sync.error("Sync failed offline: \(String(describing: error), privacy: .public)")
            syncOffline = true
            syncError = error.localizedDescription
        } catch {
            Log.sync.error("Sync failed: \(String(describing: error), privacy: .public)")
            syncOffline = false
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
        player.connect(nil)
        audio?.clear()
        downloads?.invalidate()
        downloads = nil
        try? FileManager.default.removeItem(at: Self.downloadsDirectory)
        downloadingEverything = false
        downloadNew = false
        try? await art?.clear()
        try? await library.erase()
        art = nil
        syncError = nil
        syncOffline = false
        session = nil
        connectAudio()
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
