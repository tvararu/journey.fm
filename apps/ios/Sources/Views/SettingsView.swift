import JourneyKit
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var confirmSignOut = false
    @State private var confirmRemoveAll = false

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
                    if let lyrics = model.lyrics, lyrics.total > 0 {
                        LabeledContent(
                            "Fetching lyrics",
                            value: "\(lyrics.done.formatted()) of \(lyrics.total.formatted())")
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
                if let downloads = model.downloads {
                    downloadSection(downloads)
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
                Text("This removes the library, covers and downloads from this iPhone.")
            }
            .confirmationDialog(
                "Remove all downloads?", isPresented: $confirmRemoveAll, titleVisibility: .visible
            ) {
                Button("Remove All Downloads", role: .destructive) {
                    Task { await model.removeAllDownloads() }
                }
            } message: {
                Text("Downloaded tracks will play again only when online.")
            }
        }
    }

    private func downloadSection(_ downloads: Downloads) -> some View {
        let summary = downloads.summary
        return Section {
            LabeledContent("Downloaded") {
                Text(
                    summary.saved.isEmpty
                        ? "None"
                        : "\(tracksText(summary.saved.count)) · \(summary.bytes.formatted(.byteCount(style: .file)))"
                )
            }
            .accessibilityIdentifier("downloaded")
            if let free = model.freeSpace {
                LabeledContent("Available", value: free.formatted(.byteCount(style: .file)))
            }
            if model.downloadingEverything {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(
                        value: Double(summary.saved.count), total: Double(max(summary.tracks, 1))
                    ) {
                        Text("Downloading Everything")
                    } currentValueLabel: {
                        Text("\(summary.saved.count.formatted()) of \(tracksText(summary.tracks))")
                    }
                    if let pause = model.downloadPause {
                        Text(pause).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("download-everything-progress")
            } else if !summary.everything {
                Button("Download All") { Task { await model.downloadEverything() } }
                    .accessibilityIdentifier("download-all")
            }
            Toggle("Download New Albums", isOn: Bindable(model).downloadNew)
            if summary.wanted > 0 {
                Button("Remove All Downloads", role: .destructive) { confirmRemoveAll = true }
                    .accessibilityIdentifier("remove-all-downloads")
            }
        } header: {
            Text("Downloads")
        } footer: {
            Text(
                "Download All saves every track, on Wi-Fi only, and carries on with the app closed. When it finishes, Download New Albums turns on and saves each album added later."
            )
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
