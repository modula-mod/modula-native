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

@MainActor
final class HostBoundaryTests: XCTestCase {
    func testUnknownAndMalformedNavigationRejected() {
        XCTAssertNil(ModulaBridge.route(["route": "execute", "command": "anything"]))
        XCTAssertNil(ModulaBridge.route(["route": "profile", "userId": "../../account"]))
        XCTAssertNil(ModulaBridge.route(["route": "profile", "userId": ""]))
        XCTAssertEqual(ModulaBridge.route(["route": "profile", "userId": "account-1"]), .profile("account-1"))
    }
    func testPreparingAndRevokingDoesNotInitializeReact() {
        let runtime = ModuleRuntimeController()
        let environment = ModuleEnvironment(colorScheme: "dark", oled: true, reduceMotion: true, textScale: 1.3)
        let session = runtime.prepare(moduleID: "modula.runtime-diagnostic", environment: environment)
        XCTAssertNotNil(session)
        XCTAssertEqual(runtime.initializationCount, 0)
        if let session {
            runtime.unmount(session)
            XCTAssertFalse(session.isValid)
            XCTAssertNil(runtime.sessions[session.id])
        }
        XCTAssertEqual(runtime.initializationCount, 0)
    }
    func testMissingSessionAndUnversionedRequestsDenied() {
        ModulaBridge.shared.request("{}") { result in
            XCTAssertTrue(result.contains("REQUEST_DENIED"))
        }
    }
}
