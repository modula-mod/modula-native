import SwiftUI
import XCTest
@testable import Modula

final class SettingsServiceTests: XCTestCase {
    private func json(_ text: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    }

    func testStatusSnapshotDecodesLivePayload() throws {
        let value = try json("""
        {"status":"degraded","checkedAt":"2026-10-02T23:46:39.466Z","release":{"commit":"c7c46dfa3d85","builtAt":"2026-10-02T23:43:23Z"},
         "components":[
          {"id":"api","name":"API","state":"operational","latencyMs":13,"lastSeenAt":"2026-10-02T23:46:39.466Z","ageSeconds":0,"pending":null},
          {"id":"worker","name":"Background worker","state":"degraded","latencyMs":null,"lastSeenAt":"2026-10-02T23:40:00.000Z","ageSeconds":400,"pending":null},
          {"id":"jobs","name":"Job queue","state":"operational","latencyMs":null,"lastSeenAt":null,"ageSeconds":0,"pending":0},
          {"id":"mail","name":"Email delivery","state":"brand-new-state","latencyMs":null,"lastSeenAt":null,"ageSeconds":null,"pending":3}
         ]}
        """)
        let snapshot = try GreenfieldValueDecoder.decode(ServiceStatusSnapshot.self, from: value)
        XCTAssertEqual(snapshot.status, .degraded)
        XCTAssertEqual(snapshot.components.count, 4)
        XCTAssertEqual(snapshot.components[0].detail, "13 ms")
        XCTAssertEqual(snapshot.components[1].detail, "Heartbeat 6m ago")
        XCTAssertEqual(snapshot.components[2].detail, "Queue clear")
        XCTAssertEqual(snapshot.components[3].state, .unknown, "Unknown server states must not crash or read as healthy")
        XCTAssertEqual(snapshot.components[3].detail, "3 waiting")
        XCTAssertNotNil(snapshot.checkedDate)
        XCTAssertEqual(snapshot.release?.commit, "c7c46dfa3d85")
    }

    func testRadarEnergyOnlySweepsWithLiveSignal() {
        XCTAssertEqual(ServiceComponentState.operational.radarEnergy, 1)
        XCTAssertGreaterThan(ServiceComponentState.degraded.radarEnergy, 0)
        XCTAssertEqual(ServiceComponentState.outage.radarEnergy, 0)
        XCTAssertEqual(ServiceComponentState.unknown.radarEnergy, 0)
    }

    func testSupportContactDecodes() throws {
        let value = try json("""
        {"supportEmail":"support@modula.digital","categories":["help","bug"],"inAppCases":true,
         "limits":{"subjectMax":140,"messageMax":5000,"perHour":5},"diagnosticKeys":["appVersion","osVersion"]}
        """)
        let contact = try GreenfieldValueDecoder.decode(SupportContactInfo.self, from: value)
        XCTAssertEqual(contact.supportEmail, "support@modula.digital")
        XCTAssertTrue(contact.inAppCases)
        XCTAssertEqual(contact.limits.perHour, 5)
    }

    func testSupportDraftValidationMirrorsServerLimits() {
        var draft = SupportCaseDraft()
        XCTAssertFalse(draft.isValid)
        draft.subject = "  Hi "
        draft.message = "short"
        XCTAssertNotNil(draft.subjectProblem)
        XCTAssertNotNil(draft.messageProblem)
        draft.subject = "Upload fails"
        draft.message = "Uploading a photo stops at 80 percent every time."
        XCTAssertTrue(draft.isValid)
        draft.subject = String(repeating: "a", count: 141)
        XCTAssertFalse(draft.isValid)
    }

    func testDraftBodyOmitsDiagnosticsWhenOptedOut() {
        var draft = SupportCaseDraft(category: .bug, subject: "Crash on open", message: "The app closes when I open Messages.", attachDiagnostics: true)
        let diagnostics = [SupportDiagnostic(key: "osVersion", label: "iOS version", value: "26.0")]
        XCTAssertEqual(draft.body(diagnostics: diagnostics)["diagnostics"]?["osVersion"], .string("26.0"))
        XCTAssertEqual(draft.body(diagnostics: diagnostics)["category"], .string("bug"))
        draft.attachDiagnostics = false
        XCTAssertNil(draft.body(diagnostics: diagnostics)["diagnostics"])
    }

    func testDiagnosticsRespectServerAllowList() {
        let inputs = SupportDiagnostics.Inputs(
            appVersion: "1.0.0", appBuild: "42", debugBuild: false, osVersion: "26.0", deviceModel: "iPhone18,1",
            locale: "en_GB", timeZone: "Europe/London", apiHost: "api.modula.digital", networkPath: "Wi-Fi",
            lowPowerMode: false, reduceMotion: true, dynamicType: "Default", theme: "system", installedModules: 3,
            storageFreeBytes: 1_000_000_000
        )
        let all = SupportDiagnostics.make(inputs)
        XCTAssertEqual(Set(all.map(\.key)), Set(SupportDiagnostics.allowedKeys.filter { $0 != "runtimeState" }))
        XCTAssertTrue(all.allSatisfy { SupportDiagnostics.allowedKeys.contains($0.key) })
        XCTAssertEqual(all.first { $0.key == "buildConfiguration" }?.value, "Release")
        let limited = SupportDiagnostics.make(inputs, allowed: ["appVersion", "osVersion"])
        XCTAssertEqual(limited.map(\.key), ["appVersion", "osVersion"])
    }

    func testCaseSummaryAndExportRowsDecode() throws {
        let summary = try GreenfieldValueDecoder.decode(SupportCaseSummary.self, from: try json("""
        {"caseId":"c1","reference":"MOD-7KQ2M9XA","category":"bug","subject":"Crash","state":"OPEN","createdAt":"2026-10-02T23:00:00.000Z","updatedAt":"2026-10-02T23:00:00.000Z","supportEmail":"support@modula.digital"}
        """))
        XCTAssertEqual(summary.reference, "MOD-7KQ2M9XA")
        XCTAssertNotNil(summary.createdDate)
        let row = try GreenfieldValueDecoder.decode(AccountDataRequestRow.self, from: try json("""
        {"data_request_id":"0192f0a0-1111-7222-8333-944445555666","state":"DISCOVERING","request_type":"EXPORT"}
        """))
        XCTAssertEqual(row.state, "DISCOVERING")
        XCTAssertNotNil(AccountExportModel.safeID(row.dataRequestId))
        XCTAssertNil(AccountExportModel.safeID("../../v1/admin"))
        XCTAssertEqual(AccountExportModel.stepLabel("COLLECTING"), "Collecting your data")
    }

    func testIdempotencyKeysAreHeaderSafe() {
        XCTAssertTrue(GreenfieldClient.isSafeIdempotencyKey("case-\(UUID().uuidString.lowercased())"))
        XCTAssertFalse(GreenfieldClient.isSafeIdempotencyKey("short"))
        XCTAssertFalse(GreenfieldClient.isSafeIdempotencyKey("bad key\r\nX-Injected: 1"))
    }

    func testDynamicTypeLabelsAreHumanReadable() {
        XCTAssertEqual(DynamicTypeSize.large.settingsLabel, "Default")
        XCTAssertEqual(DynamicTypeSize.accessibility3.settingsLabel, "Accessibility 3")
    }

    func testRegistryReflectsLiveHelpAndExport() {
        XCTAssertEqual(SettingsRegistry.destination(for: .help(.status))?.availability, .implemented)
        XCTAssertEqual(SettingsRegistry.destination(for: .help(.contact))?.availability, .implemented)
        XCTAssertEqual(SettingsRegistry.destination(for: .dataStorage(.export))?.availability, .implemented)
        XCTAssertTrue(SettingsRegistry.search(query: "support", includeDeveloper: false).contains { $0.route == .help(.contact) })
    }
}
