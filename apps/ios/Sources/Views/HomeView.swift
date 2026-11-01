import JourneyKit
import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Binding var path: [Route]
    @State private var played: [Album] = []
    @State private var recent: [Album] = []
    @State private var random: [Album] = []
    @State private var showSettings = false

    var body: some View {
        TabStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if !played.isEmpty {
                        Shelf(title: "Recently Played", albums: played, route: .recentlyPlayed)
                    }
                    Shelf(title: "Recently Added", albums: recent, route: .recentlyAdded)
                    Shelf(title: "Random Albums", albums: random, route: nil)
                }
                .padding(.vertical)
            }
            .navigationTitle("Home")
            .navigationSubtitle(model.syncStatus)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape") { showSettings = true }
                        .accessibilityIdentifier("settings")
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .refreshable {
                await reroll()
                await model.sync()
            }
            .task { await watch(model.library.observeRecentlyPlayed(limit: 20)) { played = $0 } }
            .task { await watch(model.library.observeRecentAlbums(limit: 20)) { recent = $0 } }
            .task(id: model.stats.albums) { if random.isEmpty { await reroll() } }
        }
    }

    private func reroll() async {
        random = (try? await model.library.randomAlbums(limit: 12)) ?? random
    }
}

struct Shelf: View {
    let title: String
    let albums: [Album]
    let route: Route?

    var body: some View {
        let repeats = repeated(albums)
        VStack(alignment: .leading, spacing: 10) {
            Group {
                if let route {
                    NavigationLink(value: route) {
                        HStack(spacing: 6) {
                            Text(title)
                            Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("shelf-\(title)")
                } else {
                    Text(title)
                }
            }
            .font(.title2.bold())
            .padding(.horizontal)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(albums) { album in
                        AlbumTile(
                            album: album,
                            subtitle: album.subtitle([album.artistName], repeats: repeats),
                            size: 150)
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, 16, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
        }
    }
}

struct RecentlyAddedView: View {
    @Environment(AppModel.self) private var model
    @State private var albums: [Album] = []

    var body: some View {
        AlbumGrid(albums: albums) { EmptyView() }
            .navigationTitle("Recently Added")
            .task { await watch(model.library.observeAlbums(sort: .added)) { albums = $0 } }
    }
}

struct RecentlyPlayedView: View {
    @Environment(AppModel.self) private var model
    @State private var albums: [Album] = []

    var body: some View {
        AlbumGrid(albums: albums) { EmptyView() }
            .navigationTitle("Recently Played")
            .task { await watch(model.library.observeRecentlyPlayed(limit: 200)) { albums = $0 } }
    }
}

struct AlbumGrid<Header: View>: View {
    let albums: [Album]
    @ViewBuilder var header: Header

    var body: some View {
        let repeats = repeated(albums)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16),
                    ],
                    spacing: 20
                ) {
                    ForEach(albums) { album in
                        AlbumTile(
                            album: album,
                            subtitle: album.subtitle([album.artistName], repeats: repeats))
                    }
                }
            }
            .padding(.horizontal)
        }
    }
}
