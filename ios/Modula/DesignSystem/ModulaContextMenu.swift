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
    var children: [ModulaContextAction]

    init(
        id: String,
        title: String,
        systemImage: String? = nil,
        role: ModulaContextActionRole = .normal,
        accessibilityLabel: String? = nil,
        children: [ModulaContextAction] = []
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.role = role
        self.accessibilityLabel = accessibilityLabel
        self.children = children
    }

    var resolvedAccessibilityLabel: String {
        accessibilityLabel ?? title
    }

    var isInteractive: Bool {
        role != .disabled && role != .loading
    }
}

struct ModulaContextActionGroup: Identifiable, Hashable, Sendable {
    let id: String
    var title: String?
    var actions: [ModulaContextAction]

    init(id: String, title: String? = nil, actions: [ModulaContextAction]) {
        self.id = id
        self.title = title
        self.actions = actions
    }
}

/// A semantic alias used when an action owns a nested action list.
typealias ModulaContextSubmenu = ModulaContextAction

enum ModulaContextDismissBehavior: String, CaseIterable, Sendable {
    case tapOutside
    case interactive
    case explicit
}

enum ModulaContextPlacement: String, CaseIterable, Sendable {
    case automatic
    case top
    case center
    case bottom

    var alignment: Alignment {
        switch self {
        case .automatic, .center: .center
        case .top: .top
        case .bottom: .bottom
        }
    }
}

struct ModulaContextMenu<MenuLabel: View>: View {
    let actions: [ModulaContextAction]
    var groups: [ModulaContextActionGroup] = []
    var onSelect: (ModulaContextAction) -> Void
    @ViewBuilder var label: () -> MenuLabel

    var body: some View {
        Menu {
            if groups.isEmpty {
                ForEach(actions) { action in menuEntry(for: action) }
            } else {
                ForEach(groups) { group in
                    Section(group.title ?? "") {
                        ForEach(group.actions) { action in menuEntry(for: action) }
                    }
                }
            }
        } label: {
            label()
        }
        .accessibilityHint("Shows available actions")
    }

    @ViewBuilder
    private func menuEntry(for action: ModulaContextAction) -> some View {
        if action.children.isEmpty {
            menuButton(for: action)
        } else {
            Menu {
                ForEach(action.children) { child in menuButton(for: child) }
            } label: {
                actionTitle(action)
            }
            .disabled(!action.isInteractive)
            .accessibilityLabel(action.resolvedAccessibilityLabel)
        }
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

struct ModulaContextSource<Content: View>: View {
    var active: Bool
    @ViewBuilder var content: () -> Content

    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        content()
            .scaleEffect(active && !reduceMotion ? 0.975 : 1)
            .shadow(color: .black.opacity(active ? 0.16 : 0), radius: active ? 16 : 0, y: active ? 8 : 0)
            .animation(ModulaMotion.animation(.instantFeedback, personality: app.appearance.motion, reduceMotion: reduceMotion), value: active)
    }
}

struct ModulaContextPreview<Content: View>: View {
    var title: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: ModulaSpacing.sm) {
            if let title { Text(title).font(.headline) }
            content()
        }
        .padding(ModulaSpacing.md)
        .modulaMaterial(.floating, in: RoundedRectangle(cornerRadius: ModulaRadius.medium, style: .continuous), depth: .overlay)
        .accessibilityElement(children: .contain)
    }
}

struct ModulaContextHost<Source: View, Preview: View>: View {
    let actions: [ModulaContextAction]
    var groups: [ModulaContextActionGroup] = []
    var placement: ModulaContextPlacement = .automatic
    var dismissBehavior: ModulaContextDismissBehavior = .interactive
    var onSelect: (ModulaContextAction) -> Void
    @ViewBuilder var source: () -> Source
    @ViewBuilder var preview: () -> Preview

    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPresented = false
    @State private var dismissalOffset: CGFloat = 0
    @AccessibilityFocusState private var menuFocused: Bool

    var body: some View {
        ZStack(alignment: placement.alignment) {
            ModulaContextSource(active: isPresented, content: source)
                .onLongPressGesture(minimumDuration: 0.42) { present() }
                .accessibilityAction(named: Text("Show actions"), present)

            if isPresented {
                Color.black.opacity(0.24)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard dismissBehavior != .explicit else { return }
                        dismiss()
                    }
                    .transition(.opacity)

                VStack(spacing: ModulaSpacing.sm) {
                    ModulaContextPreview(content: preview)
                    contextActions
                }
                .padding(ModulaSpacing.md)
                .offset(y: dismissalOffset)
                .transition(reduceMotion ? .opacity : .scale(scale: 0.96).combined(with: .opacity))
                .gesture(dismissGesture)
                .accessibilityFocused($menuFocused)
            }
        }
        .animation(ModulaMotion.animation(.overlay, personality: app.appearance.motion, reduceMotion: reduceMotion), value: isPresented)
    }

    private var flattenedActions: [ModulaContextAction] {
        groups.isEmpty ? actions : groups.flatMap(\.actions)
    }

    private var contextActions: some View {
        VStack(spacing: 1) {
            ForEach(Array(flattenedActions.enumerated()), id: \.element.id) { index, action in
                if !action.children.isEmpty {
                    Menu {
                        ForEach(action.children) { child in contextButton(child) }
                    } label: {
                        contextLabel(action, showsChevron: true)
                    }
                    .disabled(!action.isInteractive)
                } else {
                    contextButton(action)
                }
                if index < flattenedActions.count - 1 { Divider().padding(.leading, 46) }
            }
        }
        .padding(.vertical, ModulaSpacing.xxs)
        .modulaMaterial(.floating, in: RoundedRectangle(cornerRadius: ModulaRadius.medium, style: .continuous), depth: .overlay)
        .accessibilityLabel("Context actions")
    }

    private func contextButton(_ action: ModulaContextAction) -> some View {
        Button(role: action.role == .destructive ? .destructive : nil) {
            select(action)
        } label: {
            contextLabel(action, showsChevron: false)
        }
        .buttonStyle(.plain)
        .disabled(!action.isInteractive)
        .accessibilityLabel(action.resolvedAccessibilityLabel)
    }

    private func contextLabel(_ action: ModulaContextAction, showsChevron: Bool) -> some View {
        HStack(spacing: ModulaSpacing.sm) {
            if let image = action.systemImage { Image(systemName: image).frame(width: 24) }
            Text(action.title).frame(maxWidth: .infinity, alignment: .leading)
            if action.role == .loading { ProgressView().controlSize(.small) }
            if showsChevron { Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary) }
        }
        .foregroundStyle(action.role == .destructive ? Color.red : Color.primary)
        .padding(.horizontal, ModulaSpacing.sm)
        .frame(minHeight: ModulaLayout.minimumTouch)
        .contentShape(Rectangle())
    }

    private var dismissGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                guard dismissBehavior == .interactive else { return }
                dismissalOffset = max(0, value.translation.height)
            }
            .onEnded { value in
                guard dismissBehavior == .interactive else { return }
                if value.translation.height > 80 { dismiss() }
                else { dismissalOffset = 0 }
            }
    }

    private func present() {
        isPresented = true
        HapticEngine.shared.play(.contextOpened)
        Task { @MainActor in menuFocused = true }
    }

    private func select(_ action: ModulaContextAction) {
        guard action.isInteractive else { return }
        onSelect(action)
        HapticEngine.shared.play(action.role == .destructive ? .warning : .actionConfirmed)
        dismiss()
    }

    private func dismiss() {
        isPresented = false
        dismissalOffset = 0
        menuFocused = false
    }
}

private struct ModulaNativeContextMenuModifier: ViewModifier {
    let actions: [ModulaContextAction]
    let onSelect: (ModulaContextAction) -> Void

    func body(content: Content) -> some View {
        content
            .contextMenu {
                ForEach(actions) { action in
                    if action.children.isEmpty {
                        button(action)
                    } else {
                        Menu {
                            ForEach(action.children) { child in button(child) }
                        } label: {
                            Label(action.title, systemImage: action.systemImage ?? "ellipsis")
                        }
                    }
                }
            }
            .accessibilityActions {
                ForEach(actions.filter(\.children.isEmpty)) { action in
                    Button(action.resolvedAccessibilityLabel) { select(action) }
                        .disabled(!action.isInteractive)
                }
            }
    }

    private func button(_ action: ModulaContextAction) -> some View {
        Button(role: action.role == .destructive ? .destructive : nil) {
            select(action)
        } label: {
            Label(action.title, systemImage: action.systemImage ?? "ellipsis")
        }
        .disabled(!action.isInteractive)
    }

    private func select(_ action: ModulaContextAction) {
        guard action.isInteractive else { return }
        onSelect(action)
        HapticEngine.shared.play(action.role == .destructive ? .warning : .actionConfirmed)
    }
}

extension View {
    func modulaContextMenu(
        actions: [ModulaContextAction],
        onSelect: @escaping (ModulaContextAction) -> Void
    ) -> some View {
        modifier(ModulaNativeContextMenuModifier(actions: actions, onSelect: onSelect))
    }
}
