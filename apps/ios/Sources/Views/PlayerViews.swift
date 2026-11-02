import AVKit
import JourneyKit
import MediaPlayer
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
    @State private var showingQueue = false

    var body: some View {
        Group {
            if let entry = player.current {
                content(entry)
            } else {
                Color.clear.onAppear { dismiss() }
            }
        }
        .environment(\.colorScheme, .dark)
    }

    private func content(_ entry: QueueEntry) -> some View {
        VStack(spacing: 0) {
            Button("Close") { dismiss() }
                .buttonStyle(Grabber())
                .accessibilityIdentifier("now-playing-close")
            ZStack {
                if showingQueue {
                    QueuePanel { header(entry) }
                        .transition(.opacity)
                } else {
                    VStack(spacing: 0) {
                        Spacer(minLength: 12)
                        ArtView(item: entry.album.art)
                            .shadow(color: .black.opacity(0.35), radius: 20, y: 10)
                            .scaleEffect(player.isPlaying ? 1 : 0.73)
                            .animation(
                                player.isPlaying
                                    ? .spring(duration: 0.5, bounce: 0.3) : .spring(duration: 0.5),
                                value: player.isPlaying
                            )
                            .padding(.horizontal, 24)
                        Spacer(minLength: 12)
                        titleRow(entry).padding(.horizontal, 28)
                    }
                    .transition(.opacity)
                }
            }
            .frame(maxHeight: .infinity)
            controls(entry)
                .padding(.horizontal, 28)
                .padding(.top, 20)
        }
        .padding(.bottom, 8)
        .background { Backdrop(art: entry.album.art) }
    }

    private func titleRow(_ entry: QueueEntry) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.track.name).font(.title3.weight(.semibold)).lineLimit(1)
                Text(entry.track.artistName).font(.title3).foregroundStyle(.secondary)
                    .lineLimit(1)
                if let failure = player.failure {
                    Text(failure).font(.subheadline).foregroundStyle(.red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("now-playing-title")
            more(entry)
        }
    }

    private func header(_ entry: QueueEntry) -> some View {
        HStack(spacing: 12) {
            ArtView(item: entry.album.art, size: 64)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.track.name).font(.headline).lineLimit(1)
                Text(entry.track.artistName).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("now-playing-title")
            more(entry)
        }
    }

    private func more(_ entry: QueueEntry) -> some View {
        Menu {
            TrackDownloadActions(track: entry.track)
            Section {
                Button {
                    open(.album(entry.album.id))
                } label: {
                    Label("Go to Album", systemImage: "square.stack")
                    Text(entry.album.name)
                }
                if let artistId = entry.album.artistId {
                    Button {
                        open(.artist(artistId))
                    } label: {
                        Label("Go to Artist", systemImage: "music.mic")
                        Text(entry.album.artistName)
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.title3.weight(.semibold))
                .frame(width: 36, height: 36)
                .contentShape(.rect)
                .accessibilityLabel("More")
        }
        .buttonStyle(.plain)
        .menuOrder(.fixed)
        .accessibilityIdentifier("now-playing-more")
    }

    private func controls(_ entry: QueueEntry) -> some View {
        let duration = max(player.duration, 1)
        let elapsed = min(scrub ?? player.position, duration)
        return VStack(spacing: 22) {
            VStack(spacing: 6) {
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
                .sliderThumbVisibility(.hidden)
                .tint(.white.opacity(0.8))
                .accessibilityValue(timeText(elapsed))
                HStack {
                    Text(timeText(elapsed)).accessibilityIdentifier("elapsed")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if entry.track.isLossless {
                        Label("Lossless", systemImage: "waveform")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.white.opacity(0.12), in: .rect(cornerRadius: 4))
                    }
                    Text("-" + timeText(duration - elapsed))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
            HStack {
                Button("Previous", systemImage: "backward.fill") { player.previous() }
                    .frame(maxWidth: .infinity)
                Button(
                    player.isPlaying ? "Pause" : "Play",
                    systemImage: player.isPlaying ? "pause.fill" : "play.fill"
                ) { player.toggle() }
                .contentTransition(.symbolEffect(.replace))
                .font(.system(size: 52))
                .frame(maxWidth: .infinity)
                Button("Next", systemImage: "forward.fill") { player.next() }
                    .frame(maxWidth: .infinity)
            }
            .font(.system(size: 36))
            .labelStyle(.iconOnly)
            .buttonStyle(TransportButton())
            HStack(spacing: 10) {
                Image(systemName: "speaker.fill")
                VolumeSlider().frame(height: 30)
                Image(systemName: "speaker.wave.3.fill")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .contain)
            HStack {
                Color.clear.frame(width: 44, height: 44).frame(maxWidth: .infinity)
                RoutePicker().frame(width: 44, height: 44).accessibilityLabel("AirPlay")
                    .frame(maxWidth: .infinity)
                Button("Queue", systemImage: "list.bullet") {
                    withAnimation(.spring(duration: 0.4)) { showingQueue.toggle() }
                }
                .labelStyle(.iconOnly)
                .font(.title3)
                .foregroundStyle(showingQueue ? AnyShapeStyle(.black) : AnyShapeStyle(.secondary))
                .frame(width: 40, height: 40)
                .background(showingQueue ? Color.white.opacity(0.85) : .clear, in: .circle)
                .accessibilityAddTraits(showingQueue ? .isSelected : [])
                .accessibilityIdentifier("now-playing-queue")
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
        }
    }
}

struct Backdrop: View {
    let art: ArtItem?

    var body: some View {
        Color.black
            .overlay {
                ArtView(item: art)
                    .scaleEffect(3)
                    .blur(radius: 60)
                    .saturation(1.4)
                    .opacity(0.7)
            }
            .overlay(Color.black.opacity(0.25))
            .clipped()
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}

struct VolumeSlider: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView()
        let thumb = UIGraphicsImageRenderer(size: CGSize(width: 12, height: 12)).image { _ in
            UIColor.white.setFill()
            UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: 12, height: 12)).fill()
        }
        view.setVolumeThumbImage(thumb, for: .normal)
        view.tintColor = .white.withAlphaComponent(0.8)
        return view
    }

    func updateUIView(_ view: MPVolumeView, context: Context) {}
}

extension Track {
    var isLossless: Bool {
        ["flac", "alac", "wav", "aiff"].contains(container?.lowercased() ?? "")
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

struct QueuePanel<Header: View>: View {
    @Environment(AppModel.self) private var model
    @Environment(Player.self) private var player
    @ViewBuilder var header: Header
    @State private var history: [TrackHit] = []
    @State private var loaded = false

    var body: some View {
        let upNext = Array(player.queue.upNext)
        ScrollViewReader { proxy in
            List {
                if !history.isEmpty {
                    Section {
                        ForEach(history) { hit in
                            Button {
                                player.playNow(hit)
                            } label: {
                                QueueRow(entry: QueueEntry(hit), playing: false)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Color.clear)
                        }
                    } header: {
                        heading("History") { player.clearHistory() }
                    }
                }
                Section {
                    header
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .id("current")
                }
                Section {
                    ForEach(upNext) { entry in
                        row(entry)
                            .contextMenu {
                                Button("Remove", systemImage: "minus.circle", role: .destructive) {
                                    remove(entry, from: upNext)
                                }
                            }
                    }
                    .onMove { player.moveUpNext(fromOffsets: $0, toOffset: $1) }
                    if upNext.isEmpty {
                        Text("Nothing up next").foregroundStyle(.secondary)
                            .listRowBackground(Color.clear)
                    }
                } header: {
                    VStack(spacing: 14) {
                        HStack(spacing: 10) {
                            modeButton(
                                "Shuffle", systemImage: "shuffle", on: player.queue.shuffle
                            ) { player.setShuffle(!player.queue.shuffle) }
                            modeButton(
                                repeatLabel,
                                systemImage: player.queue.repeatMode == .one
                                    ? "repeat.1" : "repeat",
                                on: player.queue.repeatMode != .off
                            ) { player.cycleRepeat() }
                        }
                        heading("Up Next", clear: upNext.isEmpty ? nil : { player.clearUpNext() })
                    }
                    .padding(.top, 4)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .contentMargins(.horizontal, 12, for: .scrollContent)
            .environment(\.editMode, .constant(.active))
            .task(id: player.current?.id) {
                await watch(model.library.observeHistory(excluding: player.current?.id)) {
                    history = $0
                    loaded = true
                }
            }
            .onChange(of: loaded) { proxy.scrollTo("current", anchor: .top) }
        }
    }

    private func row(_ entry: QueueEntry) -> some View {
        Button {
            player.jump(to: entry.id)
        } label: {
            QueueRow(entry: entry, playing: false)
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
    }

    private func heading(_ title: String, clear: (() -> Void)?) -> some View {
        HStack {
            Text(title).font(.headline).foregroundStyle(.primary)
            Spacer()
            if let clear {
                Button("Clear", action: clear)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Clear \(title)")
            }
        }
        .textCase(nil)
    }

    private func modeButton(
        _ title: String, systemImage: String, on: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 34)
                .foregroundStyle(on ? AnyShapeStyle(.black) : AnyShapeStyle(.primary))
                .background(
                    on ? Color.white.opacity(0.85) : Color.white.opacity(0.15), in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var repeatLabel: String {
        switch player.queue.repeatMode {
        case .off: "Repeat Off"
        case .all: "Repeat All"
        case .one: "Repeat One"
        }
    }

    private func remove(_ entry: QueueEntry, from upNext: [QueueEntry]) {
        guard let offset = upNext.firstIndex(where: { $0.id == entry.id }) else { return }
        player.removeUpNext(atOffsets: [offset])
    }
}

struct TransportButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.85 : 1)
            .padding(14)
            .background(.white.opacity(configuration.isPressed ? 0.18 : 0), in: .circle)
            .contentShape(.circle)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
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
