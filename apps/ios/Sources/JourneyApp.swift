import SwiftUI

@main
struct JourneyApp: App {
    var body: some Scene {
        WindowGroup {
            VStack(spacing: 12) {
                Image(systemName: "music.note")
                    .font(.system(size: 64))
                Text("journey.fm")
                    .font(.largeTitle)
            }
        }
    }
}
