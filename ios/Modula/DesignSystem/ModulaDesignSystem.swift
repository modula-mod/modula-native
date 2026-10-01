import SwiftUI
import UIKit

enum ModulaSpacing { static let xxs = 4.0; static let xs = 8.0; static let sm = 12.0; static let md = 16.0; static let lg = 24.0; static let xl = 32.0 }
enum ModulaRadius { static let small = 10.0; static let medium = 16.0; static let large = 24.0 }
enum ModulaLayout {
    static let minimumTouch = 44.0
    static let contentInset = 18.0
    static let railRestingWidth = 46.0
    static let railRevealedWidth = 96.0
}
enum ModulaMotion {
    enum Role {
        case instantFeedback, selection, navigation, contentTransition
        case presentation, overlay, morph, interactiveGesture, dismissal
        case reveal, dismiss, railExpand, railCollapse, sheetPresent
    }
    static func animation(_ role: Role, personality: AppearanceStore.MotionPersonality, reduceMotion: Bool) -> Animation? {
        guard !reduceMotion else { return .easeOut(duration: 0.12) }
        switch personality {
        case .calm:
            return .easeOut(duration: role == .navigation || role == .presentation ? 0.22 : 0.16)
        case .standard:
            switch role {
            case .instantFeedback: return .easeOut(duration: 0.1)
            case .selection, .contentTransition: return .snappy(duration: 0.28, extraBounce: 0.05)
            case .interactiveGesture: return .interactiveSpring(response: 0.32, dampingFraction: 0.86)
            default: return .spring(duration: 0.38, bounce: 0.16)
            }
        case .expressive:
            return .spring(duration: role == .instantFeedback ? 0.18 : 0.5, bounce: 0.28)
        }
    }
}

enum HapticSemantic: String, CaseIterable, Sendable {
    case selection
    case navigation
    case lightImpact
    case mediumImpact
    case confirmation
    case success
    case warning
    case failure
    case contextOpen
    case reactionSelect
    case dragThreshold
    case drop
    case followComplete
    case saveComplete
    /// Legacy alias used by shell/chrome; maps to medium impact.
    case impact
}

extension HapticSemantic {
    static let selectionChanged: Self = .selection
    static let contextOpened: Self = .contextOpen
    static let actionConfirmed: Self = .confirmation
    static let reactionChanged: Self = .reactionSelect
    static let reactionCommitted: Self = .confirmation
    static let sheetDetentReached: Self = .dragThreshold
}

@MainActor final class HapticEngine {
    static let shared = HapticEngine()
    var intensityProvider: () -> AppearanceStore.HapticIntensity = { .standard }

    func play(_ semantic: HapticSemantic) {
        let intensity = intensityProvider()
        guard intensity != .off else { return }
        switch semantic {
        case .selection, .reactionSelect:
            UISelectionFeedbackGenerator().selectionChanged()
        case .navigation, .contextOpen, .lightImpact:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .mediumImpact, .impact, .dragThreshold:
            UIImpactFeedbackGenerator(style: intensity == .strong ? .heavy : intensity == .light ? .light : .medium).impactOccurred()
        case .drop:
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        case .confirmation, .success, .followComplete, .saveComplete:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .warning:
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .failure:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
}

enum ModulaIconRole: String, CaseIterable { case home, discover, module, activity, profile, search, settings, share, like, comment, back, more }
enum ModulaIconRegistry {
    static func symbol(_ role: ModulaIconRole, style: AppearanceStore.IconStyle, selected: Bool = false) -> String {
        let base: String = switch role {
        case .home: "house"; case .discover: "safari"; case .module: "shippingbox"; case .activity: "bell"
        case .profile: "person.crop.circle"; case .search: "magnifyingglass"; case .settings: "gearshape"
        case .share: "square.and.arrow.up"; case .like: "heart"; case .comment: "bubble.right"; case .back: "chevron.left"; case .more: "ellipsis"
        }
        let canFill = [.home, .discover, .module, .activity, .profile, .like].contains(role)
        return canFill && (selected || style == .filled) ? base + ".fill" : base
    }
}

struct ModulaPalette {
    var canvas: Color; var surface: Color; var elevated: Color; var primary: Color; var secondary: Color; var separator: Color; var accent: Color
    @MainActor static func resolve(_ store: AppearanceStore, scheme: ColorScheme, increasedContrast: Bool = false) -> Self {
        let dark = scheme == .dark
        let accent = store.accent.color
        if dark && store.darkStyle == .oled {
            return Self(canvas: .black, surface: Color.white.opacity(0.055), elevated: Color.white.opacity(0.1), primary: .white,
                        secondary: Color.white.opacity(increasedContrast ? 0.78 : 0.66), separator: Color.white.opacity(0.14), accent: accent)
        }
        if dark && store.darkStyle == .dim {
            return Self(canvas: Color(red: 0.075, green: 0.085, blue: 0.10), surface: Color(red: 0.105, green: 0.12, blue: 0.14),
                        elevated: Color(red: 0.14, green: 0.155, blue: 0.18), primary: Color.white.opacity(0.92),
                        secondary: Color.white.opacity(increasedContrast ? 0.76 : 0.58), separator: Color.white.opacity(0.1), accent: accent)
        }
        if dark {
            return Self(canvas: Color(uiColor: .systemBackground), surface: Color(uiColor: .secondarySystemBackground), elevated: Color(uiColor: .tertiarySystemBackground),
                        primary: .primary, secondary: .secondary, separator: Color.white.opacity(0.12), accent: accent)
        }
        return Self(canvas: Color(red: 0.975, green: 0.982, blue: 0.988), surface: .white, elevated: Color(uiColor: .secondarySystemBackground),
                    primary: .primary, secondary: .secondary, separator: Color.black.opacity(increasedContrast ? 0.16 : 0.08), accent: accent)
    }
}

struct ModulaText: View {
    enum Role { case hero, title, headline, body, callout, caption, metric }
    let text: String; var role: Role = .body; var color: Color? = nil
    @Environment(AppEnvironment.self) private var app
    @ScaledMetric(relativeTo: .body) private var baseSize = 17.0
    var body: some View { Text(text).font(font).fontDesign(design).foregroundStyle(color ?? .primary).dynamicTypeSize(...DynamicTypeSize.accessibility5) }
    private var font: Font { .system(size: baseSize * multiplier * app.appearance.textSize.scale, weight: weight, design: design) }
    private var multiplier: Double { switch role { case .hero: 2; case .title: 1.35; case .headline: 1; case .body: 1; case .callout: 0.94; case .caption: 0.76; case .metric: 1.18 } }
    private var weight: Font.Weight { switch role { case .hero, .title: .bold; case .headline, .metric: .semibold; default: .regular } }
    private var design: Font.Design { switch app.appearance.fontFamily { case .rounded, .geometric: .rounded; case .editorial: .serif; case .mono: .monospaced; default: .default } }
}
struct ModulaIcon: View { var role: ModulaIconRole; var selected = false; @Environment(AppEnvironment.self) private var app; var body: some View { Image(systemName: ModulaIconRegistry.symbol(role, style: app.appearance.iconStyle, selected: selected)).imageScale(.large) } }
/// Primary call to action. Accent capsule with distinct enabled, pressed, disabled and
/// loading states; loading keeps the accent fill so progress never reads as "disabled".
struct ModulaButton: View {
    let title: String; var symbol: String?; var isLoading = false; var loadingTitle: String?; var action: () -> Void
    @Environment(AppEnvironment.self) private var app
    @ScaledMetric(relativeTo: .headline) private var height = 52.0

    init(title: String, symbol: String? = nil, isLoading: Bool = false, loadingTitle: String? = nil, action: @escaping () -> Void) {
        self.title = title; self.symbol = symbol; self.isLoading = isLoading; self.loadingTitle = loadingTitle; self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: ModulaSpacing.xs) {
                if isLoading {
                    ProgressView().tint(.white).controlSize(.regular)
                    Text(loadingTitle ?? title)
                } else if let symbol {
                    Label(title, systemImage: symbol)
                } else {
                    Text(title)
                }
            }
            .font(.headline)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .frame(minHeight: max(ModulaLayout.minimumTouch, height))
            .contentShape(Capsule())
        }
        .buttonStyle(ModulaPrimaryButtonStyle(accent: app.appearance.accent.color, isLoading: isLoading))
        .accessibilityValue(isLoading ? (loadingTitle ?? "In progress") : "")
    }
}

struct ModulaPrimaryButtonStyle: ButtonStyle {
    var accent: Color
    var isLoading = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    func makeBody(configuration: Configuration) -> some View {
        let active = isEnabled || isLoading
        configuration.label
            .padding(.horizontal, ModulaSpacing.lg)
            .foregroundStyle(active ? Color.white : accent.opacity(contrast == .increased ? 0.9 : 0.62))
            .background {
                Capsule()
                    .fill(active ? AnyShapeStyle(accent.gradient) : AnyShapeStyle(accent.opacity(scheme == .dark ? 0.16 : 0.12)))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(active ? 0.18 : 0), lineWidth: 0.75))
                    .shadow(color: accent.opacity(active && !configuration.isPressed ? 0.32 : 0), radius: 14, y: 6)
            }
            .brightness(configuration.isPressed ? -0.06 : 0)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: configuration.isPressed)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: active)
    }
}

/// Labelled form field with a leading symbol, accent focus ring, inline validation
/// message and (for secure fields) a show/hide toggle that keeps keyboard focus.
/// Keyboard, content type, submit label and `onSubmit` modifiers applied to the
/// field propagate to the inner text input.
struct ModulaFormField<Focus: Hashable>: View {
    enum Kind { case text, secure }

    let title: String
    let symbol: String
    @Binding var text: String
    var kind: Kind = .text
    var prompt: String?
    var message: String?
    var focus: FocusState<Focus?>.Binding
    var focusValue: Focus
    var identifier: String

    @Environment(AppEnvironment.self) private var app
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @ScaledMetric(relativeTo: .body) private var fieldHeight = 56.0
    @ScaledMetric(relativeTo: .body) private var iconWidth = 22.0
    @State private var revealed = false

    private var isFocused: Bool { focus.wrappedValue == focusValue }
    private var hasError: Bool { message != nil }
    private var radius: CGFloat { app.appearance.interfaceShape.radius(for: .control) }

    var body: some View {
        VStack(alignment: .leading, spacing: ModulaSpacing.xs) {
            HStack(spacing: ModulaSpacing.sm) {
                Image(systemName: symbol)
                    .font(.body.weight(.medium))
                    .foregroundStyle(iconColor)
                    .frame(width: iconWidth)
                    .accessibilityHidden(true)
                input
                    .font(.body)
                    .frame(maxWidth: .infinity, minHeight: max(ModulaLayout.minimumTouch, fieldHeight))
                if kind == .secure {
                    Button {
                        let target = focusValue
                        let wasFocused = isFocused
                        revealed.toggle()
                        if wasFocused {
                            DispatchQueue.main.async { focus.wrappedValue = target }
                        }
                        HapticEngine.shared.play(.selection)
                    } label: {
                        Image(systemName: revealed ? "eye.slash" : "eye")
                            .font(.body.weight(.medium))
                            .foregroundStyle(.secondary)
                            .frame(width: ModulaLayout.minimumTouch, height: ModulaLayout.minimumTouch)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(revealed ? "Hide password" : "Show password")
                    .accessibilityIdentifier("\(identifier).visibility")
                }
            }
            .padding(.leading, ModulaSpacing.md)
            .padding(.trailing, kind == .secure ? ModulaSpacing.xxs : ModulaSpacing.md)
            .background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: isFocused || hasError ? 1.5 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .onTapGesture { focus.wrappedValue = focusValue }
            .opacity(isEnabled ? 1 : 0.6)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: isFocused)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: hasError)

            if let message {
                Label(message, systemImage: "exclamationmark.circle.fill")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Color.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("\(identifier).message")
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    /// Secure fields keep both inputs mounted and swap visibility in place. Removing a
    /// filled `SecureField` from the hierarchy makes iOS offer "Save Password?" and
    /// drops focus; a disabled input can't hold focus, so the shared focus value
    /// always resolves to the visible one.
    @ViewBuilder
    private var input: some View {
        let promptText = Text(prompt ?? title).foregroundStyle(Color.secondary)
        if kind == .secure {
            ZStack {
                SecureField(title, text: $text, prompt: promptText)
                    .focused(focus, equals: focusValue)
                    .disabled(revealed)
                    .opacity(revealed ? 0 : 1)
                    .accessibilityHidden(revealed)
                    .accessibilityIdentifier(identifier)
                    .accessibilityHint(message ?? "")
                TextField(title, text: $text, prompt: promptText)
                    .focused(focus, equals: focusValue)
                    .disabled(!revealed)
                    .opacity(revealed ? 1 : 0)
                    .accessibilityHidden(!revealed)
                    .accessibilityIdentifier(identifier)
                    .accessibilityHint(message ?? "")
            }
        } else {
            TextField(title, text: $text, prompt: promptText)
                .focused(focus, equals: focusValue)
                .accessibilityIdentifier(identifier)
                .accessibilityHint(message ?? "")
        }
    }

    private var iconColor: Color {
        if hasError { return .red }
        return isFocused ? app.appearance.accent.color : .secondary
    }

    private var fill: Color {
        if isFocused { return app.appearance.accent.color.opacity(scheme == .dark ? 0.14 : 0.07) }
        return Color.primary.opacity(scheme == .dark ? 0.08 : 0.045)
    }

    private var borderColor: Color {
        if hasError { return .red.opacity(0.85) }
        if isFocused { return app.appearance.accent.color }
        return Color.primary.opacity(contrast == .increased ? 0.28 : 0.1)
    }
}
struct ModulaIconButton: View { let title: String; let symbol: String; var action: () -> Void; var body: some View { Button(action: action) { Image(systemName: symbol).frame(width: 44, height: 44) }.accessibilityLabel(title) } }
struct ModulaAvatar: View {
    var initials: String
    var url: URL? = nil
    var size = 44.0
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        Group {
            if let url {
                ModulaRemoteImage(
                    url: url,
                    cacheKey: "avatar:\(url.path)",
                    maximumPixelSize: max(160, size * UIScreen.main.scale)
                ) { phase in
                    switch phase {
                    case .success(let image): Image(uiImage: image).resizable().scaledToFill()
                    case .loading: loadingView
                    case .failure: failureView
                    }
                }
            } else {
                initialsView
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityLabel("Profile avatar")
    }

    private var initialsView: some View {
        Circle()
            .fill(app.appearance.accent.color.gradient)
            .overlay(Text(initials).font(.headline).foregroundStyle(.white))
    }

    private var loadingView: some View {
        Circle()
            .fill(Color.secondary.opacity(0.12))
            .overlay(ProgressView().controlSize(.small))
            .accessibilityLabel("Loading profile avatar")
    }

    private var failureView: some View {
        Circle()
            .fill(Color.secondary.opacity(0.12))
            .overlay(Image(systemName: "person.crop.circle.badge.exclamationmark").foregroundStyle(.secondary))
            .accessibilityLabel("Profile avatar could not be loaded")
    }
}

/// Circular Profile tab glyph for the pre-iOS 26 custom tab bar.
struct ProfileTabIcon: View {
    var selected = false
    var size: CGFloat = 26
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        Image(uiImage: app.profile.tabBarAvatar ?? ProfileTabAvatarRenderer.fallback(
            profile: app.profile.ownProfile,
            account: app.auth.account,
            accent: UIColor(app.appearance.accent.color),
            pointSize: size
        ))
        .renderingMode(.original)
        .resizable()
        .scaledToFill()
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

/// SwiftUI `tabItem` snapshots flatten bitmaps into a template silhouette.
/// This keeps the real photo on the Profile `UITabBarItem` and on the
/// visible tab-button image view after Liquid Glass re-templates it.
struct ProfileTabBarAvatarApplicator: UIViewRepresentable {
    var image: UIImage?

    func makeUIView(context: Context) -> ProfileTabBarAvatarHook {
        let hook = ProfileTabBarAvatarHook()
        hook.avatar = image
        return hook
    }

    func updateUIView(_ hook: ProfileTabBarAvatarHook, context: Context) {
        hook.avatar = image
        hook.applySoon()
    }
}

final class ProfileTabBarAvatarHook: UIView {
    var avatar: UIImage? {
        didSet { applySoon() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isHidden = true
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) { nil }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        applySoon()
    }

    func applySoon() {
        apply()
        DispatchQueue.main.async { [weak self] in self?.apply() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.apply() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.apply() }
    }

    func apply() {
        guard let avatar else { return }
        let prepared = avatar.withRenderingMode(.alwaysOriginal)
        for bar in allTabBars() {
            if let item = profileItem(in: bar) {
                item.image = prepared
                item.selectedImage = prepared
            }
            if let host = profileIconView(in: bar) {
                pinOverlay(on: host, image: prepared)
            }
        }
    }

    private func profileItem(in bar: UITabBar) -> UITabBarItem? {
        bar.items?.first(where: { $0.title?.caseInsensitiveCompare("Profile") == .orderedSame })
            ?? bar.items?.last
    }

    private func profileIconView(in bar: UITabBar) -> UIView? {
        if let labeled = firstView(in: bar, matching: { $0.accessibilityLabel?.caseInsensitiveCompare("Profile") == .orderedSame }) {
            if let icon = preferredIconView(in: labeled) { return icon }
            return labeled
        }
        let buttons = tabButtons(in: bar)
        guard let button = buttons.last else { return nil }
        return preferredIconView(in: button) ?? button
    }

    private func tabButtons(in bar: UITabBar) -> [UIView] {
        bar.subviews
            .filter { view in
                let name = String(describing: type(of: view))
                return name.localizedCaseInsensitiveContains("tabbarbutton")
                    || name.localizedCaseInsensitiveContains("tabbutton")
                    || (view is UIControl && view.frame.width > 20)
            }
            .sorted { $0.frame.minX < $1.frame.minX }
    }

    private func preferredIconView(in root: UIView) -> UIView? {
        var images: [UIImageView] = []
        walk(root) { view in
            guard let imageView = view as? UIImageView else { return }
            let width = imageView.bounds.width
            if width >= 12, width <= 56 { images.append(imageView) }
        }
        return images.min(by: { abs($0.bounds.width - 26) < abs($1.bounds.width - 26) })
    }

    private func pinOverlay(on host: UIView, image: UIImage) {
        let badge: ProfileTabAvatarOverlay
        if let existing = existingAvatarOverlay(on: host) {
            badge = existing
        } else if let parent = host.superview {
            badge = ProfileTabAvatarOverlay(frame: host.bounds)
            badge.translatesAutoresizingMaskIntoConstraints = false
            parent.addSubview(badge)
            NSLayoutConstraint.activate([
                badge.centerXAnchor.constraint(equalTo: host.centerXAnchor),
                badge.centerYAnchor.constraint(equalTo: host.centerYAnchor),
                badge.widthAnchor.constraint(equalTo: host.widthAnchor),
                badge.heightAnchor.constraint(equalTo: host.heightAnchor)
            ])
        } else {
            return
        }
        badge.image = image
        badge.isHidden = false
        if let imageView = host as? UIImageView {
            imageView.tintColor = .clear
        }
    }

    private func existingAvatarOverlay(on host: UIView) -> ProfileTabAvatarOverlay? {
        host.superview?.subviews.compactMap { $0 as? ProfileTabAvatarOverlay }.first
            ?? host.subviews.compactMap { $0 as? ProfileTabAvatarOverlay }.first
    }

    private func allTabBars() -> [UITabBar] {
        var found: [UITabBar] = []
        var seen = Set<ObjectIdentifier>()
        func add(_ bar: UITabBar) {
            let id = ObjectIdentifier(bar)
            guard !seen.contains(id) else { return }
            seen.insert(id)
            found.append(bar)
        }
        if let window {
            walk(window) { view in
                if let bar = view as? UITabBar { add(bar) }
            }
        }
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                walk(window) { view in
                    if let bar = view as? UITabBar { add(bar) }
                }
            }
        }
        return found
    }

    private func firstView(in root: UIView, matching: (UIView) -> Bool) -> UIView? {
        if matching(root) { return root }
        for child in root.subviews {
            if let found = firstView(in: child, matching: matching) { return found }
        }
        return nil
    }

    private func walk(_ root: UIView, visit: (UIView) -> Void) {
        visit(root)
        for child in root.subviews { walk(child, visit: visit) }
    }
}

/// Bounces the selected system tab icon. The SwiftUI `tabItem` snapshot
/// does not run symbol effects on the live `UITabBar` buttons.
struct TabBarIconMotionApplicator: UIViewRepresentable {
    var selectedTab: AppTab
    var reduceMotion: Bool

    func makeUIView(context: Context) -> TabBarIconMotionHook {
        let hook = TabBarIconMotionHook()
        hook.reduceMotion = reduceMotion
        hook.selectedTab = selectedTab
        return hook
    }

    func updateUIView(_ hook: TabBarIconMotionHook, context: Context) {
        hook.reduceMotion = reduceMotion
        hook.applySelection(selectedTab)
    }
}

final class TabBarIconMotionHook: UIView {
    var selectedTab: AppTab = .home
    var reduceMotion = false
    private var bouncedTab: AppTab?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isHidden = true
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) { nil }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        applySoon()
    }

    func applySelection(_ tab: AppTab) {
        selectedTab = tab
        applySoon()
    }

    private func applySoon() {
        bounceSelected()
        DispatchQueue.main.async { [weak self] in self?.bounceSelected() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.bounceSelected() }
    }

    private func bounceSelected() {
        guard !reduceMotion else {
            bouncedTab = selectedTab
            return
        }
        guard bouncedTab != selectedTab else { return }
        var bounced = false
        let tabs = AppTab.allCases
        for bar in allTabBars() {
            let buttons = tabButtons(in: bar)
            for (index, button) in buttons.enumerated() {
                guard tabs.indices.contains(index) else { continue }
                let tab = tabs[index]
                guard tab == selectedTab else { continue }
                if tab == .profile {
                    bounceProfile(in: button)
                    bounced = true
                } else if let imageView = preferredIconView(in: button) {
                    imageView.addSymbolEffect(.bounce, options: .nonRepeating, animated: true)
                    bounced = true
                }
            }
        }
        if bounced { bouncedTab = selectedTab }
    }

    private func bounceProfile(in button: UIView) {
        let overlay = firstView(in: button, matching: { $0 is ProfileTabAvatarOverlay })
            ?? preferredIconView(in: button)
        guard let overlay else { return }
        overlay.layer.removeAnimation(forKey: "modula.tab.bounce")
        let pop = CASpringAnimation(keyPath: "transform.scale")
        pop.fromValue = 0.86
        pop.toValue = 1
        pop.damping = 13
        pop.stiffness = 220
        pop.mass = 0.7
        pop.duration = pop.settlingDuration
        overlay.layer.add(pop, forKey: "modula.tab.bounce")
    }

    private func allTabBars() -> [UITabBar] {
        var found: [UITabBar] = []
        var seen = Set<ObjectIdentifier>()
        func add(_ bar: UITabBar) {
            let id = ObjectIdentifier(bar)
            guard !seen.contains(id) else { return }
            seen.insert(id)
            found.append(bar)
        }
        if let window {
            walk(window) { view in
                if let bar = view as? UITabBar { add(bar) }
            }
        }
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                walk(window) { view in
                    if let bar = view as? UITabBar { add(bar) }
                }
            }
        }
        return found
    }

    private func tabButtons(in bar: UITabBar) -> [UIView] {
        bar.subviews
            .filter { view in
                let name = String(describing: type(of: view))
                return name.localizedCaseInsensitiveContains("tabbarbutton")
                    || name.localizedCaseInsensitiveContains("tabbutton")
                    || (view is UIControl && view.frame.width > 20)
            }
            .sorted { $0.frame.minX < $1.frame.minX }
    }

    private func preferredIconView(in root: UIView) -> UIImageView? {
        var images: [UIImageView] = []
        walk(root) { view in
            guard let imageView = view as? UIImageView, !(view is ProfileTabAvatarOverlay) else { return }
            let width = imageView.bounds.width
            if width >= 12, width <= 56 { images.append(imageView) }
        }
        return images.min(by: { abs($0.bounds.width - 26) < abs($1.bounds.width - 26) })
    }

    private func firstView(in root: UIView, matching: (UIView) -> Bool) -> UIView? {
        if matching(root) { return root }
        for child in root.subviews {
            if let found = firstView(in: child, matching: matching) { return found }
        }
        return nil
    }

    private func walk(_ root: UIView, visit: (UIView) -> Void) {
        visit(root)
        for child in root.subviews { walk(child, visit: visit) }
    }
}

private final class ProfileTabAvatarOverlay: UIImageView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        contentMode = .scaleAspectFill
        clipsToBounds = true
        isUserInteractionEnabled = false
        layer.masksToBounds = true
    }

    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = min(bounds.width, bounds.height) / 2
    }
}

@MainActor
enum ProfileTabAvatarRenderer {
    private static var photos: [String: UIImage] = [:]

    static func cachedPhoto(for url: URL) -> UIImage? { photos[url.absoluteString] }

    static func storePhoto(_ image: UIImage, for url: URL) {
        photos[url.absoluteString] = image
    }

    static func initials(profile: ModulaProfile?, account: GreenfieldAccount?) -> String {
        if let profile { return profile.initials }
        if let name = account?.displayName, !name.isEmpty {
            let parts = name.split(separator: " ")
            if parts.count >= 2 {
                return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
            }
            return String(name.prefix(2)).uppercased()
        }
        if let handle = account?.primaryHandle, !handle.isEmpty {
            return String(handle.prefix(2)).uppercased()
        }
        return "M"
    }

    static func placeholder(initials: String, accent: UIColor, pointSize: CGFloat = 26) -> UIImage {
        image(photo: nil, initials: initials, accent: accent, pointSize: pointSize)
    }

    static func fallback(profile: ModulaProfile?, account: GreenfieldAccount?, accent: UIColor, pointSize: CGFloat = 26) -> UIImage {
        guard profile?.avatarURL == nil else { return status(symbol: "person.crop.circle", accent: accent, pointSize: pointSize) }
        return placeholder(initials: initials(profile: profile, account: account), accent: accent, pointSize: pointSize)
    }

    static func status(symbol: String, accent: UIColor, pointSize: CGFloat = 26) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        format.scale = UIScreen.main.scale
        return UIGraphicsImageRenderer(size: CGSize(width: pointSize, height: pointSize), format: format).image { _ in
            let inset = pointSize * 0.08
            let rect = CGRect(x: inset, y: inset, width: pointSize - inset * 2, height: pointSize - inset * 2)
            accent.withAlphaComponent(0.16).setFill()
            UIBezierPath(ovalIn: rect).fill()
            let configuration = UIImage.SymbolConfiguration(pointSize: rect.height * 0.46, weight: .semibold)
            if let icon = UIImage(systemName: symbol, withConfiguration: configuration)?.withTintColor(accent, renderingMode: .alwaysOriginal) {
                let origin = CGPoint(x: rect.midX - icon.size.width / 2, y: rect.midY - icon.size.height / 2)
                icon.draw(at: origin)
            }
        }.withRenderingMode(.alwaysOriginal)
    }

    static func image(
        photo: UIImage?,
        initials: String,
        accent: UIColor,
        pointSize: CGFloat = 26
    ) -> UIImage {
        let scale = UIScreen.main.scale
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        format.scale = scale
        let canvas = CGSize(width: pointSize, height: pointSize)
        let renderer = UIGraphicsImageRenderer(size: canvas, format: format)
        let rendered = renderer.image { _ in
            let inset = pointSize * 0.08
            let rect = CGRect(origin: .zero, size: canvas).insetBy(dx: inset, dy: inset)
            let clip = UIBezierPath(ovalIn: rect)
            clip.addClip()
            if let photo, photo.size.width > 0, photo.size.height > 0 {
                let photoSize = photo.size
                let fill = max(rect.width / photoSize.width, rect.height / photoSize.height)
                let draw = CGRect(
                    x: rect.midX - photoSize.width * fill / 2,
                    y: rect.midY - photoSize.height * fill / 2,
                    width: photoSize.width * fill,
                    height: photoSize.height * fill
                )
                photo.draw(in: draw)
            } else {
                drawInitials(initials, in: rect, accent: accent)
            }
            UIGraphicsGetCurrentContext()?.resetClip()
            let ring = UIBezierPath(ovalIn: rect)
            ring.lineWidth = 1
            UIColor.white.withAlphaComponent(0.9).setStroke()
            ring.stroke()
        }
        return rendered.withRenderingMode(.alwaysOriginal)
    }

    private static func drawInitials(_ initials: String, in rect: CGRect, accent: UIColor) {
        accent.setFill()
        UIBezierPath(ovalIn: rect).fill()
        let font = UIFont.systemFont(ofSize: rect.height * 0.36, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.white
        ]
        let text = initials as NSString
        let size = text.size(withAttributes: attributes)
        let origin = CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2)
        text.draw(at: origin, withAttributes: attributes)
    }
}
struct ModulaBadge: View {
    var title: String
    var symbol: String?
    var tone: ModulaIndicatorTone = .accent
    var style: ModulaBadgeStyle = .tinted
    var selected = false

    @Environment(AppEnvironment.self) private var app

    var body: some View {
        Group {
            if let symbol {
                Label(title, systemImage: symbol)
            } else {
                Text(title)
            }
        }
        .font(.caption.weight(.semibold))
        .lineLimit(1)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(background, in: Capsule())
        .overlay(Capsule().stroke(color.opacity(style == .outlined ? 0.7 : 0), lineWidth: 1))
        .foregroundStyle(foreground)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var color: Color { tone.color(accent: app.appearance.accent.color) }
    private var background: Color {
        switch style {
        case .filled: color
        case .tinted: color.opacity(selected ? 0.22 : 0.14)
        case .outlined: .clear
        }
    }
    private var foreground: Color { style == .filled ? .white : color }
}
struct ModulaCard<Content: View>: View { @ViewBuilder var content: Content; @Environment(AppEnvironment.self) private var app; @Environment(\.colorScheme) private var scheme; var body: some View { content.padding(16 * app.appearance.density.spacingScale).frame(maxWidth: .infinity, alignment: .leading).background(ModulaPalette.resolve(app.appearance, scheme: scheme).surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous)).overlay(RoundedRectangle(cornerRadius: radius).stroke(.primary.opacity(0.07))).accessibilityElement(children: .contain) }; private var radius: Double { switch app.appearance.interfaceShape { case .soft: 24; case .balanced: 17; case .precise: 10 } } }

private struct ModulaCanvasModifier: ViewModifier {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(ModulaPalette.resolve(app.appearance, scheme: scheme).canvas)
            .modulaSoftScrollEdge()
    }
}
extension View {
    func modulaCanvas() -> some View { modifier(ModulaCanvasModifier()) }

    @ViewBuilder
    func modulaMinimizedSearchToolbar() -> some View {
        if #available(iOS 26.0, *) {
            searchToolbarBehavior(.minimize)
        } else {
            self
        }
    }

    /// Settings-matching nav chrome on full-bleed heroes: keep the *system* bar
    /// (same glass size and slot as Settings) but hide the bar material.
    func modulaImmersiveSystemNavigation() -> some View {
        self
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
    }
}
struct ModulaListRow: View { var title: String; var subtitle: String?; var symbol: String; var action: (() -> Void)?; var body: some View { Button { action?() } label: { HStack(spacing: 14) { Image(systemName: symbol).frame(width: 28).foregroundStyle(.tint); VStack(alignment: .leading, spacing: 2) { Text(title).font(.body.weight(.medium)); if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) } }; Spacer(); if action != nil { Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary) } }.frame(minHeight: 48).contentShape(Rectangle()) }.buttonStyle(.plain).disabled(action == nil).accessibilityLabel(title).accessibilityValue(subtitle ?? "") } }
struct ModulaSection<Content: View>: View { var title: String; @ViewBuilder var content: Content; var body: some View { VStack(alignment: .leading, spacing: 12) { Text(title).font(.headline); content }.frame(maxWidth: .infinity, alignment: .leading) } }
struct ModulaSearchField: View { @Binding var text: String; var prompt = "Search"; var body: some View { TextField(prompt, text: $text).textFieldStyle(.plain).padding(.horizontal, 14).frame(minHeight: 44).background(.thinMaterial, in: Capsule()).accessibilityLabel(prompt) } }
struct ModulaMetric: View { var value: String; var label: String; var body: some View { VStack(alignment: .leading, spacing: 2) { Text(value).font(.title3.bold()); Text(label).font(.caption).foregroundStyle(.secondary) }.accessibilityElement(children: .combine) } }
struct ModulaMetricPicker<Value: Hashable, Content: View>: View { @Binding var selection: Value; var values: [Value]; @ViewBuilder var label: (Value) -> Content; var body: some View { Picker("Selection", selection: $selection) { ForEach(values, id: \.self) { label($0).tag($0) } }.pickerStyle(.segmented) } }
struct ModulaChip: View { var title: String; var selected = false; var action: () -> Void; var body: some View { Button(title, action: action).buttonStyle(.bordered).buttonBorderShape(.capsule).tint(selected ? .accentColor : .secondary).frame(minHeight: 44) } }
struct ModulaToolbar<Content: View>: View { @ViewBuilder var content: Content; var body: some View { HStack(spacing: 8) { content }.padding(6).background(.regularMaterial, in: Capsule()) } }
struct ModulaTopBar: View { var title: String; var trailing: (() -> Void)?; var body: some View { HStack { Text(title).font(.largeTitle.bold()); Spacer(); if let trailing { ModulaIconButton(title: "Settings", symbol: "gearshape", action: trailing) } }.padding(.horizontal, ModulaLayout.contentInset) } }
struct ModulaMenu<Content: View>: View { var title: String; @ViewBuilder var content: Content; var body: some View { Menu(title, content: { content }) } }
struct ModulaEmptyState: View { var title: String; var message: String; var symbol: String; var body: some View { ContentUnavailableView(title, systemImage: symbol, description: Text(message)) } }
struct ModulaLoadingState: View { var title = "Loading…"; var body: some View { ProgressView(title).frame(maxWidth: .infinity, minHeight: 180) } }
struct ModulaErrorState: View { var message: String; var retry: (() -> Void)?; var body: some View { ContentUnavailableView { Label("Something went wrong", systemImage: "exclamationmark.triangle") } description: { Text(message) } actions: { if let retry { Button("Try Again", action: retry) } } } }
struct ModulaHero<Content: View>: View { var title: String; var subtitle: String; @ViewBuilder var artwork: Content; var body: some View { ZStack(alignment: .bottomLeading) { artwork.frame(maxWidth: .infinity).frame(height: 260).clipped(); LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom); VStack(alignment: .leading) { Text(title).font(.largeTitle.bold()); Text(subtitle) }.foregroundStyle(.white).padding(20) }.clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous)) } }
struct ModulaMetadataRail: View { var values: [(String, String)]; var body: some View { HStack { ForEach(Array(values.enumerated()), id: \.offset) { _, value in ModulaMetric(value: value.0, label: value.1); Spacer() } }.padding(.vertical, 8) } }
