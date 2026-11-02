import JourneyKit
import SwiftUI

enum LibraryKind: String {
    case albums, artists
}

struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("library.kind") private var kind = LibraryKind.albums
    @AppStorage("library.sort") private var sort = AlbumSort.artist
    @AppStorage("library.grid") private var grid = true
    @Binding var path: [Route]
    @State private var albums: [Album] = []
    @State private var artists: [ArtistSummary] = []

    var body: some View {
        TabStack(path: $path) {
            content
                .navigationTitle("Library")
                .toolbar {
                    if kind == .albums {
                        ToolbarItemGroup(placement: .topBarTrailing) {
                            Menu {
                                Picker("Sort By", selection: $sort) {
                                    Text("Title").tag(AlbumSort.title)
                                    Text("Artist").tag(AlbumSort.artist)
                                    Text("Year").tag(AlbumSort.year)
                                    Text("Recently Added").tag(AlbumSort.added)
                                }
                            } label: {
                                Label("Sort", systemImage: "arrow.up.arrow.down")
                            }
                            .accessibilityIdentifier("sort")
                            Button(
                                grid ? "Show as List" : "Show as Grid",
                                systemImage: grid ? "list.bullet" : "square.grid.2x2"
                            ) { grid.toggle() }
                            .accessibilityIdentifier("layout")
                        }
                    }
                }
                .refreshable { await model.sync() }
                .task(id: sort) {
                    await watch(model.library.observeAlbums(sort: sort)) { albums = $0 }
                }
                .task { await watch(model.library.observeArtists()) { artists = $0 } }
        }
    }

    @ViewBuilder private var content: some View {
        switch kind {
        case .albums where grid:
            AlbumGrid(albums: albums) { chips }
        case .albums:
            albumList
        case .artists:
            artistList
        }
    }

    private var chips: some View {
        HStack {
            chip("Albums", .albums)
            chip("Artists", .artists)
        }
    }

    @ViewBuilder private func chip(_ title: String, _ value: LibraryKind) -> some View {
        if kind == value {
            Button(title) { kind = value }
                .buttonStyle(.borderedProminent)
                .accessibilityAddTraits(.isSelected)
                .accessibilityIdentifier("chip-\(value.rawValue)")
        } else {
            Button(title) { kind = value }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("chip-\(value.rawValue)")
        }
    }

    private var albumList: some View {
        let repeats = repeated(albums)
        return List {
            chips.buttonBorderShape(.capsule).listRowSeparator(.hidden)
            ForEach(indexed(albums, key: sectionKey)) { section in
                Section {
                    ForEach(section.items) { album in
                        AlbumRow(
                            album: album,
                            subtitle: album.subtitle(
                                [album.artistName, album.year.map(String.init)], repeats: repeats))
                    }
                } header: {
                    header(section.label)
                }
                .sectionIndexLabel(section.label)
            }
        }
        .listStyle(.plain)
        .listSectionIndexVisibility(sort == .added ? .hidden : .visible)
    }

    private var artistList: some View {
        List {
            chips.buttonBorderShape(.capsule).listRowSeparator(.hidden)
            ForEach(indexed(artists) { indexLetter($0.sortName) }) { section in
                Section {
                    ForEach(section.items) { ArtistRow(artist: $0) }
                } header: {
                    header(section.label)
                }
                .sectionIndexLabel(section.label)
            }
        }
        .listStyle(.plain)
        .listSectionIndexVisibility(.visible)
    }

    @ViewBuilder private func header(_ label: String) -> some View {
        if !label.isEmpty {
            Text(label)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.primary)
                .textCase(nil)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private func sectionKey(_ album: Album) -> String {
        switch sort {
        case .title: indexLetter(album.sortName)
        case .artist: indexLetter(album.artistSortName)
        case .year: album.year.map { String(format: "%02ds", $0 / 10 % 10 * 10) } ?? "#"
        case .added: ""
        }
    }
}
