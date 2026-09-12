import SwiftUI

struct RootView: View {
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
                    case .settings: SettingsView()
                    case .post: ContentUnavailableView("Post", systemImage: "text.bubble")
                    case .product: ProductHubView()
                    case .module: ContentUnavailableView("Module unavailable", systemImage: "square.stack.3d.up")
                    }
                }
        }
        .background(app.settings.appearance == .oled ? Color.black : ModulaColor.background)
    }
}
