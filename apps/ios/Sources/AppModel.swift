import JourneyKit
import Observation
import UIKit

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
                deviceName: UIDevice.current.name)
            try SessionStore.save(session)
            error = nil
            art = Self.artCache(session)
            self.session = session
        } catch {
            self.error = error.localizedDescription
        }
    }

    func sync() async {
        guard let session, !syncing else { return }
        syncing = true
        defer { syncing = false }
        do {
            _ = try await Sync(source: JellyfinClient(session: session), library: library).run()
            error = nil
        } catch JellyfinError.unauthorized {
            await signOut()
            error = "The server signed this phone out. Sign in again."
        } catch {
            self.error = error.localizedDescription
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
            self.error = error.localizedDescription
        }
    }

    func watchRecent() async {
        do {
            for try await albums in library.observeRecentAlbums(limit: 20) { recent = albums }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private static func artCache(_ session: Session) -> ArtCache {
        ArtCache(
            directory: .cachesDirectory.appending(path: "art"),
            client: JellyfinClient(session: session))
    }
}
