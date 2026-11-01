import Foundation
import JourneyKit

let environment = ProcessInfo.processInfo.environment
let arguments = Array(CommandLine.arguments.dropFirst())
let home = URL(filePath: environment["JOURNEY_HOME"] ?? FileManager.default.currentDirectoryPath)

func value(_ name: String) -> String {
    guard let value = environment[name], !value.isEmpty else {
        FileHandle.standardError.write(Data("\(name) is not set\n".utf8))
        exit(1)
    }
    return value
}

func client() async throws -> JellyfinClient {
    guard let server = URL(string: value("JELLYFIN_URL")) else { exit(1) }
    let session = try await JellyfinClient.signIn(
        server: server, username: value("JELLYFIN_USERNAME"), password: value("JELLYFIN_PASSWORD"),
        deviceName: Host.current().localizedName ?? "Mac", deviceId: "journey-cli")
    return JellyfinClient(session: session)
}

let library = try Library(path: home.appending(path: "library.sqlite").path(percentEncoded: false))

switch arguments.first {
case "sync":
    let start = Date.now
    let report = try await Sync(source: try await client(), library: library)
        .run(full: arguments.contains("--full"))
    let stats = try await library.stats()
    print(
        """
        \(report.full ? "full" : "delta") sync in \(start.distance(to: .now).formatted(.number.precision(.fractionLength(1)))) s
        fetched \(report.artists) artists, \(report.albums) albums, \(report.tracks) tracks
        deleted \(report.deleted), deferred \(report.deferred)
        library has \(stats.artists) artists, \(stats.albums) albums, \(stats.tracks) tracks
        """)
case "stats":
    let stats = try await library.stats()
    print(
        "\(stats.artists) artists, \(stats.albums) albums, \(stats.tracks) tracks, last sync \(stats.lastSync?.formatted() ?? "never")"
    )
case "art":
    let directory = home.appending(path: "art")
    let cache = ArtCache(directory: directory, client: try await client())
    let items = try await library.artItems()
    let start = Date.now
    let failed = await cache.prefetch(items)
    let bytes = try FileManager.default.contentsOfDirectory(
        at: directory, includingPropertiesForKeys: [.fileSizeKey]
    ).reduce(0) { $0 + (try $1.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) }
    print(
        "\(items.count) covers, \(failed) failed, \(bytes.formatted(.byteCount(style: .file))) in \(start.distance(to: .now).formatted(.number.precision(.fractionLength(1)))) s"
    )
case "search":
    let results = try await library.search(arguments.dropFirst().joined(separator: " "))
    for artist in results.artists { print("artist  \(artist.name) (\(artist.albumCount))") }
    for album in results.albums { print("album   \(album.name) · \(album.artistName)") }
    for hit in results.tracks { print("track   \(hit.track.name) · \(hit.album.name)") }
default:
    print("usage: journey sync [--full] | stats | art | search <words>")
    exit(1)
}
