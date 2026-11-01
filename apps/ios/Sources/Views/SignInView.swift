import SwiftUI

struct SignInView: View {
    @Environment(AppModel.self) private var model
    @State private var server = "https://jellyfin.example"
    @State private var username = ""
    @State private var password = ""
    @State private var signingIn = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Server", text: $server)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Username", text: $username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                } footer: {
                    if let error = model.error {
                        Text(error).foregroundStyle(.red)
                    }
                }
                Section {
                    Button("Sign in") {
                        Task {
                            signingIn = true
                            await model.signIn(
                                server: server, username: username, password: password)
                            signingIn = false
                        }
                    }
                    .disabled(signingIn || server.isEmpty || username.isEmpty)
                }
            }
            .navigationTitle("journey.fm")
        }
    }
}
