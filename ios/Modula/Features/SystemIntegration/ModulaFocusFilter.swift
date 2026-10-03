import AppIntents
import Foundation

/// iOS Focus filter (Settings → Focus → <a Focus> → Focus Filters → Modula).
/// When a Focus with this filter turns on, iOS runs `perform()` with `quiet == true`;
/// when it turns off, iOS runs it again with the parameter cleared. Modula then
/// applies Settings → Focus (hide tab badges, dim Activity, still allow @mentions).
/// No entitlement and no Focus-status permission are needed — only the user's choice
/// to add the filter.
struct ModulaFocusFilter: SetFocusFilterIntent {
    static let title: LocalizedStringResource = "Quieter Modula"
    static let description: IntentDescription? = IntentDescription(
        "Hide Modula’s tab badges and dim Activity while this Focus is on. Choose what changes in Modula → Settings → Focus."
    )

    @Parameter(title: "Quiet Modula", default: true)
    var quiet: Bool?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: quiet == true ? "Quieter Modula" : "Modula unchanged",
            subtitle: quiet == true ? "Badges and Activity follow Settings → Focus" : nil
        )
    }

    func perform() async throws -> some IntentResult {
        ModulaFocusState.setActive(quiet == true)
        return .result()
    }
}

enum ModulaFocusState {
    static let didChange = Notification.Name("digital.modula.focus-filter-changed")

    static func setActive(_ active: Bool) {
        UserDefaults.standard.set(active, forKey: ModulaPreferences.Key.focusFilterActive)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: ModulaPreferences.Key.focusFilterActive + ".changedAt")
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    /// Badge for the Activity tab, honouring Settings → Focus while a Focus filter is on.
    static func activityBadge(unread: Int, unreadMentions: Int, now: Date = Date()) -> Int {
        // Settings → Notifications → Quiet Hours hides the badge inside the window.
        if QuietHoursWindow.stored().contains(now) { return 0 }
        guard ModulaPreferences.focusFilterActive else { return unread }
        if ModulaPreferences.hidesBadgesNow {
            return ModulaPreferences.focusAllowsMentions ? unreadMentions : 0
        }
        return unread
    }
}
