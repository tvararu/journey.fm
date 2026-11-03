import JourneyKit
import SwiftUI

struct LyricsPanel<Header: View>: View {
    @Environment(Player.self) private var player
    let lyrics: Lyrics
    @ViewBuilder var header: Header
    @State private var heldAt: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 28)
                .padding(.vertical, 8)
            if lyrics.synced {
                synced
            } else {
                plain
            }
        }
    }

    private var synced: some View {
        let current = lyrics.current(at: player.position + 0.2)
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(Array(lyrics.lines.enumerated()), id: \.offset) { index, line in
                        Button {
                            heldAt = nil
                            player.seek(to: line.time ?? 0)
                        } label: {
                            Text(line.text.isEmpty ? "♪" : line.text)
                                .font(.system(size: 30, weight: .bold))
                                .foregroundStyle(style(index, current: current))
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .id(index)
                        .accessibilityAddTraits(index == current ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 24)
                .padding(.bottom, 240)
            }
            .scrollIndicators(.hidden)
            .mask(Self.fade)
            .onScrollPhaseChange { _, phase in
                if phase.isScrolling { heldAt = .now }
            }
            .onAppear { proxy.scrollTo(current ?? 0, anchor: UnitPoint(x: 0, y: 0.15)) }
            .onChange(of: current) {
                guard let current, heldAt.map({ Date.now.timeIntervalSince($0) > 3 }) ?? true
                else { return }
                withAnimation(.smooth(duration: 0.5)) {
                    proxy.scrollTo(current, anchor: UnitPoint(x: 0, y: 0.15))
                }
            }
        }
        .accessibilityIdentifier("lyrics")
    }

    private func style(_ index: Int, current: Int?) -> AnyShapeStyle {
        guard let current else { return AnyShapeStyle(.secondary) }
        if index == current { return AnyShapeStyle(.primary) }
        return index < current ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.secondary)
    }

    private var plain: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Not Synced")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                ForEach(Array(lyrics.lines.enumerated()), id: \.offset) { _, line in
                    Text(line.text.isEmpty ? " " : line.text)
                        .font(.title2.weight(.bold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 16)
        }
        .scrollIndicators(.hidden)
        .mask(Self.fade)
        .accessibilityIdentifier("lyrics")
    }

    static var fade: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0), .init(color: .black, location: 0.06),
                .init(color: .black, location: 0.9), .init(color: .clear, location: 1),
            ], startPoint: .top, endPoint: .bottom)
    }
}
