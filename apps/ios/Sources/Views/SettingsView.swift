import JourneyKit
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var confirmSignOut = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    LabeledContent("Server", value: model.session?.server.host() ?? "")
                    if let username = model.session?.username {
                        LabeledContent("User", value: username)
                    }
                }
                Section {
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
                    if let covers = model.covers, covers.total > 0 {
                        LabeledContent(
                            "Fetching covers", value: "\(covers.done) of \(covers.total)")
                    }
                    Button(model.syncError == nil ? "Sync Now" : "Try Again") {
                        Task { await model.sync() }
                    }
                    .disabled(model.syncing)
                    .accessibilityIdentifier("sync-now")
                } header: {
                    Text("Library")
                } footer: {
                    if let error = model.syncError {
                        Label(failure(error), systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    } else {
                        Text(
                            "A full sync runs once a day; changes since the last sync are fetched when the app opens."
                        )
                    }
                }
                Section {
                    Button("Sign Out", role: .destructive) { confirmSignOut = true }
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("sign-out")
                } footer: {
                    Text("journey.fm \(Self.version)")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark", role: .confirm) { dismiss() }
                        .accessibilityIdentifier("done")
                }
            }
            .confirmationDialog(
                "Sign out?", isPresented: $confirmSignOut, titleVisibility: .visible
            ) {
                Button("Sign Out", role: .destructive) {
                    dismiss()
                    Task { await model.signOut() }
                }
            } message: {
                Text("This removes the library and covers from this iPhone.")
            }
        }
    }

    private func failure(_ error: String) -> String {
        let synced =
            model.stats.lastSync.map {
                " The library on this iPhone is from \($0.formatted(date: .abbreviated, time: .shortened))."
            } ?? ""
        return "Couldn't sync: \(error)\(synced)"
    }

    private static let version =
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
}
