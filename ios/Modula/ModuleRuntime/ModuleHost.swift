import SwiftUI

struct ModuleHost: View {
    let moduleID: String
    var initialLocalPath: String? = nil
    @Environment(AppEnvironment.self) private var app
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric private var textScale: Double = 1
    @State private var session: ModuleSession?
    #if DEBUG
    @State private var showLifecycleLab = false
    #endif
    private var appearance: ModuleEnvironment {
        ModuleEnvironment(colorScheme: scheme == .dark ? "dark" : "light", theme: app.appearance.theme.rawValue,
                          darkStyle: app.appearance.darkStyle.rawValue, oled: app.appearance.darkStyle == .oled && scheme == .dark,
                          accent: app.appearance.accent.hex, fontFamily: app.appearance.fontFamily.rawValue,
                          density: app.appearance.density.rawValue, motionPersonality: app.appearance.motion.rawValue,
                          hapticIntensity: app.appearance.haptics.rawValue,
                          contrastPreference: app.appearance.contrastTransparency == .higherContrast ? "higherContrast" : "standard",
                          transparencyPreference: app.appearance.contrastTransparency == .reduceTransparency ? "reduceTransparency" : "standard",
                          iconStyle: app.appearance.iconStyle.rawValue, interfaceShape: app.appearance.interfaceShape.rawValue,
                          moduleBranding: app.appearance.moduleBranding.rawValue, reduceMotion: reduceMotion || ModulaPreferences.extraMotionReduction,
                          textScale: textScale * app.appearance.textSize.scale)
    }
    private var palette: ModulaPalette { ModulaPalette.resolve(app.appearance, scheme: scheme) }

    var body: some View {
        VStack(spacing: 0) {
            if let session {
                if let gate = gateContent(for: session) {
                    gate
                } else if session.state == .failed || session.state == .unavailable {
                    ContentUnavailableView {
                        Label("\(session.manifest.name) failed to load", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(session.error ?? "Module unavailable")
                    } actions: {
                        Button("Retry") { retry() }.buttonStyle(.borderedProminent).tint(app.appearance.accent.color)
                        Button("Close") { app.navigation.close() }
                    }
                    .accessibilityIdentifier("module.host.failed")
                } else if !session.isValid || session.state == .expired {
                    stateView(
                        title: "Session ended",
                        symbol: "clock.arrow.circlepath",
                        message: "\(session.manifest.name) was closed for your security. Reopen it to continue.",
                        retryTitle: "Reopen",
                        showsProductHub: false
                    )
                } else if session.runtimeKind == .declarativeProductUI, let document = session.productUI {
                    ProductUIHostView(session: session, document: document)
                        .id(session.id)
                        .background(palette.canvas)
                } else {
                    ReactNativeContainer(session: session, runtime: app.runtime)
                        .id(session.id)
                        .background(palette.canvas)
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
        .background(palette.canvas.ignoresSafeArea())
        .modulaSoftScrollEdge()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text(session?.manifest.name ?? "Module")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    if let version = session?.manifest.version {
                        Text(version)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(session?.manifest.name ?? "Module")
                .accessibilityIdentifier("module.host.title")
            }
            #if DEBUG
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Lifecycle lab") { showLifecycleLab = true }
                    Button("Use Light Appearance") { app.appearance.appearance = .light }
                    Button("Use Dark Appearance") { app.appearance.appearance = .dark }
                    Button("Use OLED Appearance") { app.appearance.appearance = .oled }
                } label: {
                    Image(systemName: "ladybug")
                        .font(.body)
                        .foregroundStyle(ModulaColor.accent)
                }
                .accessibilityLabel("Module debug")
                .accessibilityIdentifier("module.host.debug")
            }
            #endif
        }
        #if DEBUG
        .sheet(isPresented: $showLifecycleLab) {
            ModuleLifecycleLab(moduleID: moduleID) { reloadSession() }
                .presentationDetents([.medium, .large])
        }
        .background {
            if ModulaAppNetworkIsolation.isActive {
                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityElement()
                    .accessibilityIdentifier("module.host.network-isolated")
                    .accessibilityLabel("App network isolated")
            }
        }
        #endif
        .onAppear {
            if let session, session.isValid {
                // Back from a tab switch or a pushed route: same surface, same React state.
                app.runtime.resume(session)
            } else if session == nil || session?.isValid == false && session?.state != .expired {
                session = app.runtime.prepare(moduleID: moduleID, environment: appearance, initialLocalPath: initialLocalPath)
            }
        }
        .onChange(of: appearance) { _, value in if let session { app.runtime.update(value, session: session) } }
        // Hidden ≠ closed: suspend so tab switches and pushed routes keep the module alive.
        // Real teardown happens when the surface is dismantled (ReactNativeViewController.stop).
        .onDisappear { if let session { app.runtime.suspend(session) } }
    }
    /// Native gate states decided before any module JavaScript runs.
    private func gateContent(for session: ModuleSession) -> AnyView? {
        let name = session.manifest.name
        let message = session.error ?? ""
        switch session.state {
        case .notInstalled:
            return AnyView(stateView(title: "\(name) isn’t installed", symbol: "arrow.down.app", message: message,
                                     retryTitle: "Try again", showsProductHub: true)
                .accessibilityIdentifier("module.host.notInstalled"))
        case .integrityFailed:
            return AnyView(stateView(title: "Couldn’t verify \(name)", symbol: "xmark.shield", message: message,
                                     retryTitle: "Try again", showsProductHub: true)
                .accessibilityIdentifier("module.host.integrityFailed"))
        case .updateRequired:
            return AnyView(stateView(title: "Update required", symbol: "arrow.triangle.2.circlepath", message: message,
                                     retryTitle: "Check again", showsProductHub: true)
                .accessibilityIdentifier("module.host.updateRequired"))
        case .permissionDenied:
            let list = session.deniedCapabilities.map(ModuleHostPermissions.purpose(for:))
            let detail = list.isEmpty ? message : message + "\n\n" + Array(Set(list)).sorted().joined(separator: "\n")
            return AnyView(stateView(title: "Permission needed", symbol: "hand.raised", message: detail,
                                     retryTitle: "Try again", showsProductHub: true)
                .accessibilityIdentifier("module.host.permissionDenied"))
        default:
            return nil
        }
    }

    private func stateView(title: String, symbol: String, message: String, retryTitle: String = "Retry", showsProductHub: Bool) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text(message)
        } actions: {
            Button(retryTitle) { retry() }
                .buttonStyle(.borderedProminent)
                .tint(app.appearance.accent.color)
                .frame(minHeight: ModulaLayout.minimumTouch)
            if showsProductHub {
                Button("View in Product Hub") {
                    app.navigation.push(.productHub(.module(moduleID, .overview)))
                }
                .frame(minHeight: ModulaLayout.minimumTouch)
            }
            Button("Close") { app.navigation.close() }
                .frame(minHeight: ModulaLayout.minimumTouch)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func retry() {
        reloadSession()
    }

    private func reloadSession() {
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
