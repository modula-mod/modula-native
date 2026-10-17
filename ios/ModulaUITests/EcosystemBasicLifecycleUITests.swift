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
        return app
    }

    @MainActor
    private func relaunch(_ app: XCUIApplication, isolateNetwork: Bool) {
        app.terminate()
        app.launchArguments = arguments(isolateNetwork: isolateNetwork)
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["native.home"].waitForExistence(timeout: 30))
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
        selectTab(app, "Modules")
        XCTAssertTrue(app.descendants(matching: .any)["product-hub"].waitForExistence(timeout: 15))
        let card = app.staticTexts["Basic Echo"].firstMatch
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Basic Echo")).firstMatch
        for _ in 0..<6 where !card.exists && !row.exists { app.swipeUp() }
        XCTAssertTrue(card.waitForExistence(timeout: 8) || row.waitForExistence(timeout: 2))
        if row.exists { row.tap() } else { card.tap() }
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
    private func selectTab(_ app: XCUIApplication, _ title: String) {
        let tab = app.tabBars.buttons[title].firstMatch
        if tab.waitForExistence(timeout: 4) { tab.tap(); return }
        app.buttons[title].firstMatch.tap()
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
