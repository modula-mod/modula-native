import SwiftUI

/// Appearance → Edge Picker. Live preview uses the real `ShellEdgeLoop`.
struct EdgePickerSettingsView: View {
    @Environment(AppEnvironment.self) private var app
    @State private var previewSelection = "for-you"
    @State private var confirmsReset = false

    var body: some View {
        @Bindable var store = app.appearance
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                livePreview

                SettingsGroup(title: "Placement", subtitle: "Semantic anchors — never raw pixel coordinates.") {
                    VStack(spacing: 0) {
                        pickerRow("Position", symbol: "arrow.up.and.down", selection: $store.edgePicker.position) { $0.title }
                        SettingsDivider()
                        pickerRow("Size", symbol: "arrow.up.left.and.arrow.down.right", selection: $store.edgePicker.size) { $0.title }
                        SettingsDivider()
                        pickerRow("Side", symbol: "rectangle.lefthalf.inset.filled.arrow.left", selection: $store.edgePicker.side) { $0.title }
                    }
                }

                SettingsGroup(title: "Presentation") {
                    VStack(spacing: 0) {
                        pickerRow("Labels", symbol: "textformat", selection: $store.edgePicker.labelBehavior) { $0.title }
                        SettingsDivider()
                        pickerRow("Glass", symbol: "cube.transparent", selection: $store.edgePicker.glassIntensity) { $0.title }
                        SettingsDivider()
                        pickerRow("Visibility", symbol: "eye", selection: $store.edgePicker.visibility) { $0.title }
                    }
                }

                SettingsGroup(title: "Feel") {
                    VStack(spacing: 0) {
                        pickerRow("Motion", symbol: "waveform.path", selection: $store.edgePicker.motion) { $0.title }
                        SettingsDivider()
                        pickerRow("Haptics", symbol: "hand.tap", selection: $store.edgePicker.haptics) { $0.title }
                    }
                }

                SettingsGroup(title: "Defaults") {
                    Button(role: .destructive) { confirmsReset = true } label: {
                        Label("Reset Edge Picker", systemImage: "arrow.counterclockwise")
                            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                    }
                }

                Text("Edge Picker preferences are stored with Appearance on this device. Resetting here does not change theme, accent, type, or global motion.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, ModulaLayout.contentInset)
            .padding(.top, 10)
            .padding(.bottom, 28)
        }
        .modulaCanvas()
        .navigationTitle("Edge Picker")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Reset Edge Picker?", isPresented: $confirmsReset, titleVisibility: .visible) {
            Button("Reset Edge Picker", role: .destructive) {
                store.resetEdgePicker()
                previewSelection = "for-you"
                HapticEngine.shared.play(.selection)
            }
        } message: {
            Text("Restores Middle, Standard, Right, On Change, Standard glass, Always Visible, and Follow Appearance for motion and haptics.")
        }
        .accessibilityIdentifier("settings.appearance.edge-picker")
    }

    private var livePreview: some View {
        ModulaCard {
            ZStack(alignment: app.appearance.edgePicker.side == .right ? .trailing : .leading) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.primary.opacity(0.06),
                                app.appearance.accent.color.opacity(0.18),
                                Color.primary.opacity(0.04)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Live Preview")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text("Scrub the Edge Picker to change modes. Outer carve stays fixed; the selection aperture expands for vertical labels.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .padding(app.appearance.edgePicker.side == .right ? .trailing : .leading, 56)
                    }

                ShellEdgeLoop(
                    route: .home(.forYou),
                    previewSelection: $previewSelection
                )
                .padding(.vertical, 12)
            }
            .frame(height: 280)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("edge-picker.preview")
    }

    private func pickerRow<Value: Hashable & CaseIterable & Identifiable>(
        _ title: String,
        symbol: String,
        selection: Binding<Value>,
        label: @escaping (Value) -> String
    ) -> some View where Value.AllCases: RandomAccessCollection {
        HStack(spacing: 13) {
            Image(systemName: symbol).frame(width: 28).foregroundStyle(.tint)
            Text(title).font(.body.weight(.medium))
            Spacer()
            Picker(title, selection: selection) {
                ForEach(Array(Value.allCases), id: \.id) { option in
                    Text(label(option)).tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
        .frame(minHeight: 48)
    }
}
