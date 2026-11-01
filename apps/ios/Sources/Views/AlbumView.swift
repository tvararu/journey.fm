import JourneyKit
import SwiftUI

struct AlbumView: View {
    @Environment(AppModel.self) private var model
    @Environment(Player.self) private var player
    @Environment(\.navigate) private var navigate
    let id: String
    @State private var detail: AlbumDetail?
    @State private var confirmRemove = false

    var body: some View {
        Group {
            if let detail {
                content(detail)
            } else {
                ProgressView()
            }
        }
        .toolbar {
            if let downloads = model.downloads, let detail {
                ToolbarItem {
                    if detail.tracks.allSatisfy({ downloads.state(of: $0.id) != nil }) {
                        Button("Remove Download", systemImage: "arrow.down.circle.fill") {
                            confirmRemove = true
                        }
                        .confirmationDialog(
                            "Remove the download of \(detail.album.name)?",
                            isPresented: $confirmRemove, titleVisibility: .visible
                        ) {
                            Button("Remove Download", role: .destructive) {
                                Task { await downloads.remove(albumIds: [id]) }
                            }
                        }
                    } else {
                        Button("Download", systemImage: "arrow.down.circle") {
                            Task { await downloads.save(albumIds: [id]) }
                        }
                    }
                }
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
        let hits = detail.tracks.map { TrackHit(track: $0, album: album) }
        let row = { (track: Track) in
            TrackRow(track: track, album: album) {
                player.play(hits, from: hits.firstIndex { $0.track.id == track.id })
            }
        }
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
            if let downloads = model.downloads,
                let fraction = downloads.albumProgress(detail.tracks.map(\.id))
            {
                let wanted = detail.tracks.filter { downloads.state(of: $0.id) != nil }
                let saved = wanted.filter { downloads.state(of: $0.id) == .saved }
                ProgressView(value: fraction) {
                    Text("Downloading \(saved.count) of \(wanted.count)")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .listRowSeparator(.hidden)
                .accessibilityIdentifier("album-download-progress")
            }
            PlayButtons(
                play: { player.play(hits) }, shuffle: { player.play(hits, shuffled: true) }
            )
            .listRowSeparator(.hidden)
            if discs.count > 1 {
                ForEach(discs.keys.sorted(), id: \.self) { disc in
                    Section {
                        ForEach(discs[disc] ?? []) { row($0) }
                    } header: {
                        Label("Disc \(disc)", systemImage: "opticaldisc")
                    }
                }
            } else {
                Section {
                    ForEach(detail.tracks) { row($0) }
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

struct PlayButtons: View {
    let play: () -> Void
    let shuffle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: play) {
                Label("Play", systemImage: "play.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            Button(action: shuffle) {
                Label("Shuffle", systemImage: "shuffle").frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
        }
        .labelStyle(.titleAndIcon)
        .controlSize(.large)
        .buttonBorderShape(.capsule)
    }
}

struct TrackRow: View {
    @Environment(AppModel.self) private var model
    @Environment(Player.self) private var player
    let track: Track
    let album: Album
    let play: () -> Void
    @State private var offerDownload = false

    var body: some View {
        let playing = player.current?.track.id == track.id
        let played = !playing && player.queue.played.contains(track.id)
        let state = model.downloads?.state(of: track.id)
        let away = model.offline && state != .saved && !model.isOnPhone(track)
        Button {
            if away { offerDownload = true } else { play() }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Group {
                    if playing {
                        Image(systemName: "speaker.wave.2.fill")
                            .symbolEffect(.variableColor.iterative, isActive: player.isPlaying)
                            .foregroundStyle(.tint)
                    } else {
                        Text(track.number.map(String.init) ?? "")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(minWidth: 22, alignment: .trailing)
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.name).lineLimit(2)
                        .foregroundStyle(
                            playing
                                ? AnyShapeStyle(.tint)
                                : away
                                    ? AnyShapeStyle(.tertiary)
                                    : AnyShapeStyle(played ? .secondary : .primary))
                    if !track.artistName.isEmpty && track.artistName != album.artistName {
                        Text(track.artistName)
                            .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer()
                DownloadIndicator(state: state)
                Text(timeText(track.duration)).monospacedDigit()
                    .foregroundStyle(away ? .tertiary : .secondary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .confirmationDialog(
            "\(track.name) isn't on this iPhone.", isPresented: $offerDownload,
            titleVisibility: .visible
        ) {
            Button("Download When Online") {
                Task { await model.downloads?.save(trackIds: [track.id]) }
            }
        }
        .swipeActions(edge: .leading) {
            Button("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") {
                player.playNext([TrackHit(track: track, album: album)])
            }
            .tint(.accentColor)
        }
        .swipeActions(edge: .trailing) {
            Button("Add to Queue", systemImage: "text.line.last.and.arrowtriangle.forward") {
                player.add([TrackHit(track: track, album: album)])
            }
            .tint(.indigo)
        }
        .contextMenu { TrackActions(hit: TrackHit(track: track, album: album)) }
        .accessibilityElement(children: .combine)
        .accessibilityValue(
            [
                playing ? "Now playing" : played ? "Played" : nil,
                DownloadIndicator.text(state), away ? "Not on this iPhone" : nil,
            ].compactMap(\.self).joined(separator: ", ")
        )
        .accessibilityIdentifier("track-\(track.id)")
    }
}

struct ArtistView: View {
    @Environment(AppModel.self) private var model
    @Environment(Player.self) private var player
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
            PlayButtons(
                play: { load(shuffled: false) }, shuffle: { load(shuffled: true) }
            )
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

    private func load(shuffled: Bool) {
        guard let detail else { return }
        Task {
            player.play(await model.albumTracks(detail.albums.map(\.id)), shuffled: shuffled)
        }
    }
}
