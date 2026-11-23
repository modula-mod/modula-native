import XCTest
@testable import Modula

@MainActor
final class AppearanceExperienceTests: XCTestCase {
    func testNamedAccentsRoundTripThroughLiveColour() {
        let defaults = UserDefaults(suiteName: "appearance.experience.\(UUID().uuidString)")!
        let store = AppearanceStore(defaults: defaults)
        for accent in AppearanceStore.Accent.allCases {
            store.selectNamedAccent(accent)
            XCTAssertNil(store.customAccentHex)
            XCTAssertEqual(store.accentTitle, accent.title)
            XCTAssertEqual(AppearanceStore.normalizedHex(accent.hex), accent.hex.uppercased())
            let painted = AppearanceStore.hex(from: accent.color)
            XCTAssertEqual(painted, accent.hex.uppercased(), accent.rawValue)
            XCTAssertEqual(AppearanceStore.hex(from: store.liveAccent), accent.hex.uppercased())
        }
    }

    func testCustomAccentStaysLocalAndResetClearsIt() {
        let defaults = UserDefaults(suiteName: "appearance.custom.\(UUID().uuidString)")!
        let store = AppearanceStore(defaults: defaults)
        store.theme = .light
        store.brandWordmark = .moliboos
        store.selectCustomAccent(hex: "d66056")
        XCTAssertEqual(store.customAccentHex, "#D66056")
        XCTAssertEqual(store.accentTitle, "Custom")
        XCTAssertEqual(AppearanceStore.hex(from: store.liveAccent), "#D66056")
        store.selectCustomAccent(hex: "nope")
        XCTAssertEqual(store.customAccentHex, "#D66056")

        let restored = AppearanceStore(defaults: defaults)
        XCTAssertEqual(restored.theme, .light)
        XCTAssertEqual(restored.brandWordmark, .moliboos)
        XCTAssertEqual(restored.customAccentHex, "#D66056")

        restored.reset()
        XCTAssertNil(restored.customAccentHex)
        XCTAssertEqual(restored.theme, .system)
        XCTAssertEqual(restored.brandWordmark, .modula)
        XCTAssertEqual(restored.accent, .modulaTeal)
    }

    func testLegacyAppearanceBlobIgnoresMissingCustomAccent() {
        let defaults = UserDefaults(suiteName: "appearance.legacy.\(UUID().uuidString)")!
        let legacy = """
        {"theme":"dark","darkStyle":"oled","accent":"coral","fontFamily":"system","textSize":"standard","appIcon":"default","density":"standard","motion":"standard","haptics":"standard","contrastTransparency":"standard","iconStyle":"balanced","interfaceShape":"balanced","moduleBranding":"blend"}
        """.data(using: .utf8)!
        defaults.set(legacy, forKey: "modula.native.appearance.v2")
        let store = AppearanceStore(defaults: defaults)
        XCTAssertEqual(store.theme, .dark)
        XCTAssertEqual(store.accent, .coral)
        XCTAssertNil(store.customAccentHex)
        XCTAssertEqual(store.brandWordmark, .modula)
        XCTAssertEqual(store.accentTitle, "Coral")
    }
}
