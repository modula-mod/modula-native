import XCTest

/// MOL-03 E: each new Original opens in the Living Studio and its moving-part clip visibly moves the named parts
/// on the live RealityKit stage (DEBUG `-MOL03Clip` probe compares entity / joint / world transforms before vs during the clip).
final class MOL03OriginalsUITests: XCTestCase {
    override func setUp() { continueAfterFailure = true }

    private func probe(_ app: XCUIApplication, _ id: String) -> [String: String] {
        let e = app.descendants(matching: .any)[id]
        guard e.waitForExistence(timeout: 25) else { return [:] }
        var d: [String: String] = [:]
        for kv in e.label.split(separator: " ") {
            let p = kv.split(separator: "=", maxSplits: 1)
            if p.count == 2 { d[String(p[0])] = String(p[1]) }
        }
        return d
    }

    private func run(_ id: String, clip: String, expect: [String]) {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-skip-first-run", "-composer.mascot.kind", id, "-dev.moliboo.native3D", "YES",
                               "-moliboo.studio.forceReduceMotion", "NO", "-MOL03Studio", id, "-MOL03Clip", clip]
        app.launch()
        let end = Date().addingTimeInterval(30)
        var s = probe(app, "studio.state")
        while s["moved"] == nil, Date() < end { usleep(300_000); s = probe(app, "studio.state") }
        let m = probe(app, "moliboo3d.state")
        XCTAssertEqual(m["loaded"], "1", "\(id) loaded"); XCTAssertEqual(m["failed"], "0")
        XCTAssertEqual(s["char"], id)
        XCTAssertEqual(s["played"], "1", "\(id).\(clip) played: \(s)")
        XCTAssertGreaterThan(Int(s["moved"] ?? "0") ?? 0, 0, "\(id).\(clip) moved nothing: \(s)")
        let parts = (s["parts"] ?? "").lowercased()
        for k in expect { XCTAssertTrue(parts.contains(k.lowercased()), "\(id).\(clip) expected \(k) to move; moved: \(parts)") }
        print("MOL03CLIP \(id).\(clip) moved=\(s["moved"] ?? "?") parts=\(s["parts"] ?? "")")
        if let dir = ProcessInfo.processInfo.environment["MOL03_SHOTS"] {
            try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("mol03e_\(id)_\(clip).png"))
        }
        app.terminate()
    }

    func testNimbusCloudPuff() { run("nimbus", clip: "cloud_puff", expect: []) }
    func testMochiEarTwitch() { run("mochi", clip: "ear_twitch", expect: ["Ear"]) }
    func testMochiTailCurl() { run("mochi", clip: "tail_curl", expect: []) }
    func testSproutLeafSway() { run("sprout", clip: "leaf_sway", expect: ["Leaf"]) }
    func testEmberFlicker() { run("ember", clip: "flicker", expect: ["Flame"]) }
    func testTuckWingFlap() { run("tuck", clip: "wing_flap", expect: ["Wing"]) }
}
