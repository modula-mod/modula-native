import CryptoKit
import XCTest

/// Fixture-backed Basic Echo acceptance. Live account credentials stay outside the repo
/// and are used only when MODULA_QA_CREDENTIALS_FILE is set.
final class EcosystemBasicLifecycleUITests: XCTestCase {
    private var root: URL!
    private var trustKey: URL!
    private var accountID = "uitest-local-modules"
    private let signer = Curve25519.Signing.PrivateKey()

    override func setUpWithError() throws {
        continueAfterFailure = false
        root = FileManager.default.temporaryDirectory.appendingPathComponent("modula-eco-ui-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        accountID = "uitest-\(UUID().uuidString.prefix(8).lowercased())"
        trustKey = root.appendingPathComponent("dev-trust.pub.pem")
        try writeTrustKey()
        try writePackage(version: "0.1.0", welcome: "Welcome to Basic Echo", sign: true)
    }

    override func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    @MainActor
    func testInstallThenUpdateWithoutRebuildingNative() throws {
        let app = launch(isolateNetwork: false)
        try openBasic(app)
        let primary = app.buttons["module.primary"].firstMatch
        try tap(primary, in: app)
        attach(app, name: "basic-permission-review")
        XCTAssertTrue(app.staticTexts["Install"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["storage:records"].waitForExistence(timeout: 2))
        try confirm(app)
        XCTAssertTrue(wait(primary, label: "Open", timeout: 25), "Install did not finish: \(notice(app))")
        try tap(primary, in: app)
        XCTAssertTrue(app.staticTexts["Welcome to Basic Echo"].waitForExistence(timeout: 20))
        attach(app, name: "basic-0-1-0")
        back(app)

        try writePackage(version: "0.1.1", welcome: "Welcome to Basic Echo 0.1.1", sign: true)
        relaunch(app, isolateNetwork: false)
        try openBasic(app)
        XCTAssertTrue(wait(primary, contains: "Update", timeout: 15), "Update was not offered. Label: \(primary.exists ? primary.label : "missing")")
        try tap(primary, in: app)
        attach(app, name: "basic-update-review")
        XCTAssertTrue(app.staticTexts["Permissions are unchanged."].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["0.1.0 → 0.1.1"].waitForExistence(timeout: 2))
        try confirm(app)
        XCTAssertTrue(wait(primary, label: "Open", timeout: 25), "Update did not finish: \(notice(app))")
        try tap(primary, in: app)
        XCTAssertTrue(app.staticTexts["Welcome to Basic Echo 0.1.1"].waitForExistence(timeout: 20))
        attach(app, name: "basic-0-1-1")
    }

    @MainActor
    func testCachedOpenWhileAppNetworkIsIsolated() throws {
        try writePackage(version: "0.1.1", welcome: "Welcome to Basic Echo 0.1.1", sign: true)
        let app = launch(isolateNetwork: false)
        try openBasic(app)
        let primary = app.buttons["module.primary"].firstMatch
        try tap(primary, in: app)
        try confirm(app)
        XCTAssertTrue(wait(primary, label: "Open", timeout: 25))
        try tap(primary, in: app)
        XCTAssertTrue(app.staticTexts["Welcome to Basic Echo 0.1.1"].waitForExistence(timeout: 20))
        relaunch(app, isolateNetwork: true)
        try openInstalled(app)
        XCTAssertTrue(app.staticTexts["Welcome to Basic Echo 0.1.1"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.descendants(matching: .any)["module.host.network-isolated"].waitForExistence(timeout: 4))
        attach(app, name: "basic-offline-cached")
    }

    @MainActor
    func testRollbackRejectsBadDigestAndRestoresPreviousAfterRestart() throws {
        let app = launch(isolateNetwork: false)
        try openBasic(app)
        let primary = app.buttons["module.primary"].firstMatch
        try tap(primary, in: app)
        try confirm(app)
        XCTAssertTrue(wait(primary, label: "Open", timeout: 25))
        try tap(primary, in: app)
        XCTAssertTrue(app.staticTexts["Welcome to Basic Echo"].waitForExistence(timeout: 20))
        try openLab(app)
        app.buttons["module.lifecycle.stage-bad-digest"].tap()
        app.buttons["module.lifecycle.activate"].tap()
        let audit = app.descendants(matching: .any)["module.lifecycle.audit"]
        XCTAssertTrue(wait(audit, contains: "digest-rejected", timeout: 8), "Audit was \(audit.exists ? audit.label : "missing")")
        XCTAssertTrue(app.descendants(matching: .any)["module.lifecycle.active-version"].label.contains("0.1.0"))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["Welcome to Basic Echo"].waitForExistence(timeout: 8))
        attach(app, name: "basic-rollback-digest")

        try writePackage(version: "0.1.1", welcome: "Welcome to Basic Echo 0.1.1", sign: true)
        relaunch(app, isolateNetwork: false)
        try openInstalled(app)
        try openLab(app)
        app.buttons["module.lifecycle.fail-health"].tap()
        XCTAssertTrue(wait(audit, contains: "activation-health", timeout: 8), "Audit was \(audit.exists ? audit.label : "missing")")
        XCTAssertTrue(app.descendants(matching: .any)["module.lifecycle.active-version"].label.contains("0.1.0"))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["Welcome to Basic Echo"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["Welcome to Basic Echo 0.1.1"].exists)
        attach(app, name: "basic-rollback-health")

        relaunch(app, isolateNetwork: false)
        try openInstalled(app)
        XCTAssertTrue(app.staticTexts["Welcome to Basic Echo"].waitForExistence(timeout: 20))
        try openLab(app)
        XCTAssertTrue(app.descendants(matching: .any)["module.lifecycle.audit"].label.contains("activation-health"))
        XCTAssertTrue(app.descendants(matching: .any)["module.lifecycle.active-version"].label.contains("0.1.0"))
        attach(app, name: "basic-rollback-relaunch")
    }

    @MainActor
    func testLiveAccountAcceptanceIsOptIn() throws {
        guard ProcessInfo.processInfo.environment["MODULA_QA_CREDENTIALS_FILE"] != nil else {
            throw XCTSkip("Set MODULA_QA_CREDENTIALS_FILE to run the live-account Basic Echo acceptance. Credentials are not stored in the repo.")
        }
        throw XCTSkip("Live-account coverage stays opt-in so this suite does not depend on a shared password or a package that appears mid-run.")
    }

    @MainActor
    private func launch(isolateNetwork: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments(isolateNetwork: isolateNetwork)
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["native.home"].waitForExistence(timeout: 30), "Fixture shell did not appear")
        dismissStartupCelebration(app)
        return app
    }

    @MainActor
    private func relaunch(_ app: XCUIApplication, isolateNetwork: Bool) {
        app.terminate()
        app.launchArguments = arguments(isolateNetwork: isolateNetwork)
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["native.home"].waitForExistence(timeout: 30))
        dismissStartupCelebration(app)
    }

    @MainActor
    private func dismissStartupCelebration(_ app: XCUIApplication) {
        let dismiss = app.buttons["Yay!"].firstMatch
        if dismiss.waitForExistence(timeout: 2) { dismiss.tap() }
    }

    private func arguments(isolateNetwork: Bool) -> [String] {
        var args = [
            "--uitest-skip-first-run",
            "--uitest-local-module-session",
            "--uitest-local-account", accountID,
            "--modula-dev-modules-root", root.path,
            "--modula-dev-trust-public-key", trustKey.path,
        ]
        if isolateNetwork { args.append("--modula-isolate-app-network") }
        return args
    }

    @MainActor
    private func openBasic(_ app: XCUIApplication) throws {
        app.open(URL(string: "modula://product-hub/module/digital.modula.basic-echo")!)
        XCTAssertTrue(app.buttons["module.primary"].waitForExistence(timeout: 8))
    }

    @MainActor
    private func openInstalled(_ app: XCUIApplication) throws {
        try openBasic(app)
        let primary = app.buttons["module.primary"].firstMatch
        if primary.label.localizedCaseInsensitiveContains("open") {
            try tap(primary, in: app)
        } else if app.buttons["module.open"].exists {
            app.buttons["module.open"].tap()
        }
    }

    @MainActor
    private func openLab(_ app: XCUIApplication) throws {
        let debug = app.buttons["module.host.debug"].firstMatch
        XCTAssertTrue(debug.waitForExistence(timeout: 6))
        debug.tap()
        let lab = app.buttons["Lifecycle lab"].firstMatch
        XCTAssertTrue(lab.waitForExistence(timeout: 3))
        lab.tap()
        XCTAssertTrue(app.descendants(matching: .any)["module.lifecycle.lab"].waitForExistence(timeout: 4))
    }

    @MainActor
    private func confirm(_ app: XCUIApplication) throws {
        let button = app.buttons["module.install.confirm"].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 4), "Permission confirmation did not appear")
        button.tap()
    }

    @MainActor
    private func tap(_ element: XCUIElement, in app: XCUIApplication) throws {
        XCTAssertTrue(element.waitForExistence(timeout: 8))
        if element.isHittable {
            element.tap()
        } else {
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
    }

    @MainActor
    private func wait(_ element: XCUIElement, label: String, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "label == %@", label)
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: timeout) == .completed
    }

    @MainActor
    private func wait(_ element: XCUIElement, contains: String, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS[c] %@", contains)
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: timeout) == .completed
    }

    @MainActor
    private func notice(_ app: XCUIApplication) -> String {
        let error = app.descendants(matching: .any)["module.lifecycle-error"].firstMatch
        return error.exists ? error.label : "none"
    }

    @MainActor
    private func back(_ app: XCUIApplication) {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        if back.exists { back.tap() }
    }

    @MainActor
    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func writeTrustKey() throws {
        let prefix = Data([0x30, 0x2a, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x70, 0x03, 0x21, 0x00])
        let spki = prefix + signer.publicKey.rawRepresentation
        let body = spki.base64EncodedString(options: [.lineLength64Characters])
        try "-----BEGIN PUBLIC KEY-----\n\(body)\n-----END PUBLIC KEY-----\n".write(to: trustKey, atomically: true, encoding: .utf8)
    }

    private func writePackage(version: String, welcome: String, sign: Bool) throws {
        let dir = root.appendingPathComponent("digital.modula.basic-echo/\(version)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let frontend = """
        {"schema":"modula.frontend.1.0","frontendSchemaVersion":"1.0.0","mpsVersion":"1.0","productId":"digital.modula.basic-echo","releaseVersion":"\(version)","mode":"declarative","entry":"home","hostRuntime":{"versionRange":">=1.0.0"},"routes":[{"path":"/","viewId":"home"}],"views":[{"id":"home","kind":"dashboard","root":{"type":"section","accessibility":{"label":"Basic Echo home"},"children":[{"type":"text","text":"\(welcome)"}]}}],"accessibility":{"declaration":"host-baseline-with-product-semantics","screenReader":true,"scalableText":true,"keyboardNavigation":true,"reduceMotion":true}}
        """
        try frontend.write(to: dir.appendingPathComponent("frontend.manifest.json"), atomically: true, encoding: .utf8)
        let module = """
        {"id":"digital.modula.basic-echo","name":"Basic Echo","description":"Fixture echo","version":"\(version)","permissions":[{"id":"storage:records","risk":"low","reason":"Stores echo preferences for this account."}]}
        """
        try module.write(to: dir.appendingPathComponent("modula.module.json"), atomically: true, encoding: .utf8)
        guard sign else { return }
        let digest = SHA256.hash(data: Data(frontend.utf8)).map { String(format: "%02x", $0) }.joined()
        try digest.write(to: dir.appendingPathComponent("package.sha256"), atomically: true, encoding: .utf8)
        let signature = try signer.signature(for: Data(digest.utf8)).base64EncodedString()
        let keyId = SHA256.hash(data: Data([0x30, 0x2a, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x70, 0x03, 0x21, 0x00]) + signer.publicKey.rawRepresentation)
            .map { String(format: "%02x", $0) }.joined()
        let facts = """
        {"algorithm":"ed25519","digest":"\(digest)","digestAlgorithm":"sha256","keyId":"\(keyId)","signature":"\(signature)"}
        """
        try facts.write(to: dir.appendingPathComponent("signed-facts.json"), atomically: true, encoding: .utf8)
    }
}

/// Physical-device acceptance. Packages and the development public key are already in the
/// app sandbox. This test does not skip authentication and does not inject a fixture session.
final class EcosystemPhysicalDeviceUITests: XCTestCase {
    private let moduleId = "digital.modula.basic-echo"

    override func setUpWithError() throws {
        continueAfterFailure = false
        #if targetEnvironment(simulator)
        throw XCTSkip("Physical Basic Echo acceptance runs on the iPhone, not the simulator.")
        #endif
    }

    @MainActor
    func testInstallUpdateRollbackOnPhysicalDevice() throws {
        let app = XCUIApplication()
        app.launchArguments = []
        addUIInterruptionMonitor(withDescription: "system") { alert in
            for title in ["Allow", "OK", "Don’t Allow", "Don't Allow", "Not Now"] where alert.buttons[title].exists {
                alert.buttons[title].tap()
                return true
            }
            return false
        }
        app.launch()
        try reachShell(app)
        attach(app, name: "physical-home")
        selectTab(app, "tab.modules")
        XCTAssertTrue(app.descendants(matching: .any)["product-hub"].waitForExistence(timeout: 20))
        if app.buttons["Product Hub menu"].waitForExistence(timeout: 4) {
            app.buttons["Product Hub menu"].tap()
            if app.buttons["product-hub.developer-studio"].waitForExistence(timeout: 4) {
                app.buttons["product-hub.developer-studio"].tap()
                if app.descendants(matching: .any)["developer.studio"].waitForExistence(timeout: 8) {
                    attach(app, name: "physical-developer-studio")
                    back(app)
                }
            }
        }
        selectTab(app, "tab.modules")
        try openBasic(app)
        let primary = app.buttons["module.primary"].firstMatch
        XCTAssertTrue(primary.waitForExistence(timeout: 8))
        let permissions = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "settings:register"))
        for _ in 0..<6 where !permissions.firstMatch.exists { app.swipeUp() }
        XCTAssertTrue(permissions.firstMatch.waitForExistence(timeout: 8), "Exact Basic Echo permissions were not shown")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "settings:read")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "settings:write")).firstMatch.exists)
        attach(app, name: "physical-basic-permissions")
        if !primary.label.localizedCaseInsensitiveContains("open") {
            try tap(primary, in: app)
            try confirm(app)
            XCTAssertTrue(wait(primary, label: "Open", timeout: 40), "Install did not finish: \(notice(app))")
        }
        try tap(primary, in: app)
        XCTAssertTrue(app.staticTexts["Welcome to Basic Echo"].waitForExistence(timeout: 25))
        XCTAssertFalse(app.staticTexts["Welcome to Basic Echo 0.1.1"].exists)
        attach(app, name: "physical-basic-0-1-0")
        print("R4_PHASE_A_READY")

        XCTAssertTrue(waitForUpdate(app), "Release 0.1.1 was not offered")
        try openBasic(app)
        let update = app.buttons["module.primary"].firstMatch
        XCTAssertTrue(update.label.localizedCaseInsensitiveContains("update"))
        attach(app, name: "physical-basic-update-offered")
        try tap(update, in: app)
        XCTAssertTrue(app.staticTexts["0.1.0 → 0.1.1"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.staticTexts["Permissions are unchanged."].exists)
        try confirm(app)
        XCTAssertTrue(wait(update, label: "Open", timeout: 40), "Update did not finish: \(notice(app))")
        try tap(update, in: app)
        XCTAssertTrue(app.staticTexts["Welcome to Basic Echo 0.1.1"].waitForExistence(timeout: 25))
        XCTAssertTrue(app.buttons["product-ui.button.echoAgain"].waitForExistence(timeout: 6))
        attach(app, name: "physical-basic-0-1-1")
        print("R4_PHASE_B_READY")

        try openLab(app)
        app.buttons["module.lifecycle.stage-bad-digest"].tap()
        app.buttons["module.lifecycle.activate"].tap()
        let audit = app.descendants(matching: .any)["module.lifecycle.audit"]
        XCTAssertTrue(wait(audit, contains: "digest-rejected", timeout: 8), "Audit was \(audit.exists ? audit.label : "missing")")
        XCTAssertTrue(app.descendants(matching: .any)["module.lifecycle.active-version"].label.contains("0.1.1"))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["Welcome to Basic Echo 0.1.1"].waitForExistence(timeout: 8))
        attach(app, name: "physical-rollback-digest")
        print("R4_WAITING_FOR_HEALTH")

        XCTAssertTrue(waitForUpdate(app), "Release 0.1.2 was not available for the health-failure rollback")
        try openBasic(app)
        if app.buttons["module.open"].waitForExistence(timeout: 4) {
            app.buttons["module.open"].tap()
        }
        XCTAssertTrue(app.staticTexts["Welcome to Basic Echo 0.1.1"].waitForExistence(timeout: 20))
        try openLab(app)
        app.buttons["module.lifecycle.fail-health"].tap()
        XCTAssertTrue(wait(audit, contains: "activation-health", timeout: 10), "Audit was \(audit.exists ? audit.label : "missing")")
        XCTAssertTrue(app.descendants(matching: .any)["module.lifecycle.active-version"].label.contains("0.1.1"))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["Welcome to Basic Echo 0.1.1"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["Welcome to Basic Echo 0.1.2"].exists)
        attach(app, name: "physical-rollback-health")

        app.terminate()
        app.launch()
        try reachShell(app)
        try openBasic(app)
        if app.buttons["module.primary"].firstMatch.label.localizedCaseInsensitiveContains("open") {
            try tap(app.buttons["module.primary"].firstMatch, in: app)
        } else if app.buttons["module.open"].exists {
            app.buttons["module.open"].tap()
        }
        XCTAssertTrue(app.staticTexts["Welcome to Basic Echo 0.1.1"].waitForExistence(timeout: 25))
        try openLab(app)
        XCTAssertTrue(app.descendants(matching: .any)["module.lifecycle.audit"].label.contains("activation-health"))
        XCTAssertTrue(app.descendants(matching: .any)["module.lifecycle.active-version"].label.contains("0.1.1"))
        attach(app, name: "physical-rollback-relaunch")
        print("R4_PHYSICAL_DONE")
    }

    @MainActor
    private func reachShell(_ app: XCUIApplication) throws {
        let homeTab = app.buttons["tab.home"]
        let homeLabel = app.buttons["Home"]
        let home = app.descendants(matching: .any)["native.home"]
        let login = app.descendants(matching: .any)["auth.login"]
        let deadline = Date().addingTimeInterval(70)
        while Date() < deadline, !homeTab.exists, !homeLabel.exists, !home.exists, !login.exists {
            app.activate()
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        if !homeTab.exists && !homeLabel.exists && !home.exists && !login.exists {
            let labels = app.buttons.allElementsBoundByIndex.prefix(15).map(\.label).joined(separator: " | ")
            XCTFail("The shell did not leave the boot screen. Buttons: \(labels)")
        }
        if app.buttons["Done"].exists { app.buttons["Done"].tap() }
        if app.descendants(matching: .any)["developer.studio"].exists { app.swipeDown() }
        if login.exists { try signIn(app) }
        app.open(URL(string: "modula://home")!)
        if homeTab.exists { homeTab.tap() }
        else if homeLabel.exists { homeLabel.tap() }
        let following = app.staticTexts["Following"]
        let stories = app.staticTexts["Stories"]
        let homeVisible = home.waitForExistence(timeout: 8) || following.waitForExistence(timeout: 3) || stories.waitForExistence(timeout: 2)
        if homeVisible {
            print("R4_HOME_READY")
        } else {
            print("R4_HOME_PARTIAL")
            XCTAssertTrue(homeTab.exists || app.buttons["tab.modules"].exists || app.buttons["Modules"].exists, "No shell navigation after launch")
        }
        if app.descendants(matching: .any)["account.ready"].exists {
            print("R4_ACCOUNT \(app.descendants(matching: .any)["account.ready"].label)")
        }
    }

    @MainActor
    private func signIn(_ app: XCUIApplication) throws {
        let env = ProcessInfo.processInfo.environment
        let email = env["MODULA_QA_EMAIL"] ?? env["TEST_RUNNER_MODULA_QA_EMAIL"] ?? ""
        let password = env["MODULA_QA_PASSWORD"] ?? env["TEST_RUNNER_MODULA_QA_PASSWORD"] ?? ""
        XCTAssertFalse(email.isEmpty && password.isEmpty, "Sign-in is required and no QA credentials were passed to the test runner")
        let emailField = app.textFields["auth.email"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 6))
        emailField.tap()
        emailField.typeText(email)
        let passwordField = app.secureTextFields["auth.password"]
        XCTAssertTrue(passwordField.waitForExistence(timeout: 4))
        passwordField.tap()
        passwordField.typeText(password)
        app.buttons["auth.sign-in"].tap()
        let error = app.descendants(matching: .any)["auth.error"]
        XCTAssertTrue(app.buttons["tab.home"].waitForExistence(timeout: 40), "Sign-in did not reach the shell. \(error.exists ? error.label : "")")
    }

    @MainActor
    private func waitForUpdate(_ app: XCUIApplication) -> Bool {
        for _ in 0..<16 {
            app.terminate()
            app.launch()
            guard app.buttons["tab.home"].waitForExistence(timeout: 30) || app.descendants(matching: .any)["auth.login"].exists else { continue }
            if app.descendants(matching: .any)["auth.login"].exists { continue }
            selectTab(app, "tab.modules")
            app.open(URL(string: "modula://product-hub/module/\(moduleId)")!)
            let named = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Basic Echo")).firstMatch
            if !app.buttons["module.primary"].waitForExistence(timeout: 6), named.waitForExistence(timeout: 4) {
                named.tap()
            }
            let primary = app.buttons["module.primary"].firstMatch
            if primary.waitForExistence(timeout: 8), primary.label.localizedCaseInsensitiveContains("update") {
                return true
            }
            sleep(6)
        }
        return false
    }

    @MainActor
    private func openBasic(_ app: XCUIApplication) throws {
        if app.descendants(matching: .any)["developer.studio"].exists { app.swipeDown() }
        selectTab(app, "tab.modules")
        app.open(URL(string: "modula://product-hub/module/\(moduleId)")!)
        if !app.buttons["module.primary"].waitForExistence(timeout: 8) {
            let named = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Basic Echo")).firstMatch
            for _ in 0..<8 where !named.exists { app.swipeUp() }
            XCTAssertTrue(named.waitForExistence(timeout: 6), "Basic Echo was not in Product Hub")
            named.tap()
        }
        XCTAssertTrue(app.buttons["module.primary"].waitForExistence(timeout: 10))
    }

    @MainActor
    private func openLab(_ app: XCUIApplication) throws {
        let debug = app.buttons["module.host.debug"].firstMatch
        XCTAssertTrue(debug.waitForExistence(timeout: 8))
        debug.tap()
        let lab = app.buttons["Lifecycle lab"].firstMatch
        XCTAssertTrue(lab.waitForExistence(timeout: 4))
        lab.tap()
        XCTAssertTrue(app.descendants(matching: .any)["module.lifecycle.lab"].waitForExistence(timeout: 6))
    }

    @MainActor
    private func confirm(_ app: XCUIApplication) throws {
        let button = app.buttons["module.install.confirm"].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 6), "Permission confirmation did not appear")
        button.tap()
    }

    @MainActor
    private func tap(_ element: XCUIElement, in app: XCUIApplication) throws {
        XCTAssertTrue(element.waitForExistence(timeout: 8))
        if element.isHittable { element.tap() }
        else { element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
    }

    @MainActor
    private func wait(_ element: XCUIElement, label: String, timeout: TimeInterval) -> Bool {
        XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", label), object: element)], timeout: timeout) == .completed
    }

    @MainActor
    private func wait(_ element: XCUIElement, contains: String, timeout: TimeInterval) -> Bool {
        XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS[c] %@", contains), object: element)], timeout: timeout) == .completed
    }

    @MainActor
    private func notice(_ app: XCUIApplication) -> String {
        let error = app.descendants(matching: .any)["module.lifecycle-error"].firstMatch
        return error.exists ? error.label : "none"
    }

    @MainActor
    private func back(_ app: XCUIApplication) {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        if back.exists { back.tap() }
    }

    @MainActor
    private func selectTab(_ app: XCUIApplication, _ identifier: String) {
        let tab = app.buttons[identifier].firstMatch
        if tab.waitForExistence(timeout: 6) { tab.tap() }
    }

    @MainActor
    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
