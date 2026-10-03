import Foundation
import Network
import Observation
import SwiftUI
import UIKit

// MARK: - Shared decoding

enum GreenfieldValueDecoder {
    /// Re-decodes an untyped Greenfield `data` payload into a typed model.
    static func decode<T: Decodable>(_ type: T.Type, from value: JSONValue) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONEncoder().encode(value))
    }
}

// MARK: - Service status (`GET /v1/status`)

enum ServiceComponentState: String, Decodable, Sendable {
    case operational, degraded, outage, unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ServiceComponentState(rawValue: raw) ?? .unknown
    }

    var title: String {
        switch self {
        case .operational: "Operational"
        case .degraded: "Degraded"
        case .outage: "Outage"
        case .unknown: "No signal"
        }
    }

    var symbol: String {
        switch self {
        case .operational: "checkmark.circle.fill"
        case .degraded: "exclamationmark.triangle.fill"
        case .outage: "xmark.octagon.fill"
        case .unknown: "questionmark.circle"
        }
    }

    var tint: Color {
        switch self {
        case .operational: .green
        case .degraded: .orange
        case .outage: .red
        case .unknown: .secondary
        }
    }

    /// Radar energy: sweep only when there is a live, healthy signal.
    var radarEnergy: Double {
        switch self {
        case .operational: 1
        case .degraded: 0.55
        case .outage, .unknown: 0
        }
    }
}

struct ServiceStatusComponent: Decodable, Identifiable, Sendable, Equatable {
    let id: String
    let name: String
    let state: ServiceComponentState
    let latencyMs: Int?
    let lastSeenAt: String?
    let ageSeconds: Int?
    let pending: Int?

    var symbol: String {
        switch id {
        case "api": "server.rack"
        case "database": "cylinder.split.1x2"
        case "worker": "gearshape.2"
        case "jobs": "list.bullet.rectangle"
        case "mail": "envelope"
        default: "circle.grid.cross"
        }
    }

    /// Short measured detail, never invented: latency, heartbeat age or queue depth.
    var detail: String {
        if let latencyMs { return "\(latencyMs) ms" }
        if id == "worker", let ageSeconds { return "Heartbeat \(ServiceStatusFormat.age(ageSeconds)) ago" }
        if let pending { return pending == 0 ? "Queue clear" : "\(pending) waiting" }
        return state == .unknown ? "No heartbeat yet" : state.title
    }
}

struct ServiceStatusRelease: Decodable, Sendable, Equatable {
    let commit: String?
    let builtAt: String?
}

struct ServiceStatusSnapshot: Decodable, Sendable, Equatable {
    let status: ServiceComponentState
    let checkedAt: String
    let release: ServiceStatusRelease?
    let components: [ServiceStatusComponent]

    var checkedDate: Date? { ServiceStatusFormat.date(checkedAt) }
}

enum ServiceStatusFormat {
    static func age(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3_600 { return "\(seconds / 60)m" }
        return "\(seconds / 3_600)h"
    }

    static func date(_ iso: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: iso) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: iso)
    }
}

/// Device network path, measured with `NWPathMonitor`.
@MainActor @Observable
final class DeviceNetworkMonitor {
    struct Snapshot: Equatable, Sendable {
        var satisfied: Bool
        var interface: String
        var expensive: Bool
        var constrained: Bool

        var summary: String {
            guard satisfied else { return "Offline" }
            var parts = [interface]
            if constrained { parts.append("Low Data Mode") }
            if expensive { parts.append("metered") }
            return parts.joined(separator: " · ")
        }
    }

    private(set) var snapshot: Snapshot?
    private var monitor: NWPathMonitor?

    func start() {
        guard monitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let next = Self.snapshot(for: path)
            Task { @MainActor in self?.snapshot = next }
        }
        monitor.start(queue: DispatchQueue(label: "digital.modula.settings.path"))
        self.monitor = monitor
    }

    func stop() {
        monitor?.cancel()
        monitor = nil
    }

    nonisolated static func snapshot(for path: NWPath) -> Snapshot {
        let interface: String
        if path.usesInterfaceType(.wifi) { interface = "Wi-Fi" }
        else if path.usesInterfaceType(.cellular) { interface = "Cellular" }
        else if path.usesInterfaceType(.wiredEthernet) { interface = "Ethernet" }
        else if path.status == .satisfied { interface = "Connected" }
        else { interface = "Offline" }
        return Snapshot(satisfied: path.status == .satisfied, interface: interface, expensive: path.isExpensive, constrained: path.isConstrained)
    }
}

@MainActor @Observable
final class ServiceStatusModel {
    enum Phase: Equatable {
        case idle, loading
        case loaded(ServiceStatusSnapshot, roundTripMs: Int)
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var lastRefresh: Date?

    var snapshot: ServiceStatusSnapshot? {
        if case .loaded(let snapshot, _) = phase { return snapshot }
        return nil
    }

    var overall: ServiceComponentState {
        switch phase {
        case .loaded(let snapshot, _): snapshot.status
        case .failed: .outage
        case .idle, .loading: .unknown
        }
    }

    func refresh(client: GreenfieldClient) async {
        if case .loaded = phase {} else { phase = .loading }
        let started = ContinuousClock.now
        do {
            let value = try await client.publicJSON("GET", path: "/v1/status")
            let elapsed = ContinuousClock.now - started
            let snapshot = try GreenfieldValueDecoder.decode(ServiceStatusSnapshot.self, from: value)
            let ms = Int(elapsed.components.seconds * 1_000) + Int(elapsed.components.attoseconds / 1_000_000_000_000_000)
            phase = .loaded(snapshot, roundTripMs: max(ms, 0))
        } catch {
            phase = .failed((error as? LocalizedError)?.errorDescription ?? "Modula could not be reached.")
        }
        lastRefresh = .now
    }
}

// MARK: - Support (`/v1/support/*`)

struct SupportContactInfo: Decodable, Sendable, Equatable {
    struct Limits: Decodable, Sendable, Equatable {
        let subjectMax: Int
        let messageMax: Int
        let perHour: Int
    }

    let supportEmail: String
    let categories: [String]
    let inAppCases: Bool
    let limits: Limits
    let diagnosticKeys: [String]
}

struct SupportCaseSummary: Decodable, Identifiable, Sendable, Equatable {
    let caseId: String
    let reference: String
    let category: String
    let subject: String
    let state: String
    let createdAt: String
    var id: String { caseId }
    var createdDate: Date? { ServiceStatusFormat.date(createdAt) }
}

struct SupportCaseList: Decodable, Sendable {
    let items: [SupportCaseSummary]
}

enum SupportCategory: String, CaseIterable, Identifiable, Sendable {
    case help, bug, account, privacy, safety, feedback
    var id: String { rawValue }

    var title: String {
        switch self {
        case .help: "Question"
        case .bug: "Something’s broken"
        case .account: "Account & sign-in"
        case .privacy: "Privacy & data"
        case .safety: "Safety concern"
        case .feedback: "Feedback"
        }
    }

    var symbol: String {
        switch self {
        case .help: "questionmark.bubble"
        case .bug: "ant"
        case .account: "person.crop.circle.badge.exclamationmark"
        case .privacy: "hand.raised"
        case .safety: "shield.lefthalf.filled"
        case .feedback: "lightbulb"
        }
    }
}

/// Mirrors the server limits so the form can validate before sending.
struct SupportCaseDraft: Equatable, Sendable {
    static let subjectRange = 3...140
    static let messageRange = 10...5_000

    var category: SupportCategory = .help
    var subject = ""
    var message = ""
    var attachDiagnostics = true

    var trimmedSubject: String { subject.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedMessage: String { message.trimmingCharacters(in: .whitespacesAndNewlines) }

    var subjectProblem: String? {
        Self.subjectRange.contains(trimmedSubject.count) ? nil : "Use 3–140 characters."
    }

    var messageProblem: String? {
        Self.messageRange.contains(trimmedMessage.count) ? nil : "Describe it in at least 10 characters."
    }

    var isValid: Bool { subjectProblem == nil && messageProblem == nil }

    func body(diagnostics: [SupportDiagnostic]) -> JSONValue {
        var object: [String: JSONValue] = [
            "category": .string(category.rawValue),
            "subject": .string(trimmedSubject),
            "message": .string(trimmedMessage),
        ]
        if attachDiagnostics, !diagnostics.isEmpty {
            object["diagnostics"] = .object(Dictionary(uniqueKeysWithValues: diagnostics.map { ($0.key, JSONValue.string($0.value)) }))
        }
        return .object(object)
    }
}

/// One device fact the member can review before it is attached to a support case.
struct SupportDiagnostic: Identifiable, Equatable, Sendable {
    let key: String
    let label: String
    let value: String
    var id: String { key }
}

enum SupportDiagnostics {
    /// Keys the server accepts. Anything else is dropped client-side too.
    static let allowedKeys: [String] = [
        "appVersion", "appBuild", "buildConfiguration", "platform", "osVersion", "deviceModel",
        "locale", "timeZone", "apiHost", "networkPath", "lowPowerMode", "reduceMotion",
        "dynamicType", "theme", "installedModules", "runtimeState", "storageFree",
    ]

    struct Inputs: Sendable {
        var appVersion: String?
        var appBuild: String?
        var debugBuild: Bool
        var osVersion: String
        var deviceModel: String
        var locale: String
        var timeZone: String
        var apiHost: String?
        var networkPath: String?
        var lowPowerMode: Bool
        var reduceMotion: Bool
        var dynamicType: String
        var theme: String
        var installedModules: Int
        var storageFreeBytes: Int64?
    }

    static func make(_ inputs: Inputs, allowed: [String] = allowedKeys) -> [SupportDiagnostic] {
        var items: [SupportDiagnostic] = []
        func add(_ key: String, _ label: String, _ value: String?) {
            guard let value, !value.isEmpty, allowed.contains(key) else { return }
            items.append(SupportDiagnostic(key: key, label: label, value: String(value.prefix(200))))
        }
        add("appVersion", "App version", inputs.appVersion)
        add("appBuild", "Build", inputs.appBuild)
        add("buildConfiguration", "Configuration", inputs.debugBuild ? "Debug" : "Release")
        add("platform", "Platform", "iOS")
        add("osVersion", "iOS version", inputs.osVersion)
        add("deviceModel", "Device", inputs.deviceModel)
        add("locale", "Language", inputs.locale)
        add("timeZone", "Time zone", inputs.timeZone)
        add("apiHost", "Server", inputs.apiHost)
        add("networkPath", "Network", inputs.networkPath)
        add("lowPowerMode", "Low Power Mode", inputs.lowPowerMode ? "On" : "Off")
        add("reduceMotion", "Reduce Motion", inputs.reduceMotion ? "On" : "Off")
        add("dynamicType", "Text size", inputs.dynamicType)
        add("theme", "Theme", inputs.theme)
        add("installedModules", "Modules loaded", String(inputs.installedModules))
        if let free = inputs.storageFreeBytes {
            add("storageFree", "Free storage", ByteCountFormatter.string(fromByteCount: free, countStyle: .file))
        }
        return items
    }

    @MainActor static func deviceModelIdentifier() -> String {
        var info = utsname()
        uname(&info)
        let mirror = Mirror(reflecting: info.machine)
        let id = mirror.children.reduce(into: "") { result, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            result.append(Character(UnicodeScalar(UInt8(value))))
        }
        return id.isEmpty ? UIDevice.current.model : id
    }

    static func freeStorageBytes() -> Int64? {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }
}

extension DynamicTypeSize {
    /// Human label for Dynamic Type sizes (instead of `String(describing:)`).
    var settingsLabel: String {
        switch self {
        case .xSmall: "Extra Small"
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Default"
        case .xLarge: "Large"
        case .xxLarge: "Extra Large"
        case .xxxLarge: "Extra Extra Large"
        case .accessibility1: "Accessibility 1"
        case .accessibility2: "Accessibility 2"
        case .accessibility3: "Accessibility 3"
        case .accessibility4: "Accessibility 4"
        case .accessibility5: "Accessibility 5"
        @unknown default: "System"
        }
    }
}

// MARK: - Account data export (`/v1/account/data-exports`)

struct AccountDataRequestRow: Decodable, Sendable, Equatable {
    let dataRequestId: String
    let state: String

    enum CodingKeys: String, CodingKey {
        case dataRequestId = "data_request_id"
        case state
    }
}

struct AccountDataRequestEnvelope: Decodable, Sendable {
    let request: AccountDataRequestRow
}

enum AccountExportState: Equatable {
    case idle
    case working(String)
    case ready(URL, artifactCount: Int, bytes: Int)
    case failed(String)
}

@MainActor @Observable
final class AccountExportModel {
    private(set) var state: AccountExportState = .idle
    private var key = "export-\(UUID().uuidString.lowercased())"

    nonisolated static func stepLabel(_ serverState: String) -> String {
        switch serverState {
        case "DISCOVERING": "Finding your data"
        case "COLLECTING": "Collecting your data"
        case "READY": "Packaging"
        default: "Preparing export"
        }
    }

    func start(client: GreenfieldClient) async {
        state = .working("Requesting export")
        do {
            let created = try await client.authenticatedJSON("POST", path: "/v1/account/data-exports", body: .object([:]), idempotencyKey: key)
            var row = try GreenfieldValueDecoder.decode(AccountDataRequestRow.self, from: created)
            var attempts = 0
            while !["READY", "COMPLETED"].contains(row.state) {
                if ["FAILED", "CANCELLED"].contains(row.state) { throw ExportError.server(row.state) }
                attempts += 1
                if attempts > 12 { throw ExportError.slow }
                state = .working(Self.stepLabel(row.state))
                guard let id = Self.safeID(row.dataRequestId) else { throw ExportError.server("INVALID") }
                let advanced = try await client.authenticatedJSON("POST", path: "/v1/account/data-requests/\(id)/advance", body: .object([:]))
                row = try GreenfieldValueDecoder.decode(AccountDataRequestEnvelope.self, from: advanced).request
                if !["READY", "COMPLETED"].contains(row.state) { try await Task.sleep(for: .milliseconds(600)) }
            }
            state = .working("Packaging")
            guard let id = Self.safeID(row.dataRequestId) else { throw ExportError.server("INVALID") }
            let artifacts = try await client.authenticatedJSON("GET", path: "/v1/account/data-requests/\(id)/artifacts")
            let data = try JSONEncoder.exportEncoder.encode(artifacts)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("Modula-data-export-\(Self.fileStamp()).json")
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            let count: Int = {
                if case .array(let items)? = artifacts["artifacts"] { return items.count }
                return 0
            }()
            state = .ready(url, artifactCount: count, bytes: data.count)
            key = "export-\(UUID().uuidString.lowercased())"
        } catch ExportError.slow {
            state = .failed("Your export is still being collected. Try again in a few minutes — the same request continues.")
        } catch ExportError.server(let code) {
            state = .failed(code == "CANCELLED" ? "This export was cancelled." : "The export could not be completed. Try again.")
            key = "export-\(UUID().uuidString.lowercased())"
        } catch {
            state = .failed((error as? LocalizedError)?.errorDescription ?? "The export could not be completed.")
        }
    }

    func reset() { state = .idle }

    nonisolated static func safeID(_ value: String) -> String? {
        value.range(of: "^[A-Za-z0-9-]{8,80}$", options: .regularExpression) == nil ? nil : value
    }

    private static func fileStamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: .now)
    }

    private enum ExportError: Error { case slow, server(String) }
}

private extension JSONEncoder {
    static var exportEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}

enum SettingsEnvironmentInfo {
    /// Host of the configured Greenfield API (never a token or path).
    static var apiHost: String {
        (Bundle.main.object(forInfoDictionaryKey: "ModulaAPIURL") as? String)
            .flatMap { URL(string: $0) }?
            .host ?? "unconfigured"
    }
}
