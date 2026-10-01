import SwiftUI

enum ModulaSheetDetent: String, CaseIterable, Identifiable, Sendable {
    case content
    case compact
    case medium
    case large
    case full

    var id: String { rawValue }

    var presentationDetent: PresentationDetent {
        switch self {
        case .content: .height(220)
        case .compact: .fraction(0.3)
        case .medium: .medium
        case .large: .large
        case .full: .fraction(0.98)
        }
    }
}

struct ModulaSheetState: Equatable, Sendable {
    var selectedDetent: ModulaSheetDetent
    var isDismissible: Bool
    private(set) var restoredDetent: ModulaSheetDetent?

    init(selectedDetent: ModulaSheetDetent = .large, isDismissible: Bool = true) {
        self.selectedDetent = selectedDetent
        self.isDismissible = isDismissible
    }

    mutating func select(_ detent: ModulaSheetDetent, from available: Set<ModulaSheetDetent>) -> Bool {
        guard available.contains(detent), detent != selectedDetent else { return false }
        selectedDetent = detent
        return true
    }

    mutating func remember() { restoredDetent = selectedDetent }
    mutating func restore() { if let restoredDetent { selectedDetent = restoredDetent } }
}

enum ModulaSheetBackground: Sendable {
    case automatic
    case material
    case opaque
}

enum ModulaSheetTransition: Sendable {
    case system
    case morph
    case reducedMotion
}

struct ModulaMorphSource: Hashable, Sendable {
    let id: String
    init(_ id: String) { self.id = id }
}

struct ModulaSheetHandle: View {
    var body: some View {
        Capsule()
            .fill(.secondary.opacity(0.45))
            .frame(width: 36, height: 5)
            .padding(.vertical, ModulaSpacing.xs)
            .accessibilityHidden(true)
    }
}

struct ModulaSheetHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: ModulaSpacing.sm) {
            VStack(alignment: .leading, spacing: ModulaSpacing.xxs) {
                Text(title).font(.headline)
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            trailing()
        }
        .padding(.horizontal, ModulaLayout.contentInset)
        .padding(.bottom, ModulaSpacing.sm)
    }
}

extension ModulaSheetHeader where Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = { EmptyView() }
    }
}

/// Standardizes sheet detents, background policy, interaction, and semantic feedback.
struct ModulaSheet<Content: View>: View {
    var detents: [ModulaSheetDetent] = [.large]
    @Binding var selectedDetent: ModulaSheetDetent
    var dismissible = true
    var dragEnabled = true
    var background: ModulaSheetBackground = .automatic
    var backgroundInteractionEnabled = false
    var transition: ModulaSheetTransition = .system
    var morphSource: ModulaMorphSource?
    @ViewBuilder var content: () -> Content

    @Environment(AppEnvironment.self) private var app
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        detents: [ModulaSheetDetent] = [.large],
        selectedDetent: Binding<ModulaSheetDetent>? = nil,
        dismissible: Bool = true,
        dragEnabled: Bool = true,
        background: ModulaSheetBackground = .automatic,
        backgroundInteractionEnabled: Bool = false,
        transition: ModulaSheetTransition = .system,
        morphSource: ModulaMorphSource? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        let fallback = detents.first ?? .large
        self.detents = detents.isEmpty ? [.large] : detents
        self._selectedDetent = selectedDetent ?? .constant(fallback)
        self.dismissible = dismissible
        self.dragEnabled = dragEnabled
        self.background = background
        self.backgroundInteractionEnabled = backgroundInteractionEnabled
        self.transition = transition
        self.morphSource = morphSource
        self.content = content
    }

    var body: some View {
        content()
            .presentationDetents(Set(detents.map(\.presentationDetent)), selection: presentationSelection)
            .presentationDragIndicator(dragEnabled ? .visible : .hidden)
            .interactiveDismissDisabled(!dismissible)
            .presentationBackground(backgroundStyle)
            .presentationBackgroundInteraction(backgroundInteractionEnabled ? .enabled : .disabled)
            .transaction { transaction in
                if reduceMotion || transition == .reducedMotion { transaction.animation = nil }
            }
            .onChange(of: selectedDetent) { _, _ in
                HapticEngine.shared.play(.sheetDetentReached)
            }
            .accessibilityIdentifier("modula.sheet")
    }

    private var presentationSelection: Binding<PresentationDetent> {
        Binding(
            get: { selectedDetent.presentationDetent },
            set: { next in
                if let match = detents.first(where: { $0.presentationDetent == next }) {
                    selectedDetent = match
                }
            }
        )
    }

    private var backgroundStyle: AnyShapeStyle {
        switch background {
        // Follow the app palette (Dim/OLED) instead of the system background.
        case .automatic: AnyShapeStyle(ModulaPalette.resolve(app.appearance, scheme: colorScheme).canvas)
        case .material: AnyShapeStyle(.regularMaterial)
        case .opaque: AnyShapeStyle(ModulaPalette.resolve(app.appearance, scheme: colorScheme).surface)
        }
    }
}

/// A same-hierarchy morph host for entry surfaces such as the GAIA accessory.
/// Unlike a system sheet, source and destination remain in one render tree so the
/// material can visibly grow from the originating control.
struct ModulaMorphSheetHost<Content: View, Source: View, SheetContent: View>: View {
    @Binding var isPresented: Bool
    var alignment: Alignment = .bottomTrailing
    var dismissible = true
    @ViewBuilder var content: () -> Content
    @ViewBuilder var source: () -> Source
    @ViewBuilder var sheet: () -> SheetContent

    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var morphNamespace

    var body: some View {
        ZStack(alignment: alignment) {
            content()
                .allowsHitTesting(!isPresented)

            if isPresented {
                Color.black.opacity(0.32)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture { if dismissible { dismiss() } }

                VStack(spacing: 0) {
                    ModulaSheetHandle()
                    sheet()
                }
                .frame(maxWidth: .infinity)
                .frame(maxHeight: 620, alignment: .top)
                .modulaMaterial(.floating, in: RoundedRectangle(cornerRadius: ModulaRadius.large, style: .continuous), depth: .overlay)
                .matchedGeometryEffect(id: "modula.morph.sheet", in: morphNamespace)
                .padding(.horizontal, ModulaSpacing.xs)
                .padding(.bottom, ModulaSpacing.xs)
                .transition(reduceMotion ? .opacity : .scale(scale: 0.95, anchor: .bottomTrailing).combined(with: .opacity))
                .accessibilityAddTraits(.isModal)
                .accessibilityAction(named: "Dismiss") { if dismissible { dismiss() } }
            } else {
                Button {
                    withAnimation(animation) { isPresented = true }
                    HapticEngine.shared.play(.contextOpened)
                } label: {
                    source()
                }
                .buttonStyle(.plain)
                .matchedGeometryEffect(id: "modula.morph.sheet", in: morphNamespace)
                .transition(.opacity)
                .padding(ModulaSpacing.md)
                .accessibilityLabel("Open sheet")
            }
        }
        .animation(animation, value: isPresented)
    }

    private var animation: Animation? {
        ModulaMotion.animation(.morph, personality: app.appearance.motion, reduceMotion: reduceMotion)
    }

    private func dismiss() {
        withAnimation(animation) { isPresented = false }
    }
}
