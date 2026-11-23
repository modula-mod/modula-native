import Observation
import SwiftUI
import UIKit

enum ModulaSelectionIndicatorState: String, Sendable {
    case unselected
    case selected
    case partial
}

@MainActor @Observable
final class ModulaSelectionState<ID: Hashable> {
    private(set) var selectedIDs: Set<ID>
    private(set) var isActive: Bool

    init(selectedIDs: Set<ID> = [], isActive: Bool = false) {
        self.selectedIDs = selectedIDs
        self.isActive = isActive || !selectedIDs.isEmpty
    }

    func enter(selecting id: ID? = nil) {
        isActive = true
        if let id { selectedIDs.insert(id) }
        announce()
    }

    func toggle(_ id: ID) {
        isActive = true
        if selectedIDs.contains(id) { selectedIDs.remove(id) } else { selectedIDs.insert(id) }
        announce()
    }

    func select(_ id: ID) {
        isActive = true
        selectedIDs.insert(id)
        announce()
    }

    func deselect(_ id: ID) {
        selectedIDs.remove(id)
        announce()
    }

    func selectAll<S: Sequence>(_ ids: S) where S.Element == ID {
        isActive = true
        selectedIDs.formUnion(ids)
        announce()
    }

    func deselectAll() { selectedIDs.removeAll(); announce() }

    func clear() {
        selectedIDs.removeAll()
        isActive = false
        announce(message: "Selection cleared")
    }

    func isSelected(_ id: ID) -> Bool { selectedIDs.contains(id) }

    private func announce(message: String? = nil) {
        let resolved = message ?? "\(selectedIDs.count) selected"
        UIAccessibility.post(notification: .announcement, argument: resolved)
    }
}

struct ModulaSelectionIndicator: View {
    let state: ModulaSelectionIndicatorState

    @Environment(AppEnvironment.self) private var app

    var body: some View {
        Image(systemName: symbol)
            .font(.title3.weight(.semibold))
            .foregroundStyle(state == .unselected ? Color.secondary : app.appearance.liveAccent)
            .frame(width: ModulaLayout.minimumTouch, height: ModulaLayout.minimumTouch)
            .contentShape(Circle())
            .accessibilityLabel(accessibilityLabel)
    }

    private var symbol: String {
        switch state {
        case .unselected: "circle"
        case .selected: "checkmark.circle.fill"
        case .partial: "minus.circle.fill"
        }
    }

    private var accessibilityLabel: String {
        switch state {
        case .unselected: "Not selected"
        case .selected: "Selected"
        case .partial: "Partially selected"
        }
    }
}

struct ModulaSelectableRow<ID: Hashable, Content: View>: View {
    let id: ID
    @Bindable var selection: ModulaSelectionState<ID>
    var partial = false
    var onOpen: (() -> Void)?
    @ViewBuilder var content: () -> Content

    var body: some View {
        Button {
            if selection.isActive { selection.toggle(id) } else { onOpen?() }
        } label: {
            HStack(spacing: ModulaSpacing.sm) {
                if selection.isActive {
                    ModulaSelectionIndicator(state: indicatorState)
                        .transition(.opacity.combined(with: .scale))
                }
                content()
                Spacer(minLength: 0)
            }
            .frame(minHeight: ModulaLayout.minimumTouch)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.42).onEnded { _ in
                guard !selection.isActive else { return }
                selection.enter(selecting: id)
                HapticEngine.shared.play(.contextOpened)
            }
        )
        .accessibilityAddTraits(selection.isSelected(id) ? .isSelected : [])
        .accessibilityAction(named: Text(selection.isSelected(id) ? "Deselect" : "Select")) {
            selection.toggle(id)
        }
    }

    private var indicatorState: ModulaSelectionIndicatorState {
        if partial { return .partial }
        return selection.isSelected(id) ? .selected : .unselected
    }
}

enum ModulaSelectionActionRole: String, Sendable {
    case normal
    case destructive
}

struct ModulaSelectionAction: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let systemImage: String
    var role: ModulaSelectionActionRole = .normal
    var isEnabled = true
}

struct ModulaSelectionToolbar: View {
    let count: Int
    let actions: [ModulaSelectionAction]
    var onAction: (ModulaSelectionAction) -> Void
    var onClose: () -> Void

    var body: some View {
        HStack(spacing: ModulaSpacing.xs) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .frame(width: ModulaLayout.minimumTouch, height: ModulaLayout.minimumTouch)
            }
            .accessibilityLabel("Exit selection")
            Text("\(count) selected")
                .font(.headline)
                .monospacedDigit()
            Spacer()
            ForEach(actions) { action in
                Button(role: action.role == .destructive ? .destructive : nil) {
                    onAction(action)
                    HapticEngine.shared.play(action.role == .destructive ? .warning : .actionConfirmed)
                } label: {
                    Image(systemName: action.systemImage)
                        .frame(width: ModulaLayout.minimumTouch, height: ModulaLayout.minimumTouch)
                }
                .disabled(!action.isEnabled)
                .accessibilityLabel(action.title)
            }
        }
        .padding(.horizontal, ModulaSpacing.sm)
        .modulaMaterial(.floating, in: Capsule(), depth: .floating)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("modula.selection.toolbar")
    }
}
