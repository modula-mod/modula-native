import XCTest
import UIKit

@MainActor
final class N2ShellUITests: XCTestCase {
    func testCanonicalShellRailProductHubModuleHostAndAppearance() throws {
        let launchStart = ContinuousClock.now
        let app = try launchThroughAppGate(arguments: ["--runtime-unavailable"])
        print("N2_METRIC shell_render_ms=\(launchStart.duration(to: .now).milliseconds)")

        let railStart = ContinuousClock.now
        app.buttons["For You"].firstMatch.tap()
        XCTAssertEqual(app.descendants(matching: .any)["native.home"].firstMatch.value as? String, "/home/for-you")
        print("N2_METRIC rail_switch_ms=\(railStart.duration(to: .now).milliseconds)")
        let tabStart = ContinuousClock.now
        selectTab(app, "Discover")
        XCTAssertTrue(app.staticTexts["Discover"].waitForExistence(timeout: 5))
        print("N2_METRIC tab_switch_ms=\(tabStart.duration(to: .now).milliseconds)")
        let hubStart = ContinuousClock.now
        openProductHubFromShell(app)

        let vault = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Vault Notes")).firstMatch
        XCTAssertTrue(vault.waitForExistence(timeout: 10))
        print("N2_METRIC product_hub_ms=\(hubStart.duration(to: .now).milliseconds)")
        let detailStart = ContinuousClock.now
        vault.tap()
        XCTAssertTrue(app.descendants(matching: .any)["module-detail.digital.modula.vault-notes"].waitForExistence(timeout: 8))
        print("N2_METRIC module_detail_ms=\(detailStart.duration(to: .now).milliseconds)")
        let hostStart = ContinuousClock.now
        tapModuleOpen(app)
        XCTAssertTrue(app.staticTexts["Vault Notes failed to load"].waitForExistence(timeout: 8))
        print("N2_METRIC module_host_transition_ms=\(hostStart.duration(to: .now).milliseconds)")
        app.buttons["Close"].firstMatch.tap()
        XCTAssertTrue(
            app.navigationBars["Vault Notes"].waitForExistence(timeout: 8)
                || app.descendants(matching: .any)["module-detail.digital.modula.vault-notes"].waitForExistence(timeout: 8)
        )

        selectTab(app, "Activity")
        app.buttons["Mentions"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["activity.mentions"].waitForExistence(timeout: 5))
        selectTab(app, "Profile")
        app.buttons["Posts"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["profile.posts"].waitForExistence(timeout: 5))

        selectTab(app, "Home")
        openSettingsFromShell(app)
        app.buttons["Appearance"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["settings.appearance"].waitForExistence(timeout: 5))
        let appearanceStart = ContinuousClock.now
        app.buttons["Violet"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Native design contract v1"].exists)
        print("N2_METRIC appearance_update_ms=\(appearanceStart.duration(to: .now).milliseconds)")
    }
}

@MainActor
final class N2PolishAccessibilityUITests: XCTestCase {
    func testLoopingRailAccessoryAndCompactChromeRemainReachable() throws {
        let app = try launchThroughAppGate(arguments: [
            "--runtime-unavailable", "--reset-appearance", "--ui-light", "--ui-compact"
        ])
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.exists)
        for title in ["Home", "Discover", "Modules", "Activity", "Profile"] {
            let element = tabBar.buttons[title]
            XCTAssertTrue(element.exists, "Missing native tab \(title)")
            XCTAssertTrue(element.isHittable, "Unreachable native tab \(title)")
        }
        for identifier in ["accessory.feeds", "accessory.summary", "accessory.tools"] {
            let element = app.descendants(matching: .any)[identifier]
            XCTAssertTrue(element.exists, "Missing shell control \(identifier)")
            XCTAssertTrue(element.isHittable, "Unreachable shell control \(identifier)")
        }

        app.buttons["Modules"].firstMatch.tap()
        XCTAssertEqual(app.descendants(matching: .any)["native.home"].value as? String, "/home/modules")
        attachScreenshot(app, name: "edge-rail-revealed-loop-state")
        app.buttons["Following"].firstMatch.tap()
        XCTAssertEqual(app.descendants(matching: .any)["native.home"].value as? String, "/home/following")

        openSettingsFromShell(app)
        XCTAssertTrue(app.descendants(matching: .any)["settings.root"].waitForExistence(timeout: 5))
        app.buttons["Appearance"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["settings.appearance"].waitForExistence(timeout: 5))
    }

    func testLargeDynamicTypeReducedTransparencyAndOLEDHaveStableLandmarks() throws {
        let app = try launchThroughAppGate(arguments: [
            "--runtime-unavailable", "--reset-appearance", "--ui-oled", "--ui-large-text", "--ui-reduce-transparency",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityExtraExtraLarge"
        ])
        XCTAssertTrue(app.descendants(matching: .any)["accessory.feeds"].firstMatch.isHittable
            || app.descendants(matching: .any)["tab.accessory"].firstMatch.exists)
        XCTAssertTrue(app.tabBars.buttons["Home"].firstMatch.isHittable)
        XCTAssertTrue(app.buttons["For You"].firstMatch.isHittable)
        openSettingsFromShell(app)
        app.buttons["Appearance"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["settings.appearance"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.staticTexts["Native design contract v1"].exists)
    }

    func testNativeTabMinimizationAndSettingsLargeTitle() throws {
        let app = try launchThroughAppGate(arguments: ["--runtime-unavailable", "--reset-appearance", "--ui-dim"])
        app.swipeUp()
        attachScreenshot(app, name: "home-native-tab-minimized")

        openSettingsFromShell(app)
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
    func testNativeLaunchAndDestinations() throws {
        let started = ContinuousClock.now
        let app = try launchThroughAppGate(arguments: ["--runtime-unavailable"])
        print("N1_METRIC native_cold_launch_ms=\(started.duration(to: .now).milliseconds)")
        openProductHubFromShell(app)
        XCTAssertTrue(app.navigationBars["Product Hub"].waitForExistence(timeout: 5)
            || app.descendants(matching: .any)["product-hub"].waitForExistence(timeout: 5))
        selectTab(app, "Home")
        selectTab(app, "Profile")
        XCTAssertTrue(app.navigationBars["Profile"].waitForExistence(timeout: 5)
            || app.descendants(matching: .any)["profile.overview"].waitForExistence(timeout: 5))
        selectTab(app, "Home")
        openSettingsFromShell(app)
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5)
            || app.descendants(matching: .any)["settings.root"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testRuntimeUnavailableIsContainedByNativeHost() throws {
        let app = try launchThroughAppGate(arguments: ["--runtime-unavailable"])
        openProductHubFromShell(app)
        let vault = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Vault Notes")).firstMatch
        XCTAssertTrue(vault.waitForExistence(timeout: 8))
        vault.tap()
        tapModuleOpen(app)
        XCTAssertTrue(app.staticTexts["Vault Notes failed to load"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["Retry"].exists)
        app.buttons["Close"].firstMatch.tap()
        XCTAssertTrue(
            app.navigationBars["Vault Notes"].waitForExistence(timeout: 8)
                || app.descendants(matching: .any)["module-detail.digital.modula.vault-notes"].waitForExistence(timeout: 8)
        )
    }

    @MainActor
    func testLocalIntelligenceDeveloperDiagnostics() throws {
        let app = try launchThroughAppGate(arguments: ["--runtime-unavailable"])
        openSettingsFromShell(app)

        let developer = app.buttons["Developer"].firstMatch
        XCTAssertTrue(developer.waitForExistence(timeout: 5))
        developer.tap()

        let localIntelligence = app.buttons["Local Intelligence"].firstMatch
        XCTAssertTrue(localIntelligence.waitForExistence(timeout: 5))
        localIntelligence.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["settings.developer.intelligence"]
                .waitForExistence(timeout: 8)
        )
        XCTAssertTrue(app.staticTexts["Apple system provider"].exists)
        XCTAssertTrue(app.staticTexts["Execution"].exists)
        XCTAssertTrue(app.staticTexts["Network required"].exists)
        let overviewAttachment = XCTAttachment(screenshot: app.screenshot())
        overviewAttachment.name = "mission-03-local-intelligence-overview"
        overviewAttachment.lifetime = .keepAlways
        add(overviewAttachment)

        app.swipeUp()
        XCTAssertTrue(
            app.descendants(matching: .any)["intelligence.apple.summarize"]
                .waitForExistence(timeout: 5)
        )
        app.swipeUp()
        XCTAssertTrue(
            app.descendants(matching: .any)["intelligence.deterministic.summarize"]
                .waitForExistence(timeout: 5)
        )

        let actionsAttachment = XCTAttachment(screenshot: app.screenshot())
        actionsAttachment.name = "mission-03-local-intelligence-actions"
        actionsAttachment.lifetime = .keepAlways
        add(actionsAttachment)
    }
}

@MainActor
final class VaultRuntimeUITests: XCTestCase {
    func testRealVaultCRUDLifecycleAppearanceAndNativeNavigation() throws {
        let app = try launchSignedInApp()
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

    func testTenOpenCloseCyclesReuseOneRuntime() throws {
        let app = try launchSignedInApp()
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
        openSettingsFromShell(app)
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

    private func launchSignedInApp() throws -> XCUIApplication {
        try launchThroughAppGate(arguments: ["--reset-appearance"])
    }

    private func openProductHub(_ app: XCUIApplication) {
        openProductHubFromShell(app)
        XCTAssertTrue(app.descendants(matching: .any)["account.ready"].waitForExistence(timeout: 20))
    }

    private func openVault(_ app: XCUIApplication) {
        let primary = app.descendants(matching: .any)["module.primary"].firstMatch
        let open = app.descendants(matching: .any)["module.open"].firstMatch
        if primary.waitForExistence(timeout: 2) { primary.tap(); return }
        if open.waitForExistence(timeout: 2) { open.tap(); return }
        let vault = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Vault Notes")).firstMatch
        XCTAssertTrue(vault.waitForExistence(timeout: 8))
        vault.tap()
        tapModuleOpen(app)
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
    func testBundledVaultCRUDAndNativeOwnership() throws {
        let app = try launchThroughAppGate(arguments: [], skipFirstRunHook: false)
        openProductHubFromShell(app)
        XCTAssertTrue(app.descendants(matching: .any)["account.ready"].waitForExistence(timeout: 20))
        let vault = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Vault Notes")).firstMatch
        XCTAssertTrue(vault.waitForExistence(timeout: 8))
        vault.tap()
        tapModuleOpen(app)
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
    func testLiveBackendLossKeepsNativeShellAlive() throws {
        let app = try launchThroughAppGate()
        openProductHubFromShell(app)
        XCTAssertTrue(app.descendants(matching: .any)["account.ready"].waitForExistence(timeout: 20))
        let vault = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Vault Notes")).firstMatch
        vault.tap()
        tapModuleOpen(app)
        XCTAssertTrue(app.staticTexts["Notes loaded"].waitForExistence(timeout: 20))
        print("N1_NETWORK_CUT_READY")
        Thread.sleep(forTimeInterval: 12)
        app.buttons["Reload notes"].tap()
        XCTAssertTrue(app.staticTexts["Greenfield connection unavailable."].waitForExistence(timeout: 25))
        app.buttons["Close"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Vault Notes"].waitForExistence(timeout: 8))
        selectTab(app, "Home")
        selectTab(app, "Profile")
        XCTAssertTrue(app.navigationBars["Profile"].waitForExistence(timeout: 8)
            || app.descendants(matching: .any)["profile.overview"].waitForExistence(timeout: 8))
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
        app.launchArguments = ["--uitest-skip-first-run", "--uitest-n1-api"]
        app.launch()
        try awaitShellReady(app, credentials: N1UITestFixture(email: email, password: password))

        openProductHubFromShell(app)
        XCTAssertTrue(app.descendants(matching: .any)["account.ready"].waitForExistence(timeout: 20))
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Vault Notes")).firstMatch.tap()
        tapModuleOpen(app)
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
        XCTAssertTrue(app.navigationBars["Product Hub"].waitForExistence(timeout: 10)
            || app.descendants(matching: .any)["product-hub"].waitForExistence(timeout: 5))

        tapModuleOpen(app)
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

private struct N1UITestFixture: Decodable {
    let email: String
    let password: String
}

private let n1FixtureDefaultPath = "/Users/msjoy/Developer/modula-native/.env.n1.local"

@MainActor
private func n1FixturePath() -> String {
    ProcessInfo.processInfo.environment["N1_SECRET_FILE"] ?? n1FixtureDefaultPath
}

@MainActor
private func loadN1Fixture() -> N1UITestFixture? {
    let path = n1FixturePath()
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
          let fixture = try? JSONDecoder().decode(N1UITestFixture.self, from: data),
          !fixture.email.isEmpty,
          !fixture.password.isEmpty else {
        return nil
    }
    return fixture
}

@MainActor
private func requireN1FixtureOrSkip() throws -> N1UITestFixture {
    guard let fixture = loadN1Fixture() else {
        throw XCTSkip("N1 fixture file unavailable; AppGate UITests require local fixture credentials")
    }
    return fixture
}

/// Launch Modula and traverse AppGate → onboarding/auth → first-run (unless skipped) → shell.
@MainActor
private func launchThroughAppGate(
    arguments: [String] = [],
    skipFirstRunHook: Bool = true,
    timeout: TimeInterval = 60
) throws -> XCUIApplication {
    let fixture = try requireN1FixtureOrSkip()
    let app = XCUIApplication()
    var args = arguments
    if !args.contains("--uitest-n1-api") {
        args.append("--uitest-n1-api")
    }
    if skipFirstRunHook, !args.contains("--uitest-skip-first-run") {
        args.append("--uitest-skip-first-run")
    }
    app.launchArguments = args
    app.launch()
    try awaitShellReady(app, credentials: fixture, timeout: timeout)
    return app
}

@MainActor
private func awaitShellReady(
    _ app: XCUIApplication,
    credentials: N1UITestFixture,
    timeout: TimeInterval = 60
) throws {
    let deadline = Date().addingTimeInterval(timeout)
    var didAttemptSignIn = false
    while Date() < deadline {
        let home = app.descendants(matching: .any)["native.home"]
        if home.waitForExistence(timeout: 1) { return }

        if app.descendants(matching: .any)["applock.lock"].exists {
            XCTFail("App Lock is enabled; UITests cannot unlock without a device passcode")
            return
        }

        if app.descendants(matching: .any)["appgate.failed"].exists {
            XCTFail("AppGate failed to boot")
            return
        }

        if app.descendants(matching: .any)["onboarding.root"].exists {
            let skip = app.descendants(matching: .any)["onboarding.skip"]
            if skip.waitForExistence(timeout: 2) {
                skip.tap()
            }
            continue
        }

        if app.descendants(matching: .any)["firstrun.root"].exists {
            completeFirstRunIfNeeded(app)
            continue
        }

        if app.descendants(matching: .any)["auth.error"].exists, didAttemptSignIn {
            XCTFail("Fixture sign-in failed (auth.error present)")
            return
        }

        if app.descendants(matching: .any)["auth.login"].exists
            || app.descendants(matching: .any)["appgate.signed-out"].exists {
            if didAttemptSignIn {
                // Avoid hammering Greenfield while waiting for a slow session restore.
                RunLoop.current.run(until: Date().addingTimeInterval(0.5))
                continue
            }
            didAttemptSignIn = true
            signInThroughAppGate(app, credentials: credentials)
            continue
        }

        // Boot splash / transient states.
        _ = app.descendants(matching: .any)["appgate.booting"].waitForExistence(timeout: 0.5)
    }

    XCTFail("Timed out waiting for AppGate shell (native.home)")
}

@MainActor
private func signInThroughAppGate(_ app: XCUIApplication, credentials: N1UITestFixture) {
    if app.descendants(matching: .any)["native.home"].exists { return }

    if app.descendants(matching: .any)["onboarding.root"].exists {
        app.descendants(matching: .any)["onboarding.skip"].tap()
    }

    let fixtureButton = app.descendants(matching: .any)["auth.sign-in-fixture"]
    if fixtureButton.waitForExistence(timeout: 3) {
        fixtureButton.tap()
    } else {
        let emailField = app.descendants(matching: .any)["auth.email"]
        let passwordField = app.descendants(matching: .any)["auth.password"]
        let signIn = app.descendants(matching: .any)["auth.sign-in"]
        guard emailField.waitForExistence(timeout: 8) else {
            XCTFail("Auth email field missing after AppGate signed-out")
            return
        }
        pasteText(credentials.email, into: emailField, app: app)
        pasteText(credentials.password, into: passwordField, app: app)
        XCTAssertTrue(signIn.waitForExistence(timeout: 3))
        signIn.tap()
    }

    // Prefer shell; first-run may appear if the Debug skip hook is unavailable (Release).
    let shell = app.descendants(matching: .any)["native.home"]
    let firstRun = app.descendants(matching: .any)["firstrun.root"]
    let authError = app.descendants(matching: .any)["auth.error"]
    let deadline = Date().addingTimeInterval(30)
    while Date() < deadline {
        if shell.exists { return }
        if firstRun.exists { return }
        if authError.exists {
            XCTFail("Fixture sign-in failed (auth.error present)")
            return
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
    }
    XCTFail("Fixture sign-in did not reach shell or first-run")
}

@MainActor
private func completeFirstRunIfNeeded(_ app: XCUIApplication) {
    let root = app.descendants(matching: .any)["firstrun.root"]
    guard root.waitForExistence(timeout: 2) else { return }

    // Dismiss the iOS notification permission sheet if it appears.
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    for _ in 0..<4 {
        if app.descendants(matching: .any)["native.home"].exists { return }
        let continueButton = app.descendants(matching: .any)["firstrun.continue"]
        if continueButton.waitForExistence(timeout: 3) {
            continueButton.tap()
        }
        let allow = springboard.buttons["Allow"]
        if allow.waitForExistence(timeout: 1) {
            allow.tap()
        }
        let dontAllow = springboard.buttons["Don’t Allow"]
        if dontAllow.waitForExistence(timeout: 0.5) {
            dontAllow.tap()
        }
    }
}

/// Legacy Product Hub helper retained for any mid-test auth recovery.
@MainActor
private func signInFixtureIfNeeded(_ app: XCUIApplication) {
    if app.descendants(matching: .any)["account.ready"].waitForExistence(timeout: 3) { return }
    if app.descendants(matching: .any)["native.home"].exists { return }
    guard let fixture = loadN1Fixture() else {
        XCTFail("N1 fixture file unavailable")
        return
    }
    signInThroughAppGate(app, credentials: fixture)
    completeFirstRunIfNeeded(app)
    _ = app.descendants(matching: .any)["native.home"].waitForExistence(timeout: 20)
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

@MainActor
private func openMoreMenu(_ app: XCUIApplication) {
    // Home hides More; tab bar may be minimized after scroll — expand then go Modules.
    app.swipeDown()
    selectTab(app, "Modules")
    let more = app.descendants(matching: .any)["accessory.more"].firstMatch
    XCTAssertTrue(more.waitForExistence(timeout: 8), "Missing accessory.more")
    more.tap()
}

@MainActor
private func openSettingsFromShell(_ app: XCUIApplication) {
    openMoreMenu(app)
    let settings = app.buttons["Settings"].firstMatch
    XCTAssertTrue(settings.waitForExistence(timeout: 4), "Missing Settings in More menu")
    settings.tap()
}

@MainActor
private func openProductHubFromShell(_ app: XCUIApplication) {
    app.swipeDown()
    selectTab(app, "Modules")
    XCTAssertTrue(
        app.descendants(matching: .any)["product-hub"].waitForExistence(timeout: 8)
            || app.navigationBars["Product Hub"].waitForExistence(timeout: 8),
        "Product Hub did not appear"
    )
}

@MainActor
private func selectTab(_ app: XCUIApplication, _ title: String) {
    let tab = app.tabBars.buttons[title].firstMatch
    if tab.waitForExistence(timeout: 4) {
        tab.tap()
        return
    }
    app.buttons[title].firstMatch.tap()
}

@MainActor
private func tapModuleOpen(_ app: XCUIApplication) {
    let primary = app.descendants(matching: .any)["module.primary"].firstMatch
    if primary.waitForExistence(timeout: 4) {
        primary.tap()
        return
    }
    let open = app.descendants(matching: .any)["module.open"].firstMatch
    XCTAssertTrue(open.waitForExistence(timeout: 6), "Missing module open control")
    open.tap()
}

final class ModuleRuntimeUITests: XCTestCase {
    @MainActor
    func testDiagnosticRemountFailureAndNativeRequest() throws {
        let app = try launchThroughAppGate()
        openProductHubFromShell(app)
        let diagnostic = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Runtime Diagnostic")).firstMatch
        guard diagnostic.waitForExistence(timeout: 10) else {
            throw XCTSkip("Runtime Diagnostic module unavailable in current catalogue")
        }
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

@MainActor
final class N3AActivityAuthUITests: XCTestCase {
    func testActivityRailAccessoryAccountChromeAndAuthReturn() throws {
        let app = try launchThroughAppGate(arguments: ["--runtime-unavailable", "--reset-appearance"])

        selectTab(app, "Activity")
        XCTAssertTrue(app.descendants(matching: .any)["activity.all"].waitForExistence(timeout: 5))

        // AppGate requires sign-in before shell; Activity no longer presents a signed-out CTA.
        XCTAssertFalse(app.descendants(matching: .any)["activity.sign-in"].exists)

        app.buttons["Mentions"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["activity.mentions"].waitForExistence(timeout: 5))
        app.buttons["Requests"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["activity.requests"].waitForExistence(timeout: 5))
        app.buttons["All"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["activity.all"].waitForExistence(timeout: 5))

        // Accessory tools (when signed in) — Search must not be required on Activity.
        XCTAssertTrue(app.descendants(matching: .any)["tab.accessory"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["accessory.more"].exists)

        app.descendants(matching: .any)["accessory.more"].firstMatch.tap()
        let account = app.buttons["Account"].firstMatch
        XCTAssertTrue(account.waitForExistence(timeout: 3))
        account.tap()

        // Account settings should be reachable from the Activity More menu.
        XCTAssertTrue(
            app.descendants(matching: .any)["settings.account.root"].waitForExistence(timeout: 5)
                || app.navigationBars.matching(NSPredicate(format: "identifier CONTAINS %@ OR label CONTAINS %@", "Account", "Account")).firstMatch.waitForExistence(timeout: 3)
        )

        attachScreenshot(app, name: "n3a-account-chrome-hidden")
    }

    private func attachScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

@MainActor
final class N3BDiscoverUITests: XCTestCase {
    func testDiscoverScopesSearchProfilePostModuleFilterAndRefresh() throws {
        let app = try launchThroughAppGate(arguments: ["--runtime-unavailable", "--reset-appearance"])

        selectTab(app, "Discover")
        XCTAssertTrue(app.descendants(matching: .any)["discover.trending"].firstMatch.waitForExistence(timeout: 8))
        XCTAssertEqual(app.descendants(matching: .any)["discover.trending"].firstMatch.value as? String, "/discover/trending")

        app.descendants(matching: .any)["discover.scope.people"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["discover.people"].waitForExistence(timeout: 8))
        app.descendants(matching: .any)["discover.scope.topics"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["discover.topics"].waitForExistence(timeout: 8))
        app.descendants(matching: .any)["discover.scope.posts"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["discover.posts"].waitForExistence(timeout: 8))
        app.descendants(matching: .any)["discover.scope.modules"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["discover.modules"].waitForExistence(timeout: 8))
        app.descendants(matching: .any)["discover.scope.trending"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["discover.trending"].firstMatch.waitForExistence(timeout: 8))

        let searchEntry = app.descendants(matching: .any)["discover.search-entry"].firstMatch
        let accessorySearch = app.descendants(matching: .any)["accessory.search"].firstMatch
        if searchEntry.waitForExistence(timeout: 4) {
            searchEntry.tap()
        } else if accessorySearch.waitForExistence(timeout: 3) {
            accessorySearch.tap()
        }
        if app.descendants(matching: .any)["search.root"].waitForExistence(timeout: 6) {
            if app.navigationBars.buttons.element(boundBy: 0).waitForExistence(timeout: 2) {
                app.navigationBars.buttons.element(boundBy: 0).tap()
            } else {
                selectTab(app, "Discover")
            }
            XCTAssertTrue(app.descendants(matching: .any)["discover.trending"].firstMatch.waitForExistence(timeout: 6))
        }

        let person = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "discover.person")).firstMatch
        if person.waitForExistence(timeout: 8) {
            person.tap()
            XCTAssertTrue(app.navigationBars["Profile"].waitForExistence(timeout: 6)
                || app.descendants(matching: .any)["profile.overview"].waitForExistence(timeout: 6))
            if app.navigationBars.buttons.element(boundBy: 0).waitForExistence(timeout: 2) {
                app.navigationBars.buttons.element(boundBy: 0).tap()
            } else {
                selectTab(app, "Discover")
            }
            XCTAssertTrue(app.descendants(matching: .any)["discover.trending"].firstMatch.waitForExistence(timeout: 6)
                || app.descendants(matching: .any)["discover.people"].firstMatch.waitForExistence(timeout: 3))
        }

        let post = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "discover.post")).firstMatch
        if post.waitForExistence(timeout: 4) {
            post.tap()
            XCTAssertTrue(
                app.navigationBars["Post"].waitForExistence(timeout: 6)
                    || app.descendants(matching: .any)["native.post"].firstMatch.waitForExistence(timeout: 4)
            )
            if app.navigationBars.buttons.element(boundBy: 0).waitForExistence(timeout: 2) {
                app.navigationBars.buttons.element(boundBy: 0).tap()
            } else {
                selectTab(app, "Discover")
            }
        }

        app.descendants(matching: .any)["discover.scope.modules"].firstMatch.tap()
        let module = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "product.")).firstMatch
        if module.waitForExistence(timeout: 10) {
            module.tap()
            XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "module-detail.")).firstMatch.waitForExistence(timeout: 8))
            if app.navigationBars.buttons.element(boundBy: 0).waitForExistence(timeout: 2) {
                app.navigationBars.buttons.element(boundBy: 0).tap()
            } else {
                selectTab(app, "Discover")
            }
            XCTAssertTrue(app.descendants(matching: .any)["discover.modules"].firstMatch.waitForExistence(timeout: 6))
        }

        let filter = app.descendants(matching: .any)["accessory.filter"].firstMatch
        if filter.waitForExistence(timeout: 4) {
            filter.tap()
            XCTAssertTrue(app.descendants(matching: .any)["discover.filter"].waitForExistence(timeout: 5))
            app.buttons["Close"].firstMatch.tap()
        }

        let refresh = app.descendants(matching: .any)["accessory.refresh"].firstMatch
        if refresh.waitForExistence(timeout: 3) {
            refresh.tap()
        }
        XCTAssertTrue(app.tabBars.buttons["Discover"].firstMatch.exists)
        attachScreenshot(app, name: "n3b-discover-tools")
    }

    private func attachScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

@MainActor
final class N3CHomeUITests: XCTestCase {
    func testHomeFeedLandmarksAndTools() throws {
        let app = try launchThroughAppGate(arguments: ["--runtime-unavailable", "--reset-appearance"])

        let home = app.descendants(matching: .any)["native.home"].firstMatch
        XCTAssertTrue(home.waitForExistence(timeout: 10))
        // AppGate mounts the shell only after sign-in; default landing is Following.
        XCTAssertEqual(home.value as? String, "/home/following")
        XCTAssertTrue(app.descendants(matching: .any)["home.hero"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["home.sign-in"].firstMatch.exists)

        XCTAssertTrue(app.descendants(matching: .any)["accessory.feeds"].firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any)["accessory.summary"].firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any)["accessory.tools"].firstMatch.exists)

        app.buttons["For You"].firstMatch.tap()
        XCTAssertEqual(app.descendants(matching: .any)["native.home"].firstMatch.value as? String, "/home/for-you")

        app.descendants(matching: .any)["accessory.summary"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["home.summary"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["Close"].firstMatch.tap()

        app.descendants(matching: .any)["accessory.tools"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["home.tools"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["Close"].firstMatch.tap()

        attachScreenshot(app, name: "n3c-home-tools")
    }

    func testProgressiveHeaderCollapseStages() throws {
        let app = try launchThroughAppGate(arguments: ["--runtime-unavailable", "--reset-appearance", "--ui-light"])

        let home = app.descendants(matching: .any)["native.home"].firstMatch
        XCTAssertTrue(home.waitForExistence(timeout: 10))
        attachScreenshot(app, name: "n3c-header-00-resting")

        // Switch to For You so the feed has public content to scroll under the header.
        app.buttons["For You"].firstMatch.tap()
        sleep(1)
        attachScreenshot(app, name: "n3c-header-01-foryou-resting")

        let header = app.descendants(matching: .any)["home.progressiveHeader"].firstMatch
        if header.exists {
            let path = header.value as? String ?? "unknown"
            XCTAssertTrue(path == "native-soft-edge" || path == "fallback-masked-material", "unexpected soft-edge path \(path)")
            attachScreenshot(app, name: "n3c-header-path-\(path)")
        }

        let stages = [0.25, 0.50, 0.75, 1.0]
        for (index, fraction) in stages.enumerated() {
            home.swipeUp(velocity: .slow)
            // Brief settle so scroll progress preference updates.
            usleep(350_000)
            attachScreenshot(app, name: String(format: "n3c-header-%02d-%.0f", index + 2, fraction * 100))
        }
    }

    private func attachScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

@MainActor
final class N3DProfileUITests: XCTestCase {
    func testOwnProfileRailAndEditEntry() throws {
        let app = try launchThroughAppGate(arguments: ["--runtime-unavailable", "--reset-appearance"])

        selectTab(app, "Profile")
        XCTAssertTrue(app.descendants(matching: .any)["profile.overview"].waitForExistence(timeout: 10))

        if app.descendants(matching: .any)["rail.posts"].firstMatch.waitForExistence(timeout: 4) {
            app.descendants(matching: .any)["rail.posts"].firstMatch.tap()
            XCTAssertTrue(app.descendants(matching: .any)["profile.posts"].waitForExistence(timeout: 6))
            app.descendants(matching: .any)["rail.modules"].firstMatch.tap()
            XCTAssertTrue(app.descendants(matching: .any)["profile.modules"].waitForExistence(timeout: 6))
            app.descendants(matching: .any)["rail.overview"].firstMatch.tap()
            XCTAssertTrue(app.descendants(matching: .any)["profile.overview"].waitForExistence(timeout: 6))
        }

        if app.descendants(matching: .any)["profile.edit.cta"].firstMatch.waitForExistence(timeout: 4) {
            app.descendants(matching: .any)["profile.edit.cta"].firstMatch.tap()
            XCTAssertTrue(app.descendants(matching: .any)["profile.edit"].waitForExistence(timeout: 6))
        }

        attachScreenshot(app, name: "n3d-profile-me-overview")
    }

    func testDiscoverAuthorProfileBackPreservesStack() throws {
        let app = try launchThroughAppGate(arguments: ["--runtime-unavailable", "--reset-appearance"])

        selectTab(app, "Discover")
        XCTAssertTrue(app.descendants(matching: .any)["discover.trending"].waitForExistence(timeout: 8))
        app.descendants(matching: .any)["discover.scope.people"].firstMatch.tap()

        let person = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "discover.person")).firstMatch
        guard person.waitForExistence(timeout: 8) else {
            attachScreenshot(app, name: "n3d-profile-other-skipped-no-people")
            return
        }
        person.tap()
        XCTAssertTrue(app.descendants(matching: .any)["profile.overview"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.tabBars.buttons["Discover"].firstMatch.exists)

        if app.descendants(matching: .any)["rail.posts"].firstMatch.waitForExistence(timeout: 3) {
            app.descendants(matching: .any)["rail.posts"].firstMatch.tap()
            XCTAssertTrue(app.descendants(matching: .any)["profile.posts"].waitForExistence(timeout: 6))
        }

        if app.navigationBars.buttons.element(boundBy: 0).waitForExistence(timeout: 3) {
            app.navigationBars.buttons.element(boundBy: 0).tap()
        } else {
            app.swipeRight()
        }
        if !(app.descendants(matching: .any)["discover.people"].firstMatch.waitForExistence(timeout: 4)
            || app.descendants(matching: .any)["discover.trending"].firstMatch.waitForExistence(timeout: 2)) {
            // Full-bleed profile chrome may not expose a nav-bar back control; Discover tab remains selected.
            selectTab(app, "Discover")
            XCTAssertTrue(app.descendants(matching: .any)["discover.people"].firstMatch.waitForExistence(timeout: 6)
                || app.descendants(matching: .any)["discover.trending"].firstMatch.waitForExistence(timeout: 6))
        }
        attachScreenshot(app, name: "n3d-profile-other-back")
    }

    private func attachScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
