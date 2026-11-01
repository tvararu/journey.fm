import JourneyKit
import Observation
import UIKit
import os

@MainActor
@Observable
final class AppModel {
    var session: Session?
    var stats = LibraryStats()
    var recent: [Album] = []
    var syncing = false
    var error: String?
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
            fail(Log.session, "Sign-in failed", error)
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
        guard let session, !syncing else { return }
        syncing = true
        defer { syncing = false }
        do {
            _ = try await Sync(source: JellyfinClient(session: session), library: library).run()
            error = nil
        } catch JellyfinError.unauthorized {
            Log.session.error("The server rejected the token; signing out")
            await signOut()
            error = "The server signed this phone out. Sign in again."
        } catch {
            fail(Log.sync, "Sync failed", error)
        }
    }

    func signOut() async {
        SessionStore.clear()
        session = nil
        try? await art?.clear()
        art = nil
        try? await library.erase()
    }

    func watchStats() async {
        do {
            for try await stats in library.observeStats() { self.stats = stats }
        } catch {
            fail(Log.sync, "Watching the library failed", error)
        }
    }

    func watchRecent() async {
        do {
            for try await albums in library.observeRecentAlbums(limit: 20) { recent = albums }
        } catch {
            fail(Log.sync, "Watching the library failed", error)
        }
    }

    private func fail(_ log: Logger, _ what: String, _ error: any Error) {
        log.error("\(what, privacy: .public): \(String(describing: error), privacy: .public)")
        self.error = error.localizedDescription
    }

    private static func artCache(_ session: Session) -> ArtCache {
        ArtCache(
            directory: .cachesDirectory.appending(path: "art"),
            client: JellyfinClient(session: session))
    }
}
