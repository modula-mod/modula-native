import SwiftUI

struct ProductHubView: View {
    @Environment(AppEnvironment.self) private var app
    var body: some View {
        List {
            Section("Account") {
                if app.auth.busy {
                    ProgressView("Restoring secure session…")
                } else if let account = app.auth.account {
                    LabeledContent("Signed in", value: account.primaryHandle)
                        .accessibilityIdentifier("account.ready")
                } else {
                    Button("Sign in to Modula") { app.navigation.open(.account) }
                }
            }
            Section("Bundled modules") {
                ForEach(app.runtime.manifests, id: \.id) { manifest in
                    Button { app.navigation.open(.module(manifest.id)) } label: {
                        VStack(alignment: .leading) {
                            Text(manifest.name).font(.headline)
                            Text("Bundled \(manifest.version)").font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 8)
                    }
                }
            }
        }.navigationTitle("Product Hub")
    }
}
