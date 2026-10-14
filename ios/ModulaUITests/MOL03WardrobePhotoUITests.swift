import XCTest

/// MOL-03 D: Wardrobe 2.0 (search, filters, live preview without reload, apply/undo, saved outfits) and Photo capture.
final class MOL03WardrobePhotoUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch(panel: String?) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-skip-first-run", "-composer.mascot.kind", "pip", "-dev.moliboo.native3D", "YES",
                               "-moliboo.studio.forceReduceMotion", "NO", "-MOL03Studio", "pip"] + (panel.map { ["-MOL03Panel", $0] } ?? [])
        app.launch()
        return app
    }

    private func probe(_ app: XCUIApplication, _ id: String) -> [String: String] {
        let e = app.descendants(matching: .any)[id]
        guard e.waitForExistence(timeout: 20) else { return [:] }
        var d: [String: String] = [:]
        for kv in e.label.split(separator: " ") {
            let p = kv.split(separator: "=", maxSplits: 1)
            if p.count == 2 { d[String(p[0])] = String(p[1]) } else if p.count == 1, kv.hasSuffix("=") { d[String(kv.dropLast())] = "" }
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

    private func shot(_ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["MOL03_SHOTS"] else { return }
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    private func ids(_ s: String?) -> Set<String> { Set((s ?? "").split(separator: ",").map(String.init)) }

    func testWardrobeSearchPreviewApplyUndoSave() {
        let app = launch(panel: "wardrobe")
        let m = wait(app, "moliboo3d.state", 25) { $0["loaded"] == "1" && $0["failed"] == "0" }
        let loadms = m["loadms"]
        let start = wait(app) { $0["wpv"] == "0" }
        let saved0 = ids(start["wsaved"])
        let capOn0 = saved0.contains("cap.moliboo.signature")

        // Search narrows the grid.
        let search = app.textFields["wardrobe.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap(); search.typeText("party\n")   // return dismisses the keyboard so the stage stays visible
        let party = app.buttons["wardrobe.item.hat.party"]
        XCTAssertTrue(party.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["wardrobe.item.cap.moliboo.signature"].exists, "search must filter")
        shot("wardrobe-search-party")

        // Try on (preview only): the saved outfit is untouched.
        party.tap()
        var s = wait(app) { self.ids($0["wprev"]).contains("hat.party") && $0["wpv"] == "1" }
        XCTAssertEqual(ids(s["wsaved"]), saved0)

        // Apply → saved; Undo → back.
        app.buttons["wardrobe.apply"].tap()
        s = wait(app) { self.ids($0["wsaved"]).contains("hat.party") && $0["wpv"] == "0" }
        XCTAssertFalse(ids(s["wsaved"]).contains("cap.moliboo.signature"), "same slot: party cone replaces the cap")
        app.buttons["wardrobe.undo"].tap()
        wait(app) { self.ids($0["wsaved"]) == saved0 }

        // 3D filter + live 3D preview of the Signature Cap without reloading Pip.
        app.buttons["wardrobe.search.clear"].tap()
        app.buttons["wardrobe.filter.3d"].tap()
        let capTile = app.buttons["wardrobe.item.cap.moliboo.signature"]
        XCTAssertTrue(capTile.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["wardrobe.item.hat.party"].exists, "3D filter hides 2D-only items")
        capTile.tap()
        let m2 = wait(app, "moliboo3d.state", 10) { $0["cap"] == (capOn0 ? "0" : "1") }
        XCTAssertEqual(m2["loadms"], loadms, "preview must not reload the character")
        XCTAssertEqual(m2["loaded"], "1")
        shot("wardrobe-3d-preview-cap")
        app.buttons["wardrobe.revert"].tap()
        wait(app, "moliboo3d.state", 10) { $0["cap"] == (capOn0 ? "1" : "0") }

        // Save the current look as an outfit.
        let n = Int(probe(app, "studio.state")["wpresets"] ?? "0") ?? 0
        app.buttons["wardrobe.save"].tap()
        let name = app.alerts.textFields.firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.typeText("UITest look")
        app.alerts.buttons["Save"].tap()
        wait(app) { Int($0["wpresets"] ?? "0") == n + 1 }
        XCTAssertTrue(app.buttons["wardrobe.preset.UITest look"].firstMatch.waitForExistence(timeout: 5))
        shot("wardrobe-saved-outfit")
        // Clean up so repeated runs don't pile up presets.
        app.buttons["wardrobe.preset.UITest look"].firstMatch.press(forDuration: 1.0)
        let del = app.buttons["Delete"]
        if del.waitForExistence(timeout: 3) { del.tap(); wait(app) { Int($0["wpresets"] ?? "0") == n } }
    }

    func testPhotoCaptureShowsCharacterAndShare() {
        let app = launch(panel: nil)
        wait(app, "moliboo3d.state", 25) { $0["loaded"] == "1" && $0["failed"] == "0" }
        app.buttons["studio.rail.photo"].tap()
        let shutter = app.buttons["studio.photo.capture"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 8))
        shot("photo-mode-shutter")
        shutter.tap()
        XCTAssertTrue(app.descendants(matching: .any)["studio.photo.preview"].waitForExistence(timeout: 10))
        let s = wait(app) { $0["shots"] == "1" }
        XCTAssertEqual(s["subject"], "1", "captured frame must contain the 3D character, not a blank layer")
        XCTAssertTrue(app.buttons["studio.photo.share"].exists)
        shot("photo-preview-share")
        app.buttons["studio.photo.previewDone"].tap()
        XCTAssertTrue(shutter.waitForExistence(timeout: 5))
    }
}
