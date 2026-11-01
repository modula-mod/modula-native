import SwiftUI

enum ModulaIndicatorTone: String, CaseIterable, Sendable {
    case accent
    case neutral
    case muted
    case success
    case warning
    case error

    @MainActor
    func color(accent: Color) -> Color {
        switch self {
        case .accent: accent
        case .neutral: .primary
        case .muted: .secondary
        case .success: .green
        case .warning: .orange
        case .error: .red
        }
    }
}

enum ModulaBadgeStyle: String, CaseIterable, Sendable {
    case filled
    case tinted
    case outlined
}

enum ModulaCountBadge {
    static func label(for count: Int, maximum: Int = 99) -> String? {
        guard count > 0 else { return nil }
        return count > maximum ? "\(maximum)+" : String(count)
    }
}

struct ModulaNotificationDot: View {
    var tone: ModulaIndicatorTone = .accent
    var size: CGFloat = 9
    var accessibilityLabel: String = "New activity"

    @Environment(AppEnvironment.self) private var app

    var body: some View {
        Circle()
            .fill(tone.color(accent: app.appearance.liveAccent))
            .frame(width: size, height: size)
            .accessibilityLabel(accessibilityLabel)
    }
}

struct ModulaUnreadIndicator: View {
    let count: Int
    var tone: ModulaIndicatorTone = .neutral
    var maximum = 99

    @Environment(AppEnvironment.self) private var app

    var body: some View {
        if let value = ModulaCountBadge.label(for: count, maximum: maximum) {
            Text(value)
                .font(.caption2.weight(.bold))
                .monospacedDigit()
                .padding(.horizontal, 6)
                .frame(minWidth: 20, minHeight: 20)
                .background(tone.color(accent: app.appearance.liveAccent), in: Capsule())
                .foregroundStyle(contrastColor)
                .accessibilityLabel("\(count) unread")
        }
    }

    private var contrastColor: Color {
        switch tone {
        case .neutral: Color(uiColor: .systemBackground)
        default: .white
        }
    }
}

enum ModulaPresence: String, CaseIterable, Sendable {
    case online
    case away
    case busy
    case offline

    var label: String { rawValue.capitalized }
    var color: Color {
        switch self {
        case .online: .green
        case .away: .orange
        case .busy: .red
        case .offline: .secondary
        }
    }
}

struct ModulaPresenceIndicator: View {
    let presence: ModulaPresence
    var size: CGFloat = 11

    var body: some View {
        Circle()
            .fill(presence.color)
            .frame(width: size, height: size)
            .overlay(Circle().stroke(Color(uiColor: .systemBackground), lineWidth: 2))
            .accessibilityLabel(presence.label)
    }
}
