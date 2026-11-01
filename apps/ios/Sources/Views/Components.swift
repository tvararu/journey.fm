import JourneyKit
import SwiftUI

enum Route: Hashable {
    case album(String)
    case artist(String)
    case recentlyAdded
    case recentlyPlayed
    case searchArtists(String)
    case searchAlbums(String)
    case searchTracks(String)
}

struct Navigator: Equatable {
    let push: @MainActor (Route) -> Void

    @MainActor func callAsFunction(_ route: Route) { push(route) }

    static func == (lhs: Navigator, rhs: Navigator) -> Bool { true }
}

extension EnvironmentValues {
    @Entry var navigate = Navigator { _ in }
}

struct TabStack<Content: View>: View {
    @Binding var path: [Route]
    @ViewBuilder var content: Content

    var body: some View {
        NavigationStack(path: $path) {
            content.navigationDestination(for: Route.self) { route in
                switch route {
                case .album(let id): AlbumView(id: id)
                case .artist(let id): ArtistView(id: id)
                case .recentlyAdded: RecentlyAddedView()
                case .recentlyPlayed: RecentlyPlayedView()
                case .searchArtists(let query): SearchAllView(query: query, kind: .artists)
                case .searchAlbums(let query): SearchAllView(query: query, kind: .albums)
                case .searchTracks(let query): SearchAllView(query: query, kind: .tracks)
                }
            }
        }
        .environment(\.navigate, Navigator { path.append($0) })
    }
}

@MainActor
func watch<S: AsyncSequence>(_ values: S, _ update: (S.Element) -> Void) async {
    do {
        for try await value in values { update(value) }
    } catch {
        Log.sync.error(
            "Watching the library failed: \(String(describing: error), privacy: .public)")
    }
}

extension Album {
    var art: ArtItem? { imageTag.map { ArtItem(id: id, tag: $0) } }

    var meta: String {
        [year.map(String.init), genres.isEmpty ? nil : genres].compactMap(\.self)
            .joined(separator: " · ")
    }

    var counts: String { "\(tracksText(trackCount)) · \(lengthText(duration))" }

    var repeatKey: String { "\(name)\u{0}\(artistName)".lowercased() }

    func subtitle(_ parts: [String?], repeats: Set<String>) -> String {
        (parts + [repeats.contains(repeatKey) ? tracksText(trackCount) : nil]).compactMap(\.self)
            .filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

extension ArtistSummary {
    var art: ArtItem? { imageTag.map { ArtItem(id: id, tag: $0) } }

    var albumsText: String { albumCount == 1 ? "1 album" : "\(albumCount) albums" }

    var span: String? {
        guard let firstYear, let lastYear else { return nil }
        return firstYear == lastYear ? String(firstYear) : "\(firstYear)–\(lastYear)"
    }
}

func repeated(_ albums: [Album]) -> Set<String> {
    var seen = Set<String>()
    var repeats = Set<String>()
    for album in albums where !seen.insert(album.repeatKey).inserted {
        repeats.insert(album.repeatKey)
    }
    return repeats
}

func tracksText(_ count: Int) -> String { count == 1 ? "1 track" : "\(count) tracks" }

func lengthText(_ seconds: Double) -> String {
    Duration.seconds(seconds.rounded()).formatted(
        .units(allowed: [.hours, .minutes], width: .abbreviated))
}

func timeText(_ seconds: Double) -> String {
    Duration.seconds(seconds.rounded()).formatted(.time(pattern: .minuteSecond))
}

func indexLetter(_ sortName: String) -> String {
    guard let first = sortName.first else { return "#" }
    let letter = String(first).folding(options: .diacriticInsensitive, locale: nil).uppercased()
    return letter.count == 1 && ("A"..."Z").contains(letter) ? letter : "#"
}

struct IndexedSection<Item: Identifiable>: Identifiable {
    var id: String
    var label: String
    var items: [Item]
}

func indexed<Item: Identifiable>(_ items: [Item], key: (Item) -> String) -> [IndexedSection<Item>] {
    var sections: [IndexedSection<Item>] = []
    for item in items {
        let label = key(item)
        if sections.last?.label == label {
            sections[sections.count - 1].items.append(item)
        } else {
            sections.append(
                IndexedSection(id: "\(sections.count)-\(label)", label: label, items: [item]))
        }
    }
    return sections
}

@MainActor
enum ArtMemory {
    static let cache = NSCache<NSString, UIImage>()
}

struct ArtView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.displayScale) private var displayScale
    let item: ArtItem?
    var size: CGFloat?
    var circle = false
    var placeholder = "music.note"
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: placeholder)
                    .font(.system(size: (size ?? 150) / 3))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .aspectRatio(1, contentMode: .fit)
        .clipShape(
            circle ? AnyShape(.circle) : AnyShape(.rect(cornerRadius: (size ?? 150) > 100 ? 8 : 4))
        )
        .accessibilityHidden(true)
        .task(id: item) { image = await load() }
    }

    private func load() async -> UIImage? {
        guard let item, let art = model.art else { return nil }
        let pixels = size.map { Int($0 * displayScale) } ?? ArtCache.width
        let key = "\(item.id)-\(item.tag)-\(pixels)" as NSString
        if let hit = ArtMemory.cache.object(forKey: key) { return hit }
        do {
            guard let full = UIImage(data: try await art.image(item)) else { return nil }
            let scale = CGFloat(pixels) / min(full.size.width, full.size.height)
            let image =
                scale < 1
                ? await full.byPreparingThumbnail(
                    ofSize: CGSize(width: full.size.width * scale, height: full.size.height * scale)
                )
                    ?? full
                : full
            ArtMemory.cache.setObject(image, forKey: key)
            return image
        } catch {
            Log.art.error(
                "Art for \(item.id, privacy: .public) failed: \(String(describing: error), privacy: .public)"
            )
            return nil
        }
    }
}

struct AlbumMenu: ViewModifier {
    @Environment(\.navigate) private var navigate
    let album: Album
    var artistMenu = true

    func body(content: Content) -> some View {
        content.contextMenu {
            PlayActions(albumIds: [album.id])
            if artistMenu, let artistId = album.artistId {
                Button("Go to Artist", systemImage: "music.mic") { navigate(.artist(artistId)) }
            }
        }
    }
}

struct PlayActions: View {
    @Environment(AppModel.self) private var model
    @Environment(Player.self) private var player
    let albumIds: [String]

    var body: some View {
        Section {
            Button("Play", systemImage: "play") { load { player.play($0) } }
            Button("Shuffle", systemImage: "shuffle") { load { player.play($0, shuffled: true) } }
            Button("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") {
                load { player.playNext($0) }
            }
            Button("Add to Queue", systemImage: "text.line.last.and.arrowtriangle.forward") {
                load { player.add($0) }
            }
        }
    }

    private func load(_ action: @escaping @MainActor ([TrackHit]) -> Void) {
        Task { action(await model.albumTracks(albumIds)) }
    }
}

struct TrackActions: View {
    @Environment(Player.self) private var player
    let hit: TrackHit

    var body: some View {
        Section {
            Button("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") {
                player.playNext([hit])
            }
            Button("Add to Queue", systemImage: "text.line.last.and.arrowtriangle.forward") {
                player.add([hit])
            }
        }
    }
}

struct AlbumTile: View {
    let album: Album
    let subtitle: String
    var size: CGFloat?

    var body: some View {
        NavigationLink(value: Route.album(album.id)) {
            VStack(alignment: .leading, spacing: 2) {
                ArtView(item: album.art, size: size)
                    .padding(.bottom, 6)
                Text(album.name).lineLimit(1)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(width: size, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .modifier(AlbumMenu(album: album))
        .accessibilityIdentifier("album-\(album.id)")
    }
}

struct AlbumRow: View {
    let album: Album
    let subtitle: String
    var artistMenu = true

    var body: some View {
        NavigationLink(value: Route.album(album.id)) {
            HStack(spacing: 12) {
                ArtView(item: album.art, size: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(album.name).lineLimit(1)
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .modifier(AlbumMenu(album: album, artistMenu: artistMenu))
        .accessibilityIdentifier("album-\(album.id)")
    }
}

struct ArtistRow: View {
    let artist: ArtistSummary

    var body: some View {
        NavigationLink(value: Route.artist(artist.id)) {
            HStack(spacing: 12) {
                ArtView(item: artist.art, size: 56, circle: true, placeholder: "music.mic")
                VStack(alignment: .leading, spacing: 2) {
                    Text(artist.name).lineLimit(1)
                    Text(artist.albumsText).font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityIdentifier("artist-\(artist.id)")
    }
}

struct TrackHitRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.navigate) private var navigate
    @Environment(Player.self) private var player
    let hit: TrackHit

    var body: some View {
        Button {
            navigate(.album(hit.album.id))
            Task {
                let hits = await model.albumTracks([hit.album.id])
                player.play(hits, from: hits.firstIndex { $0.track.id == hit.track.id })
            }
        } label: {
            HStack(spacing: 12) {
                ArtView(item: hit.album.art, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(hit.track.name).lineLimit(1)
                    Text("\(hit.track.artistName) · \(hit.album.name)")
                        .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Text(timeText(hit.track.duration)).monospacedDigit().foregroundStyle(.secondary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .contextMenu {
            TrackActions(hit: hit)
            Button("Go to Album", systemImage: "square.stack") { navigate(.album(hit.album.id)) }
            if let artistId = hit.album.artistId {
                Button("Go to Artist", systemImage: "music.mic") { navigate(.artist(artistId)) }
            }
        }
        .accessibilityIdentifier("track-\(hit.track.id)")
    }
}
