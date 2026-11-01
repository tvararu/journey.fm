import SwiftUI

@main
struct JourneyApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            Group {
                if model.session == nil {
                    SignInView()
                } else if !model.statsLoaded {
                    Color.clear
                } else if model.needsFirstSync {
                    FirstSyncView()
                } else {
                    RootView()
                }
            }
            .environment(model)
            .environment(model.player)
            .task { await model.watchStats() }
            .task { await model.tick() }
            .onChange(of: scenePhase, initial: true) { _, phase in
                if phase == .active { Task { await model.sync() } }
            }
        }
    }
}
