import XCTest
@testable import Modula

@MainActor
final class NativeFoundationTests: XCTestCase {
    func testNativeRoutingWithoutRuntime() {
        let coordinator = NavigationCoordinator()
        coordinator.open(.productHub)
        coordinator.open(.profile("user-1"))
        XCTAssertEqual(coordinator.path, [.productHub, .profile("user-1")])
        coordinator.close()
        XCTAssertEqual(coordinator.path, [.productHub])
        coordinator.home()
        coordinator.close()
        XCTAssertTrue(coordinator.path.isEmpty)
    }

    func testDeviceAppearancePersistence() {
        let name = "modula-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.appearance, .system)
        store.appearance = .oled
        XCTAssertEqual(SettingsStore(defaults: defaults).appearance, .oled)
    }
}
