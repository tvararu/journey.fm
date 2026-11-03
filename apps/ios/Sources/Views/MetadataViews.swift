import JourneyKit
import SwiftUI

struct SectionHeading: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.title3.weight(.semibold))
            .foregroundStyle(Color.primary)
            .textCase(nil)
            .accessibilityAddTraits(.isHeader)
    }
}

struct AlbumMetaLine: View {
    @Environment(\.navigate) private var navigate
    let detail: AlbumDetail
    let facts: AlbumFacts

    var body: some View {
        let text = [facts.releaseType, detail.album.year.map(String.init), detail.album.genres]
            .compactMap(\.self).filter { !$0.isEmpty }.joined(separator: " · ")
        Group {
            switch detail.genres.count {
            case 0:
                Text(text)
            case 1:
                Button(text) { navigate(.genre(detail.genres[0])) }
                    .accessibilityHint("Shows \(detail.genres[0]) albums")
            default:
                Menu(text) {
                    ForEach(detail.genres, id: \.self) { genre in
                        Button(genre) { navigate(.genre(genre)) }
                    }
                }
            }
        }
        .lineLimit(1)
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .buttonStyle(.borderless)
        .accessibilityIdentifier("album-meta")
    }
}

struct AlbumSections: View {
    let detail: AlbumDetail
    let facts: AlbumFacts

    var body: some View {
        if !facts.details.isEmpty {
            Section {
                ForEach(facts.details) { FactRow(fact: $0) }
            } header: {
                SectionHeading(title: "Details")
            }
            .accessibilityIdentifier("album-details")
        }
        let credits = creditSummary(detail.credits, tracks: detail.tracks)
        if !credits.isEmpty {
            Section {
                ForEach(credits) { credit in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(credit.name)
                        Text(credit.text).font(.subheadline).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            } header: {
                SectionHeading(title: "Credits")
            }
            .accessibilityIdentifier("album-credits")
        }
        if let rating = facts.rating {
            Section {
                if let url = facts.rymURL {
                    Link(destination: url) {
                        LabeledContent {
                            HStack(spacing: 6) {
                                Text(rating)
                                Image(systemName: "arrow.up.right").font(.footnote)
                            }
                            .foregroundStyle(.secondary)
                        } label: {
                            Text("RYM").foregroundStyle(.primary)
                        }
                    }
                    .accessibilityIdentifier("album-rym")
                } else {
                    LabeledContent("RYM", value: rating)
                }
                if let rank = facts.rank {
                    LabeledContent("Rank", value: rank)
                }
            } header: {
                SectionHeading(title: "Ratings")
            } footer: {
                if let fetched = facts.fetched {
                    Text("RYM rating fetched \(fetched).")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct FactRow: View {
    let fact: Fact

    var body: some View {
        if fact.value.count > 32 {
            VStack(alignment: .leading, spacing: 2) {
                Text(fact.label)
                Text(fact.value).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        } else {
            LabeledContent(fact.label, value: fact.value)
        }
    }
}

struct ExpandableText: View {
    let text: String
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(text)
                .lineLimit(expanded ? nil : 3)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if !expanded {
                Button("More") { withAnimation { expanded = true } }
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("overview-more")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CreditsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let hit: TrackHit
    @State private var credits: TrackCredits?

    static let groups: [(title: String, kinds: Set<String>)] = [
        ("Performers", ["Performer", "Conductor"]),
        ("Written By", ["Composer", "Lyricist", "Writer", "Arranger"]),
    ]

    var body: some View {
        NavigationStack {
            Group {
                if let credits {
                    if credits.credits.isEmpty && credits.isrc.isEmpty {
                        ContentUnavailableView("No Credits", systemImage: "person.2")
                    } else {
                        list(credits)
                    }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(hit.track.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("credits-done")
                }
            }
        }
        .task {
            credits =
                (try? await model.library.trackCredits(trackId: hit.track.id))
                ?? TrackCredits(credits: [], isrc: [])
        }
    }

    private func list(_ credits: TrackCredits) -> some View {
        let known = Self.groups.reduce(Set<String>()) { $0.union($1.kinds) }
        let sections =
            Self.groups.map {
                ($0.title, credits.credits.filter { [kinds = $0.kinds] in kinds.contains($0.kind) })
            }
            + [("Production and Engineering", credits.credits.filter { !known.contains($0.kind) })]
        return List {
            ForEach(sections, id: \.0) { title, credits in
                let people = Self.people(credits)
                if !people.isEmpty {
                    Section(title) {
                        ForEach(people, id: \.name) { person in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(person.name)
                                Text(person.reads).font(.subheadline).foregroundStyle(.secondary)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
            if !credits.isrc.isEmpty {
                Section("ISRC") {
                    ForEach(credits.isrc, id: \.self) { Text($0).monospaced() }
                }
            }
        }
        .accessibilityIdentifier("credits-list")
    }

    static func people(_ credits: [Credit]) -> [(name: String, reads: String)] {
        var order: [String] = []
        var reads: [String: [String]] = [:]
        for credit in credits {
            if reads[credit.name] == nil { order.append(credit.name) }
            if !reads[credit.name, default: []].contains(credit.reads) {
                reads[credit.name, default: []].append(credit.reads)
            }
        }
        return order.map { name in
            let text = reads[name]!.joined(separator: ", ")
            return (name, text.prefix(1).uppercased() + text.dropFirst())
        }
    }
}

struct GenreView: View {
    @Environment(AppModel.self) private var model
    @Environment(Player.self) private var player
    @AppStorage("library.grid") private var grid = true
    let name: String
    @State private var albums: [Album] = []

    var body: some View {
        Group {
            if grid {
                AlbumGrid(albums: albums) { buttons.padding(.top, 8) }
            } else {
                let repeats = repeated(albums)
                List {
                    buttons.listRowSeparator(.hidden)
                    ForEach(albums) { album in
                        AlbumRow(
                            album: album,
                            subtitle: album.subtitle(
                                [album.artistName, album.year.map(String.init)], repeats: repeats))
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(name)
        .toolbar {
            Button(
                grid ? "Show as List" : "Show as Grid",
                systemImage: grid ? "list.bullet" : "square.grid.2x2"
            ) { grid.toggle() }
            .accessibilityIdentifier("layout")
        }
        .task(id: name) { await watch(model.library.observeGenre(name: name)) { albums = $0 } }
    }

    private var buttons: some View {
        PlayButtons(play: { load(shuffled: false) }, shuffle: { load(shuffled: true) })
    }

    private func load(shuffled: Bool) {
        Task { player.play(await model.albumTracks(albums.map(\.id)), shuffled: shuffled) }
    }
}

struct GenreRow: View {
    let genre: GenreSummary

    var body: some View {
        NavigationLink(value: Route.genre(genre.name)) {
            VStack(alignment: .leading, spacing: 2) {
                Text(genre.name).lineLimit(1)
                Text(genre.albumCount == 1 ? "1 album" : "\(genre.albumCount) albums")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("genre-\(genre.name)")
    }
}
