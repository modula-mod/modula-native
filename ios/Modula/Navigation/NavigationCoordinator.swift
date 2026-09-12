import Observation

@MainActor @Observable
final class NavigationCoordinator {
    var path: [AppRoute] = []
    func open(_ route: AppRoute) { path.append(route) }
    func close() { if !path.isEmpty { path.removeLast() } }
    func home() { path.removeAll() }
}
