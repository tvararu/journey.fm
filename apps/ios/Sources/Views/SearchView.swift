import JourneyKit
import SwiftUI

struct SearchView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("search.recent") private var recentText = ""
    @Binding var path: [Route]
    @State private var query = ""
    @State private var results = SearchResults()

    var body: some View {
        TabStack(path: $path) {
            content
                .navigationTitle("Search")
                .searchable(
                    text: $query, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Artists, Albums and Tracks"
                )
                .task(id: query) {
                    try? await Task.sleep(for: .milliseconds(150))
                    guard !Task.isCancelled else { return }
                    results = (try? await model.library.search(query)) ?? SearchResults()
                }
                .onChange(of: path) { old, new in
                    if new.count > old.count { remember(query) }
                }
        }
    }

    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }

    private var recent: [String] { recentText.split(separator: "\n").map(String.init) }

    @ViewBuilder private var content: some View {
        if trimmed.isEmpty {
            if recent.isEmpty {
                ContentUnavailableView(
                    "Search Your Library", systemImage: "magnifyingglass",
                    description: Text("Artists, albums and tracks, searched on this iPhone."))
            } else {
                List {
                    Section {
                        ForEach(recent, id: \.self) { text in
                            Button(text) { query = text }
                                .accessibilityIdentifier("recent-\(text)")
                        }
                    } header: {
                        HStack {
                            Text("Recent Searches")
                            Spacer()
                            Button("Clear") { recentText = "" }
                                .accessibilityIdentifier("clear-recent")
                        }
                    }
                }
                .listStyle(.plain)
            }
        } else if results.isEmpty {
            ContentUnavailableView.search(text: trimmed)
        } else {
            List {
                if !results.artists.isEmpty {
                    Section("Artists") {
                        ForEach(results.artists.prefix(3)) { ArtistRow(artist: $0) }
                        seeAll(results.artists.count, "Artists", 3, .searchArtists(trimmed))
                    }
                }
                if !results.albums.isEmpty {
                    Section("Albums") {
                        ForEach(results.albums.prefix(4)) { album in
                            AlbumRow(album: album, subtitle: searchSubtitle(album))
                        }
                        seeAll(results.albums.count, "Albums", 4, .searchAlbums(trimmed))
                    }
                }
                if !results.tracks.isEmpty {
                    Section("Tracks") {
                        ForEach(results.tracks.prefix(4)) { TrackHitRow(hit: $0) }
                        seeAll(results.tracks.count, "Tracks", 4, .searchTracks(trimmed))
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    @ViewBuilder
    private func seeAll(_ count: Int, _ noun: String, _ shown: Int, _ route: Route) -> some View {
        if count > shown {
            NavigationLink("See All \(count) \(noun)", value: route)
                .foregroundStyle(.tint)
                .accessibilityIdentifier("see-all-\(noun)")
        }
    }

    private func remember(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        recentText = ([text] + recent.filter { $0 != text }).prefix(8).joined(separator: "\n")
    }
}

func searchSubtitle(_ album: Album) -> String {
    [album.artistName, album.year.map(String.init)].compactMap(\.self).joined(separator: " · ")
}

struct SearchAllView: View {
    enum Kind {
        case artists, albums, tracks
    }

    @Environment(AppModel.self) private var model
    let query: String
    let kind: Kind
    @State private var results = SearchResults()

    var body: some View {
        List {
            switch kind {
            case .artists: ForEach(results.artists) { ArtistRow(artist: $0) }
            case .albums:
                ForEach(results.albums) { AlbumRow(album: $0, subtitle: searchSubtitle($0)) }
            case .tracks: ForEach(results.tracks) { TrackHitRow(hit: $0) }
            }
        }
        .listStyle(.plain)
        .navigationTitle(title)
        .task { results = (try? await model.library.search(query)) ?? SearchResults() }
    }

    private var title: String {
        switch kind {
        case .artists: "Artists"
        case .albums: "Albums"
        case .tracks: "Tracks"
        }
    }
}
