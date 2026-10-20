import XCTest
import UIKit

/// The accepted Edge Picker is scrub-only. Drive the real adjustable surface
/// instead of reviving the obsolete tappable-item contract.
@MainActor
private func scrubEdgePicker(_ app: XCUIApplication, to route: String, forward: Bool = true) {
    let picker = app.descendants(matching: .any)["shell.edge-loop"].firstMatch
    XCTAssertTrue(picker.waitForExistence(timeout: 5))
    // The accessibility element spans the screen-height rail. Keep the scrub to
    // one item stride; a large normalized drag can legitimately coast through
    // several looping items and make the destination device-size dependent.
    let start = picker.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: forward ? 0.42 : 0.58))
    let end = picker.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.50))
    start.press(forDuration: 0.12, thenDragTo: end)
    if route.hasPrefix("/home/") {
        let home = app.descendants(matching: .any)["native.home"].firstMatch
        XCTAssertTrue(home.waitForExistence(timeout: 5))
        XCTAssertTrue(NSPredicate(format: "value == %@", route).evaluate(with: home))
    } else {
        let identifier = String(route.dropFirst()).replacingOccurrences(of: "/", with: ".")
        XCTAssertTrue(app.descendants(matching: .any)[identifier].firstMatch.waitForExistence(timeout: 5))
    }
}

@MainActor
private func dismissModulaSheet(_ sheet: XCUIElement) {
    let handle = sheet.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.02))
    let destination = sheet.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.92))
    handle.press(forDuration: 0.12, thenDragTo: destination)
    XCTAssertFalse(sheet.waitForExistence(timeout: 4))
}

@MainActor
final class N2ShellUITests: XCTestCase {
    func testCanonicalShellRailProductHubModuleHostAndAppearance() throws {
        let launchStart = ContinuousClock.now
        let app = try launchThroughAppGate(arguments: ["--runtime-unavailable"])
        print("N2_METRIC shell_render_ms=\(launchStart.duration(to: .now).milliseconds)")

        let railStart = ContinuousClock.now
        scrubEdgePicker(app, to: "/home/for-you")
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
        scrubEdgePicker(app, to: "/activity/mentions")
        selectTab(app, "Profile")
        scrubEdgePicker(app, to: "/profile/posts")

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

        scrubEdgePicker(app, to: "/home/for-you")
        scrubEdgePicker(app, to: "/home/modules")
        attachScreenshot(app, name: "edge-rail-revealed-loop-state")
        scrubEdgePicker(app, to: "/home/for-you", forward: false)
        scrubEdgePicker(app, to: "/home/following", forward: false)

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
        XCTAssertTrue(app.descendants(matching: .any)["shell.edge-loop"].firstMatch.isHittable)
        scrubEdgePicker(app, to: "/home/for-you")
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

        let developer = scrollToElement(named: "Developer", in: app, maximumSwipes: 8)
        XCTAssertTrue(developer.exists)
        developer.tap()

        let localIntelligence = scrollToElement(named: "Local Intelligence", in: app, maximumSwipes: 4)
        XCTAssertTrue(localIntelligence.exists)
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

        let appleAction = app.descendants(matching: .any)["intelligence.apple.summarize"]
        for _ in 0..<8 where !appleAction.exists { app.swipeUp() }
        XCTAssertTrue(appleAction.waitForExistence(timeout: 5))
        let deterministicAction = app.descendants(matching: .any)["intelligence.deterministic.summarize"]
        for _ in 0..<8 where !deterministicAction.exists { app.swipeUp() }
        XCTAssertTrue(deterministicAction.waitForExistence(timeout: 5))

        let actionsAttachment = XCTAttachment(screenshot: app.screenshot())
        actionsAttachment.name = "mission-03-local-intelligence-actions"
        actionsAttachment.lifetime = .keepAlways
        add(actionsAttachment)
    }

    @MainActor
    func testNodusConfidenceVerificationQueueAndCancellationUI() throws {
        let app = try launchThroughAppGate(arguments: ["--runtime-unavailable", "--uitest-nodus-fixture"])
        openSettingsFromShell(app)
        let developer = scrollToElement(named: "Developer", in: app, maximumSwipes: 8)
        XCTAssertTrue(developer.exists)
        developer.tap()
        let localIntelligence = scrollToElement(named: "Local Intelligence", in: app, maximumSwipes: 4)
        XCTAssertTrue(localIntelligence.exists)
        localIntelligence.tap()

        let prompt = app.descendants(matching: .any)["intelligence.nodus.prompt"]
        for _ in 0..<4 where !prompt.exists { app.swipeUp() }
        XCTAssertTrue(prompt.waitForExistence(timeout: 8))
        pasteText("What's today's weather?", into: prompt, app: app, replacing: true)
        let generate = app.descendants(matching: .any)["intelligence.nodus.generate"]
        XCTAssertTrue(generate.waitForExistence(timeout: 5))
        generate.tap()

        let confidence = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "Confidence, Needs verification")
        ).firstMatch
        for _ in 0..<4 where !confidence.exists { app.swipeUp() }
        XCTAssertTrue(confidence.waitForExistence(timeout: 5))
        let freshness = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "Freshness, Current data needed")
        ).firstMatch
        for _ in 0..<3 where !freshness.exists { app.swipeUp() }
        XCTAssertTrue(freshness.waitForExistence(timeout: 5))
        let verification = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "Verification, Recommended")
        ).firstMatch
        for _ in 0..<3 where !verification.exists { app.swipeUp() }
        XCTAssertTrue(verification.waitForExistence(timeout: 5))
        let verify = app.descendants(matching: .any)["intelligence.nodus.verify"]
        for _ in 0..<3 where !verify.exists { app.swipeUp() }
        XCTAssertTrue(verify.waitForExistence(timeout: 5))
        verify.tap()
        let queued = app.staticTexts["Verification Mission queued locally"]
        for _ in 0..<4 where !queued.exists { app.swipeDown() }
        XCTAssertTrue(queued.waitForExistence(timeout: 5))

        for _ in 0..<4 where !prompt.exists { app.swipeUp() }
        pasteText("CANCEL_TEST", into: prompt, app: app, replacing: true)
        generate.tap()
        let cancel = app.descendants(matching: .any)["intelligence.nodus.cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 3))
        cancel.tap()
        let cancelled = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "Status, Cancelled")
        ).firstMatch
        for _ in 0..<4 where !cancelled.exists { app.swipeUp() }
        XCTAssertTrue(cancelled.waitForExistence(timeout: 8))

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "nodus-01-confidence-verification"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testNodusChatModelNotInstalledState() throws {
        let app = try launchThroughAppGate(arguments: ["--runtime-unavailable", "--uitest-nodus-missing"])
        openSettingsFromShell(app)
        let developer = scrollToElement(named: "Developer", in: app, maximumSwipes: 8)
        XCTAssertTrue(developer.exists)
        developer.tap()
        let localIntelligence = scrollToElement(named: "Local Intelligence", in: app, maximumSwipes: 4)
        XCTAssertTrue(localIntelligence.exists)
        localIntelligence.tap()
        let openChat = scrollToElement(named: "Open Nodus Chat", in: app, maximumSwipes: 4)
        XCTAssertTrue(openChat.exists)
        openChat.tap()

        XCTAssertTrue(app.descendants(matching: .any)["nodus.chat.screen"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)["nodus.chat.model-not-installed"].exists)
        XCTAssertTrue(app.staticTexts["modula.nodus"].exists)
        XCTAssertTrue(app.staticTexts["Model not installed"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["nodus.chat.input"].isEnabled)
    }

    @MainActor
    func testNodus02AWorkspaceAndSimulatorSurfaces() throws {
        let app = try launchThroughAppGate(arguments: ["--runtime-unavailable", "--uitest-nodus-missing"])
        openSettingsFromShell(app)
        let developer = scrollToElement(named: "Developer", in: app, maximumSwipes: 8)
        XCTAssertTrue(developer.exists)
        developer.tap()
        let localIntelligence = scrollToElement(named: "Local Intelligence", in: app, maximumSwipes: 4)
        XCTAssertTrue(localIntelligence.exists)
        localIntelligence.tap()

        let openWorkspace = scrollToElement(named: "Open Nodus Workspace", in: app, maximumSwipes: 8)
        XCTAssertTrue(openWorkspace.exists)
        openWorkspace.tap()
        XCTAssertTrue(app.descendants(matching: .any)["nodus.workspace"].waitForExistence(timeout: 8))

        let chats = app.descendants(matching: .any)["nodus.workspace.chats"].firstMatch
        XCTAssertTrue(chats.exists)
        chats.tap()
        XCTAssertTrue(app.descendants(matching: .any)["nodus.chat.screen"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["Think"].exists)
        XCTAssertTrue(app.buttons["Search"].exists)
        app.buttons["nodus.chat.add-context"].tap()
        XCTAssertTrue(app.buttons["Knowledge"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Turn Memory On"].exists || app.buttons["Turn Memory Off"].exists)
        app.tap()
        app.descendants(matching: .any)["nodus.chat.conversations"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["nodus.conversations"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["New Chat"].exists)
        app.buttons["Done"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()

        let knowledge = app.descendants(matching: .any)["nodus.workspace.knowledge"]
        XCTAssertTrue(knowledge.waitForExistence(timeout: 5))
        knowledge.tap()
        XCTAssertTrue(app.descendants(matching: .any)["nodus.knowledge"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Modula Core"].exists)
        XCTAssertTrue(app.staticTexts["My Knowledge"].exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()

        let memory = app.descendants(matching: .any)["nodus.workspace.memory"]
        XCTAssertTrue(memory.waitForExistence(timeout: 5))
        memory.tap()
        XCTAssertTrue(app.descendants(matching: .any)["nodus.memory"].waitForExistence(timeout: 8))
        app.navigationBars.buttons.element(boundBy: 0).tap()

        let learning = app.descendants(matching: .any)["nodus.workspace.learning"]
        XCTAssertTrue(learning.waitForExistence(timeout: 5))
        learning.tap()
        XCTAssertTrue(app.descendants(matching: .any)["nodus.learning"].waitForExistence(timeout: 8))
        app.navigationBars.buttons.element(boundBy: 0).tap()

        let diagnostics = app.descendants(matching: .any)["nodus.workspace.diagnostics"]
        XCTAssertTrue(diagnostics.waitForExistence(timeout: 5))
        diagnostics.tap()
        XCTAssertTrue(app.descendants(matching: .any)["nodus.diagnostics"].waitForExistence(timeout: 8))
    }

    @MainActor
    func testNodusAccessoryChatUsesPersistentComposer() throws {
        let app = try launchThroughAppGate(arguments: ["--runtime-unavailable", "--uitest-nodus-fixture"])
        openIntelligenceChat(app)

        XCTAssertTrue(app.descendants(matching: .any)["intelligence.chat"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)["nodus.chat.screen"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["nodus.chat.input"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["nodus.chat.add-context"].exists)
        XCTAssertEqual(app.descendants(matching: .any)["nodus.chat.screen"].label, "Nodus")

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "nodus-accessory-chat-composer"
        attachment.lifetime = .keepAlways
        add(attachment)

        app.buttons["intelligence.chat.close"].firstMatch.tap()
        XCTAssertFalse(app.descendants(matching: .any)["intelligence.chat"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testNodusAccessoryComposerModesAndKeyboard() throws {
        let app = try launchThroughAppGate(arguments: ["--runtime-unavailable", "--uitest-nodus-fixture"])
        openIntelligenceChat(app)
        let actions = app.buttons["nodus.chat.actions"].firstMatch
        XCTAssertTrue(actions.waitForExistence(timeout: 8))
        actions.tap()
        app.buttons["New Chat"].tap()

        let think = app.buttons["Think"].firstMatch
        XCTAssertTrue(think.waitForExistence(timeout: 8))
        XCTAssertEqual(think.value as? String, "Off")
        think.tap()
        let thinkOn = NSPredicate(format: "value == %@", "On")
        expectation(for: thinkOn, evaluatedWith: think)
        waitForExpectations(timeout: 5)

        let addContext = app.descendants(matching: .any)["nodus.chat.add-context"]
        addContext.tap()
        XCTAssertTrue(app.buttons["Knowledge"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Turn Search On"].exists)
        app.buttons["Turn Memory Off"].tap()
        XCTAssertFalse(app.buttons["Memory"].waitForExistence(timeout: 2))
        addContext.tap()
        app.buttons["Turn Memory On"].tap()
        XCTAssertTrue(app.buttons["Memory"].waitForExistence(timeout: 5))

        let input = app.descendants(matching: .any)["nodus.chat.input"]
        pasteText(
            "Give me a concise two-line status update, using my active context and preserving the local-only boundary.",
            into: input,
            app: app
        )
        let send = app.descendants(matching: .any)["nodus.chat.send"]
        XCTAssertTrue(send.waitForExistence(timeout: 5))
        XCTAssertTrue(send.isHittable)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "nodus-accessory-composer-keyboard"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testNodus02ASearchFixtureGroundingAndSources() throws {
        let app = try launchThroughAppGate(arguments: [
            "--runtime-unavailable", "--uitest-nodus-fixture", "--uitest-nodus-search-fixture",
        ])
        openSettingsFromShell(app)
        let developer = scrollToElement(named: "Developer", in: app, maximumSwipes: 8)
        XCTAssertTrue(developer.exists)
        developer.tap()
        let localIntelligence = scrollToElement(named: "Local Intelligence", in: app, maximumSwipes: 4)
        XCTAssertTrue(localIntelligence.exists)
        localIntelligence.tap()
        let openChat = scrollToElement(named: "Open Nodus Chat", in: app, maximumSwipes: 8)
        XCTAssertTrue(openChat.exists)
        openChat.tap()

        let input = app.descendants(matching: .any)["nodus.chat.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 8))
        app.descendants(matching: .any)["nodus.chat.conversations"].firstMatch.tap()
        XCTAssertTrue(app.buttons["New Chat"].waitForExistence(timeout: 5))
        app.buttons["New Chat"].tap()
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        app.buttons["Search"].tap()
        XCTAssertTrue(app.buttons["Enable Online Search"].waitForExistence(timeout: 5))
        app.buttons["Enable Online Search"].tap()
        pasteText("What's the latest stable version of Swift?", into: input, app: app)
        app.descendants(matching: .any)["nodus.chat.send"].tap()

        let searched = app.staticTexts["Searched the web"]
        for _ in 0..<5 where !searched.exists { app.swipeUp() }
        XCTAssertTrue(searched.waitForExistence(timeout: 15))
        let sources = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Sources")).firstMatch
        XCTAssertTrue(sources.waitForExistence(timeout: 5))
        sources.tap()
        XCTAssertTrue(app.staticTexts["Swift releases fixture"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["swift.org"].exists)
    }

    @MainActor
    func testNodusChatFixtureSendMetadataVerifyAndClear() throws {
        let app = try launchThroughAppGate(arguments: ["--runtime-unavailable", "--uitest-nodus-fixture"])
        openSettingsFromShell(app)
        let developer = scrollToElement(named: "Developer", in: app, maximumSwipes: 8)
        XCTAssertTrue(developer.exists)
        developer.tap()
        let localIntelligence = scrollToElement(named: "Local Intelligence", in: app, maximumSwipes: 4)
        XCTAssertTrue(localIntelligence.exists)
        localIntelligence.tap()
        let openChat = scrollToElement(named: "Open Nodus Chat", in: app, maximumSwipes: 4)
        XCTAssertTrue(openChat.exists)
        openChat.tap()

        let input = app.descendants(matching: .any)["nodus.chat.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 8))
        pasteText("What's today's weather?", into: input, app: app)
        app.descendants(matching: .any)["nodus.chat.send"].tap()
        XCTAssertTrue(app.buttons["Verify"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Needs verification"].exists)
        XCTAssertTrue(app.staticTexts["Current data needed"].exists)
        let goodRating = app.descendants(matching: .any)["nodus.chat.rating.good"]
        XCTAssertTrue(goodRating.waitForExistence(timeout: 5))
        goodRating.tap()
        XCTAssertTrue(goodRating.exists)
        app.buttons["Verify"].tap()
        XCTAssertTrue(app.buttons["Verify"].exists)

        app.descendants(matching: .any)["nodus.chat.actions"].firstMatch.tap()
        app.buttons["Clear"].tap()
        XCTAssertTrue(app.staticTexts["Local Intelligence"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testNodusChatRealBundledModelOnPhysicalDevice() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("MLX does not support inference in the iOS Simulator")
        #else
        // Device-hosted UI tests cannot read the Mac-only N1 secret file. The
        // DEBUG fixture sign-in button does not use those credentials, so enter
        // through that accepted AppGate hook without copying a secret to the
        // test bundle or device.
        let app = XCUIApplication()
        app.launchArguments = ["--runtime-unavailable", "--uitest-n1-api", "--uitest-skip-first-run"]
        app.launch()
        try awaitShellReady(
            app,
            credentials: N1UITestFixture(email: "unused@example.invalid", password: "unused"),
            timeout: 90
        )
        openSettingsFromShell(app)
        let developer = scrollToElement(named: "Developer", in: app, maximumSwipes: 8)
        XCTAssertTrue(developer.exists)
        developer.tap()
        let localIntelligence = scrollToElement(named: "Local Intelligence", in: app, maximumSwipes: 4)
        XCTAssertTrue(localIntelligence.exists)
        localIntelligence.tap()
        let openChat = scrollToElement(named: "Open Nodus Chat", in: app, maximumSwipes: 4)
        XCTAssertTrue(openChat.exists)
        openChat.tap()

        XCTAssertTrue(app.staticTexts["Not approved for production"].waitForExistence(timeout: 8))
        let input = app.descendants(matching: .any)["nodus.chat.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 8))
        pasteText("What is the capital of Romania?", into: input, app: app)
        app.descendants(matching: .any)["nodus.chat.send"].tap()
        let answer = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Bucharest")
        ).firstMatch
        XCTAssertTrue(answer.waitForExistence(timeout: 60))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "nodus-01d-real-physical-response"
        attachment.lifetime = .keepAlways
        add(attachment)
        #endif
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

        // Module routes push onto the current stack and the hidden host is suspended, not
        // unmounted: Back returns to the same Vault surface with its React state intact.
        app.buttons["Open my native Profile"].tap()
        assertNativeProfileVisible(app)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["Notes loaded"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["resumed"].waitForExistence(timeout: 8), "the kept-alive surface receives resumed")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Runtime: 1'")).firstMatch.exists)
        app.buttons["Close"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Vault Notes"].waitForExistence(timeout: 8))

        openVault(app)
        XCTAssertTrue(app.staticTexts["Notes loaded"].waitForExistence(timeout: 20))
        XCTAssertFalse(noteButton(app, title: editedTitle).exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Runtime: 1'")).firstMatch.exists)
        app.buttons["Close"].firstMatch.tap()
    }

    /// Rich editing, search, sort and the unsaved-changes guard against real n1 records.
    func testVaultRichEditingSearchSortAndDiscardGuard() throws {
        let app = try launchSignedInApp()
        openProductHub(app)
        openVault(app)
        XCTAssertTrue(app.staticTexts["Notes loaded"].waitForExistence(timeout: 20))
        attachVaultScreenshot(app, name: "vault-list")

        let title = "VaultRich-\(UUID().uuidString.prefix(6))"
        app.buttons["New Note"].tap()
        pasteText(title, into: textInput(app, label: "Note title"), app: app)
        pasteText("Intro paragraph for the rich note.", into: textInput(app, label: "Note content"), app: app)
        app.buttons["Checklist"].tap()
        let item = labelled(app, "Checklist item 1")
        XCTAssertTrue(item.waitForExistence(timeout: 5), "Inserting a checklist switches to block editing")
        pasteText("Ship the renderer", into: item, app: app)
        app.buttons["Heading"].tap()
        let heading = labelled(app, "Heading")
        XCTAssertTrue(heading.waitForExistence(timeout: 5))
        pasteText("Next steps", into: heading, app: app)
        XCTAssertTrue(app.staticTexts["Unsaved changes"].exists)
        app.buttons["Save note"].tap()
        XCTAssertTrue(app.staticTexts["Saved"].waitForExistence(timeout: 20))
        attachVaultScreenshot(app, name: "vault-rich-editor")

        // Unsaved edits ask before leaving.
        let titleField = textInput(app, label: "Note title")
        titleField.tap()
        titleField.typeText(" draft")
        app.buttons["Notes"].tap()
        XCTAssertTrue(app.alerts["Discard changes?"].waitForExistence(timeout: 5))
        app.alerts.buttons["Discard"].tap()
        XCTAssertTrue(app.staticTexts["Notes loaded"].waitForExistence(timeout: 20))

        // Search narrows the list on the server; sort switches order.
        let search = app.descendants(matching: .any)["vault.search"].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        pasteText(title, into: search, app: app)
        XCTAssertTrue(app.buttons[title].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["N1 Fixture 1"].waitForExistence(timeout: 2), "Search filters other notes out")
        attachVaultScreenshot(app, name: "vault-search")
        app.buttons["Clear search"].firstMatch.tap()
        pasteText("zz-no-such-note-\(UUID().uuidString.prefix(4))", into: search, app: app)
        XCTAssertTrue(app.staticTexts["No matching notes"].waitForExistence(timeout: 15))
        attachVaultScreenshot(app, name: "vault-no-results")
        app.buttons["Clear search"].firstMatch.tap()
        // Sort options are RN tabs (role tab), not buttons.
        let byTitle = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "A–Z")).firstMatch
        XCTAssertTrue(byTitle.waitForExistence(timeout: 5))
        byTitle.tap()
        expectation(for: NSPredicate(format: "isSelected == true"), evaluatedWith: byTitle)
        waitForExpectations(timeout: 5)
        XCTAssertTrue(app.staticTexts["Notes loaded"].waitForExistence(timeout: 15))
        attachVaultScreenshot(app, name: "vault-sorted-az")

        // Reopen: structure survived the round trip; then clean up.
        pasteText(title, into: search, app: app)
        XCTAssertTrue(app.buttons[title].waitForExistence(timeout: 15))
        app.buttons[title].tap()
        XCTAssertTrue(app.descendants(matching: .any)["vault.blocks"].waitForExistence(timeout: 10))
        XCTAssertTrue(labelled(app, "Checklist item 1").waitForExistence(timeout: 5))
        attachVaultScreenshot(app, name: "vault-rich-reopened")
        app.buttons["Move to Trash"].tap()
        XCTAssertTrue(app.alerts.buttons["Move to Trash"].waitForExistence(timeout: 5))
        app.alerts.buttons["Move to Trash"].tap()
        XCTAssertTrue(app.staticTexts["Notes loaded"].waitForExistence(timeout: 20))
        app.buttons["Close"].firstMatch.tap()
    }

    private func labelled(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@ AND (elementType == %d OR elementType == %d)",
            label, XCUIElement.ElementType.textField.rawValue, XCUIElement.ElementType.textView.rawValue)).firstMatch
    }

    private func attachVaultScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Product Hub store page end to end against n1: icons and cover in the list, rich
    /// detail page, uninstall (data kept), reinstall with permission confirmation, open
    /// into the renderer. Leaves Vault installed.
    func testStoreDetailInstallOpenUninstallLifecycle() throws {
        let app = try launchSignedInApp()
        openProductHub(app)
        XCTAssertTrue(app.descendants(matching: .any)["artwork.digital.modula.vault-notes"].firstMatch.waitForExistence(timeout: 15))
        attachVaultScreenshot(app, name: "D-hub-list")
        let card = app.buttons["product.digital.modula.vault-notes"].firstMatch
        if card.waitForExistence(timeout: 5) { card.tap() } else { app.buttons["product-hub.featured"].firstMatch.tap() }

        let primary = app.buttons["module.primary"].firstMatch
        XCTAssertTrue(primary.waitForExistence(timeout: 15))
        XCTAssertTrue(app.descendants(matching: .any)["module.stats"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["What’s New"].waitForExistence(timeout: 10))
        attachVaultScreenshot(app, name: "D-detail-top")

        // Make sure we start installed (a previous failed run may have left it removed).
        if primary.label == "Install" {
            primary.tap()
            app.buttons["module.install.confirm"].firstMatch.tap()
            XCTAssertTrue(waitForLabel(primary, "Open", timeout: 60))
        }
        XCTAssertEqual(primary.label, "Open")

        app.swipeUp()
        XCTAssertTrue(app.descendants(matching: .any)["module.screenshots"].firstMatch.waitForExistence(timeout: 5))
        attachVaultScreenshot(app, name: "D-detail-screenshots")
        app.swipeUp()
        attachVaultScreenshot(app, name: "D-detail-privacy-permissions")
        let uninstall = app.buttons["module.uninstall"].firstMatch
        for _ in 0..<4 where !uninstall.isHittable { app.swipeUp() }
        attachVaultScreenshot(app, name: "D-detail-information")
        uninstall.tap()
        let confirmUninstall = app.buttons["module.uninstall.confirm"].firstMatch
        XCTAssertTrue(confirmUninstall.waitForExistence(timeout: 5))
        confirmUninstall.tap()

        for _ in 0..<8 where !primary.isHittable { app.swipeDown() }
        XCTAssertTrue(waitForLabel(primary, "Install", timeout: 60),
                      "Uninstall should settle; error: \(app.descendants(matching: .any)["module.lifecycle-error"].firstMatch.label)")
        attachVaultScreenshot(app, name: "D-detail-not-installed")

        primary.tap()
        let confirmInstall = app.buttons["module.install.confirm"].firstMatch
        XCTAssertTrue(confirmInstall.waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 1)
        attachVaultScreenshot(app, name: "D-install-confirm")
        confirmInstall.tap()
        XCTAssertTrue(waitForLabel(primary, "Open", timeout: 60),
                      "Install should settle; error: \(app.descendants(matching: .any)["module.lifecycle-error"].firstMatch.label)")
        attachVaultScreenshot(app, name: "D-detail-reinstalled")

        primary.tap()
        XCTAssertTrue(app.staticTexts["Notes loaded"].waitForExistence(timeout: 25), "Reinstalled module opens with its kept data")
        XCTAssertTrue(noteButton(app, title: "N1 Fixture 1").waitForExistence(timeout: 5), "keepData uninstall preserves notes")
        attachVaultScreenshot(app, name: "D-opened-after-reinstall")
    }

    private func waitForLabel(_ element: XCUIElement, _ label: String, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "label == %@", label)
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: timeout) == .completed
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

    /// Upgrade/downgrade between registry versions. Needs a build whose ModulaAPIURL points
    /// at a registry with several Vault Notes versions and MODULA_VERSIONS_FIXTURE credentials
    /// for an account that has Vault Notes installed at an older version (1.6.0).
    func testModuleVersionsListSwitchConfirmationUpgradeAndDowngrade() throws {
        guard let path = ProcessInfo.processInfo.environment["MODULA_VERSIONS_FIXTURE"],
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let fixture = try? JSONDecoder().decode(N1UITestFixture.self, from: data) else {
            throw XCTSkip("MODULA_VERSIONS_FIXTURE unavailable; version switching needs a registry fixture account")
        }
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-skip-first-run", "--reset-appearance"]
        app.launch()
        // Sign in with the registry fixture account explicitly (the Debug fixture button
        // would use the N1 credentials instead).
        let email = app.descendants(matching: .any)["auth.email"]
        let home = app.descendants(matching: .any)["native.home"]
        let deadline = Date().addingTimeInterval(45)
        while Date() < deadline, !home.exists, !email.exists {
            let landing = app.descendants(matching: .any)["onboarding.landing.continue"]
            if landing.exists { landing.tap() }
            let skip = app.descendants(matching: .any)["onboarding.skip"]
            if skip.exists { skip.tap() }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        if email.exists {
            pasteText(fixture.email, into: email, app: app)
            pasteText(fixture.password, into: app.descendants(matching: .any)["auth.password"], app: app)
            app.descendants(matching: .any)["auth.sign-in"].tap()
        }
        try awaitShellReady(app, credentials: fixture, timeout: 90)
        openProductHub(app)
        let card = app.buttons["product.digital.modula.vault-notes"].firstMatch
        if card.waitForExistence(timeout: 10) { card.tap() } else { app.buttons["product-hub.featured"].firstMatch.tap() }
        XCTAssertTrue(app.buttons["module.primary"].firstMatch.waitForExistence(timeout: 15))

        let installed = app.staticTexts["module.versions.installed"].firstMatch
        for _ in 0..<8 where !(installed.exists && installed.isHittable) { app.swipeUp() }
        XCTAssertTrue(installed.waitForExistence(timeout: 15))
        XCTAssertEqual(installed.label, "Installed 1.6.0")
        let update = app.buttons["module.version.1.7.0.action"].firstMatch
        XCTAssertTrue(update.waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["module.version.1.5.0.action"].firstMatch.exists, "Older releases offer Install this version (Downgrade)")
        app.swipeUp()
        let toggle = app.buttons["module.versions.toggle"].firstMatch
        if toggle.waitForExistence(timeout: 3) { toggle.tap() }
        for _ in 0..<3 where !app.buttons["module.version.0.2.0.action"].firstMatch.isHittable { app.swipeUp() }
        Thread.sleep(forTimeInterval: 1)
        attachVaultScreenshot(app, name: "V-versions-list")
        app.swipeDown()
        Thread.sleep(forTimeInterval: 1)
        attachVaultScreenshot(app, name: "V-versions-list-top")

        // Downgrade to a superseded release: new permissions need consent, older data schema warns.
        let older = app.buttons["module.version.0.2.0.action"].firstMatch
        for _ in 0..<3 where !older.isHittable { app.swipeUp() }
        older.tap()
        let confirm = app.buttons["module.version-switch.confirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 20), app.descendants(matching: .any)["module.version-switch.error"].firstMatch.label)
        XCTAssertTrue(app.descendants(matching: .any)["module.version-switch.downgrade-warning"].firstMatch.exists)
        XCTAssertTrue(confirm.label.hasPrefix("Allow & Downgrade"))
        Thread.sleep(forTimeInterval: 1)
        attachVaultScreenshot(app, name: "V-confirm-downgrade")
        app.buttons["module.version-switch.cancel"].firstMatch.tap()

        // Update to the latest release.
        for _ in 0..<6 where !update.isHittable { app.swipeDown() }
        update.tap()
        XCTAssertTrue(confirm.waitForExistence(timeout: 20), app.descendants(matching: .any)["module.version-switch.error"].firstMatch.label)
        Thread.sleep(forTimeInterval: 1)
        attachVaultScreenshot(app, name: "V-confirm-update")
        confirm.tap()
        XCTAssertTrue(waitForLabel(installed, "Installed 1.7.0", timeout: 60),
                      "Update should settle; error: \(app.descendants(matching: .any)["module.lifecycle-error"].firstMatch.label)")

        // And back down to 1.5.0 (no schema change, so no acknowledgement needed).
        let downgrade = app.buttons["module.version.1.5.0.action"].firstMatch
        for _ in 0..<4 where !downgrade.isHittable { app.swipeUp() }
        downgrade.tap()
        XCTAssertTrue(confirm.waitForExistence(timeout: 20))
        XCTAssertTrue(confirm.label.hasPrefix("Downgrade to 1.5.0"), confirm.label)
        Thread.sleep(forTimeInterval: 1)
        attachVaultScreenshot(app, name: "V-confirm-downgrade-plain")
        confirm.tap()
        XCTAssertTrue(waitForLabel(installed, "Installed 1.5.0", timeout: 60),
                      "Downgrade should settle; error: \(app.descendants(matching: .any)["module.lifecycle-error"].firstMatch.label)")
        attachVaultScreenshot(app, name: "V-after-downgrade")
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
        // Transport failures reach the module as NETWORK_UNAVAILABLE with host-written text.
        XCTAssertTrue(app.staticTexts["You appear to be offline."].waitForExistence(timeout: 25))
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
        assertNativeProfileVisible(app)
        selectTab(app, "Modules")
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

@MainActor
final class Vault21CandidateUITests: XCTestCase {
    private struct GalleryFixture: Decodable {
        struct Note: Decodable { let recordId: String }
        let folders: [String: Note]
        let tags: [String: Note]
        let notes: [String: Note]
    }

    private struct MediaFixture: Decodable { let bindingId: String }

    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "vault21-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testEightScreenVisualBaseline() throws {
        continueAfterFailure = false
        let qaPath = "/Users/msjoy/Library/Application Support/Modula/QA/vault21-n1.json"
        guard FileManager.default.fileExists(atPath: qaPath) else {
            throw XCTSkip("Disposable Vault 2.1 N1 QA credentials are unavailable on this Mac")
        }
        let credentials = try JSONDecoder().decode(N1UITestFixture.self, from: Data(contentsOf: URL(fileURLWithPath: qaPath)))
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-signed-out", "--uitest-n1-api", "--uitest-skip-first-run"]
        app.launchEnvironment["N1_SECRET_FILE"] = qaPath
        app.launch()
        try awaitShellReady(app, credentials: credentials, timeout: 90)
        openProductHubFromShell(app)
        let vault = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Vault Notes")).firstMatch
        XCTAssertTrue(vault.waitForExistence(timeout: 20))
        vault.tap()
        tapModuleOpen(app)
        XCTAssertTrue(app.descendants(matching: .any)["module.host.product-ui"].firstMatch.waitForExistence(timeout: 30))
        capture("home", app: app)
        for (label, name) in [("Pinned", "pinned"), ("Favourites", "favourites"), ("Folders", "folders"), ("Tags", "tags"), ("Trash", "trash")] {
            let button = app.buttons[label].firstMatch
            XCTAssertTrue(button.waitForExistence(timeout: 10), "Missing \(label) button: \(app.debugDescription)")
            button.tap()
            capture(name, app: app)
            let back = app.buttons["product-ui.back"].firstMatch
            XCTAssertTrue(back.waitForExistence(timeout: 8), "Missing back control from \(label)")
            back.tap()
        }
        let record = app.buttons["product-ui.record.01a154d4-cb2f-7283-a80b-65b0302df3e6"].firstMatch
        XCTAssertTrue(record.waitForExistence(timeout: 10), "Rich writing QA note missing from Home")
        app.swipeUp()
        record.tap()
        capture("detail", app: app)
        let edit = app.buttons["Edit"].firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 10), "Edit action missing from note detail")
        edit.tap()
        capture("editor", app: app)
    }

    func testGalleryVisualCandidateWithDisposableAccount() throws {
        continueAfterFailure = false
        let qaPath = "/Users/msjoy/Library/Application Support/Modula/QA/vault21-n1-secondary.json"
        let fixturesPath = "/Users/msjoy/Documents/Codex/2026-10-18/modula-vault-21-acceptance-02-full/evidence/n1-vault21-gallery-fixtures.json"
        guard FileManager.default.fileExists(atPath: qaPath), FileManager.default.fileExists(atPath: fixturesPath) else {
            throw XCTSkip("Disposable gallery QA fixtures are unavailable on this Mac")
        }
        let credentials = try JSONDecoder().decode(N1UITestFixture.self, from: Data(contentsOf: URL(fileURLWithPath: qaPath)))
        let fixtures = try JSONDecoder().decode(GalleryFixture.self, from: Data(contentsOf: URL(fileURLWithPath: fixturesPath)))
        guard let writing = fixtures.notes["A garden after rain"] else { throw XCTSkip("Rich writing fixture missing") }
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-signed-out", "--uitest-n1-api", "--uitest-skip-first-run"]
        app.launchEnvironment["N1_SECRET_FILE"] = qaPath
        app.launch()
        try awaitShellReady(app, credentials: credentials, timeout: 90)
        openProductHubFromShell(app)
        let vault = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Vault Notes")).firstMatch
        XCTAssertTrue(vault.waitForExistence(timeout: 20))
        vault.tap()
        tapModuleOpen(app)
        XCTAssertTrue(app.descendants(matching: .any)["module.host.product-ui"].firstMatch.waitForExistence(timeout: 30))
        XCTAssertTrue(app.buttons["product-ui.record.\(writing.recordId)"].firstMatch.waitForExistence(timeout: 30), "Gallery Home did not finish loading its notes")
        capture("gallery-home", app: app)
        for (label, name, expectedRecordId) in [
            ("Folders", "gallery-folders", fixtures.folders["Writing"]?.recordId ?? ""),
            ("Tags", "gallery-tags", fixtures.tags["Ideas"]?.recordId ?? "")
        ] {
            XCTAssertFalse(expectedRecordId.isEmpty, "Gallery \(label) fixture missing")
            let button = app.buttons[label].firstMatch
            XCTAssertTrue(button.waitForExistence(timeout: 10))
            button.tap()
            XCTAssertTrue(app.buttons["product-ui.record.\(expectedRecordId)"].firstMatch.waitForExistence(timeout: 30), "Gallery \(label) did not finish loading")
            capture(name, app: app)
            let back = app.buttons["product-ui.back"].firstMatch
            XCTAssertTrue(back.waitForExistence(timeout: 8))
            back.tap()
        }
        let search = app.textFields["product-ui.search"].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText("garden")
        let result = app.buttons["product-ui.record.\(writing.recordId)"].firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 20), "Body search did not show the gallery note")
        if app.keyboards.buttons["Search"].exists { app.keyboards.buttons["Search"].tap() }
        capture("gallery-search", app: app)
        result.tap()
        capture("gallery-detail", app: app)
        let edit = app.buttons["Edit"].firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 10))
        edit.tap()
        capture("gallery-editor", app: app)
    }

    func testDisposableAttachmentReopensInVault() throws {
        continueAfterFailure = false
        let qaPath = "/Users/msjoy/Library/Application Support/Modula/QA/vault21-n1-secondary.json"
        let fixturesPath = "/Users/msjoy/Documents/Codex/2026-10-18/modula-vault-21-acceptance-02-full/evidence/n1-vault21-gallery-fixtures.json"
        let mediaPath = "/Users/msjoy/Documents/Codex/2026-10-18/modula-vault-21-acceptance-02-full/evidence/n1-vault21-media-qa.json"
        guard [qaPath, fixturesPath, mediaPath].allSatisfy(FileManager.default.fileExists(atPath:)) else {
            throw XCTSkip("Disposable Vault attachment fixture is unavailable on this Mac")
        }
        let credentials = try JSONDecoder().decode(N1UITestFixture.self, from: Data(contentsOf: URL(fileURLWithPath: qaPath)))
        let fixtures = try JSONDecoder().decode(GalleryFixture.self, from: Data(contentsOf: URL(fileURLWithPath: fixturesPath)))
        let media = try JSONDecoder().decode(MediaFixture.self, from: Data(contentsOf: URL(fileURLWithPath: mediaPath)))
        let noteId = try XCTUnwrap(fixtures.notes["A garden after rain"]?.recordId)
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-signed-out", "--uitest-n1-api", "--uitest-skip-first-run"]
        app.launchEnvironment["N1_SECRET_FILE"] = qaPath
        app.launch()
        try awaitShellReady(app, credentials: credentials, timeout: 90)
        openProductHubFromShell(app)
        let vault = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Vault Notes")).firstMatch
        XCTAssertTrue(vault.waitForExistence(timeout: 20))
        vault.tap()
        tapModuleOpen(app)
        let note = app.buttons["product-ui.record.\(noteId)"].firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 30))
        note.tap()
        let attachment = app.buttons["product-ui.record.\(media.bindingId)"].firstMatch
        XCTAssertTrue(attachment.waitForExistence(timeout: 30), "Uploaded file is missing from the note")
        capture("attachment-bound", app: app)
        attachment.tap()
        XCTAssertTrue(app.buttons["Done"].firstMatch.waitForExistence(timeout: 20), "Attachment preview did not open: \(app.debugDescription)")
        Thread.sleep(forTimeInterval: 2)
        capture("attachment-preview", app: app)
        app.buttons["Done"].firstMatch.tap()
        let actions = app.buttons["product-ui.record-actions.\(media.bindingId)"].firstMatch
        XCTAssertTrue(actions.waitForExistence(timeout: 8))
        actions.tap()
        let remove = app.buttons["Remove attachment"].firstMatch
        XCTAssertTrue(remove.waitForExistence(timeout: 8))
        remove.tap()
        let confirm = app.buttons["Remove attachment"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 8))
        confirm.tap()
        let removed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: attachment)
        XCTAssertEqual(XCTWaiter.wait(for: [removed], timeout: 20), .completed, "Attachment remained bound after removal")
        capture("attachment-removed", app: app)
    }

    func testRichEditorKeyboardUndoRedoAndSave() throws {
        continueAfterFailure = false
        let qaPath = "/Users/msjoy/Library/Application Support/Modula/QA/vault21-n1.json"
        guard FileManager.default.fileExists(atPath: qaPath) else {
            throw XCTSkip("Disposable Vault 2.1 N1 QA credentials are unavailable on this Mac")
        }
        let credentials = try JSONDecoder().decode(N1UITestFixture.self, from: Data(contentsOf: URL(fileURLWithPath: qaPath)))
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-signed-out", "--uitest-n1-api", "--uitest-skip-first-run"]
        app.launchEnvironment["N1_SECRET_FILE"] = qaPath
        app.launch()
        try awaitShellReady(app, credentials: credentials, timeout: 90)
        openProductHubFromShell(app)
        let vault = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Vault Notes")).firstMatch
        XCTAssertTrue(vault.waitForExistence(timeout: 20))
        vault.tap()
        tapModuleOpen(app)
        XCTAssertTrue(app.descendants(matching: .any)["module.host.product-ui"].firstMatch.waitForExistence(timeout: 30))
        let record = app.buttons["product-ui.record.01a154d4-cb2f-7283-a80b-65b0302df3e6"].firstMatch
        XCTAssertTrue(record.waitForExistence(timeout: 10))
        app.swipeUp()
        record.tap()
        let edit = app.buttons["Edit"].firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 10))
        edit.tap()
        let block = app.descendants(matching: .any)["product-ui.block.welcome-opening"].firstMatch
        XCTAssertTrue(block.waitForExistence(timeout: 15), "Structured paragraph is not editable")
        let before = String(describing: block.value)
        block.tap()
        block.typeText(" simulator proof")
        capture("editor-keyboard", app: app)
        let typed = String(describing: block.value)
        XCTAssertNotEqual(typed, before, "Keyboard input did not change the structured paragraph")
        let undo = app.buttons["product-ui.richtext.undo"].firstMatch
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        undo.tap()
        let redo = app.buttons["product-ui.richtext.redo"].firstMatch
        XCTAssertTrue(redo.waitForExistence(timeout: 5))
        redo.tap()
        let done = app.buttons["product-ui.form.done"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
        capture("editor-saved", app: app)
        XCTAssertFalse(app.descendants(matching: .any)["module.host.failed"].exists)
    }

    func testSignedN1CandidateOpensInGenericModuleHost() throws {
        continueAfterFailure = false
        let qaPath = "/Users/msjoy/Library/Application Support/Modula/QA/vault21-n1.json"
        guard FileManager.default.fileExists(atPath: qaPath) else {
            throw XCTSkip("Disposable Vault 2.1 N1 QA credentials are unavailable on this Mac")
        }
        let credentials = try JSONDecoder().decode(N1UITestFixture.self, from: Data(contentsOf: URL(fileURLWithPath: qaPath)))
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-signed-out", "--uitest-n1-api", "--uitest-skip-first-run"]
        app.launchEnvironment["N1_SECRET_FILE"] = qaPath
        app.launch()
        try awaitShellReady(app, credentials: credentials, timeout: 90)
        openProductHubFromShell(app)
        let vault = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Vault Notes")).firstMatch
        XCTAssertTrue(vault.waitForExistence(timeout: 20), "Vault catalogue entry missing in N1")
        vault.tap()
        let primary = app.descendants(matching: .any)["module.primary"].firstMatch
        XCTAssertTrue(primary.waitForExistence(timeout: 15), "Vault detail has no primary action")
        let detail = XCTAttachment(screenshot: app.screenshot())
        detail.name = "vault21-n1-detail-before-open"
        detail.lifetime = .keepAlways
        add(detail)
        XCTAssertEqual(primary.label, "Open", "The QA account should already have signed Vault 2.1 installed")
        tapModuleOpen(app)
        let productUI = app.descendants(matching: .any)["module.host.product-ui"].firstMatch
        let loaded = productUI.waitForExistence(timeout: 30)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "vault21-n1-first-open"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCTAssertTrue(loaded, "Signed Vault 2.1 did not render in ModuleHost: \(app.debugDescription)")
        XCTAssertFalse(app.descendants(matching: .any)["module.host.failed"].exists)
    }
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

@MainActor
private func openIntelligenceChat(_ app: XCUIApplication) {
    app.typeKey("k", modifierFlags: .command)
    let search = app.textFields["Search commands"].firstMatch
    XCTAssertTrue(search.waitForExistence(timeout: 8))
    search.tap()
    search.typeText("Nodus")
    let row = app.descendants(matching: .any)["command.row.open.intelligence.chat"]
    XCTAssertTrue(row.waitForExistence(timeout: 8))
    row.tap()
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
    if let secretPath = ProcessInfo.processInfo.environment["N1_SECRET_FILE"] {
        app.launchEnvironment["N1_SECRET_FILE"] = secretPath
    }
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

        let landing = app.descendants(matching: .any)["onboarding.landing.continue"]
        if landing.exists {
            landing.tap()
            continue
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

    let landing = app.descendants(matching: .any)["onboarding.landing.continue"]
    if landing.waitForExistence(timeout: 2) { landing.tap() }

    if app.descendants(matching: .any)["onboarding.root"].waitForExistence(timeout: 2) {
        app.descendants(matching: .any)["onboarding.skip"].tap()
    }

    let fixtureButton = app.descendants(matching: .any)["auth.sign-in-fixture"]
    if fixtureButton.waitForExistence(timeout: 3), app.launchEnvironment["N1_SECRET_FILE"] == nil {
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
        UIPasteboard.general.string = nil
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
private func scrollToElement(
    named name: String,
    in app: XCUIApplication,
    maximumSwipes: Int
) -> XCUIElement {
    let element = app.descendants(matching: .any)[name].firstMatch
    if element.waitForExistence(timeout: 1) { return element }
    for _ in 0..<maximumSwipes {
        app.swipeUp()
        if element.waitForExistence(timeout: 1) { return element }
    }
    return element
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

/// The own profile is a full-bleed tab root (no "Profile" navigation bar since the
/// shell redesign); accept either the legacy bar or the profile's own controls.
@MainActor
private func assertNativeProfileVisible(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
    let shown = app.navigationBars["Profile"].waitForExistence(timeout: 8)
        || app.descendants(matching: .any)["profile.share"].waitForExistence(timeout: 4)
        || app.descendants(matching: .any)["accessory.share"].waitForExistence(timeout: 2)
    XCTAssertTrue(shown, "Native Profile did not open", file: file, line: line)
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

        scrubEdgePicker(app, to: "/activity/mentions")
        scrubEdgePicker(app, to: "/activity/requests")
        scrubEdgePicker(app, to: "/activity/mentions", forward: false)
        scrubEdgePicker(app, to: "/activity/all", forward: false)

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
final class SignInUITests: XCTestCase {
    /// Real Sign In surface against the N1 fixture: landmarks, disabled → enabled CTA,
    /// show/hide password, inline server error, then manual email/password sign-in.
    func testSignInStatesErrorAndManualSignIn() throws {
        let fixture = try requireN1FixtureOrSkip()
        let app = XCUIApplication()
        app.launchArguments = [
            "--uitest-n1-api", "--uitest-skip-first-run", "--uitest-signed-out", "--reset-appearance", "--ui-light"
        ]
        app.launch()
        let login = app.descendants(matching: .any)["auth.login"].firstMatch
        let deadline = Date().addingTimeInterval(20)
        while !login.exists && Date() < deadline {
            let landing = app.descendants(matching: .any)["onboarding.landing.continue"]
            if landing.exists { landing.tap() }
            let skip = app.descendants(matching: .any)["onboarding.skip"]
            if skip.exists { skip.tap() }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        XCTAssertTrue(login.waitForExistence(timeout: 5), "Sign In did not appear")

        let email = app.descendants(matching: .any)["auth.email"].firstMatch
        let password = app.secureTextFields["auth.password"].firstMatch
        let signIn = app.buttons["auth.sign-in"].firstMatch
        XCTAssertTrue(email.waitForExistence(timeout: 5))
        XCTAssertTrue(password.exists)
        XCTAssertTrue(signIn.exists)
        XCTAssertFalse(signIn.isEnabled, "Sign In must be disabled until both fields are filled")
        XCTAssertTrue(app.buttons["auth.forgot-password"].exists)
        XCTAssertTrue(app.buttons["auth.create-account"].exists)
        attachScreenshot(app, name: "signin-empty-light")

        pasteText(fixture.email, into: email, app: app)
        pasteText("definitely-not-the-password", into: password, app: app)
        XCTAssertTrue(signIn.isEnabled)

        let toggle = app.buttons["auth.password.visibility"].firstMatch
        XCTAssertTrue(toggle.exists)
        XCTAssertEqual(toggle.label, "Show password")
        toggle.tap()
        XCTAssertTrue(app.textFields["auth.password"].firstMatch.waitForExistence(timeout: 3))
        XCTAssertEqual(app.buttons["auth.password.visibility"].firstMatch.label, "Hide password")
        attachScreenshot(app, name: "signin-filled-revealed-light")
        let hide = app.buttons["Hide password"].firstMatch
        expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: hide)
        waitForExpectations(timeout: 5)
        hide.tap()
        XCTAssertTrue(app.secureTextFields["auth.password"].firstMatch.waitForExistence(timeout: 3))

        signIn.tap()
        let error = app.descendants(matching: .any)["auth.error"].firstMatch
        XCTAssertTrue(error.waitForExistence(timeout: 20), "Wrong password should show an inline error")
        XCTAssertFalse(app.descendants(matching: .any)["native.home"].exists)
        attachScreenshot(app, name: "signin-error-light")

        // Password is cleared after a failed attempt; enter the real one by hand.
        pasteText(fixture.password, into: app.secureTextFields["auth.password"].firstMatch, app: app)
        XCTAssertFalse(error.exists, "Editing should clear the stale error")
        signIn.tap()
        let home = app.descendants(matching: .any)["native.home"].firstMatch
        let firstRun = app.descendants(matching: .any)["firstrun.root"].firstMatch
        let signedIn = Date().addingTimeInterval(30)
        while !(home.exists || firstRun.exists) && Date() < signedIn {
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        }
        XCTAssertTrue(home.exists || firstRun.exists, "Manual sign-in did not reach the shell")
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
    func testConversationUsesContinuousDetailAndPinnedComposer() throws {
        let app = try launchThroughAppGate(arguments: ["--runtime-unavailable", "--reset-appearance", "--ui-dark"])
        let comment = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "home.action.comment.")).firstMatch
        XCTAssertTrue(comment.waitForExistence(timeout: 12))
        comment.tap()
        XCTAssertTrue(app.buttons["Close comments"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.textFields["Add a comment…"].exists)
        let message = "A clearer conversation, with room for the content."
        app.textFields["Add a comment…"].tap()
        app.textFields["Add a comment…"].typeText(message)
        app.buttons["Send"].tap()
        XCTAssertTrue(app.staticTexts[message].firstMatch.waitForExistence(timeout: 10))
        attachScreenshot(app, name: "post05-comments-dark")
        app.buttons["Close comments"].tap()
        let open = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "post.open.")).firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        open.tap()
        XCTAssertTrue(app.descendants(matching: .any)["native.post"].firstMatch.waitForExistence(timeout: 6))
        XCTAssertTrue(app.textFields["Add a comment…"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts[message].firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(app.tabBars.firstMatch.isHittable)
        XCTAssertEqual(app.scrollViews.count, 1)
        attachScreenshot(app, name: "post05-continuous-detail-dark")
    }

    func testSocialEntriesOpenStoryComposerAndReels() throws {
        let app = try launchThroughAppGate(arguments: ["--runtime-unavailable", "--reset-appearance", "--ui-light"])
        let create = app.buttons["Create story"].firstMatch
        XCTAssertTrue(create.waitForExistence(timeout: 8))
        create.tap()
        XCTAssertTrue(app.descendants(matching: .any)["story.create"].firstMatch.waitForExistence(timeout: 6))
        XCTAssertTrue(app.buttons["Add a photo"].exists)
        XCTAssertTrue(app.staticTexts["Available for 24 hours"].exists)
        attachScreenshot(app, name: "post05-story-composer")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let reels = app.buttons["home.open-reels"].firstMatch
        XCTAssertTrue(reels.waitForExistence(timeout: 5))
        reels.tap()
        XCTAssertTrue(app.descendants(matching: .any)["reels.feed"].firstMatch.waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["Post a video"].exists)
        attachScreenshot(app, name: "post05-reels-entry")
        app.buttons["Back"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["native.home"].firstMatch.waitForExistence(timeout: 5))
    }

    /// Regression for stories over nginx's 1 MiB body limit: injects a >1 MB prepared
    /// photo (DEBUG hook, N1 fixture host only) and shares it to the N1 test server.
    func testLargeStoryPhotoSharesToN1Fixture() throws {
        let app = try launchThroughAppGate(arguments: [
            "--runtime-unavailable", "--reset-appearance", "--ui-light", "--uitest-story-large-photo"
        ])
        let create = app.buttons["Create story"].firstMatch
        XCTAssertTrue(create.waitForExistence(timeout: 8))
        create.tap()
        let composer = app.descendants(matching: .any)["story.create"].firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 6))
        let photo = app.descendants(matching: .any)["story.create.photo"].firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 6))
        let selected = NSPredicate(format: "value BEGINSWITH %@", "Photo selected")
        expectation(for: selected, evaluatedWith: photo)
        waitForExpectations(timeout: 30)
        let digits = (photo.value as? String)?.components(separatedBy: CharacterSet.decimalDigits.inverted).joined() ?? ""
        XCTAssertGreaterThan(Int(digits) ?? 0, 1_048_576, "Injected story photo must exceed the 1 MiB proxy limit")
        let caption = app.textFields["Add a caption"].firstMatch
        if caption.waitForExistence(timeout: 3) {
            caption.tap()
            caption.typeText("N1 large photo regression")
        }
        let share = app.buttons["story.create.share"].firstMatch
        XCTAssertTrue(share.waitForExistence(timeout: 5))
        XCTAssertTrue(share.isEnabled)
        attachScreenshot(app, name: "story-large-photo-ready")
        share.tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: composer)
        waitForExpectations(timeout: 90)
        XCTAssertTrue(app.descendants(matching: .any)["native.home"].firstMatch.waitForExistence(timeout: 10))
        attachScreenshot(app, name: "story-large-photo-posted")

        // The posted story must surface as a live own story, before and after a rail refresh.
        let own = app.descendants(matching: .any)["home.story.own"].firstMatch
        XCTAssertTrue(own.waitForExistence(timeout: 8))
        XCTAssertEqual(own.value as? String, "active", "Own story tile must not fall back to the empty composer tile")
        app.swipeDown()
        app.swipeDown()
        sleep(3)
        XCTAssertEqual(own.value as? String, "active", "Rail refresh must keep the posted story visible")
        own.tap()
        XCTAssertTrue(app.descendants(matching: .any)["story.viewer"].firstMatch.waitForExistence(timeout: 10),
                      "Tapping your story opens the viewer, not the composer")
        XCTAssertFalse(app.descendants(matching: .any)["story.create"].firstMatch.exists)
        attachScreenshot(app, name: "story-large-photo-viewer")
    }

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

        scrubEdgePicker(app, to: "/home/for-you")
        XCTAssertEqual(app.descendants(matching: .any)["native.home"].firstMatch.value as? String, "/home/for-you")

        let summary = app.buttons["accessory.summary"].firstMatch
        XCTAssertTrue(summary.waitForExistence(timeout: 4))
        summary.tap()
        let sheet = app.descendants(matching: .any)["modula.sheet"].firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Overview"].waitForExistence(timeout: 4))
        dismissModulaSheet(sheet)

        let tools = app.buttons["accessory.tools"].firstMatch
        XCTAssertTrue(tools.waitForExistence(timeout: 4))
        tools.tap()
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["home.tools.refresh"].waitForExistence(timeout: 4))
        dismissModulaSheet(sheet)

        attachScreenshot(app, name: "n3c-home-tools")
    }

    func testProgressiveHeaderCollapseStages() throws {
        let app = try launchThroughAppGate(arguments: ["--runtime-unavailable", "--reset-appearance", "--ui-light"])

        let home = app.descendants(matching: .any)["native.home"].firstMatch
        XCTAssertTrue(home.waitForExistence(timeout: 10))
        attachScreenshot(app, name: "n3c-header-00-resting")

        // Switch to For You so the feed has public content to scroll under the header.
        scrubEdgePicker(app, to: "/home/for-you")
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
    func testProfileHeroKeepsIdentityAndMetricsInFirstViewport() throws {
        let app = try launchThroughAppGate(arguments: ["--runtime-unavailable", "--reset-appearance", "--ui-light"])
        selectTab(app, "Profile")
        let identity = app.descendants(matching: .any)["profile.identity"].firstMatch
        XCTAssertTrue(identity.waitForExistence(timeout: 10))
        let avatar = app.buttons["profile.avatar"].firstMatch
        let metrics = app.descendants(matching: .any)["profile.metrics"].firstMatch
        XCTAssertTrue(avatar.exists)
        XCTAssertTrue(metrics.exists)
        XCTAssertLessThan(avatar.frame.minY, identity.frame.minY)
        XCTAssertLessThan(identity.frame.minY - avatar.frame.maxY, 40)
        XCTAssertLessThan(metrics.frame.maxY, app.frame.maxY - 80)
        XCTAssertLessThanOrEqual(metrics.frame.maxX, app.frame.maxX - 40, "Metrics must clear the Edge Picker")
        attachScreenshot(app, name: "post05-compact-profile-light")
    }

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

@MainActor
final class MCAT02CatalogUITests: XCTestCase {
    func testAdvancedInteractionCatalogPagesOpen() throws {
        let app = try launchThroughAppGate(arguments: ["--runtime-unavailable", "--reset-appearance"])
        openSettingsFromShell(app)

        let catalog = scrollToElement(named: "Component Catalog", in: app, maximumSwipes: 10)
        XCTAssertTrue(catalog.waitForExistence(timeout: 5))
        catalog.tap()
        XCTAssertTrue(app.descendants(matching: .any)["developer.components"].waitForExistence(timeout: 6))

        let advanced = scrollToElement(named: "Open interaction laboratory", in: app, maximumSwipes: 6)
        XCTAssertTrue(advanced.exists)
        advanced.tap()
        XCTAssertTrue(app.descendants(matching: .any)["catalog.advanced"].waitForExistence(timeout: 6))

        for title in ["Context", "Reactions", "Overlays", "Sheets", "Tabs", "Spaces", "Selection", "Media", "Sharing", "Indicators", "Composer"] {
            let row = scrollToElement(named: title, in: app, maximumSwipes: 8)
            XCTAssertTrue(row.exists, "Missing catalog page \(title)")
            row.tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 4), "Failed to open \(title)")
            app.navigationBars.buttons.element(boundBy: 0).tap()
            XCTAssertTrue(app.descendants(matching: .any)["catalog.advanced"].waitForExistence(timeout: 4))
        }

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "mcat-02-advanced-interaction-catalog"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testCoreInteractionsInOLEDAndReducedMotion() throws {
        let app = try launchThroughAppGate(arguments: [
            "--runtime-unavailable", "--reset-appearance", "--ui-oled", "-UIAccessibilityReduceMotionEnabled", "YES"
        ])
        try openAdvancedCatalog(app)

        openPage("Context", app: app)
        let contextSource = app.staticTexts["Long-press this source"].firstMatch
        XCTAssertTrue(contextSource.waitForExistence(timeout: 4))
        contextSource.press(forDuration: 1.0)
        let save = app.buttons["Save"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 4))
        save.tap()
        XCTAssertTrue(app.staticTexts["Latest action: Save"].waitForExistence(timeout: 4))
        back(app)

        openPage("Reactions", app: app)
        let bar = app.descendants(matching: .any)["modula.reaction.bar"].firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: 4))
        bar.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5))
            .press(forDuration: 0.5, thenDragTo: bar.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5)))
        XCTAssertTrue(bar.exists)
        back(app)

        openPage("Sheets", app: app)
        let morph = app.buttons["Open sheet"].firstMatch
        XCTAssertTrue(morph.waitForExistence(timeout: 4))
        morph.tap()
        XCTAssertTrue(app.staticTexts["Morphing Sheet"].waitForExistence(timeout: 4))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
        XCTAssertTrue(app.navigationBars["Sheets"].waitForExistence(timeout: 4))
        back(app)

        openPage("Tabs", app: app)
        app.buttons["For You"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Selected: forYou"].waitForExistence(timeout: 4))
        back(app)

        openPage("Selection", app: app)
        app.buttons["Select all"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["5 selected"].waitForExistence(timeout: 4))
        back(app)

        openPage("Media", app: app)
        app.buttons["Portrait"].firstMatch.tap()
        let viewer = app.descendants(matching: .any)["media.viewer"].firstMatch
        XCTAssertTrue(viewer.waitForExistence(timeout: 4))
        viewer.doubleTap()
        app.buttons["Close media"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Media"].waitForExistence(timeout: 4))
        back(app)

        openPage("Composer", app: app)
        let field = app.textFields["Ask or reply…"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 4))
        field.tap()
        field.typeText("Catalog acceptance")
        XCTAssertTrue(app.buttons["Send"].firstMatch.isEnabled)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "mcat-02-oled-reduced-motion-composer"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func openAdvancedCatalog(_ app: XCUIApplication) throws {
        openSettingsFromShell(app)
        let catalog = scrollToElement(named: "Component Catalog", in: app, maximumSwipes: 10)
        XCTAssertTrue(catalog.waitForExistence(timeout: 5))
        catalog.tap()
        let advanced = scrollToElement(named: "Open interaction laboratory", in: app, maximumSwipes: 6)
        XCTAssertTrue(advanced.exists)
        advanced.tap()
        XCTAssertTrue(app.descendants(matching: .any)["catalog.advanced"].waitForExistence(timeout: 6))
    }

    private func openPage(_ title: String, app: XCUIApplication) {
        let row = scrollToElement(named: title, in: app, maximumSwipes: 8)
        XCTAssertTrue(row.exists)
        row.tap()
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 4))
    }

    private func back(_ app: XCUIApplication) {
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.descendants(matching: .any)["catalog.advanced"].waitForExistence(timeout: 4))
    }
}

@MainActor
final class POST03CatalogUITests: XCTestCase {
    func testProductionRailHasLabelledContextActions() throws {
        let app = try launchThroughAppGate(arguments: ["--runtime-unavailable", "--reset-appearance", "--ui-light"])
        try openContentCatalog(app)
        openPage("Media Action Rail", app: app)
        let more = app.buttons["More actions"].firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 6))
        more.tap()
        XCTAssertTrue(app.buttons["Copy Link"].firstMatch.waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["Close post actions"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "post05-labelled-media-context-light"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["Copy Link"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Copy Link selected · preview only"].exists)
    }

    func testContentPostCatalogPagesAndFullInteractionOpen() throws {
        let app = try launchThroughAppGate(arguments: ["--runtime-unavailable", "--reset-appearance", "--ui-light"])
        try openContentCatalog(app)

        for title in [
            "Immersive Post Shell", "Post Header", "Text Post", "Image Post", "Image Gallery", "Video Post",
            "PDF Post", "Document Post", "Audio Post", "Link Post", "Mixed Content", "Media Action Rail",
            "Metadata Chips", "Comments Morph", "Post Detail", "Feed Rhythm", "Loading States",
            "Error States", "Attachment Diagnostics"
        ] {
            openPage(title, app: app)
            XCTAssertFalse(app.staticTexts[title].firstMatch.frame.isEmpty, "Invisible catalog content for \(title)")
            back(app)
        }

        openPage("Full Post Interaction", app: app)
        let reactionBar = app.descendants(matching: .any)["post.reaction.picker"]
        for _ in 0..<5 where !reactionBar.exists { app.swipeUp() }
        XCTAssertTrue(reactionBar.waitForExistence(timeout: 4))
        app.buttons["Comments"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Comments"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.textFields["Add a comment…"].waitForExistence(timeout: 4))

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "post-03-full-interaction-comments"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testContentCatalogSupportsOLEDAndReduceMotion() throws {
        let app = try launchThroughAppGate(arguments: [
            "--runtime-unavailable", "--reset-appearance", "--ui-oled", "-UIAccessibilityReduceMotionEnabled", "YES"
        ])
        try openContentCatalog(app)
        openPage("Mixed Content", app: app)
        XCTAssertTrue(app.staticTexts["+1 attachments"].waitForExistence(timeout: 4) || app.staticTexts["Mixed Content"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "post-03-oled-reduced-motion-mixed-content"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testPOST04PublishingLabAndMixedFeedStressRoute() throws {
        let app = try launchThroughAppGate(arguments: ["--runtime-unavailable", "--reset-appearance", "--ui-dark"])
        try openContentCatalog(app)

        openPage("Upload Queue", app: app)
        XCTAssertTrue(app.staticTexts["Uploading 38%"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["Retry"].exists)
        XCTAssertTrue(app.buttons["Cancel"].exists)
        back(app)

        openPage("60+ Mixed Feed", app: app)
        XCTAssertTrue(app.staticTexts["catalog.posts.stress-count"].waitForExistence(timeout: 4))
        XCTAssertTrue(
            ["60 live-backed mixed posts", "60 state fixtures · live feed unavailable"]
                .contains(app.staticTexts["catalog.posts.stress-count"].label)
        )
        let firstFixture = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Fixture '")).firstMatch
        XCTAssertTrue(firstFixture.waitForExistence(timeout: 4))
        let firstFixtureLabel = firstFixture.label
        for _ in 0..<18 { app.swipeUp(velocity: .fast) }
        XCTAssertFalse(app.staticTexts[firstFixtureLabel].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Fixture '")).firstMatch.exists)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "post-04-sixty-item-mixed-feed"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func openContentCatalog(_ app: XCUIApplication) throws {
        openSettingsFromShell(app)
        let catalog = scrollToElement(named: "Component Catalog", in: app, maximumSwipes: 10)
        XCTAssertTrue(catalog.waitForExistence(timeout: 5))
        catalog.tap()
        let content = scrollToElement(named: "Open universal content laboratory", in: app, maximumSwipes: 8)
        XCTAssertTrue(content.exists)
        content.tap()
        XCTAssertTrue(app.descendants(matching: .any)["catalog.posts"].waitForExistence(timeout: 6))
    }

    private func openPage(_ title: String, app: XCUIApplication) {
        let row = scrollToElement(named: title, in: app, maximumSwipes: 12)
        XCTAssertTrue(row.exists, "Missing content catalog page \(title)")
        row.tap()
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5), "Failed to open \(title)")
    }

    private func back(_ app: XCUIApplication) {
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.descendants(matching: .any)["catalog.posts"].waitForExistence(timeout: 4))
    }
}
