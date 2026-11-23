import SwiftUI

// MARK: - Live appearance preview

/// Settings root card: tap an accent or theme and see it applied to a sample row and CTA right away.
/// Writes through `AppearanceStore` (the sole theme authority); the full Appearance pages are unchanged.
/// Psychology: immediate feedback / WYSIWYG lowers the cost of trying a look (reversibility encourages exploration).
struct SettingsLiveAppearanceCard: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    var onOpenAppearance: () -> Void

    var body: some View {
        let appearance = app.appearance
        let calm = ModulaEffectGate.reduceMotion(systemReduceMotion)
        VStack(alignment: .leading, spacing: 12) {
            // Sample: what a post row and the primary button will look like.
            HStack(spacing: 10) {
                MolibooEmptyArt(mood: .happy, size: 18, animated: false)
                    .frame(width: 44, height: 40)
                VStack(alignment: .leading, spacing: 4) {
                    RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.75)).frame(width: 110, height: 8)
                    RoundedRectangle(cornerRadius: 3).fill(Color.secondary.opacity(0.35)).frame(width: 160, height: 6)
                }
                Spacer(minLength: 0)
                Text("Follow")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 14).frame(height: 32)
                    .modulaAccentCTA()
                    .accessibilityHidden(true)
            }
            .padding(10)
            .modulaGlass(in: RoundedRectangle(cornerRadius: ModulaRadius.medium, style: .continuous), interactive: false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Preview of the current accent")

            HStack(spacing: 10) {
                ForEach(AppearanceStore.Accent.allCases) { accent in
                    let selected = appearance.customAccentHex == nil && appearance.accent == accent
                    Button {
                        HapticEngine.shared.play(.selection)
                        withAnimation(ModulaSurfaceMotion.animation(reduce: calm)) { appearance.selectNamedAccent(accent) }
                    } label: {
                        Circle()
                            .fill(accent.color)
                            .frame(width: 30, height: 30)
                            .overlay(Circle().strokeBorder(.white, lineWidth: selected ? 3 : 0))
                            .overlay(Circle().strokeBorder(accent.color, lineWidth: selected ? 1.5 : 0).padding(-3))
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Circle())
                    }
                    .buttonStyle(ModulaPressStyle(scale: 0.9, haptic: nil))
                    .accessibilityLabel(accent.title)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                ForEach(AppearanceStore.Theme.allCases) { theme in
                    let selected = appearance.theme == theme
                    Button {
                        HapticEngine.shared.play(.selection)
                        withAnimation(ModulaSurfaceMotion.animation(reduce: calm)) { appearance.theme = theme }
                    } label: {
                        Text(theme.rawValue.capitalized)
                            .font(.footnote.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 34)
                            .modifier(SettingsChoiceChrome(selected: selected))
                    }
                    .buttonStyle(ModulaPressStyle(scale: 0.95, haptic: nil))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }

            Button(action: onOpenAppearance) {
                Label("More appearance options", systemImage: "paintbrush.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 40)
            }
            .buttonStyle(ModulaPressStyle(scale: 0.97, haptic: .selection))
            .modulaAccentCTA()
            .accessibilityIdentifier("settings.live-appearance.more")
        }
        .padding(14)
        .accessibilityIdentifier("settings.live-appearance")
    }
}

private struct SettingsChoiceChrome: ViewModifier {
    let selected: Bool
    @Environment(AppEnvironment.self) private var app
    func body(content: Content) -> some View {
        if selected {
            content.modulaAccentCTA()
        } else {
            content.foregroundStyle(app.appearance.liveAccent).modulaGlass(in: Capsule(), interactive: true)
        }
    }
}

// MARK: - Privacy dashboard

/// One glanceable view of the privacy and security switches that are real on this build.
///
/// Every row reads live state (App Lock store, local preferences) and links to the page that changes it.
/// No server privacy score is invented: the ring counts only the local protections listed here.
/// Psychology: goal-gradient + progress feedback ("3 of 5 on") nudges people to finish securing their account,
/// and grouping by "who can see me / what this device does / your data" follows chunking.
struct SettingsPrivacyDashboard: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var shown = false

    private struct Check: Identifiable {
        let id: String; let title: String; let detail: String; let symbol: String; let on: Bool; let route: SettingsRoute
    }

    private var checks: [Check] {
        let lock = app.appLock.settings
        return [
            Check(id: "lock", title: "App Lock", detail: lock.enabled ? "On" : "Off", symbol: "lock.fill", on: lock.enabled, route: .privacy(.appLock)),
            Check(id: "bio", title: "Face ID / Touch ID", detail: lock.biometricsEnabled ? "On" : "Off", symbol: "faceid", on: lock.enabled && lock.biometricsEnabled, route: .privacy(.biometrics)),
            Check(id: "switcher", title: "Hide in App Switcher", detail: lock.hideInAppSwitcher ? "On" : "Off", symbol: "eye.slash.fill", on: lock.hideInAppSwitcher, route: .privacy(.appLock)),
            Check(id: "receipts", title: "Read receipts shown", detail: ModulaPreferences.chatShowReadReceipts ? "Shown" : "Hidden", symbol: "checkmark.message.fill", on: !ModulaPreferences.chatShowReadReceipts, route: .chats(.root)),
            Check(id: "suggest", title: "Suggested people", detail: ModulaPreferences.showsSuggestedPeople ? "On" : "Off", symbol: "person.2.wave.2.fill", on: !ModulaPreferences.showsSuggestedPeople, route: .personalisation(.root))
        ]
    }

    var body: some View {
        let accent = app.appearance.liveAccent
        let calm = ModulaEffectGate.reduceMotion(systemReduceMotion)
        let onCount = checks.filter(\.on).count
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 16) {
                        ZStack {
                            Circle().stroke(accent.opacity(0.18), lineWidth: 8)
                            Circle()
                                .trim(from: 0, to: shown || calm ? Double(onCount) / Double(max(checks.count, 1)) : 0)
                                .stroke(accent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                            Text("\(onCount)/\(checks.count)").font(.headline.monospacedDigit())
                        }
                        .frame(width: 72, height: 72)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Device protections").font(.title3.weight(.semibold))
                            Text("Switches on this iPhone that keep Modula private. Account visibility and blocks live on Greenfield.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)

                    group("On this iPhone") {
                        ForEach(checks) { check in
                            row(check.title, check.detail, check.symbol, on: check.on) { open(check.route) }
                        }
                    }
                    group("Who can reach you") {
                        row("Privacy settings", "Profile visibility, mentions, messages", "hand.raised.fill", on: nil) { open(.privacy(.privacy)) }
                        row("Blocked accounts", "People who can't see or contact you", "nosign", on: nil) { open(.privacy(.blocked)) }
                        row("Muted accounts", "Hidden from your feeds", "speaker.slash.fill", on: nil) { open(.safety(.muted)) }
                    }
                    group("Your data") {
                        row("Signed-in devices", "Review and sign out sessions", "laptopcomputer.and.iphone", on: nil) { open(.account(.sessions)) }
                        row("Export your data", "Request a copy from Greenfield", "square.and.arrow.up.on.square.fill", on: nil) { open(.dataStorage(.export)) }
                        row("Privacy Policy", "What Modula keeps", "doc.text.fill", on: nil) { open(.about(.privacy)) }
                    }
                }
                .padding(16)
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Privacy Dashboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .padding(.horizontal, 12)
                        .modulaAccentCTA()
                }
            }
            .onAppear { withAnimation(calm ? nil : .spring(response: 0.8, dampingFraction: 0.9)) { shown = true } }
        }
        .accessibilityIdentifier("settings.privacy-dashboard")
    }

    private func open(_ route: SettingsRoute) {
        dismiss()
        app.navigation.open(.settings(route))
    }

    private func group(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.footnote.weight(.semibold)).foregroundStyle(.secondary).padding(.leading, 4)
            VStack(spacing: 0) { content() }
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func row(_ title: String, _ detail: String, _ symbol: String, on: Bool?, action: @escaping () -> Void) -> some View {
        Button {
            HapticEngine.shared.play(.selection)
            action()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(app.appearance.liveAccent))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.body).foregroundStyle(.primary)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if let on {
                    Image(systemName: on ? "checkmark.shield.fill" : "shield")
                        .foregroundStyle(on ? app.appearance.liveAccent : .secondary)
                        .accessibilityLabel(on ? "Protected" : "Not enabled")
                }
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
