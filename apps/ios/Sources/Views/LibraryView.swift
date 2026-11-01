import JourneyKit
import SwiftUI

struct LibraryView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            List {
                Section("Library") {
                    LabeledContent("Albums", value: model.stats.albums.formatted())
                    LabeledContent("Artists", value: model.stats.artists.formatted())
                    LabeledContent("Tracks", value: model.stats.tracks.formatted())
                    LabeledContent("Last sync") {
                        if model.syncing {
                            ProgressView()
                        } else if let lastSync = model.stats.lastSync {
                            Text(lastSync, format: .relative(presentation: .named))
                        } else {
                            Text("Never")
                        }
                    }
                    Button("Sync now") { Task { await model.sync() } }
                        .disabled(model.syncing)
                }
                if let error = model.error {
                    Section { Text(error).foregroundStyle(.red) }
                }
                Section("Recently added") {
                    ForEach(model.recent) { album in
                        HStack(spacing: 12) {
                            ArtView(album: album, size: 44)
                            VStack(alignment: .leading) {
                                Text(album.name)
                                Text(album.artistName)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .lineLimit(1)
                        }
                    }
                }
                Section {
                    Button("Sign out", role: .destructive) { Task { await model.signOut() } }
                }
            }
            .navigationTitle("journey.fm")
            .task { await model.watchStats() }
            .task { await model.watchRecent() }
            .task { await model.sync() }
        }
    }
}

struct ArtView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.displayScale) private var displayScale
    let album: Album
    let size: CGFloat
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Rectangle().fill(.quaternary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: 4))
        .task(id: album.imageTag) {
            guard let tag = album.imageTag, let art = model.art else { return }
            let width = Int(size * displayScale)
            do {
                image = UIImage(
                    data: try await art.image(itemId: album.id, tag: tag, maxWidth: width))
            } catch {
                Log.art.error(
                    "Art for \(album.id, privacy: .public) failed: \(String(describing: error), privacy: .public)"
                )
            }
        }
    }
}
