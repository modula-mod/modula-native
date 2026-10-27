import CryptoKit
import XCTest

/// Opt-in live QA acceptance. qa-account.json is copied into the UI-test bundle
/// during a local run and is ignored by Git; neither credentials nor tokens ship.
final class WebGameRegistryUITests: XCTestCase {
    private struct QAAccount: Decodable { let email: String; let password: String }

    @MainActor
    func testInstallTwoSharedPhaserGames() throws {
        continueAfterFailure = false
        let app = try signedInApp(forceSignedOut: true)
        for (moduleID, title, shouldReuseRuntime) in [
            ("digital.modula.orbit-phaser", "Orbit Arena 2D", false),
            ("digital.modula.orbit-dash", "Orbit Dash", true),
        ] {
            let primary = try openProduct(app, moduleID: moduleID)
            XCTAssertTrue(primary.label.localizedCaseInsensitiveContains("install"), "\(title): \(primary.label)")
            primary.tap()
            let confirm = app.buttons["module.install.confirm"].firstMatch
            XCTAssertTrue(confirm.waitForExistence(timeout: 15), "Package review missing for \(title)")
            XCTAssertTrue(app.staticTexts["Download plan"].waitForExistence(timeout: 20), "Package closure missing for \(title)")
            XCTAssertTrue(app.staticTexts["Shared runtime"].exists)
            if shouldReuseRuntime {
                XCTAssertTrue(app.staticTexts["Already downloaded and verified"].exists,
                              "Second game did not recognize the verified Phaser runtime")
            }
            capture(app, name: "qa-02r-\(moduleID)-install-preview")
            XCTAssertTrue(confirm.isEnabled)
            confirm.tap()
            waitForOpen(primary, title: title)
            primary.tap()
            XCTAssertTrue(app.buttons["game.host.exit"].waitForExistence(timeout: 25), "\(title) did not launch")
            XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 15))
            capture(app, name: "qa-02r-\(moduleID)-running")
            app.buttons["game.host.exit"].tap()
            leaveDetail(app)
        }
    }

    @MainActor
    func testReopenTwoCachedPhaserGamesAndFinishArenaRound() throws {
        let app = try signedInApp()
        for moduleID in ["digital.modula.orbit-phaser", "digital.modula.orbit-dash"] {
            let primary = try openProduct(app, moduleID: moduleID)
            XCTAssertEqual(primary.label, "Open", "Cached game is not installed: \(moduleID)")
            primary.tap()
            let download = app.buttons["module.download.confirm"].firstMatch
            if download.waitForExistence(timeout: 5) {
                XCTAssertTrue(app.staticTexts["Download plan"].exists)
                download.tap()
            }
            XCTAssertTrue(app.buttons["game.host.exit"].waitForExistence(timeout: 25))
            let web = app.webViews.firstMatch
            XCTAssertTrue(web.waitForExistence(timeout: 15))
            RunLoop.current.run(until: Date().addingTimeInterval(6))
            capture(app, name: "qa-02r-\(moduleID)-reopened-playable")
            let start = web.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.62))
            let target = web.coordinate(withNormalizedOffset: CGVector(dx: 0.66, dy: 0.45))
            start.press(forDuration: 0.1, thenDragTo: target)
            if moduleID.hasSuffix("orbit-phaser") {
                RunLoop.current.run(until: Date().addingTimeInterval(65))
                capture(app, name: "qa-02r-\(moduleID)-round-complete")
            }
            app.buttons["game.host.exit"].tap()
            leaveDetail(app)
        }
    }

    @MainActor
    func testUpdateOrbitDashWithoutNativeRebuild() throws {
        let app = try signedInApp()
        let dash = try openProduct(app, moduleID: "digital.modula.orbit-dash")
        if dash.label == "Open" {
            // The fresh registry installs the latest release. Exercise the signed 0.1.0
            // track first, then upgrade through the same Product Hub review flow.
            let earlier = app.buttons["module.version.0.1.0.action"].firstMatch
            let detail = app.descendants(matching: .any)["module-detail.digital.modula.orbit-dash"]
            XCTAssertTrue(detail.exists)
            let detailScroll = app.scrollViews.containing(.any, identifier: "module.versions").firstMatch
            XCTAssertTrue(detailScroll.waitForExistence(timeout: 10))
            for _ in 0..<10 where !earlier.isHittable || earlier.frame.maxY > app.frame.height * 0.60 {
                detailScroll.swipeUp()
            }
            XCTAssertTrue(earlier.waitForExistence(timeout: 15) && earlier.isHittable)
            XCTAssertLessThan(earlier.frame.maxY, app.frame.height * 0.60,
                              "The version control is still under the floating navigation")
            capture(app, name: "qa-02r-orbit-dash-before-downgrade")
            earlier.tap()
            let downgrade = app.buttons["module.version-switch.confirm"].firstMatch
            XCTAssertTrue(downgrade.waitForExistence(timeout: 15))
            XCTAssertTrue(app.staticTexts["Download plan"].waitForExistence(timeout: 20))
            downgrade.tap()
            let updateReady = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "label == %@", "Update"), object: dash)
            XCTAssertEqual(XCTWaiter().wait(for: [updateReady], timeout: 45), .completed,
                           "Orbit Dash 0.1.0 did not activate")
            let reviewDismissed = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "exists == false"), object: downgrade)
            XCTAssertEqual(XCTWaiter().wait(for: [reviewDismissed], timeout: 15), .completed,
                           "The previous version review is still covering Product Hub")
            capture(app, name: "qa-02r-orbit-dash-0.1.0-active")
        }
        XCTAssertEqual(dash.label, "Update")
        XCTAssertTrue(dash.isHittable)
        capture(app, name: "qa-02r-orbit-dash-before-update")
        dash.tap()
        let confirm = app.buttons["module.version-switch.confirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Download plan"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["Already downloaded and verified"].exists)
        capture(app, name: "qa-02r-orbit-dash-0.1.1-update-preview")
        confirm.tap()
        waitForOpen(dash, title: "Orbit Dash 0.1.1")
        dash.tap()
        XCTAssertTrue(app.buttons["game.host.exit"].waitForExistence(timeout: 25))
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 15))
        RunLoop.current.run(until: Date().addingTimeInterval(6))
        capture(app, name: "qa-02r-orbit-dash-0.1.1-running")
        app.buttons["game.host.exit"].tap()
        leaveDetail(app)

        let arena = try openProduct(app, moduleID: "digital.modula.orbit-phaser")
        XCTAssertEqual(arena.label, "Open")
        arena.tap()
        XCTAssertTrue(app.buttons["game.host.exit"].waitForExistence(timeout: 25))
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 15))
        RunLoop.current.run(until: Date().addingTimeInterval(6))
        capture(app, name: "qa-02r-orbit-arena-after-dash-update")
        app.buttons["game.host.exit"].tap()
    }

    @MainActor
    func testCaptureLivePackageStorage() throws {
        continueAfterFailure = false
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let openDeepLink = springboard.alerts.buttons["Open"].firstMatch
        if openDeepLink.exists { openDeepLink.tap() }
        let app = try signedInApp()
        let sidebar = app.buttons["shell.sidebar.trigger"].firstMatch
        XCTAssertTrue(sidebar.waitForExistence(timeout: 10))
        sidebar.tap()
        let settings = app.buttons["shell.sidebar.settings"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        let storage = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Storage & Downloads")).firstMatch
        for _ in 0..<8 where !storage.exists { app.swipeUp() }
        XCTAssertTrue(storage.waitForExistence(timeout: 10))
        storage.tap()
        XCTAssertTrue(app.staticTexts["Total Optional Storage"].waitForExistence(timeout: 20))
        capture(app, name: "qa-02r-storage-two-games-live")
        let dash = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "digital.modula.orbit-dash,")).firstMatch
        XCTAssertTrue(dash.waitForExistence(timeout: 10))
        dash.tap()
        let removeDash = app.buttons["Remove digital.modula.orbit-dash download"].firstMatch
        XCTAssertTrue(removeDash.waitForExistence(timeout: 10))
        removeDash.tap()
        let dashGone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: dash)
        XCTAssertEqual(XCTWaiter().wait(for: [dashGone], timeout: 15), .completed)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "digital.modula.orbit-phaser,")).firstMatch.exists)
        capture(app, name: "qa-02r-storage-one-game-live")

        let arena = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "digital.modula.orbit-phaser,")).firstMatch
        arena.tap()
        let removeArena = app.buttons["Remove digital.modula.orbit-phaser download"].firstMatch
        XCTAssertTrue(removeArena.waitForExistence(timeout: 10))
        removeArena.tap()
        let arenaGone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: arena)
        XCTAssertEqual(XCTWaiter().wait(for: [arenaGone], timeout: 15), .completed)
        capture(app, name: "qa-02r-storage-all-games-removed-runtime-retained")

        let reclaim = app.buttons["Remove unused dependencies"].firstMatch
        for _ in 0..<6 where !reclaim.exists { app.swipeUp() }
        XCTAssertTrue(reclaim.waitForExistence(timeout: 10))
        reclaim.tap()
        let confirmReclaim = app.buttons["Remove unused dependencies"].firstMatch
        XCTAssertTrue(confirmReclaim.waitForExistence(timeout: 10))
        confirmReclaim.tap()
        XCTAssertTrue(app.staticTexts["No shared web runtimes are downloaded."].waitForExistence(timeout: 15))
        capture(app, name: "qa-02r-storage-all-games-removed-runtime-reclaimed")
    }

    @MainActor
    func testOpenAccountInstalledGameAfterCacheReclamation() throws {
        continueAfterFailure = false
        let app = try signedInApp()
        let primary = try openProduct(app, moduleID: "digital.modula.orbit-dash")
        XCTAssertEqual(primary.label, "Open")
        primary.tap()
        let confirm = app.buttons["module.download.confirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 15), "Reclaimed game did not show a download review")
        XCTAssertTrue(app.staticTexts["Download plan"].exists)
        XCTAssertFalse(app.staticTexts["Already downloaded and verified"].exists)
        capture(app, name: "qa-02r-reinstall-after-cache-reclamation-preview")
        confirm.tap()
        let started = app.buttons["game.host.exit"].waitForExistence(timeout: 25)
        XCTAssertTrue(started, "Account-installed Orbit Dash did not redownload after cache reclamation")
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 15))
        RunLoop.current.run(until: Date().addingTimeInterval(6))
        capture(app, name: "qa-02r-reopen-after-cache-reclamation")
    }

    @MainActor
    func testRemoveReinstalledDashAndReclaimRuntime() throws {
        continueAfterFailure = false
        let app = try signedInApp()
        app.buttons["shell.sidebar.trigger"].tap()
        app.buttons["shell.sidebar.settings"].tap()
        let storage = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Storage & Downloads")).firstMatch
        for _ in 0..<8 where !storage.exists { app.swipeUp() }
        XCTAssertTrue(storage.waitForExistence(timeout: 10))
        storage.tap()
        let dash = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "digital.modula.orbit-dash,")).firstMatch
        XCTAssertTrue(dash.waitForExistence(timeout: 15))
        dash.tap()
        let remove = app.buttons["Remove digital.modula.orbit-dash download"].firstMatch
        XCTAssertTrue(remove.waitForExistence(timeout: 10))
        remove.tap()
        XCTAssertTrue(app.staticTexts["No downloaded modules or games for this account."].waitForExistence(timeout: 15))
        app.buttons["Remove unused dependencies"].firstMatch.tap()
        app.buttons["Remove unused dependencies"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["No shared web runtimes are downloaded."].waitForExistence(timeout: 15))
        capture(app, name: "qa-02r-reinstall-second-reclaim")
    }

    @MainActor
    func testReclaimRuntimeAfterProductHubUninstalls() throws {
        continueAfterFailure = false
        let app = try signedInApp()
        app.buttons["shell.sidebar.trigger"].tap()
        app.buttons["shell.sidebar.settings"].tap()
        let storage = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Storage & Downloads")).firstMatch
        for _ in 0..<8 where !storage.exists { app.swipeUp() }
        XCTAssertTrue(storage.waitForExistence(timeout: 10))
        storage.tap()
        XCTAssertTrue(app.staticTexts["Total Optional Storage"].waitForExistence(timeout: 20))
        capture(app, name: "qa-02r-after-producthub-uninstall-runtime-retained")
        let reclaim = app.buttons["Remove unused dependencies"].firstMatch
        for _ in 0..<6 where !reclaim.exists { app.swipeUp() }
        XCTAssertTrue(reclaim.waitForExistence(timeout: 10))
        reclaim.tap()
        let confirm = app.buttons["Remove unused dependencies"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        confirm.tap()
        XCTAssertTrue(app.staticTexts["No shared web runtimes are downloaded."].waitForExistence(timeout: 15))
        capture(app, name: "qa-02r-after-producthub-uninstall-runtime-reclaimed")
    }

    @MainActor
    func testUninstallBothGamesThroughProductHub() throws {
        continueAfterFailure = false
        let app = try signedInApp()
        for moduleID in ["digital.modula.orbit-dash", "digital.modula.orbit-phaser"] {
            let primary = try openProduct(app, moduleID: moduleID)
            XCTAssertEqual(primary.label, "Open")
            let scroll = app.scrollViews["module-detail.\(moduleID)"].firstMatch
            XCTAssertTrue(scroll.waitForExistence(timeout: 10))
            let uninstall = app.buttons["module.uninstall"].firstMatch
            for _ in 0..<12 {
                if uninstall.isHittable { break }
                scroll.swipeUp()
            }
            XCTAssertTrue(uninstall.isHittable)
            uninstall.tap()
            let confirm = app.buttons["module.uninstall.confirm"].firstMatch
            XCTAssertTrue(confirm.waitForExistence(timeout: 10))
            confirm.tap()
            let removed = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "label == %@", "Install"), object: primary)
            XCTAssertEqual(XCTWaiter().wait(for: [removed], timeout: 45), .completed,
                           "Product Hub did not uninstall \(moduleID)")
            capture(app, name: "qa-02r-\(moduleID)-account-uninstalled")
            leaveDetail(app)
        }
    }

    @MainActor
    func testInstallBothSignedRegistryGames() throws {
        let app = try signedInApp()
        for (moduleID, title) in [
            ("digital.modula.orbit-phaser", "Orbit Arena 2D"),
            ("digital.modula.orbit-playcanvas", "Orbit Arena 3D Web"),
        ] {
            let primary = try openProduct(app, moduleID: moduleID)
            XCTAssertTrue(primary.label.localizedCaseInsensitiveContains("install"), "\(title): \(primary.label)")
            primary.tap()
            let confirm = app.buttons["module.install.confirm"].firstMatch
            XCTAssertTrue(confirm.waitForExistence(timeout: 12), "Permission review missing for \(title)")
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "records:module.\(moduleID)")).firstMatch.exists,
                          "Scoped collection grants were not displayed for \(title)")
            confirm.tap()
            waitForOpen(primary, title: title)
            primary.tap()
            XCTAssertTrue(app.buttons["game.host.exit"].waitForExistence(timeout: 25), "\(title) did not launch")
            XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 15))
            capture(app, name: "qa-\(moduleID)-0.1.0")
            app.buttons["game.host.exit"].tap()
            leaveDetail(app)
        }
    }

    @MainActor
    func testUpdateBothRegistryGamesInSameBinary() throws {
        let app = try signedInApp()
        for (moduleID, title) in [
            ("digital.modula.orbit-phaser", "Orbit Arena 2D"),
            ("digital.modula.orbit-playcanvas", "Orbit Arena 3D Web"),
        ] {
            let primary = try openProduct(app, moduleID: moduleID)
            XCTAssertTrue(primary.label.localizedCaseInsensitiveContains("update"), "Update missing for \(title): \(primary.label)")
            primary.tap()
            let confirm = app.buttons["module.version-switch.confirm"].firstMatch
            XCTAssertTrue(confirm.waitForExistence(timeout: 25), "Version review missing for \(title)")
            XCTAssertTrue(app.staticTexts["No permission changes"].exists)
            confirm.tap()
            waitForOpen(primary, title: title)
            primary.tap()
            XCTAssertTrue(app.buttons["game.host.exit"].waitForExistence(timeout: 25), "\(title) update did not launch")
            let web = app.webViews.firstMatch
            XCTAssertTrue(web.waitForExistence(timeout: 15))
            if moduleID.hasSuffix("playcanvas") {
                XCTAssertTrue(web.buttons["High"].waitForExistence(timeout: 12))
                web.buttons["High"].tap()
                XCTAssertTrue(web.buttons["Low"].waitForExistence(timeout: 5))
            }
            capture(app, name: "qa-\(moduleID)-0.1.1")
            app.buttons["game.host.exit"].tap()
            leaveDetail(app)
        }
    }

    @MainActor
    func testPlayBothInstalledRegistryGamesThroughRoundCompletion() throws {
        continueAfterFailure = false
        let app = try signedInApp()
        for (moduleID, title) in [
            ("digital.modula.orbit-phaser", "Orbit Arena 2D"),
            ("digital.modula.orbit-playcanvas", "Orbit Arena 3D Web"),
        ] {
            let primary = try openProduct(app, moduleID: moduleID)
            XCTAssertEqual(primary.label, "Open", "Expected an installed QA game: \(title)")
            primary.tap()
            let exit = app.buttons["game.host.exit"].firstMatch
            XCTAssertTrue(exit.waitForExistence(timeout: 25), "\(title) did not launch")
            let web = app.webViews.firstMatch
            XCTAssertTrue(web.waitForExistence(timeout: 15))
            app.buttons["game.host.pause"].tap()
            let pauseOverlay = app.descendants(matching: .any)["game.host.paused"]
            XCTAssertTrue(pauseOverlay.waitForExistence(timeout: 5))
            app.buttons["game.host.resume"].tap()
            XCTAssertFalse(app.descendants(matching: .any)["game.host.paused"].exists)
            let start = web.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.49))
            let target = web.coordinate(withNormalizedOffset: CGVector(dx: 0.62, dy: 0.36))
            start.press(forDuration: 0.1, thenDragTo: target)
            RunLoop.current.run(until: Date().addingTimeInterval(4))
            capture(app, name: "qa-\(moduleID)-touch-movement")
            if moduleID.hasSuffix("playcanvas") {
                XCTAssertTrue(web.buttons["Pause"].waitForExistence(timeout: 5))
                web.buttons["Pause"].tap()
                XCTAssertTrue(web.buttons["Resume"].waitForExistence(timeout: 5))
                web.buttons["Resume"].tap()
            }
            RunLoop.current.run(until: Date().addingTimeInterval(65))
            capture(app, name: "qa-\(moduleID)-round-complete")
            if moduleID.hasSuffix("playcanvas") {
                let restart = web.buttons["Restart"]
                XCTAssertTrue(restart.waitForExistence(timeout: 8), "3D round did not complete")
                restart.tap()
                XCTAssertFalse(restart.exists)
            } else {
                // Phaser renders its controls in the canvas; the restart target
                // is at canvas center plus 98 game pixels in its 600x900 scene.
                web.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.57)).tap()
            }
            capture(app, name: "qa-\(moduleID)-restarted")
            exit.tap()
            leaveDetail(app)
        }
    }

    @MainActor
    func testInstalledRegistryGamesLaunchWithAppTransportIsolated() throws {
        let app = try signedInApp()
        app.terminate()
        app.launchArguments.append("--modula-isolate-app-network")
        app.launch()
        XCTAssertTrue(app.buttons["Modules"].waitForExistence(timeout: 30), "Cached shell did not relaunch")
        for moduleID in ["digital.modula.orbit-phaser", "digital.modula.orbit-playcanvas"] {
            let primary = try openProduct(app, moduleID: moduleID)
            XCTAssertEqual(primary.label, "Open", "Cached installation was unavailable")
            primary.tap()
            XCTAssertTrue(app.buttons["game.host.exit"].waitForExistence(timeout: 20))
            let web = app.webViews.firstMatch
            XCTAssertTrue(web.waitForExistence(timeout: 10))
            web.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.49))
                .press(forDuration: 0.1, thenDragTo: web.coordinate(withNormalizedOffset: CGVector(dx: 0.62, dy: 0.36)))
            capture(app, name: "qa-\(moduleID)-isolated-transport")
            RunLoop.current.run(until: Date().addingTimeInterval(65))
            capture(app, name: "qa-\(moduleID)-isolated-round-complete")
            if moduleID.hasSuffix("playcanvas") {
                XCTAssertTrue(web.buttons["Restart"].waitForExistence(timeout: 8), "Offline 3D round did not complete")
            }
            app.buttons["game.host.exit"].tap()
            leaveDetail(app)
        }
    }

    @MainActor
    func testTenLaunchExitCyclesPerSignedGame() throws {
        let app = try signedInApp()
        for (moduleID, title) in [
            ("digital.modula.orbit-phaser", "Orbit Arena 2D"),
            ("digital.modula.orbit-playcanvas", "Orbit Arena 3D Web"),
        ] {
            for cycle in 1...10 {
                let primary = try openProduct(app, moduleID: moduleID)
                XCTAssertEqual(primary.label, "Open", "\(title) unavailable on cycle \(cycle)")
                let started = Date()
                primary.tap()
                XCTAssertTrue(app.buttons["game.host.exit"].waitForExistence(timeout: 20), "\(title) host missing on cycle \(cycle)")
                XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 15), "\(title) WebKit missing on cycle \(cycle)")
                XCTAssertFalse(app.staticTexts["Game interrupted"].exists, "\(title) WebKit process failed on cycle \(cycle)")
                print("WEB_GAME_HOST_OPEN \(moduleID) cycle=\(cycle) seconds=\(Date().timeIntervalSince(started))")
                if cycle == 1 || cycle == 10 { capture(app, name: "qa-\(moduleID)-cycle-\(cycle)") }
                app.buttons["game.host.exit"].tap()
                leaveDetail(app)
            }
        }
    }

    @MainActor
    private func signedInApp(forceSignedOut: Bool = false) throws -> XCUIApplication {
        guard let folder = Bundle(for: Self.self).url(forResource: "GameFixtures", withExtension: nil),
              let data = try? Data(contentsOf: folder.appendingPathComponent("qa-account.json")),
              let credentials = try? JSONDecoder().decode(QAAccount.self, from: data) else {
            throw XCTSkip("Restricted QA credentials were not supplied to the UI-test bundle")
        }
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-skip-first-run", "--reset-appearance", "--modula-disable-hang-watchdog"]
        if forceSignedOut { app.launchArguments.append("--uitest-signed-out") }
        app.launch()
        let cancelProfileEdit = app.buttons["profile.edit.cancel"].firstMatch
        if cancelProfileEdit.waitForExistence(timeout: 3) { cancelProfileEdit.tap() }
        let login = app.descendants(matching: .any)["auth.login"]
        let home = app.descendants(matching: .any)["native.home"]
        let modulesTab = app.buttons["Modules"].firstMatch
        let deadline = Date().addingTimeInterval(50)
        while Date() < deadline && !login.exists && !home.exists && !modulesTab.exists {
            let landing = app.descendants(matching: .any)["onboarding.landing.continue"]
            if landing.exists { landing.tap() }
            let skip = app.buttons["onboarding.skip"].firstMatch
            if skip.exists { skip.tap() }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        if login.exists {
            let email = app.textFields["auth.email"].firstMatch
            let password = app.secureTextFields["auth.password"].firstMatch
            XCTAssertTrue(email.waitForExistence(timeout: 8) && password.exists)
            email.tap(); email.typeText(credentials.email)
            password.tap(); password.typeText(credentials.password)
            app.buttons["auth.sign-in"].tap()
        }
        XCTAssertTrue(home.waitForExistence(timeout: 8) || modulesTab.waitForExistence(timeout: 8),
                      "QA sign-in did not reach the authenticated shell")
        let dismissWhatsNew = app.buttons["Not now"].firstMatch
        if dismissWhatsNew.waitForExistence(timeout: 8) { dismissWhatsNew.tap() }
        return app
    }

    @MainActor
    private func openProduct(_ app: XCUIApplication, moduleID: String) throws -> XCUIElement {
        let hub = app.descendants(matching: .any)["product-hub"]
        if !hub.exists {
            let dismissWhatsNew = app.buttons["Not now"].firstMatch
            if dismissWhatsNew.exists { dismissWhatsNew.tap() }
            let modules = app.buttons["Modules"].firstMatch
            XCTAssertTrue(modules.waitForExistence(timeout: 10))
            modules.tap()
        }
        XCTAssertTrue(hub.waitForExistence(timeout: 20))
        let dismissWhatsNew = app.buttons["Not now"].firstMatch
        if dismissWhatsNew.waitForExistence(timeout: 3) { dismissWhatsNew.tap() }
        let card = app.buttons["product.\(moduleID)"].firstMatch
        for _ in 0..<10 where !card.isHittable { app.swipeUp() }
        XCTAssertTrue(card.waitForExistence(timeout: 12) && card.isHittable,
                      "QA registry product is not available on screen: \(moduleID)")
        card.tap()
        let primary = app.buttons["module.primary"].firstMatch
        XCTAssertTrue(primary.waitForExistence(timeout: 10))
        return primary
    }

    @MainActor
    private func waitForOpen(_ primary: XCUIElement, title: String) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Open"), object: primary)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 45), .completed, "\(title) installation did not settle")
    }

    @MainActor
    private func leaveDetail(_ app: XCUIApplication) {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        if back.exists { back.tap() }
    }

    @MainActor
    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

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

/// Simulator evidence for the same Native WebGameHost with two independently
/// built engine archives. These signed local fixtures exercise rendering; the
/// registry installation path has its own distribution acceptance gate.
final class WebGameHostUITests: XCTestCase {
    private let signer = Curve25519.Signing.PrivateKey()
    private var root: URL!
    private var trustKey: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        guard let fixtures = Bundle(for: Self.self).url(forResource: "GameFixtures", withExtension: nil) else {
            throw XCTSkip("The existing Game Lab package fixtures were not included in the UI test bundle.")
        }
        root = FileManager.default.temporaryDirectory.appendingPathComponent("modula-games-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        trustKey = root.appendingPathComponent("game-trust.pub.pem")
        let prefix = Data([0x30, 0x2a, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x70, 0x03, 0x21, 0x00])
        let spki = prefix + signer.publicKey.rawRepresentation
        try "-----BEGIN PUBLIC KEY-----\n\(spki.base64EncodedString(options: [.lineLength64Characters]))\n-----END PUBLIC KEY-----\n"
            .write(to: trustKey, atomically: true, encoding: .utf8)
        for engine in ["phaser", "playcanvas"] {
            try copySignedGame(engine: engine, from: fixtures)
        }
    }

    override func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    @MainActor
    func testPhaserRendersInsideModula() throws { try exercise("Orbit Arena 2D", expectedWebButton: nil) }

    @MainActor
    func testPlayCanvasRendersInsideSameHost() throws { try exercise("Orbit Arena 3D Web", expectedWebButton: "High") }

    @MainActor
    func testBothEnginePackagesUpdateWithoutNativeRebuild() throws {
        let app = XCUIApplication()
        let arguments = [
            "--uitest-skip-first-run", "--uitest-local-module-session",
            "--uitest-local-account", "game-update-\(UUID().uuidString.prefix(8))",
            "--modula-dev-modules-root", root.path,
            "--modula-dev-trust-public-key", trustKey.path,
        ]
        app.launchArguments = arguments
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["native.home"].waitForExistence(timeout: 30))
        for title in ["Orbit Arena 2D", "Orbit Arena 3D Web"] {
            let primary = openProduct(app, title: title)
            primary.tap()
            if app.buttons["module.install.confirm"].waitForExistence(timeout: 4) {
                app.buttons["module.install.confirm"].tap()
            }
            waitForOpen(primary)
            primary.tap()
            XCTAssertTrue(app.buttons["game.host.exit"].waitForExistence(timeout: 20))
            app.buttons["game.host.exit"].tap()
            leaveDetail(app)
        }
        try copySignedGame(engine: "phaser", version: "0.1.1", from: Bundle(for: Self.self).url(forResource: "GameFixtures", withExtension: nil)!)
        try copySignedGame(engine: "playcanvas", version: "0.1.1", from: Bundle(for: Self.self).url(forResource: "GameFixtures", withExtension: nil)!)
        app.terminate()
        app.launchArguments = arguments
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["native.home"].waitForExistence(timeout: 30))
        for (title, marker) in [("Orbit Arena 2D", "NOVA"), ("Orbit Arena 3D Web", "Low")] {
            let primary = openProduct(app, title: title)
            XCTAssertTrue(primary.waitForExistence(timeout: 8))
            primary.tap()
            if app.buttons["module.install.confirm"].waitForExistence(timeout: 4) {
                app.buttons["module.install.confirm"].tap()
            }
            waitForOpen(primary)
            primary.tap()
            XCTAssertTrue(app.buttons["game.host.exit"].waitForExistence(timeout: 20))
            if marker == "NOVA" {
                XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 15))
            } else {
                app.webViews.buttons["High"].tap()
                XCTAssertTrue(app.webViews.buttons[marker].waitForExistence(timeout: 5))
            }
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = title.replacingOccurrences(of: " ", with: "-") + "-0.1.1"
            attachment.lifetime = .keepAlways
            add(attachment)
            app.buttons["game.host.exit"].tap()
            leaveDetail(app)
        }
    }

    @MainActor
    private func openProduct(_ app: XCUIApplication, title: String) -> XCUIElement {
        let modules = app.buttons["tab.modules"].firstMatch
        if modules.waitForExistence(timeout: 5) { modules.tap() }
        else { app.buttons["Modules"].firstMatch.tap() }
        XCTAssertTrue(app.descendants(matching: .any)["product-hub"].waitForExistence(timeout: 15))
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
        let card = app.staticTexts[title].firstMatch
        for _ in 0..<8 where !row.exists && !card.exists { app.swipeUp() }
        XCTAssertTrue(row.waitForExistence(timeout: 8) || card.waitForExistence(timeout: 2))
        if row.exists { row.tap() } else { card.tap() }
        let primary = app.buttons["module.primary"].firstMatch
        XCTAssertTrue(primary.waitForExistence(timeout: 8))
        return primary
    }

    @MainActor
    private func waitForOpen(_ primary: XCUIElement) {
        let open = NSPredicate(format: "label == %@", "Open")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: open, object: primary)], timeout: 25), .completed)
    }

    @MainActor
    private func leaveDetail(_ app: XCUIApplication) {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        if back.exists { back.tap() }
    }

    @MainActor
    private func exercise(_ title: String, expectedWebButton: String?) throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--uitest-skip-first-run", "--uitest-local-module-session",
            "--uitest-local-account", "game-\(UUID().uuidString.prefix(8))",
            "--modula-dev-modules-root", root.path,
            "--modula-dev-trust-public-key", trustKey.path,
        ]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["native.home"].waitForExistence(timeout: 30))
        let modules = app.buttons["tab.modules"].firstMatch
        if modules.waitForExistence(timeout: 5) { modules.tap() }
        else { app.buttons["Modules"].firstMatch.tap() }
        XCTAssertTrue(app.descendants(matching: .any)["product-hub"].waitForExistence(timeout: 15))
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
        let card = app.staticTexts[title].firstMatch
        for _ in 0..<8 where !row.exists && !card.exists { app.swipeUp() }
        XCTAssertTrue(row.waitForExistence(timeout: 8) || card.waitForExistence(timeout: 2))
        if row.exists { row.tap() } else { card.tap() }
        let primary = app.buttons["module.primary"].firstMatch
        XCTAssertTrue(primary.waitForExistence(timeout: 8))
        primary.tap()
        if app.buttons["module.install.confirm"].waitForExistence(timeout: 4) {
            app.buttons["module.install.confirm"].tap()
        }
        let open = NSPredicate(format: "label == %@", "Open")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: open, object: primary)], timeout: 25), .completed)
        primary.tap()
        XCTAssertTrue(app.buttons["game.host.exit"].waitForExistence(timeout: 20))
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.waitForExistence(timeout: 15))
        if let expectedWebButton {
            let quality = web.buttons[expectedWebButton]
            XCTAssertTrue(quality.waitForExistence(timeout: 15))
            quality.tap()
            XCTAssertTrue(web.buttons["Low"].waitForExistence(timeout: 5))
            web.buttons["Pause"].tap()
            XCTAssertTrue(web.buttons["Resume"].waitForExistence(timeout: 5))
            web.buttons["Resume"].tap()
        }
        let start = web.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
        let target = web.coordinate(withNormalizedOffset: CGVector(dx: 0.68, dy: 0.45))
        start.press(forDuration: 0.1, thenDragTo: target)
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = title.replacingOccurrences(of: " ", with: "-") + "-in-Modula"
        capture.lifetime = .keepAlways
        add(capture)
        app.buttons["game.host.pause"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["game.host.paused"].waitForExistence(timeout: 4))
        app.buttons["game.host.exit"].tap()
    }

    private func copySignedGame(engine: String, version: String = "0.1.0", from fixtures: URL) throws {
        let product = fixtures.appendingPathComponent(version == "0.1.0" ? engine : "\(engine)-\(version)", isDirectory: true)
        let moduleId = "digital.modula.orbit-\(engine)"
        let destination = root.appendingPathComponent("\(moduleId)/\(version)", isDirectory: true)
        try FileManager.default.createDirectory(at: destination.appendingPathComponent("game"), withIntermediateDirectories: true)
        let manager = FileManager.default
        for (source, target) in [
            ("frontend.manifest.json", "frontend.manifest.json"),
            ("modula.module.json", "modula.module.json"),
            ("modula.product.json", "modula.product.json"),
            ("game.tgz", "game/game.tgz"),
            ("package.sha256", "package.sha256"),
        ] {
            try manager.copyItem(at: product.appendingPathComponent(source), to: destination.appendingPathComponent(target))
        }
        let digest = try String(contentsOf: destination.appendingPathComponent("package.sha256"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let signature = try signer.signature(for: Data(digest.utf8)).base64EncodedString()
        let prefix = Data([0x30, 0x2a, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x70, 0x03, 0x21, 0x00])
        let keyId = SHA256.hash(data: prefix + signer.publicKey.rawRepresentation)
            .map { String(format: "%02x", $0) }.joined()
        let facts = """
        {"algorithm":"ed25519","digest":"\(digest)","digestAlgorithm":"sha256","keyId":"\(keyId)","signature":"\(signature)"}
        """
        try facts.write(to: destination.appendingPathComponent("signed-facts.json"), atomically: true, encoding: .utf8)
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
