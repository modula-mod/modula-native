import AppIntents
import CoreSpotlight
import SwiftUI

// Enhancements-50: system-integration polish kept in one new file.
// - Intent inbox so Siri / Shortcuts / Spotlight intents actually land on their route.
// - Extra App Intents (Saved, Drafts, Activity, Settings) — open-only, never publish.
// - iPad hardware-keyboard shortcuts for tabs, sidebar destinations and scroll-to-top.
// - Spotlight entries for sidebar destinations (navigation only; no private content).

// MARK: - Intent inbox

@MainActor
enum ModulaIntentInbox {
    static let notification = Notification.Name("modula.intent.route")
    private(set) static var pending: AppRoute?

    static func deliver(_ route: AppRoute) {
        pending = route
        NotificationCenter.default.post(name: notification, object: nil)
    }

    static func take() -> AppRoute? {
        defer { pending = nil }
        return pending
    }
}

private struct IntentInboxConsumer: ViewModifier {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .onAppear(perform: consume)
            .onChange(of: scenePhase) { _, phase in if phase == .active { consume() } }
            .onReceive(NotificationCenter.default.publisher(for: ModulaIntentInbox.notification)) { _ in consume() }
    }

    private func consume() {
        guard app.gate.state == .ready, let route = ModulaIntentInbox.take() else { return }
        if case .module(let id, _) = route,
           !ModulaAppIntentBridge.canOpenModule(id: id, installed: app.catalogue.installedIDs, signedIn: app.auth.isSignedIn) {
            app.navigation.flash("Install that module to open it.", symbol: "shippingbox")
            return
        }
        app.openRouted(route)
    }
}

extension View {
    func modulaConsumesIntentRoutes() -> some View { modifier(IntentInboxConsumer()) }
}

// MARK: - More App Intents

@available(iOS 16.0, *)
struct OpenSavedIntent: AppIntent {
    static var title: LocalizedStringResource { "Open Saved" }
    static var description: IntentDescription { IntentDescription("Opens your saved posts in Modula.") }
    static var openAppWhenRun: Bool { true }
    @MainActor func perform() async throws -> some IntentResult {
        ModulaIntentInbox.deliver(.saved(.root)); return .result()
    }
}

@available(iOS 16.0, *)
struct OpenDraftsIntent: AppIntent {
    static var title: LocalizedStringResource { "Open Drafts" }
    static var description: IntentDescription { IntentDescription("Opens your unfinished drafts in Modula.") }
    static var openAppWhenRun: Bool { true }
    @MainActor func perform() async throws -> some IntentResult {
        ModulaIntentInbox.deliver(.drafts(.root)); return .result()
    }
}

@available(iOS 16.0, *)
struct OpenActivityIntent: AppIntent {
    static var title: LocalizedStringResource { "Open Activity" }
    static var description: IntentDescription { IntentDescription("Opens your Modula activity.") }
    static var openAppWhenRun: Bool { true }
    @MainActor func perform() async throws -> some IntentResult {
        ModulaIntentInbox.deliver(.activity(.all)); return .result()
    }
}

@available(iOS 16.0, *)
struct OpenSettingsIntent: AppIntent {
    static var title: LocalizedStringResource { "Open Modula Settings" }
    static var description: IntentDescription { IntentDescription("Opens Modula Settings.") }
    static var openAppWhenRun: Bool { true }
    @MainActor func perform() async throws -> some IntentResult {
        ModulaIntentInbox.deliver(.settings(.root)); return .result()
    }
}

// MARK: - iPad keyboard shortcuts

struct ModulaPolishKeyboardCommands: Commands {
    var environment: AppEnvironment

    var body: some Commands {
        CommandMenu("Go") {
            ForEach(Array(AppTab.allCases.enumerated()), id: \.element) { index, tab in
                Button(tab.title) { go { environment.navigation.select(tab) } }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
            Divider()
            Button("Scroll to Top") { go { ModulaTabReselect.post(environment.navigation.selectedTab) } }
                .keyboardShortcut(.upArrow, modifiers: .command)
            Button("Saved") { go { environment.openRouted(.saved(.root)) } }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            Button("Drafts") { go { environment.openRouted(.drafts(.root)) } }
                .keyboardShortcut("d", modifiers: [.command, .shift])
            Button("Messages") { go { environment.openRouted(.messages(.inbox)) } }
                .keyboardShortcut("m", modifiers: [.command, .shift])
            Button("Settings") { go { environment.openRouted(.settings(.root)) } }
                .keyboardShortcut(",", modifiers: .command)
            Button("Toggle Sidebar") { go { environment.navigation.sidebarPresented.toggle() } }
                .keyboardShortcut("l", modifiers: [.command, .shift])
        }
    }

    private func go(_ action: () -> Void) {
        guard environment.gate.state == .ready else { return }
        action()
        HapticEngine.shared.play(.navigation)
    }
}

// MARK: - Spotlight destinations

enum ModulaSpotlightDestinations {
    static let domain = "digital.modula.spotlight.destinations"
    static let entries: [(id: String, title: String, keywords: [String], route: AppRoute)] = [
        ("saved", "Saved", ["saved", "bookmarks"], .saved(.root)),
        ("collections", "Collections", ["collections", "boards"], .collections(.root)),
        ("drafts", "Drafts", ["drafts", "unfinished"], .drafts(.root)),
        ("messages", "Messages", ["messages", "dm", "inbox"], .messages(.inbox)),
        ("activity", "Activity", ["activity", "mentions", "notifications"], .activity(.all))
    ]

    static func refresh() {
        let items = entries.map { entry -> CSSearchableItem in
            let attributes = CSSearchableItemAttributeSet(contentType: .content)
            attributes.title = entry.title
            attributes.contentDescription = "Open \(entry.title) in Modula"
            attributes.keywords = ["modula"] + entry.keywords
            return CSSearchableItem(uniqueIdentifier: "destination:\(entry.id)", domainIdentifier: domain, attributeSet: attributes)
        }
        let index = CSSearchableIndex.default()
        index.deleteSearchableItems(withDomainIdentifiers: [domain]) { _ in index.indexSearchableItems(items) { _ in } }
    }

    static func route(for identifier: String) -> AppRoute? {
        guard identifier.hasPrefix("destination:") else { return nil }
        let id = String(identifier.dropFirst("destination:".count))
        return entries.first { $0.id == id }?.route
    }
}
