import XCTest

final class MOL03WorldDiagUITests: XCTestCase {
    func testPushFromWorld() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-skip-first-run", "-MOLWorldNoLaunchWake", "-composer.mascot.kind", "pip", "-dev.moliboo.native3D", "YES",
                               "--debug-settings-route", "/settings/moliboo", "-moliboo.onboarded.v1", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["world.nav.studio"].waitForExistence(timeout: 20))
        app.buttons["world.nav.studio"].tap()
        print("MOLDIAG tapped \(Date().timeIntervalSince1970)")
        sleep(25)
        let t0 = Date()
        print("MOLDIAG debug=\(app.debugDescription.count) secs=\(Date().timeIntervalSince(t0))")
    }
}
