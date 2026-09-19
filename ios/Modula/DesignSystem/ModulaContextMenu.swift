import SwiftUI

/// Shared interaction vocabulary for Profile, Posts, Modules, and Activity.
enum ModulaContextActionRole: String, Sendable {
    case normal
    case destructive
    case disabled
    case loading
}

struct ModulaContextAction: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    var systemImage: String?
    var role: ModulaContextActionRole
    var accessibilityLabel: String?

    init(
        id: String,
        title: String,
        systemImage: String? = nil,
        role: ModulaContextActionRole = .normal,
        accessibilityLabel: String? = nil
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.role = role
        self.accessibilityLabel = accessibilityLabel
    }

    var resolvedAccessibilityLabel: String {
        accessibilityLabel ?? title
    }

    var isInteractive: Bool {
        role != .disabled && role != .loading
    }
}

struct ModulaContextMenu<MenuLabel: View>: View {
    let actions: [ModulaContextAction]
    var onSelect: (ModulaContextAction) -> Void
    @ViewBuilder var label: () -> MenuLabel

    var body: some View {
        Menu {
            ForEach(actions) { action in
                menuButton(for: action)
            }
        } label: {
            label()
        }
        .accessibilityHint("Shows available actions")
    }

    @ViewBuilder
    private func menuButton(for action: ModulaContextAction) -> some View {
        if action.role == .destructive {
            Button(role: .destructive) {
                select(action)
            } label: {
                actionTitle(action)
            }
            .disabled(!action.isInteractive)
            .accessibilityLabel(action.resolvedAccessibilityLabel)
        } else {
            Button {
                select(action)
            } label: {
                actionTitle(action)
            }
            .disabled(!action.isInteractive)
            .accessibilityLabel(action.resolvedAccessibilityLabel)
        }
    }

    @ViewBuilder
    private func actionTitle(_ action: ModulaContextAction) -> some View {
        if let systemImage = action.systemImage {
            SwiftUI.Label(action.title, systemImage: systemImage)
        } else {
            Text(action.title)
        }
    }

    private func select(_ action: ModulaContextAction) {
        guard action.isInteractive else { return }
        HapticEngine.shared.play(.contextOpen)
        onSelect(action)
    }
}
