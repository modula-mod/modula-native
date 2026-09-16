import SwiftUI

struct AppGateHost: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @State private var showPrivacyCover = false

    var body: some View {
        ZStack {
            gatedContent
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
    private var gatedContent: some View {
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

struct PreShellAuthHost: View {
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        @Bindable var navigation = app.navigation
        NavigationStack(path: navigation.binding(for: .home)) {
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
