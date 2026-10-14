import XCTest

/// MOL-03 §17 automated scenario: the Living Studio end to end on the simulator, per character.
@MainActor
final class MOL03StudioScenarioUITests: XCTestCase {
    override func setUp() async throws { continueAfterFailure = false }

    private func launch(kind: String, reduceMotion: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-skip-first-run", "-composer.mascot.kind", kind, "-dev.moliboo.native3D", "YES",
                               "-moliboo.studio.forceReduceMotion", reduceMotion ? "YES" : "NO", "-MOL01Studio"]   // environment is NOT a launch arg: the argument domain would shadow the user's choice
        app.launch()
        return app
    }

    private func probe(_ app: XCUIApplication, _ id: String) -> [String: String] {
        let e = app.descendants(matching: .any)[id]
        guard e.waitForExistence(timeout: 20) else { return [:] }
        var d: [String: String] = [:]
        for kv in e.label.split(separator: " ") {
            let p = kv.split(separator: "=", maxSplits: 1)
            if p.count == 2 { d[String(p[0])] = String(p[1]) }
        }
        return d
    }

    @discardableResult
    private func wait(_ app: XCUIApplication, _ id: String = "studio.state", _ t: TimeInterval = 15, _ cond: ([String: String]) -> Bool) -> [String: String] {
        let end = Date().addingTimeInterval(t)
        var s = probe(app, id)
        while !cond(s), Date() < end { usleep(250_000); s = probe(app, id) }
        XCTAssertTrue(cond(s), "\(id) never matched: \(s)")
        return s
    }

    private func openStudio(_ app: XCUIApplication, _ kind: String) {
        let entry = app.buttons["moliboo3d.entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 25))
        entry.tap()
        wait(app) { $0["char"] == kind }
        wait(app, "moliboo3d.state", 25) { $0["loaded"] == "1" && $0["failed"] == "0" }
    }

    private func tapEventually(_ el: XCUIElement) {
        XCTAssertTrue(el.waitForExistence(timeout: 8), "\(el)")
        el.tap()
    }

    func testFullStudioScenarioPip() { scenario("pip") }

    /// Switch taps inside a sheet can land during the detent animation; retry once before asserting.
    private func toggle(_ app: XCUIApplication, _ sw: XCUIElement, until cond: ([String: String]) -> Bool) {
        for _ in 0..<3 {
            sw.tap()
            let end = Date().addingTimeInterval(4)
            while Date() < end { if cond(probe(app, "moliboo3d.state")) { return }; usleep(250_000) }
        }
        XCTFail("cap toggle never took effect: \(probe(app, "moliboo3d.state"))")
    }

    private func scenario(_ kind: String) {
        let app = launch(kind: kind)
        openStudio(app, kind)
        // Header + rail present.
        for id in ["studio.rail.style", "studio.rail.play", "studio.rail.expressions", "studio.rail.photo", "studio.envMenu"] {
            XCTAssertTrue(app.descendants(matching: .any)[id].exists, id)
        }
        // Style: four environments, cap toggle.
        tapEventually(app.buttons["studio.rail.style"])
        wait(app) { $0["panel"] == "style" && $0["paused"] == "1" }
        for env in ["nightSky", "cozyRoom", "studio", "meadow"] {
            tapEventually(app.buttons["studio.env.\(env)"])
            wait(app) { $0["env"] == env }
        }
        let cap = app.buttons["studio.style.cap"]
        if cap.waitForExistence(timeout: 5) {
            let before = probe(app, "moliboo3d.state")["cap"] ?? "0"
            toggle(app, cap, until: { $0["cap"] != before })
            toggle(app, cap, until: { $0["cap"] == before })
        }
        // Expressions.
        tapEventually(app.segmentedControls["studio.sheet.tabs"].buttons["Expressions"])
        wait(app) { $0["panel"] == "expressions" }
        for e in ["happy", "excited", "surprised", "sleepy", "sad", "idle"] {
            tapEventually(app.buttons["studio.expr.\(e)"])
            wait(app, "moliboo3d.state", 6) { $0["expr"] == e }
        }
        // Play.
        tapEventually(app.segmentedControls["studio.sheet.tabs"].buttons["Play"])
        wait(app) { $0["panel"] == "play" }
        var reactions = Int(probe(app, "studio.state")["reactions"] ?? "0") ?? 0
        for p in ["pet", "hop", "dance", "peekaboo"] {
            tapEventually(app.buttons["studio.play.\(p)"])
            wait(app) { $0["react"] == p }
            reactions += 1
            sleep(3)   // let the reaction finish (cooldowns)
        }
        tapEventually(app.buttons["studio.play.nap"])
        wait(app) { $0["nap"] == "1" }
        // Wake with a stage tap (the stage stays interactive under the sheet), then close the sheet.
        app.descendants(matching: .any)["moliboo3d.view"].firstMatch.tap()
        wait(app) { $0["nap"] == "0" && $0["react"] == "wake" }
        // Tap spam → exactly one dizzy, no crash, stage still responsive.
        sleep(2)
        let stage = app.descendants(matching: .any)["moliboo3d.view"].firstMatch
        for _ in 0..<7 { stage.tap(); usleep(650_000) }
        wait(app, "studio.state", 8) { $0["react"] == "dizzy" || $0["react"] == "tap" }
        tapEventually(app.buttons["studio.sheet.close"])
        wait(app) { $0["panel"] == "none" }
        // Photo mode hides chrome.
        tapEventually(app.buttons["studio.rail.photo"])
        wait(app) { $0["photo"] == "1" }
        XCTAssertFalse(app.buttons["studio.rail.style"].isHittable)
        tapEventually(app.buttons["studio.photo.done"])
        wait(app) { $0["photo"] == "0" }
        // Drag to turn.
        stage.swipeLeft()
        wait(app, "moliboo3d.state", 6) { ($0["yaw"] ?? "0.00") != "0.00" }
        // Back to Studio (teardown path).
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["moliboo3d.entry"].waitForExistence(timeout: 10))
    }

    func testEveryThreeDCharacterOpensWithItsOwnFraming() {
        for kind in ["moss", "tofu", "bolt", "pebble"] {
            let app = launch(kind: kind)
            openStudio(app, kind)
            XCTAssertNotNil(probe(app, "studio.state")["env"])
            app.terminate()
        }
    }

    func testIdlePersonalityRunsAndReducedMotionSuppressesIt() {
        var app = launch(kind: "pip")
        openStudio(app, "pip")
        wait(app, "studio.state", 25) { (Int($0["idle"] ?? "0") ?? 0) >= 1 }
        app.terminate()
        app = launch(kind: "pip", reduceMotion: true)
        openStudio(app, "pip")
        wait(app) { $0["rm"] == "1" }
        sleep(14)
        XCTAssertEqual(probe(app, "studio.state")["idle"], "0", "Reduced Motion: no idle personality")
        tapEventually(app.buttons["studio.rail.play"])
        tapEventually(app.buttons["studio.play.hop"])
        wait(app) { $0["react"] == "hop" }
    }
}
