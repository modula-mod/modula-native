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
                    } description: { Text(session.error ?? "Module unavailable") } actions: {
                        Button("Retry") { retry() }.buttonStyle(.borderedProminent)
                        Button("Close") { app.navigation.close() }
                    }
                } else {
                    ReactNativeContainer(session: session, runtime: app.runtime)
                        .id(session.id)
                        .overlay(alignment: .top) {
                            if session.state == .loadingModule || session.state == .startingRuntime { ProgressView("Opening module…").padding() }
                        }
                }
            } else {
                ContentUnavailableView("Module unavailable", systemImage: "square.stack.3d.up")
            }
        }
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
