import SwiftUI

struct SettingsView: View {
    @Environment(AppEnvironment.self) private var app
    var body: some View {
        @Bindable var settings = app.settings
        Form {
            Section("Appearance") {
                Picker("Color scheme", selection: $settings.appearance) {
                    ForEach(SettingsStore.Appearance.allCases, id: \.self) { value in
                        Text(value.rawValue.capitalized).tag(value)
                    }
                }
            }
            Section {
                Text("Appearance is saved on this device. Account settings will follow in the next phase.")
                    .foregroundStyle(.secondary)
            }
            Section("About") { LabeledContent("Version", value: "0.1.0 · Native foundation") }
        }
        .navigationTitle("Settings")
    }
}
