import Foundation

enum DeepLink: Equatable {
    case tab(AppTab)
    case route(AppTab, Route)
    case release([String], track: Int?, play: Int?)
    case artist(String)
    case genre(String)
    case player
    case settings

    init?(_ url: URL) {
        guard url.scheme == "journey", let host = url.host(percentEncoded: false) else {
            return nil
        }
        let rest = url.pathComponents.filter { $0 != "/" }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let item = { (name: String) in query.first { $0.name == name }?.value }
        switch (host, rest.count) {
        case ("home", 0): self = .tab(.home)
        case ("library", 0): self = .tab(.library)
        case ("player", 0): self = .player
        case ("settings", 0): self = .settings
        case ("recently-added", 0): self = .route(.home, .recentlyAdded)
        case ("recently-played", 0): self = .route(.home, .recentlyPlayed)
        case ("release", 3):
            self = .release(
                [host] + rest, track: item("track").flatMap(Int.init),
                play: item("play").flatMap(Int.init))
        case ("artist", 1): self = .artist(rest[0])
        case ("genre", 1): self = .genre(rest[0])
        case ("search", 0):
            guard let q = item("q") else {
                self = .tab(.search)
                return
            }
            let routes: [String: (String) -> Route] = [
                "artists": Route.searchArtists, "albums": Route.searchAlbums,
                "tracks": Route.searchTracks, "credits": Route.searchCredits,
                "lyrics": Route.searchLyrics,
            ]
            guard let route = routes[item("type") ?? "albums"] else { return nil }
            self = .route(.search, route(q))
        default: return nil
        }
    }
}
