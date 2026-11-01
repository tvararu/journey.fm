import SwiftUI

@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    let model = AppModel()

    func application(
        _ application: UIApplication, handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        model.downloads?.finishedEvents = completionHandler
    }
}

@main
struct JourneyApp: App {
    @UIApplicationDelegateAdaptor private var delegate: AppDelegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        let model = delegate.model
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
