import SwiftUI

@main
struct JourneyApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            Group {
                if model.session == nil {
                    SignInView()
                } else {
                    LibraryView()
                }
            }
            .environment(model)
        }
    }
}
