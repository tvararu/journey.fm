import JourneyKit
import SwiftUI

struct AlbumView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.navigate) private var navigate
    let id: String
    @State private var detail: AlbumDetail?

    var body: some View {
        Group {
            if let detail {
                content(detail)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(detail?.album.name ?? "")
        .toolbarTitleDisplayMode(.inline)
        .toolbar(removing: .title)
        .task(id: id) { await watch(model.library.observeAlbum(id: id)) { detail = $0 } }
    }

    private func content(_ detail: AlbumDetail) -> some View {
        let album = detail.album
        let discs = Dictionary(grouping: detail.tracks) { $0.disc ?? 1 }
        return List {
            VStack(spacing: 4) {
                ArtView(item: album.art, size: 270)
                    .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
                    .padding(.bottom, 12)
                Text(album.name)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                artists(detail)
                Text(album.meta).lineLimit(1)
                    .font(.subheadline).foregroundStyle(.secondary)
                Text(album.counts)
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .listRowSeparator(.hidden)
            if discs.count > 1 {
                ForEach(discs.keys.sorted(), id: \.self) { disc in
                    Section {
                        ForEach(discs[disc] ?? []) { TrackRow(track: $0, album: album) }
                    } header: {
                        Label("Disc \(disc)", systemImage: "opticaldisc")
                    }
                }
            } else {
                Section {
                    ForEach(detail.tracks) { TrackRow(track: $0, album: album) }
                }
            }
            if let artist = detail.artists.first, !detail.more.isEmpty {
                Section("More by \(artist.name)") {
                    ScrollView(.horizontal) {
                        LazyHStack(alignment: .top, spacing: 12) {
                            ForEach(detail.more) { other in
                                AlbumTile(
                                    album: other, subtitle: other.year.map(String.init) ?? "",
                                    size: 130)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .contentMargins(.horizontal, 16, for: .scrollContent)
                    .scrollTargetBehavior(.viewAligned)
                    .scrollIndicators(.hidden)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .listRowSeparator(.hidden)
                }
            }
        }
        .listStyle(.plain)
    }

    @ViewBuilder private func artists(_ detail: AlbumDetail) -> some View {
        switch detail.artists.count {
        case 0:
            Text(detail.album.artistName).font(.title3)
        case 1:
            Button(detail.artists[0].name) { navigate(.artist(detail.artists[0].id)) }
                .font(.title3)
                .buttonStyle(.borderless)
                .accessibilityIdentifier("album-artist")
        default:
            Menu(detail.album.artistName) {
                ForEach(detail.artists) { artist in
                    Button(artist.name) { navigate(.artist(artist.id)) }
                }
            }
            .font(.title3)
            .buttonStyle(.borderless)
            .accessibilityIdentifier("album-artist")
        }
    }
}

struct TrackRow: View {
    let track: Track
    let album: Album

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(track.number.map(String.init) ?? "")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: 22, alignment: .trailing)
            VStack(alignment: .leading, spacing: 2) {
                Text(track.name).lineLimit(2)
                if !track.artistName.isEmpty && track.artistName != album.artistName {
                    Text(track.artistName)
                        .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            Text(timeText(track.duration)).monospacedDigit().foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

struct ArtistView: View {
    @Environment(AppModel.self) private var model
    let id: String
    @State private var detail: ArtistDetail?

    var body: some View {
        Group {
            if let detail {
                content(detail)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(detail?.artist.name ?? "")
        .toolbarTitleDisplayMode(.inline)
        .toolbar(removing: .title)
        .task(id: id) { await watch(model.library.observeArtist(id: id)) { detail = $0 } }
    }

    private func content(_ detail: ArtistDetail) -> some View {
        let artist = detail.artist
        return List {
            VStack(spacing: 4) {
                ArtView(item: artist.art, size: 120, circle: true, placeholder: "music.mic")
                    .padding(.bottom, 12)
                Text(artist.name)
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                Text([artist.albumsText, artist.span].compactMap(\.self).joined(separator: " · "))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .listRowSeparator(.hidden)
            Section(detail.albums.count == 1 ? "Album" : "Albums") {
                ForEach(detail.albums) { album in
                    AlbumRow(
                        album: album,
                        subtitle: [album.year.map(String.init), tracksText(album.trackCount)]
                            .compactMap(\.self).joined(separator: " · "),
                        artistMenu: false)
                }
            }
        }
        .listStyle(.plain)
    }
}
