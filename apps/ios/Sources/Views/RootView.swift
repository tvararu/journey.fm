import JourneyKit
import SwiftUI

enum AppTab: Hashable {
    case home, library, search
}

struct RootView: View {
    @State private var tab = AppTab.home

    var body: some View {
        TabView(selection: $tab) {
            Tab("Home", systemImage: "house", value: AppTab.home) { HomeView() }
            Tab("Library", systemImage: "square.stack", value: AppTab.library) { LibraryView() }
            Tab(value: AppTab.search, role: .search) { SearchView() }
        }
        .tabBarMinimizeBehavior(tab == .library ? .onScrollDown : .never)
    }
}

struct FirstSyncView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let progress = model.syncProgress
        NavigationStack {
            List {
                Section {
                    phase("Artists", count: progress.artists, started: true)
                    phase("Albums", count: progress.albums, started: progress.artists != nil)
                    phase("Tracks", count: progress.tracks, started: progress.albums != nil)
                    phase("Saving", count: nil, started: progress.tracks != nil)
                } footer: {
                    Text(
                        "The first sync fetches the whole library from the server, which takes about half a minute. Covers follow in the background."
                    )
                }
                if let error = model.syncError, !model.syncing {
                    Section {
                        Button("Try Again") { Task { await model.sync() } }
                            .accessibilityIdentifier("try-again")
                    } footer: {
                        Text("Couldn't sync: \(error)").foregroundStyle(.red)
                    }
                }
                Section {
                    Button("Sign Out", role: .destructive) { Task { await model.signOut() } }
                        .accessibilityIdentifier("sign-out")
                }
            }
            .navigationTitle("First Sync")
        }
        .task { await model.sync() }
    }

    private func phase(_ title: String, count: Int?, started: Bool) -> some View {
        LabeledContent(title) {
            if let count {
                HStack {
                    Text(count.formatted()).monospacedDigit()
                    Image(systemName: "checkmark").foregroundStyle(.green)
                }
            } else if started && model.syncing {
                ProgressView()
            }
        }
    }
}
