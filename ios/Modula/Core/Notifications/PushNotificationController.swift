import Foundation
import Observation
import UIKit
import UserNotifications

// MARK: - Flag

/// Push is behind a flag until the Greenfield push routes (`/v1/push/*`) and the
/// APNs worker are deployed. Release reads `ModulaPushEnabled` from Info.plist
/// (ships `NO`); Debug can also be switched on from Settings → Notifications or
/// with the `--push-enabled` launch argument.
enum PushFeatureFlags {
    static let debugOverrideKey = "dev.push.enabled"

    static func enabled(defaults: UserDefaults = .standard, bundle: Bundle = .main) -> Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--push-enabled") { return true }
        if let override = defaults.object(forKey: debugOverrideKey) as? Bool { return override }
        #endif
        return bundle.object(forInfoDictionaryKey: "ModulaPushEnabled") as? Bool ?? false
    }
}

// MARK: - API

/// Greenfield push routes added in modula-latest `feature/push-notifications`.
enum PushAPI {
    static let devices = "/v1/push/devices"
    static func device(_ token: String) -> String { "/v1/push/devices/\(token)" }
    static let preferences = "/v1/push/preferences"

    /// APNs environment the token belongs to. Debug builds are signed with the
    /// development aps-environment; archives exported for TestFlight/App Store use production.
    static var environment: String {
        #if DEBUG
        "development"
        #else
        "production"
        #endif
    }

    static func hexToken(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined() }
}

/// Mirrors `PushPreferencesDto` from `services/greenfield-api/src/domains/push/service.ts`.
struct PushPreferences: Codable, Equatable, Sendable {
    struct QuietHours: Codable, Equatable, Sendable {
        var enabled: Bool
        var start: String
        var end: String
        var timezone: String
    }
    var enabled: Bool
    var categories: [String: Bool]
    var quietHours: QuietHours
    var version: Int
}

enum PushCategoryKey: String, CaseIterable, Identifiable, Sendable {
    case likes, comments, replies, mentions, follows, messages, stories, molibooCare, gubicInvites
    var id: String { rawValue }

    var title: String {
        switch self {
        case .likes: "Likes"
        case .comments: "Comments"
        case .replies: "Replies"
        case .mentions: "Mentions"
        case .follows: "Follows & requests"
        case .messages: "Messages"
        case .stories: "Stories"
        case .molibooCare: "Moliboo care"
        case .gubicInvites: "GUBIC invites"
        }
    }

    var detail: String {
        switch self {
        case .likes: "When someone likes your post"
        case .comments: "Comments on your posts"
        case .replies: "Replies to your comments"
        case .mentions: "When someone mentions you"
        case .follows: "New followers and follow requests"
        case .messages: "Direct messages and message requests"
        case .stories: "Activity on your stories"
        case .molibooCare: "When your Moliboo needs you"
        case .gubicInvites: "Game invites from friends"
        }
    }

    var symbol: String {
        switch self {
        case .likes: "heart"
        case .comments: "bubble.left"
        case .replies: "arrowshape.turn.up.left"
        case .mentions: "at"
        case .follows: "person.badge.plus"
        case .messages: "paperplane"
        case .stories: "circle.dashed"
        case .molibooCare: "leaf"
        case .gubicInvites: "gamecontroller"
        }
    }
}

// MARK: - Categories & actions

/// Identifiers must match `apnsCategoryFor` in `services/greenfield-worker/src/push/dispatch.ts`.
enum PushNotificationCategories {
    static let comment = "MODULA_COMMENT"
    static let message = "MODULA_MESSAGE"
    static let followRequest = "MODULA_FOLLOW_REQUEST"
    static let gubicInvite = "MODULA_GUBIC_INVITE"

    static let replyAction = "MODULA_REPLY"
    static let likeAction = "MODULA_LIKE"
    static let acceptAction = "MODULA_ACCEPT"
    static let markReadAction = "MODULA_MARK_READ"

    static func all() -> Set<UNNotificationCategory> {
        let reply = UNTextInputNotificationAction(
            identifier: replyAction,
            title: "Reply",
            options: [.authenticationRequired],
            icon: UNNotificationActionIcon(systemImageName: "arrowshape.turn.up.left"),
            textInputButtonTitle: "Send",
            textInputPlaceholder: "Reply…"
        )
        let like = UNNotificationAction(
            identifier: likeAction,
            title: "Like",
            options: [.authenticationRequired],
            icon: UNNotificationActionIcon(systemImageName: "heart")
        )
        let markRead = UNNotificationAction(
            identifier: markReadAction,
            title: "Mark as read",
            options: [.authenticationRequired],
            icon: UNNotificationActionIcon(systemImageName: "checkmark.bubble")
        )
        let accept = UNNotificationAction(
            identifier: acceptAction,
            title: "Accept",
            options: [.authenticationRequired],
            icon: UNNotificationActionIcon(systemImageName: "checkmark")
        )
        let acceptInvite = UNNotificationAction(
            identifier: acceptAction,
            title: "Accept",
            options: [.authenticationRequired, .foreground],
            icon: UNNotificationActionIcon(systemImageName: "gamecontroller")
        )
        return [
            UNNotificationCategory(identifier: comment, actions: [reply, like], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: message, actions: [reply, markRead], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: followRequest, actions: [accept], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: gubicInvite, actions: [acceptInvite], intentIdentifiers: [], options: []),
        ]
    }
}

/// Sendable copy of the `modula` dictionary in an APNs payload.
struct PushPayload: Equatable, Sendable {
    var deliveryId: String?
    var category: String?
    var deepLink: String?
    var resourceType: String?
    var resourceId: String?
    var conversationId: String?
    var messageId: String?
    var messageType: String?
    var followRequestId: String?
    var notificationId: String?

    init(userInfo: [AnyHashable: Any]) {
        let modula = userInfo["modula"] as? [String: Any] ?? [:]
        deliveryId = modula["deliveryId"] as? String
        category = modula["category"] as? String
        deepLink = modula["deepLink"] as? String
        resourceType = modula["resourceType"] as? String
        resourceId = modula["resourceId"] as? String
        conversationId = modula["conversationId"] as? String
        messageId = modula["messageId"] as? String
        messageType = modula["messageType"] as? String
        followRequestId = modula["followRequestId"] as? String
        notificationId = modula["notificationId"] as? String
    }

    /// Canonical in-app route; only `modula://` links the RouteParser accepts are followed.
    var route: AppRoute? {
        guard let deepLink, deepLink.lowercased().hasPrefix("modula://") else { return nil }
        return RouteParser.parse(deepLink)
    }
}

enum PushNotificationAction: Equatable, Sendable {
    case open
    case reply(String)
    case like
    case markRead
    case accept
    case dismiss

    init(identifier: String, text: String?) {
        switch identifier {
        case PushNotificationCategories.replyAction: self = .reply(text ?? "")
        case PushNotificationCategories.likeAction: self = .like
        case PushNotificationCategories.markReadAction: self = .markRead
        case PushNotificationCategories.acceptAction: self = .accept
        case UNNotificationDismissActionIdentifier: self = .dismiss
        default: self = .open
        }
    }

    /// The Greenfield request an action maps to, or nil when it should just open the app.
    func request(for payload: PushPayload) -> (method: String, path: String, body: JSONValue?)? {
        func escape(_ value: String) -> String { value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? value }
        switch self {
        case .reply(let raw):
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            if let conversation = payload.conversationId {
                var body: [String: JSONValue] = ["text": .string(text)]
                // clientMessageId only when a v3 probe has confirmed idempotent send
                // (push can fire before this session has probed).
                if MessagingV3FlagStore.idempotentSend {
                    body["clientMessageId"] = .string(UUID().uuidString)
                }
                return ("POST", "/v1/conversations/\(escape(conversation))/messages", .object(body))
            }
            if payload.resourceType == "post", let post = payload.resourceId {
                return ("POST", "/v1/posts/\(escape(post))/comments", .object(["text": .string(text)]))
            }
            return nil
        case .like:
            guard payload.resourceType == "post", let post = payload.resourceId else { return nil }
            return ("POST", "/v1/posts/\(escape(post))/like", .object([:]))
        case .markRead:
            guard let conversation = payload.conversationId else { return nil }
            return ("POST", "/v1/conversations/\(escape(conversation))/read", nil)
        case .accept:
            guard payload.category == "follows", let id = payload.followRequestId else { return nil }
            return ("POST", "/v1/follow-requests/\(escape(id))/accept", .object([:]))
        case .open, .dismiss:
            return nil
        }
    }
}

// MARK: - Soft pre-prompt timing

enum PushPrePromptMoment: String, Sendable {
    /// Opened Activity: value is visible right there.
    case activityViewed
    /// Sent a message: replies are worth hearing about.
    case messageSent
    /// Explicit tap in Settings.
    case settings
}

/// Never on launch. Offer after a moment that shows the value, at most three
/// times, with a growing cool-down after each "Not now".
struct PushPrePromptPolicy: Equatable, Sendable {
    var launches: Int
    var dismissals: Int
    var lastDismissedAt: Date?

    static let maxDismissals = 3
    static let coolDown: TimeInterval = 7 * 24 * 60 * 60

    func shouldOffer(
        moment: PushPrePromptMoment,
        status: UNAuthorizationStatus,
        signedIn: Bool,
        flagEnabled: Bool,
        now: Date = Date()
    ) -> Bool {
        guard flagEnabled, signedIn, status == .notDetermined else { return false }
        if moment == .settings { return true }
        guard dismissals < Self.maxDismissals else { return false }
        if let lastDismissedAt, now.timeIntervalSince(lastDismissedAt) < Self.coolDown * Double(max(1, dismissals)) {
            return false
        }
        switch moment {
        case .messageSent: return true
        case .activityViewed: return launches >= 2
        case .settings: return true
        }
    }
}

extension Notification.Name {
    /// Posted by feature code at value moments (`object` is a `PushPrePromptMoment.rawValue`).
    static let modulaPushMoment = Notification.Name("modula.push.moment")
}

// MARK: - Controller

@MainActor @Observable
final class PushNotificationController {
    enum RegistrationState: Equatable { case idle, registering, registered, failed(String), unavailable }

    private(set) var authorization: UNAuthorizationStatus = .notDetermined
    private(set) var registration: RegistrationState = .idle
    var prePromptPresented = false
    var flagEnabled: Bool { PushFeatureFlags.enabled() }

    private let client: GreenfieldClient
    private let defaults: UserDefaults
    private weak var environment: AppEnvironment?
    private var momentObserver: NSObjectProtocol?

    private static let launchesKey = "push.prePrompt.launches"
    private static let dismissalsKey = "push.prePrompt.dismissals"
    private static let lastDismissedKey = "push.prePrompt.lastDismissedAt"
    private static let tokenKey = "push.registeredToken"

    static weak var current: PushNotificationController?

    init(client: GreenfieldClient, defaults: UserDefaults = .standard) {
        self.client = client
        self.defaults = defaults
        Self.current = self
    }

    /// A notification tapped before `attach` (cold launch) is held until the environment exists.
    private var pendingPayload: PushPayload?

    var policy: PushPrePromptPolicy {
        PushPrePromptPolicy(
            launches: defaults.integer(forKey: Self.launchesKey),
            dismissals: defaults.integer(forKey: Self.dismissalsKey),
            lastDismissedAt: defaults.object(forKey: Self.lastDismissedKey) as? Date
        )
    }

    /// Called once per cold launch from `bootstrapLaunch`. Never prompts; only
    /// refreshes the APNs token when the user already allowed notifications.
    func attach(environment: AppEnvironment) async {
        self.environment = environment
        let center = UNUserNotificationCenter.current()
        center.delegate = PushNotificationDelegate.shared
        center.setNotificationCategories(PushNotificationCategories.all())
        if let pendingPayload {
            self.pendingPayload = nil
            open(pendingPayload)
        }
        defaults.set(defaults.integer(forKey: Self.launchesKey) + 1, forKey: Self.launchesKey)
        if momentObserver == nil {
            momentObserver = NotificationCenter.default.addObserver(forName: .modulaPushMoment, object: nil, queue: .main) { note in
                let raw = note.object as? String
                MainActor.assumeIsolated {
                    guard let moment = raw.flatMap(PushPrePromptMoment.init(rawValue:)) else { return }
                    PushNotificationController.current?.noteMoment(moment)
                }
            }
        }
        await refreshAuthorization()
        if flagEnabled, environment.auth.isSignedIn, authorization.allowsRemote {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    func refreshAuthorization() async {
        authorization = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        if !flagEnabled { registration = .unavailable }
    }

    /// Sign-in after launch: refresh the token when permission already exists.
    func accountChanged(signedIn: Bool) async {
        guard signedIn, flagEnabled else { return }
        await refreshAuthorization()
        if authorization.allowsRemote { UIApplication.shared.registerForRemoteNotifications() }
    }

    func noteMoment(_ moment: PushPrePromptMoment) {
        guard !prePromptPresented, let environment else { return }
        Task {
            await refreshAuthorization()
            if policy.shouldOffer(moment: moment, status: authorization, signedIn: environment.auth.isSignedIn, flagEnabled: flagEnabled) {
                prePromptPresented = true
            }
        }
    }

    /// Whether onboarding may show its notification primer. Same back-off as the soft
    /// pre-prompt (at most three "Another time", growing cool-down) and still never on
    /// launch: the user reaches it by tapping through onboarding. Allowed before sign-in;
    /// the token registers on the next sign-in via `accountChanged`.
    var offersOnboardingPrimer: Bool {
        guard flagEnabled, authorization == .notDetermined else { return false }
        let p = policy
        guard p.dismissals < PushPrePromptPolicy.maxDismissals else { return false }
        if let last = p.lastDismissedAt,
           Date().timeIntervalSince(last) < PushPrePromptPolicy.coolDown * Double(max(1, p.dismissals)) {
            return false
        }
        return true
    }

    /// "Turn On" in the soft pre-prompt: only now does iOS show its one-time alert.
    func requestPermission() async {
        prePromptPresented = false
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])) ?? false
        await refreshAuthorization()
        if granted, flagEnabled { UIApplication.shared.registerForRemoteNotifications() }
    }

    func dismissPrePrompt() {
        prePromptPresented = false
        defaults.set(defaults.integer(forKey: Self.dismissalsKey) + 1, forKey: Self.dismissalsKey)
        defaults.set(Date(), forKey: Self.lastDismissedKey)
    }

    // MARK: Token lifecycle

    func didRegister(deviceToken: Data) async {
        guard flagEnabled, environment?.auth.isSignedIn == true else { return }
        let token = PushAPI.hexToken(deviceToken)
        registration = .registering
        let body: JSONValue = .object([
            "token": .string(token),
            "platform": .string("ios"),
            "environment": .string(PushAPI.environment),
            "bundleId": .string(Bundle.main.bundleIdentifier ?? "digital.modula.app.native"),
            "appVersion": .string(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"),
            "locale": .string(Locale.current.identifier),
            "timezone": .string(TimeZone.current.identifier),
        ])
        do {
            _ = try await client.authenticatedJSON("POST", path: PushAPI.devices, body: body)
            defaults.set(token, forKey: Self.tokenKey)
            registration = .registered
        } catch {
            registration = .failed(Self.message(error))
        }
    }

    func didFailToRegister(_ message: String) {
        registration = .failed(message)
    }

    /// Called before sign-out while the session can still authenticate the DELETE.
    func unregisterForSignOut() async {
        guard let token = defaults.string(forKey: Self.tokenKey) else { return }
        _ = try? await client.authenticatedJSON("DELETE", path: PushAPI.device(token), body: nil)
        defaults.removeObject(forKey: Self.tokenKey)
        registration = .idle
        try? await UNUserNotificationCenter.current().setBadgeCount(0)
    }

    // MARK: Badge

    func syncBadge(unread: Int?) {
        guard let unread, authorization.allowsRemote else { return }
        Task { try? await UNUserNotificationCenter.current().setBadgeCount(max(0, unread)) }
    }

    // MARK: Responses

    func handle(action: PushNotificationAction, payload: PushPayload) async {
        if let request = action.request(for: payload) {
            do {
                _ = try await client.authenticatedJSON(request.method, path: request.path, body: request.body)
            } catch {
                // A failed quick action falls back to opening the right screen.
                open(payload)
            }
            return
        }
        switch action {
        case .dismiss: return
        default: open(payload)
        }
    }

    private func open(_ payload: PushPayload) {
        guard let environment else { pendingPayload = payload; return }
        environment.openRouted(payload.route ?? .activity(.all))
    }

    private static func message(_ error: Error) -> String {
        if case APIError.rejected(404, _) = error as? APIError ?? .invalidResponse {
            return "Push isn’t available on this server yet."
        }
        return (error as? APIError)?.userFacingMessage ?? "Couldn’t register this device."
    }
}

extension UNAuthorizationStatus {
    var allowsRemote: Bool { self == .authorized || self == .provisional || self == .ephemeral }
}

// MARK: - Delegate

/// Foreground banners and response routing. Extracts Sendable values before
/// hopping to the main actor.
/// Kept private so it stays out of the generated Objective-C header (the React
/// Native bridge compiles that header without UserNotifications).
enum PushNotificationDelegate {
    static var shared: any UNUserNotificationCenterDelegate { pushNotificationDelegate }
}

private let pushNotificationDelegate = PushNotificationCenterDelegate()

private final class PushNotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate, Sendable {

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound, .badge]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let payload = PushPayload(userInfo: response.notification.request.content.userInfo)
        let text = (response as? UNTextInputNotificationResponse)?.userText
        let action = PushNotificationAction(identifier: response.actionIdentifier, text: text)
        let controller = await PushNotificationController.current
        await controller?.handle(action: action, payload: payload)
    }
}
