import AVKit
import JourneyKit
import SwiftUI

struct MiniPlayer: View {
    @Environment(Player.self) private var player
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    let open: () -> Void

    var body: some View {
        if let entry = player.current {
            HStack(spacing: 12) {
                Button(action: open) {
                    HStack(spacing: 10) {
                        ArtView(item: entry.album.art, size: 32)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(entry.track.name).font(.subheadline.weight(.medium)).lineLimit(1)
                            if placement != .inline {
                                Text(entry.track.artistName)
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Now Playing, \(entry.track.name)")
                .accessibilityIdentifier("mini-player")
                PlayPauseButton()
                if placement != .inline {
                    Button("Next", systemImage: "forward.fill") { player.next() }
                }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .font(.title3)
            .padding(.horizontal, 14)
        }
    }
}

struct PlayPauseButton: View {
    @Environment(Player.self) private var player

    var body: some View {
        Button(
            player.isPlaying ? "Pause" : "Play",
            systemImage: player.isPlaying ? "pause.fill" : "play.fill"
        ) { player.toggle() }
        .contentTransition(.symbolEffect(.replace))
    }
}

struct NowPlayingView: View {
    @Environment(Player.self) private var player
    @Environment(\.dismiss) private var dismiss
    let open: (Route) -> Void
    @State private var scrub: Double?
    @State private var scrubbing = false
    @State private var showQueue = false

    var body: some View {
        Group {
            if let entry = player.current {
                content(entry)
            } else {
                Color.clear.onAppear { dismiss() }
            }
        }
        .sheet(isPresented: $showQueue) {
            QueueView().presentationDetents([.medium, .large])
        }
    }

    private func content(_ entry: QueueEntry) -> some View {
        let duration = max(player.duration, 1)
        let elapsed = min(scrub ?? player.position, duration)
        return VStack(spacing: 24) {
            HStack {
                Spacer()
                Menu("More", systemImage: "ellipsis") {
                    Button("Go to Album", systemImage: "square.stack") {
                        open(.album(entry.album.id))
                    }
                    if let artistId = entry.album.artistId {
                        Button("Go to Artist", systemImage: "music.mic") { open(.artist(artistId)) }
                    }
                    TrackDownloadActions(track: entry.track)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .accessibilityIdentifier("now-playing-more")
            }
            .overlay(alignment: .top) {
                Button("Close") { dismiss() }
                    .buttonStyle(Grabber())
                    .accessibilityIdentifier("now-playing-close")
            }
            ArtView(item: entry.album.art)
                .shadow(color: .black.opacity(0.2), radius: 16, y: 6)
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.track.name).font(.title2.bold()).lineLimit(2)
                Text("\(entry.track.artistName) · \(entry.album.name)")
                    .foregroundStyle(.secondary).lineLimit(1)
                if let failure = player.failure {
                    Text(failure).font(.subheadline).foregroundStyle(.red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("now-playing-title")
            VStack(spacing: 4) {
                Slider(
                    value: Binding {
                        elapsed
                    } set: {
                        if scrubbing { scrub = $0 } else { player.seek(to: $0) }
                    }, in: 0...duration
                ) {
                    Text("Position")
                } onEditingChanged: { editing in
                    scrubbing = editing
                    if !editing, let scrub {
                        player.seek(to: scrub)
                        self.scrub = nil
                    }
                }
                .accessibilityValue(timeText(elapsed))
                HStack {
                    Text(timeText(elapsed)).accessibilityIdentifier("elapsed")
                    Spacer()
                    Text("-" + timeText(duration - elapsed))
                }
                .font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Previous", systemImage: "backward.fill") { player.previous() }
                Spacer()
                PlayPauseButton().font(.system(size: 44))
                Spacer()
                Button("Next", systemImage: "forward.fill") { player.next() }
                Spacer()
            }
            .font(.largeTitle)
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            Spacer(minLength: 0)
            HStack {
                Toggle(
                    isOn: Binding {
                        player.queue.shuffle
                    } set: {
                        player.setShuffle($0)
                    }
                ) {
                    Label("Shuffle", systemImage: "shuffle")
                }
                .toggleStyle(.button)
                .foregroundStyle(
                    player.queue.shuffle ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                Spacer()
                Button(
                    repeatLabel,
                    systemImage: player.queue.repeatMode == .one ? "repeat.1" : "repeat"
                ) {
                    player.cycleRepeat()
                }
                .foregroundStyle(
                    player.queue.repeatMode == .off
                        ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
                Spacer()
                RoutePicker().frame(width: 44, height: 44).accessibilityLabel("AirPlay")
                Spacer()
                Button("Queue", systemImage: "list.bullet") { showQueue = true }
                    .foregroundStyle(.secondary)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .font(.title3)
        }
        .padding(.horizontal, 28)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    private var repeatLabel: String {
        switch player.queue.repeatMode {
        case .off: "Repeat Off"
        case .all: "Repeat All"
        case .one: "Repeat One"
        }
    }
}

struct Grabber: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Capsule()
            .fill(.tertiary)
            .frame(width: 36, height: 5)
            .padding(.vertical, 6)
            .padding(.horizontal, 24)
            .contentShape(.rect)
            .opacity(configuration.isPressed ? 0.5 : 1)
            .accessibilityLabel(Text("Close"))
    }
}

struct RoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = .secondaryLabel
        return view
    }

    func updateUIView(_ view: AVRoutePickerView, context: Context) {}
}

struct QueueView: View {
    @Environment(Player.self) private var player
    @State private var editMode = EditMode.inactive

    var body: some View {
        let upNext = Array(player.queue.upNext)
        NavigationStack {
            List {
                if let current = player.current {
                    Section("Now Playing") {
                        QueueRow(entry: current, playing: true)
                            .moveDisabled(true)
                            .deleteDisabled(true)
                    }
                }
                if !upNext.isEmpty {
                    Section("Up Next · \(tracksText(upNext.count))") {
                        ForEach(upNext) { entry in
                            Button {
                                player.jump(to: entry.id)
                            } label: {
                                QueueRow(entry: entry, playing: false)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing) {
                                Button("Remove", systemImage: "trash", role: .destructive) {
                                    remove(entry, from: upNext)
                                }
                            }
                        }
                        .onDelete { player.removeUpNext(atOffsets: $0) }
                        .onMove { player.moveUpNext(fromOffsets: $0, toOffset: $1) }
                    }
                }
            }
            .navigationTitle("Up Next")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Clear", role: .destructive) { player.clearUpNext() }
                        .disabled(upNext.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) { EditButton() }
            }
            .environment(\.editMode, $editMode)
        }
    }

    private func remove(_ entry: QueueEntry, from upNext: [QueueEntry]) {
        guard let offset = upNext.firstIndex(where: { $0.id == entry.id }) else { return }
        player.removeUpNext(atOffsets: [offset])
    }
}

struct QueueRow: View {
    @Environment(AppModel.self) private var model
    @Environment(Player.self) private var player
    let entry: QueueEntry
    let playing: Bool

    var body: some View {
        let away = model.offline && !model.isOnPhone(entry.track)
        HStack(spacing: 12) {
            ArtView(item: entry.album.art, size: 44)
                .opacity(away ? 0.4 : 1)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.track.name).lineLimit(1)
                        .foregroundStyle(
                            playing
                                ? AnyShapeStyle(.tint)
                                : AnyShapeStyle(away ? .tertiary : .primary))
                    if entry.playNext {
                        Text("Play Next").font(.caption.weight(.medium)).foregroundStyle(.tint)
                    }
                }
                Text(entry.missing ? "Skipped: not on this iPhone" : entry.track.artistName)
                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if playing {
                Image(systemName: "speaker.wave.2.fill")
                    .symbolEffect(.variableColor.iterative, isActive: player.isPlaying)
                    .foregroundStyle(.tint)
            } else {
                Text(timeText(entry.track.duration)).monospacedDigit().foregroundStyle(.secondary)
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityValue(away ? "Not on this iPhone" : "")
        .accessibilityIdentifier("queue-\(entry.track.id)")
    }
}
