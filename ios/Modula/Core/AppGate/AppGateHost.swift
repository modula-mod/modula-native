import SwiftUI

struct AppGateHost: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @State private var showPrivacyCover = false

    var body: some View {
        ZStack {
            rootContent
            if showPrivacyCover {
                PrivacyCoverView()
            }
        }
        .task {
            await app.bootstrapLaunch()
        }
        .onOpenURL { url in
            app.handleIncomingURL(url)
        }
        .onChange(of: scenePhase) { _, phase in
            app.handleScenePhase(phase)
            showPrivacyCover = shouldCover(phase)
        }
        .onChange(of: app.appLock.isAuthenticating) { _, _ in
            showPrivacyCover = shouldCover(scenePhase)
        }
        .onChange(of: app.gate.state) { _, state in
            if state == .ready { UserDefaults.standard.removeObject(forKey: AppLockView.pendingKey) }
            showPrivacyCover = shouldCover(scenePhase)
        }
        .onChange(of: app.auth.account?.accountId) { _, _ in
            app.refreshLaunchState()
        }
    }

    @ViewBuilder
    private var rootContent: some View {
        #if DEBUG
        if PDFInlineLab.isEnabled {
            PDFInlineLabView()
        } else if ProcessInfo.processInfo.arguments.contains("--debug-moliboo-picker") {
            MolibooPickerHarnessView()
        } else if ProcessInfo.processInfo.arguments.contains("--debug-moliboo-hub") {
            // Straight to the Moliboo settings hub (World → ⋯ → Moliboo settings), e.g. for device screenshots.
            NavigationStack { MolibooSettingsView() }
        } else if ProcessInfo.processInfo.arguments.contains("--debug-moliboo-studio") {
            // Straight to the 2D Moliboo Studio, for simulator screenshots.
            // `--debug-studio-scene <n>` equips the n-th owned background scene first (local only).
            NavigationStack { MascotStudioView() }
                .task {
                    // After the Studio's own outfit-of-the-day pass on appear.
                    try? await Task.sleep(for: .milliseconds(700))
                    DebugSettingsHarness.equipStudioSceneIfRequested()
                }
        } else if ProcessInfo.processInfo.arguments.contains("--debug-moliboo-world") {
            // Straight to the Moliboo home (World), for simulator screenshots of the hero / number label.
            NavigationStack { MolibooWorldView() }
        } else if let mode = DebugSettingsHarness.modulaCodeMode {
            // `--debug-modula-code mycode|scan`: the Modula Code screen with a sample public profile link.
            ModulaCodeView(subject: DebugSettingsHarness.sampleCodeSubject, initialMode: mode) {}
        } else if let payload = DebugSettingsHarness.sharePayload {
            // `--debug-share profile|post|link`: the share sheet over a plain canvas, for screenshots.
            Color(uiColor: .systemBackground).ignoresSafeArea()
                .sheet(isPresented: .constant(true)) { ModulaShareSheet(payload: payload) }
        } else if let route = DebugSettingsHarness.route ?? DebugSettingsHarness.anyRoute {
            DebugSettingsHarnessView(route: route)
        } else {
            gatedContent
        }
        #else
        gatedContent
        #endif
    }

    @ViewBuilder
    private var gatedContent: some View {
        #if DEBUG
        if OnboardingLandingDebug.isEnabled {
            // `--debug-onboarding-landing`: render the landing regardless of session, for screenshots.
            OnboardingLandingView(onContinue: {})
        } else {
            launchContent
        }
        #else
        launchContent
        #endif
    }

    /// Locked and ready share one tree: the app is built *under* the lock screen, so unlocking
    /// only fades the lock away instead of constructing the whole RootView after success
    /// (that cold build was most of the 1–2s Face ID → app delay).
    @ViewBuilder
    private var launchContent: some View {
        if app.gate.state == .locked || app.gate.state == .ready {
            ZStack {
                RootView()
                    .allowsHitTesting(app.gate.state == .ready)
                    .accessibilityHidden(app.gate.state != .ready)
                if app.gate.state == .locked {
                    AppLockView()
                        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
        } else {
            otherLaunchContent
        }
    }

    @ViewBuilder
    private var otherLaunchContent: some View {
        switch app.gate.state {
        case .booting:
            BootSplashView()
                .transition(.opacity)
        case .signedOut:
            PreShellAuthHost()
        case .firstRun:
            FirstRunView()
        case .locked:
            AppLockView()
        case .ready:
            RootView()
        case .failed(let message):
            FailedBootView(message: message)
        }
    }

    private func shouldCover(_ phase: ScenePhase) -> Bool {
        // Only while backgrounded or in the app switcher — never over our own Face ID prompt.
        guard phase != .active, !app.appLock.isAuthenticating else { return false }
        return app.appLock.shouldCoverAppSwitcher
    }
}

struct BootSplashView: View {
    var body: some View {
        // Branded splash matching the launch background (no white "Starting" page). The spinner
        // only fades in if boot is actually slow.
        BootSplashContent()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .accessibilityIdentifier("appgate.booting")
        .accessibilityLabel("Starting Modula")
    }
}

private struct BootSplashContent: View {
    @Environment(\.colorScheme) private var scheme
    @State private var slow = false
    var body: some View {
        VStack(spacing: 22) {
            ModulaWordmark(height: 28, onDark: scheme == .dark)
            ProgressView()
                .controlSize(.small)
                .opacity(slow ? 0.7 : 0)
        }
        .task {
            try? await Task.sleep(for: .milliseconds(900))
            withAnimation(.easeIn(duration: 0.3)) { slow = true }
        }
    }
}

struct FailedBootView: View {
    let message: String
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        ContentUnavailableView {
            Label("Modula couldn’t start", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again") {
                Task { await app.bootstrapLaunch() }
            }
        }
        .modulaCanvas()
        .accessibilityIdentifier("appgate.failed")
    }
}

#if DEBUG
enum OnboardingLandingDebug {
    static var isEnabled: Bool { ProcessInfo.processInfo.arguments.contains("--debug-onboarding-landing") }
}
#endif

struct PreShellAuthHost: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The landing is the front door for every signed-out launch. It is passed once per
    /// app session, and skipped if something (a deep link, sign-out) already opened an
    /// auth route.
    @State private var landingPassed = false

    var body: some View {
        ZStack {
            if showsLanding {
                OnboardingLandingView {
                    withAnimation(ModulaMotion.animation(.presentation, personality: app.appearance.motion, reduceMotion: reduceMotion)) {
                        landingPassed = true
                    }
                }
                .transition(.opacity)
                .zIndex(1)
            } else {
                authFlow
                    .transition(.opacity)
            }
        }
    }

    private var showsLanding: Bool {
        !landingPassed && app.navigation.binding(for: .home).wrappedValue.isEmpty
    }

    private var authFlow: some View {
        @Bindable var navigation = app.navigation
        return NavigationStack(path: navigation.binding(for: .home)) {
            Group {
                if app.gate.signedOutSurface == .onboarding {
                    OnboardingView()
                } else {
                    SignInView()
                }
            }
            .navigationDestination(for: AppRoute.self) { route in
                if case .auth(let authRoute) = route {
                    AuthRouteView(route: authRoute)
                } else {
                    AuthRouteView(route: .login)
                }
            }
        }
        .accessibilityIdentifier("appgate.signed-out")
    }
}
