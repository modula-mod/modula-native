import SwiftUI

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppEnvironment.self) private var app
    var body: some View {
        @Bindable var navigation = app.navigation
        NavigationStack(path: $navigation.path) {
            HomeView()
                .navigationDestination(for: AppRoute.self) { route in
                    switch route {
                    case .home: HomeView()
                    case .productHub: ProductHubView()
                    case .profile(let id): ProfileView(userID: id)
                    case .account: SignInView()
                    case .settings: SettingsView()
                    case .post: ContentUnavailableView("Post", systemImage: "text.bubble")
                    case .product: ProductHubView()
                    case .module(let id): ModuleHost(moduleID: id)
                    }
                }
        }
        .onAppear { app.runtime.markNativeUsable() }
        .task { await app.auth.restore() }
        .onChange(of: scenePhase) { previous, phase in
            if phase == .active {
                if previous == .background { app.runtime.lifecycle("foregrounded") }
                app.runtime.lifecycle("active")
            } else { app.runtime.lifecycle(phase == .background ? "backgrounded" : "inactive") }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in app.runtime.lifecycle("memoryPressure") }
        .background(app.settings.appearance == .oled ? Color.black : ModulaColor.background)
    }
}
