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
        .onChange(of: app.gate.state) { _, _ in
            showPrivacyCover = shouldCover(scenePhase)
        }
        .onChange(of: app.auth.account?.accountId) { _, _ in
            app.refreshLaunchState()
        }
    }

    @ViewBuilder
    private var rootContent: some View {
        #if DEBUG
        if let route = DebugSettingsHarness.route ?? DebugSettingsHarness.anyRoute {
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

    @ViewBuilder
    private var launchContent: some View {
        switch app.gate.state {
        case .booting:
            BootSplashView()
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
        guard phase != .active else { return false }
        return app.appLock.shouldCoverAppSwitcher
    }
}

struct BootSplashView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Starting Modula")
                .font(.headline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .modulaCanvas()
        .accessibilityIdentifier("appgate.booting")
        .accessibilityLabel("Starting Modula")
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
