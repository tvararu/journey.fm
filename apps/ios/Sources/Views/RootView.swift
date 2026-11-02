import JourneyKit
import SwiftUI

enum AppTab: Hashable {
    case home, library, search
}

struct RootView: View {
    @Environment(Player.self) private var player
    @State private var tab = AppTab.home
    @State private var paths: [AppTab: [Route]] = [:]
    @State private var showPlayer = false
    @State private var focusSearch = 0
    @Namespace private var playerZoom

    var body: some View {
        TabView(selection: Binding(get: { tab }, set: select)) {
            Tab("Home", systemImage: "house", value: AppTab.home) { HomeView(path: path(.home)) }
            Tab("Library", systemImage: "square.stack", value: AppTab.library) {
                LibraryView(path: path(.library))
            }
            Tab(value: AppTab.search, role: .search) {
                SearchView(path: path(.search), focusRequest: focusSearch)
            }
        }
        .tabBarMinimizeBehavior(tab == .library ? .onScrollDown : .never)
        .tabViewBottomAccessory(isEnabled: player.current != nil) {
            MiniPlayer { showPlayer = true }
                .matchedTransitionSource(id: "player", in: playerZoom)
        }
        .sheet(isPresented: $showPlayer) {
            NowPlayingView { route in
                showPlayer = false
                paths[tab, default: []].append(route)
            }
            .navigationTransition(.zoom(sourceID: "player", in: playerZoom))
        }
    }

    private func select(_ chosen: AppTab) {
        if chosen == tab {
            if !(paths[chosen] ?? []).isEmpty {
                paths[chosen] = []
            } else if chosen == .search {
                focusSearch += 1
            }
        }
        tab = chosen
    }

    private func path(_ tab: AppTab) -> Binding<[Route]> {
        Binding {
            paths[tab] ?? []
        } set: {
            paths[tab] = $0
        }
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
