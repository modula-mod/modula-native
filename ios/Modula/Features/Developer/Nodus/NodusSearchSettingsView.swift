import SwiftUI

#if DEBUG
struct NodusSearchSettingsView: View {
    @Environment(AppEnvironment.self) private var app
    @State private var apiKey = ""
    @State private var configured = false
    @State private var status = "Not tested"
    @State private var testing = false

    var body: some View {
        Form {
            Section("Provider") {
                LabeledContent("Provider", value: "Brave Search")
                LabeledContent("Status", value: configured ? "Configured" : "Not configured")
                SecureField(configured ? "Replace masked key" : "API key", text: $apiKey)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("Save API Key") { save() }
                    .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Remove API Key", role: .destructive) { remove() }
                    .disabled(!configured)
            }
            Section("Connection") {
                Button(testing ? "Testing…" : "Test Connection") { Task { await test() } }
                    .disabled(!configured || testing)
                LabeledContent("Result", value: status)
            }
            Section("Privacy") {
                Text("Before a real search, the query is sent to the configured search provider. Nodus model inference remains local. Search is never used when the chat Search control is off.")
                    .font(.footnote).foregroundStyle(.secondary)
                LabeledContent("Key storage", value: "Keychain")
                LabeledContent("Key in exports", value: "No")
                LabeledContent("Remote model calls", value: "0")
            }
        }
        .modulaSoftScrollEdge()
        .navigationTitle("Online Search")
        .onAppear { configured = app.nodusSearchCredentials.isConfigured() }
        .accessibilityIdentifier("nodus.search.settings")
    }

    private func save() {
        do {
            try app.nodusSearchCredentials.saveKey(apiKey)
            apiKey = ""
            configured = true
            status = "Saved securely"
        } catch {
            status = "Could not save key"
        }
    }

    private func remove() {
        do {
            try app.nodusSearchCredentials.removeKey()
            configured = false
            apiKey = ""
            status = "Removed"
        } catch {
            status = "Could not remove key"
        }
    }

    private func test() async {
        testing = true
        defer { testing = false }
        do {
            guard let key = try app.nodusSearchCredentials.loadKey() else { throw NodusSearchError.notConfigured }
            let response = try await BraveDeveloperSearchProvider(apiKey: key).search(query: "Modula", limit: 1)
            status = response.results.isEmpty ? "Connected · no results" : "Connected"
        } catch let error as NodusSearchError {
            status = error.localizedDescription
        } catch {
            status = "Connection failed"
        }
    }
}
#endif

