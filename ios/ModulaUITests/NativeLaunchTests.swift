import XCTest
import UIKit

@MainActor
final class N2ShellUITests: XCTestCase {
    func testCanonicalShellRailProductHubModuleHostAndAppearance() {
        let launchStart = ContinuousClock.now
        let app = XCUIApplication()
        app.launchArguments = ["--runtime-unavailable"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["native.home"].waitForExistence(timeout: 10))
        print("N2_METRIC shell_render_ms=\(launchStart.duration(to: .now).milliseconds)")

        let railStart = ContinuousClock.now
        app.buttons["For You"].tap()
        XCTAssertEqual(app.descendants(matching: .any)["native.home"].value as? String, "/home/for-you")
        print("N2_METRIC rail_switch_ms=\(railStart.duration(to: .now).milliseconds)")
        let tabStart = ContinuousClock.now
        app.buttons["Discover"].tap()
        XCTAssertTrue(app.staticTexts["Discover"].waitForExistence(timeout: 5))
        print("N2_METRIC tab_switch_ms=\(tabStart.duration(to: .now).milliseconds)")
        let hubStart = ContinuousClock.now
        app.tabBars.firstMatch.buttons["Modules"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["product-hub"].waitForExistence(timeout: 10))
        signInFixtureIfNeeded(app)

        let vault = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Vault Notes")).firstMatch
        XCTAssertTrue(vault.waitForExistence(timeout: 10))
        print("N2_METRIC product_hub_ms=\(hubStart.duration(to: .now).milliseconds)")
        let detailStart = ContinuousClock.now
        vault.tap()
        XCTAssertTrue(app.descendants(matching: .any)["module-detail.digital.modula.vault-notes"].waitForExistence(timeout: 8))
        print("N2_METRIC module_detail_ms=\(detailStart.duration(to: .now).milliseconds)")
        let hostStart = ContinuousClock.now
        app.descendants(matching: .any)["module.open"].tap()
        XCTAssertTrue(app.staticTexts["Vault Notes failed to load"].waitForExistence(timeout: 8))
        print("N2_METRIC module_host_transition_ms=\(hostStart.duration(to: .now).milliseconds)")
        app.buttons["Close"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Vault Notes"].waitForExistence(timeout: 8))

        app.buttons["Activity"].tap()
        app.buttons["Mentions"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["activity.mentions"].waitForExistence(timeout: 5))
        app.buttons["Profile"].tap()
        app.buttons["Posts"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["profile.posts"].waitForExistence(timeout: 5))

        app.buttons["Home"].tap()
        app.buttons["Settings"].firstMatch.tap()
        app.buttons["Appearance"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["settings.appearance"].waitForExistence(timeout: 5))
        let appearanceStart = ContinuousClock.now
        app.buttons["Violet"].tap()
        XCTAssertTrue(app.staticTexts["Native design contract v1"].exists)
        print("N2_METRIC appearance_update_ms=\(appearanceStart.duration(to: .now).milliseconds)")
    }
}

@MainActor
final class N2PolishAccessibilityUITests: XCTestCase {
    func testLoopingRailAccessoryAndCompactChromeRemainReachable() {
        let app = XCUIApplication()
        app.launchArguments = ["--runtime-unavailable", "--reset-appearance", "--ui-light", "--ui-compact"]
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["native.home"].waitForExistence(timeout: 10))
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.exists)
        for title in ["Home", "Discover", "Modules", "Activity", "Profile"] {
            let element = tabBar.buttons[title]
            XCTAssertTrue(element.exists, "Missing native tab \(title)")
            XCTAssertTrue(element.isHittable, "Unreachable native tab \(title)")
        }
        for identifier in ["accessory.search", "accessory.more"] {
            let element = app.descendants(matching: .any)[identifier]
            XCTAssertTrue(element.exists, "Missing shell control \(identifier)")
            XCTAssertTrue(element.isHittable, "Unreachable shell control \(identifier)")
        }

        app.buttons["Modules"].firstMatch.tap()
        XCTAssertEqual(app.descendants(matching: .any)["native.home"].value as? String, "/home/modules")
        attachScreenshot(app, name: "edge-rail-revealed-loop-state")
        app.buttons["Following"].firstMatch.tap()
        XCTAssertEqual(app.descendants(matching: .any)["native.home"].value as? String, "/home/following")

        app.descendants(matching: .any)["accessory.more"].tap()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Appearance"].exists)
    }

    func testLargeDynamicTypeReducedTransparencyAndOLEDHaveStableLandmarks() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--runtime-unavailable", "--reset-appearance", "--ui-oled", "--ui-large-text", "--ui-reduce-transparency",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityExtraExtraLarge"
        ]
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["native.home"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Settings"].firstMatch.isHittable)
        XCTAssertTrue(app.tabBars.firstMatch.buttons["Home"].isHittable)
        XCTAssertTrue(app.buttons["For You"].firstMatch.isHittable)
        app.descendants(matching: .any)["accessory.more"].tap()
        app.buttons["Appearance"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["settings.appearance"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.staticTexts["Native design contract v1"].exists)
    }

    func testNativeTabMinimizationAndSettingsLargeTitle() {
        let app = XCUIApplication()
        app.launchArguments = ["--runtime-unavailable", "--reset-appearance", "--ui-dim"]
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["native.home"].waitForExistence(timeout: 10))
        app.swipeUp()
        attachScreenshot(app, name: "home-native-tab-minimized")

        app.buttons["Settings"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["settings.root"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.navigationBars["Settings"].exists)
        attachScreenshot(app, name: "settings-large-title-and-search")
    }

    private func attachScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

final class NativeLaunchTests: XCTestCase {
    @MainActor
    func testNativeLaunchAndDestinations() {
        let started = ContinuousClock.now
        let app = XCUIApplication()
        app.launchArguments = ["--runtime-unavailable"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Modula"].waitForExistence(timeout: 10))
        print("N1_METRIC native_cold_launch_ms=\(started.duration(to: .now).milliseconds)")
        app.buttons["Product Hub"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Product Hub"].waitForExistence(timeout: 5))
        app.buttons["Home"].firstMatch.tap()
        app.buttons["Profile"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Profile"].waitForExistence(timeout: 5))
        app.buttons["Home"].firstMatch.tap()
        app.buttons["Settings"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testRuntimeUnavailableIsContainedByNativeHost() {
        let app = XCUIApplication()
        app.launchArguments = ["--runtime-unavailable"]
        app.launch()
        app.buttons["Product Hub"].tap()
        let vault = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Vault Notes")).firstMatch
        XCTAssertTrue(vault.waitForExistence(timeout: 8))
        vault.tap()
        XCTAssertTrue(app.descendants(matching: .any)["module.open"].waitForExistence(timeout: 8))
        app.descendants(matching: .any)["module.open"].tap()
        XCTAssertTrue(app.staticTexts["Vault Notes failed to load"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["Retry"].exists)
        app.buttons["Close"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Vault Notes"].waitForExistence(timeout: 8))
    }
}

@MainActor
final class VaultRuntimeUITests: XCTestCase {
    func testRealVaultCRUDLifecycleAppearanceAndNativeNavigation() {
        let app = launchSignedInApp()
        openProductHub(app)
        openVault(app)

        XCTAssertTrue(app.staticTexts["Notes loaded"].waitForExistence(timeout: 20))
        XCTAssertTrue(noteButton(app, title: "N1 Fixture 1").waitForExistence(timeout: 5))
        let firstStatus = try? XCTUnwrap(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Runtime: 1'")).firstMatch)
        XCTAssertTrue(firstStatus?.exists == true)

        let title = "NativeVaultBridge-\(UUID().uuidString.prefix(6))"
        app.buttons["New Note"].tap()
        pasteText(title, into: textInput(app, label: "Note title"), app: app)
        pasteText("Created by the custom React Native Vault through authenticated Swift.", into: textInput(app, label: "Note content"), app: app)
        app.buttons["Save note"].tap()
        XCTAssertTrue(app.staticTexts["Saved"].waitForExistence(timeout: 20))
        app.buttons["Notes"].tap()
        XCTAssertTrue(noteButton(app, title: title).waitForExistence(timeout: 20))

        noteButton(app, title: title).tap()
        let titleInput = textInput(app, label: "Note title")
        XCTAssertTrue(titleInput.waitForExistence(timeout: 10))
        let editedTitle = "\(title) edited"
        pasteText(editedTitle, into: titleInput, app: app, replacing: true)
        app.buttons["Save note"].tap()
        XCTAssertTrue(app.staticTexts["Saved"].waitForExistence(timeout: 20))
        app.buttons["Notes"].tap()
        XCTAssertTrue(noteButton(app, title: editedTitle).waitForExistence(timeout: 20))

        noteButton(app, title: editedTitle).tap()
        XCTAssertTrue(app.buttons["Move to Trash"].waitForExistence(timeout: 10))
        app.buttons["Move to Trash"].tap()
        XCTAssertTrue(app.alerts.buttons["Move to Trash"].waitForExistence(timeout: 5))
        app.alerts.buttons["Move to Trash"].tap()
        XCTAssertTrue(app.staticTexts["Notes loaded"].waitForExistence(timeout: 20))
        XCTAssertFalse(noteButton(app, title: editedTitle).exists)

        app.buttons["Test appearance"].tap()
        app.buttons["Use Dark Appearance"].tap()
        XCTAssertTrue(app.staticTexts["dark · OLED false · #369CAA"].waitForExistence(timeout: 8))
        app.buttons["Test appearance"].tap()
        app.buttons["Use OLED Appearance"].tap()
        XCTAssertTrue(app.staticTexts["dark · OLED true · #369CAA"].waitForExistence(timeout: 8))
        app.buttons["Test appearance"].tap()
        app.buttons["Use Light Appearance"].tap()
        XCTAssertTrue(app.staticTexts["light · OLED false · #369CAA"].waitForExistence(timeout: 8))

        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.staticTexts["Notes loaded"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["active"].waitForExistence(timeout: 8))

        app.buttons["Open my native Profile"].tap()
        XCTAssertTrue(app.navigationBars["Profile"].waitForExistence(timeout: 8))
        app.buttons["tab.modules"].tap()
        XCTAssertTrue(app.staticTexts["Notes loaded"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Runtime: 1'")).firstMatch.exists)
        app.buttons["Close"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Vault Notes"].waitForExistence(timeout: 8))

        openVault(app)
        XCTAssertTrue(app.staticTexts["Notes loaded"].waitForExistence(timeout: 20))
        XCTAssertFalse(noteButton(app, title: editedTitle).exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Runtime: 1'")).firstMatch.exists)
        app.buttons["Close"].firstMatch.tap()
    }

    func testTenOpenCloseCyclesReuseOneRuntime() {
        let app = launchSignedInApp()
        openProductHub(app)
        var durations: [Double] = []
        for _ in 0..<10 {
            let start = ContinuousClock.now
            openVault(app)
            XCTAssertTrue(app.staticTexts["Notes loaded"].waitForExistence(timeout: 20))
            durations.append(start.duration(to: .now).milliseconds)
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Runtime: 1'")).firstMatch.exists)
            app.buttons["Close"].firstMatch.tap()
            XCTAssertTrue(app.navigationBars["Vault Notes"].waitForExistence(timeout: 8))
        }
        print("N1_METRIC vault_open_ms=\(durations.map { String(format: "%.1f", $0) }.joined(separator: ","))")
        app.buttons["Home"].firstMatch.tap()
        app.buttons["Settings"].firstMatch.tap()
        let diagnostics = app.descendants(matching: .any)["settings.runtime"]
        for _ in 0..<4 where !diagnostics.exists { app.swipeUp() }
        XCTAssertTrue(diagnostics.waitForExistence(timeout: 5))
        diagnostics.tap()
        for id in ["metric.nativeUsable", "metric.factory", "metric.runtimeReady", "metric.vaultFirst", "metric.vaultSecond", "metric.vaultData", "metric.memoryBefore", "metric.memoryWith", "metric.memoryAfter"] {
            let metric = app.descendants(matching: .any)[id]
            if !metric.waitForExistence(timeout: 2) {
                app.swipeUp()
            }
            XCTAssertTrue(metric.waitForExistence(timeout: 8), "Missing runtime diagnostic \(id)")
            print("N1_METRIC \(id)=\(metric.label)")
        }
    }

    private func launchSignedInApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--reset-appearance"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Modula"].waitForExistence(timeout: 10))
        return app
    }

    private func openProductHub(_ app: XCUIApplication) {
        app.buttons["Product Hub"].firstMatch.tap()
        signInFixtureIfNeeded(app)
        XCTAssertTrue(app.descendants(matching: .any)["account.ready"].waitForExistence(timeout: 20))
    }

    private func openVault(_ app: XCUIApplication) {
        let open = app.descendants(matching: .any)["module.open"]
        if open.waitForExistence(timeout: 2) { open.tap(); return }
        let vault = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Vault Notes")).firstMatch
        XCTAssertTrue(vault.waitForExistence(timeout: 8))
        vault.tap()
        XCTAssertTrue(app.descendants(matching: .any)["module.open"].waitForExistence(timeout: 8))
        app.descendants(matching: .any)["module.open"].tap()
    }

    private func textInput(_ app: XCUIApplication, label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@ OR identifier == %@", label, label == "Note title" ? "vault.title" : "vault.content")).firstMatch
    }

    private func noteButton(_ app: XCUIApplication, title: String) -> XCUIElement {
        app.buttons[title]
    }
}

@MainActor
final class ReleaseVaultUITests: XCTestCase {
    func testBundledVaultCRUDAndNativeOwnership() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.navigationBars["Modula"].waitForExistence(timeout: 10))
        app.buttons["Product Hub"].tap()
        signInFixtureIfNeeded(app)
        XCTAssertTrue(app.descendants(matching: .any)["account.ready"].waitForExistence(timeout: 20))
        let vault = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Vault Notes")).firstMatch
        XCTAssertTrue(vault.waitForExistence(timeout: 8))
        vault.tap()
        XCTAssertTrue(app.descendants(matching: .any)["module.open"].waitForExistence(timeout: 8))
        app.descendants(matching: .any)["module.open"].tap()
        XCTAssertTrue(app.staticTexts["Notes loaded"].waitForExistence(timeout: 20))

        let title = "NativeReleaseBridge-\(UUID().uuidString.prefix(6))"
        app.buttons["New Note"].tap()
        pasteText(title, into: input(app, "Note title", "vault.title"), app: app)
        pasteText("Bundled Hermes and Swift bridge release proof.", into: input(app, "Note content", "vault.content"), app: app)
        app.buttons["Save note"].tap()
        XCTAssertTrue(app.staticTexts["Saved"].waitForExistence(timeout: 20))
        app.buttons["Notes"].tap()
        XCTAssertTrue(app.buttons[title].waitForExistence(timeout: 20))

        app.buttons[title].tap()
        let titleInput = input(app, "Note title", "vault.title")
        let edited = "\(title) edited"
        pasteText(edited, into: titleInput, app: app, replacing: true)
        app.buttons["Save note"].tap()
        XCTAssertTrue(app.staticTexts["Saved"].waitForExistence(timeout: 20))
        app.buttons["Notes"].tap()
        XCTAssertTrue(app.buttons[edited].waitForExistence(timeout: 20))
        app.buttons[edited].tap()
        app.buttons["Move to Trash"].tap()
        XCTAssertTrue(app.alerts.buttons["Move to Trash"].waitForExistence(timeout: 5))
        app.alerts.buttons["Move to Trash"].tap()
        XCTAssertTrue(app.staticTexts["Notes loaded"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.buttons[edited].exists)

        app.buttons["Open my native Profile"].tap()
        XCTAssertTrue(app.navigationBars["Profile"].waitForExistence(timeout: 8))
    }

    private func input(_ app: XCUIApplication, _ label: String, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@ OR identifier == %@", label, id)).firstMatch
    }
}

@MainActor
final class VaultNetworkFailureUITests: XCTestCase {
    /// Run alone. The harness cuts the local TLS tunnel after the marker below.
    func testLiveBackendLossKeepsNativeShellAlive() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["Product Hub"].tap()
        signInFixtureIfNeeded(app)
        XCTAssertTrue(app.descendants(matching: .any)["account.ready"].waitForExistence(timeout: 20))
        let vault = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Vault Notes")).firstMatch
        vault.tap()
        XCTAssertTrue(app.descendants(matching: .any)["module.open"].waitForExistence(timeout: 8))
        app.descendants(matching: .any)["module.open"].tap()
        XCTAssertTrue(app.staticTexts["Notes loaded"].waitForExistence(timeout: 20))
        print("N1_NETWORK_CUT_READY")
        Thread.sleep(forTimeInterval: 12)
        app.buttons["Reload notes"].tap()
        XCTAssertTrue(app.staticTexts["Greenfield connection unavailable."].waitForExistence(timeout: 25))
        app.buttons["Close"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Vault Notes"].waitForExistence(timeout: 8))
        app.buttons["Home"].firstMatch.tap()
        app.buttons["Profile"].tap()
        XCTAssertTrue(app.navigationBars["Profile"].waitForExistence(timeout: 8))
    }
}

@MainActor
final class PhysicalN1AcceptanceTests: XCTestCase {
    func testPhysicalVaultLifecycleAndNativeOwnership() throws {
        guard let email = ProcessInfo.processInfo.environment["N1_PHYSICAL_EMAIL"],
              let password = ProcessInfo.processInfo.environment["N1_PHYSICAL_PASSWORD"] else {
            throw XCTSkip("Dedicated physical N1 credential environment is unavailable")
        }

        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.navigationBars["Modula"].waitForExistence(timeout: 15))
        app.buttons["Product Hub"].tap()

        if !app.descendants(matching: .any)["account.ready"].waitForExistence(timeout: 5) {
            app.buttons["Sign in to Modula"].tap()
            let emailField = app.textFields["Email"]
            let passwordField = app.secureTextFields["Password"]
            XCTAssertTrue(emailField.waitForExistence(timeout: 8))
            emailField.tap()
            typeSlowly(email, into: emailField)
            passwordField.tap()
            typeSlowly(password, into: passwordField)
            app.buttons["Sign in"].tap()
            XCTAssertTrue(app.staticTexts["Account"].waitForExistence(timeout: 25))
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }

        XCTAssertTrue(app.descendants(matching: .any)["account.ready"].waitForExistence(timeout: 20))
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Vault Notes")).firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["module.open"].waitForExistence(timeout: 10))
        app.descendants(matching: .any)["module.open"].tap()
        XCTAssertTrue(app.staticTexts["Notes loaded"].waitForExistence(timeout: 25))
        XCTAssertTrue(app.buttons["N1 Fixture 1"].waitForExistence(timeout: 8))

        let title = "PhysicalVault-\(UUID().uuidString.prefix(6))"
        app.buttons["New Note"].tap()
        let titleField = app.descendants(matching: .any)["vault.title"]
        let contentField = app.descendants(matching: .any)["vault.content"]
        titleField.tap()
        typeSlowly(title, into: titleField)
        contentField.tap()
        typeSlowly("Physical device bridge proof.", into: contentField)
        app.buttons["Save note"].tap()
        XCTAssertTrue(app.staticTexts["Saved"].waitForExistence(timeout: 25))
        app.buttons["Notes"].tap()
        XCTAssertTrue(app.buttons[title].waitForExistence(timeout: 25))

        app.buttons[title].tap()
        titleField.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        typeSlowly(" edited", into: titleField)
        app.buttons["Save note"].tap()
        XCTAssertTrue(app.staticTexts["Saved"].waitForExistence(timeout: 25))
        app.buttons["Notes"].tap()
        let edited = "\(title) edited"
        XCTAssertTrue(app.buttons[edited].waitForExistence(timeout: 25))

        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.staticTexts["Notes loaded"].waitForExistence(timeout: 20))
        app.buttons["Open my native Profile"].tap()
        XCTAssertTrue(app.navigationBars["Profile"].waitForExistence(timeout: 10))
        app.buttons["tab.modules"].tap()
        app.buttons["Close"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Product Hub"].waitForExistence(timeout: 10))

        app.descendants(matching: .any)["module.open"].tap()
        XCTAssertTrue(app.buttons[edited].waitForExistence(timeout: 25))
        app.buttons[edited].tap()
        app.buttons["Move to Trash"].tap()
        XCTAssertTrue(app.alerts.buttons["Move to Trash"].waitForExistence(timeout: 8))
        app.alerts.buttons["Move to Trash"].tap()
        XCTAssertTrue(app.staticTexts["Notes loaded"].waitForExistence(timeout: 25))
        app.buttons["Close"].firstMatch.tap()
    }

    private func typeSlowly(_ text: String, into element: XCUIElement) {
        for character in text {
            element.typeText(String(character))
            usleep(20_000)
        }
    }
}

private extension Duration {
    var milliseconds: Double { Double(components.seconds) * 1_000 + Double(components.attoseconds) / 1e15 }
}

private struct N1UITestFixture: Decodable { let email: String; let password: String }

@MainActor
private func signInFixtureIfNeeded(_ app: XCUIApplication) {
    if app.descendants(matching: .any)["account.ready"].waitForExistence(timeout: 3) { return }
    let path = ProcessInfo.processInfo.environment["N1_SECRET_FILE"] ?? "/Users/msjoy/Developer/modula-native/.env.n1.local"
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)), let fixture = try? JSONDecoder().decode(N1UITestFixture.self, from: data) else {
        XCTFail("N1 fixture file unavailable"); return
    }
    let signIn = app.buttons["Sign in to Modula"]
    XCTAssertTrue(signIn.waitForExistence(timeout: 5)); signIn.tap()
    pasteText(fixture.email, into: app.textFields["Email"], app: app)
    pasteText(fixture.password, into: app.secureTextFields["Password"], app: app)
    app.buttons["Sign in"].tap()
    XCTAssertTrue(app.staticTexts["Account"].waitForExistence(timeout: 25))
    app.navigationBars["Account"].buttons.element(boundBy: 0).tap()
}

@MainActor
private func pasteText(_ text: String, into element: XCUIElement, app: XCUIApplication, replacing: Bool = false) {
    XCTAssertTrue(element.waitForExistence(timeout: 8))
    UIPasteboard.general.string = text
    element.tap()
    if replacing {
        element.press(forDuration: 1)
        let selectAll = app.menuItems["Select All"]
        XCTAssertTrue(selectAll.waitForExistence(timeout: 5))
        selectAll.tap()
        element.typeText(text)
        if element.elementType != .secureTextField { XCTAssertEqual(element.value as? String, text) }
        return
    }
    element.press(forDuration: 1)
    let paste = app.menuItems["Paste"]
    XCTAssertTrue(paste.waitForExistence(timeout: 5))
    paste.tap()
    if element.elementType != .secureTextField { XCTAssertEqual(element.value as? String, text) }
}

final class ModuleRuntimeUITests: XCTestCase {
    @MainActor
    func testDiagnosticRemountFailureAndNativeRequest() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["Product Hub"].firstMatch.tap()
        for _ in 0..<2 {
            app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Runtime Diagnostic")).firstMatch.tap()
            XCTAssertTrue(app.staticTexts["Module runtime ready"].waitForExistence(timeout: 25))
            app.buttons["Reject invalid action"].tap()
            XCTAssertTrue(app.staticTexts["Invalid action safely rejected"].waitForExistence(timeout: 5))
            app.buttons["Close"].firstMatch.tap()
        }
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Runtime Diagnostic")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Module runtime ready"].waitForExistence(timeout: 10))
        app.buttons["Throw module error"].tap()
        XCTAssertTrue(app.buttons["Retry"].waitForExistence(timeout: 10))
        app.buttons["Retry"].tap()
        XCTAssertTrue(app.staticTexts["Module runtime ready"].waitForExistence(timeout: 10))
        app.buttons["Open native Profile"].tap()
        XCTAssertTrue(app.navigationBars["Profile"].waitForExistence(timeout: 5))
    }
}
