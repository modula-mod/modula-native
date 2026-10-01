import SwiftUI

struct ModuleHost: View {
    let moduleID: String
    var initialLocalPath: String? = nil
    @Environment(AppEnvironment.self) private var app
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric private var textScale: Double = 1
    @State private var session: ModuleSession?
    private var appearance: ModuleEnvironment {
        ModuleEnvironment(colorScheme: scheme == .dark ? "dark" : "light", theme: app.appearance.theme.rawValue,
                          darkStyle: app.appearance.darkStyle.rawValue, oled: app.appearance.darkStyle == .oled && scheme == .dark,
                          accent: app.appearance.accent.hex, fontFamily: app.appearance.fontFamily.rawValue,
                          density: app.appearance.density.rawValue, motionPersonality: app.appearance.motion.rawValue,
                          hapticIntensity: app.appearance.haptics.rawValue,
                          contrastPreference: app.appearance.contrastTransparency == .higherContrast ? "higherContrast" : "standard",
                          transparencyPreference: app.appearance.contrastTransparency == .reduceTransparency ? "reduceTransparency" : "standard",
                          iconStyle: app.appearance.iconStyle.rawValue, interfaceShape: app.appearance.interfaceShape.rawValue,
                          moduleBranding: app.appearance.moduleBranding.rawValue, reduceMotion: reduceMotion,
                          textScale: textScale * app.appearance.textSize.scale)
    }
    var body: some View {
        VStack(spacing: 0) {
            if let session {
                if session.state == .failed || session.state == .unavailable {
                    ContentUnavailableView {
                        Label("\(session.manifest.name) failed to load", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(session.error ?? "Module unavailable")
                    } actions: {
                        Button("Retry") { retry() }.buttonStyle(.borderedProminent).tint(app.appearance.accent.color)
                        Button("Close") { app.navigation.close() }
                    }
                    .accessibilityIdentifier("module.host.failed")
                } else {
                    ReactNativeContainer(session: session, runtime: app.runtime)
                        .id(session.id)
                        .overlay {
                            if session.state == .loadingModule || session.state == .startingRuntime {
                                ModuleOpeningOverlay(name: session.manifest.name, accent: app.appearance.accent.color, reduceMotion: reduceMotion)
                                    .transition(reduceMotion ? .identity : .opacity)
                            }
                        }
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: session.state)
                }
            } else {
                ContentUnavailableView {
                    Label("Module unavailable", systemImage: "square.stack.3d.up.slash")
                } description: {
                    Text(app.runtime.unavailableReason(for: moduleID) ?? "This module can’t be opened right now.")
                } actions: {
                    Button("Close") { app.navigation.close() }.buttonStyle(.bordered)
                }
                .accessibilityIdentifier("module.host.unavailable")
            }
        }
        .modulaSoftScrollEdge()
        .navigationTitle(session?.manifest.name ?? "Module")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button("Close", systemImage: "xmark") { app.navigation.close() } }
            #if DEBUG
            ToolbarItem(placement: .bottomBar) { Text("Runtime: \(app.runtime.initializationCount) · \(session?.state.rawValue ?? "idle")").font(.caption).accessibilityIdentifier("runtime.status") }
            ToolbarItem(placement: .topBarLeading) {
                Menu("Test appearance", systemImage: "circle.lefthalf.filled") {
                    Button("Use Light Appearance") { app.appearance.appearance = .light }
                    Button("Use Dark Appearance") { app.appearance.appearance = .dark }
                    Button("Use OLED Appearance") { app.appearance.appearance = .oled }
                }
            }
            #endif
        }
        .onAppear { if session == nil || session?.isValid == false { session = app.runtime.prepare(moduleID: moduleID, environment: appearance, initialLocalPath: initialLocalPath) } }
        .onChange(of: appearance) { _, value in if let session { app.runtime.update(value, session: session) } }
        .onDisappear { if let session { app.runtime.unmount(session) } }
    }
    private func retry() {
        if let session { app.runtime.unmount(session) }
        session = app.runtime.prepare(moduleID: moduleID, environment: appearance, initialLocalPath: initialLocalPath)
    }
}

/// Opening state drawn with design-system materials; static (no spinner) under Reduce Motion.
private struct ModuleOpeningOverlay: View {
    let name: String
    let accent: Color
    let reduceMotion: Bool

    var body: some View {
        VStack(spacing: 12) {
            if reduceMotion {
                Image(systemName: "square.stack.3d.up").font(.title2).foregroundStyle(accent)
            } else {
                ProgressView().controlSize(.large).tint(accent)
            }
            Text("Opening \(name)…").font(.subheadline.weight(.medium)).multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Opening \(name)")
        .accessibilityAddTraits(.updatesFrequently)
        .accessibilityIdentifier("module.host.loading")
    }
}
