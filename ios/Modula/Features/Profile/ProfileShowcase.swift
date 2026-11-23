import SwiftUI

// MARK: - Showcase shelf

/// Your three favourite Moliboos, shown on your own profile.
///
/// Greenfield has no profile-showcase field yet, so the picks are stored on this device and only shown
/// on your own profile, with an honest footnote. Nothing is invented for other people's profiles.
/// Psychology: self-presentation / IKEA effect (curating your shelf makes the profile feel like yours),
/// and three slots keep the choice small (Hick's law).
enum ProfileShowcaseStore {
    static let key = "profile.showcase.moliboos"
    static let slots = 3

    static func decode(_ raw: String) -> [ModulaMascotKind] {
        raw.split(separator: ",").compactMap { ModulaMascotKind(rawValue: String($0)) }.filter(MascotEntitlements.canUse)
    }

    static func encode(_ kinds: [ModulaMascotKind]) -> String {
        kinds.prefix(slots).map(\.rawValue).joined(separator: ",")
    }
}

struct ProfileShowcaseShelf: View {
    @AppStorage(ProfileShowcaseStore.key) private var raw = ""
    @AppStorage(ModulaMascotSettings.kindKey) private var companionRaw = ModulaMascotKind.pip.rawValue
    @Environment(AppEnvironment.self) private var app
    @State private var editing = false

    private var picks: [ModulaMascotKind] { ProfileShowcaseStore.decode(raw) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                ModulaSectionHeader(title: "Showcase", subtitle: "Your favourite Moliboos")
                Button(picks.isEmpty ? "Add" : "Edit") {
                    HapticEngine.shared.play(.selection)
                    editing = true
                }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .frame(minHeight: 34)
                .modulaAccentCTA()
                .accessibilityIdentifier("profile.showcase.edit")
            }
            HStack(spacing: 10) {
                ForEach(0..<ProfileShowcaseStore.slots, id: \.self) { index in
                    slot(index < picks.count ? picks[index] : nil)
                }
            }
            Text("Only shown on your profile on this device until profiles can sync a showcase.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .sheet(isPresented: $editing) {
            ProfileShowcasePicker(selection: Binding(
                get: { picks },
                set: { raw = ProfileShowcaseStore.encode($0) }
            ))
            .presentationDetents([.medium, .large])
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("profile.showcase")
    }

    @ViewBuilder private func slot(_ kind: ModulaMascotKind?) -> some View {
        let shape = RoundedRectangle(cornerRadius: ModulaRadius.medium, style: .continuous)
        Button { editing = true } label: {
            VStack(spacing: 4) {
                if let kind {
                    MolibooEmptyArt(kind: kind, mood: kind.rawValue == companionRaw ? .happy : .idle, size: 24, animated: false)
                        .frame(height: 52)
                    Text(kind.name).font(.caption.weight(.semibold)).lineLimit(1)
                } else {
                    Image(systemName: "plus")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(app.appearance.liveAccent)
                        .frame(height: 52)
                    Text("Empty slot").font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .modulaGlass(in: shape, interactive: true)
        }
        .buttonStyle(ModulaPressStyle(scale: 0.96, haptic: nil))
        .accessibilityLabel(kind.map { "Showcase: \($0.name)" } ?? "Empty showcase slot")
    }
}

/// Pick up to three Moliboos. Premium kinds are listed with a lock and cannot be picked unless entitled.
struct ProfileShowcasePicker: View {
    @Binding var selection: [ModulaMascotKind]
    @Environment(\.dismiss) private var dismiss
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private let columns = [GridItem(.adaptive(minimum: 92), spacing: 10)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(ModulaMascotKind.allCases) { kind in
                        cell(kind)
                    }
                }
                .padding(16)
            }
            .modulaCanvas()
            .navigationTitle("Showcase \(selection.count)/\(ProfileShowcaseStore.slots)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .padding(.horizontal, 12)
                        .modulaAccentCTA()
                }
            }
        }
    }

    private func cell(_ kind: ModulaMascotKind) -> some View {
        let usable = MascotEntitlements.canUse(kind)
        let index = selection.firstIndex(of: kind)
        let shape = RoundedRectangle(cornerRadius: ModulaRadius.medium, style: .continuous)
        return Button { toggle(kind) } label: {
            VStack(spacing: 4) {
                MolibooEmptyArt(kind: usable ? kind : nil, mood: index != nil ? .happy : .idle, size: 22, animated: false)
                    .frame(height: 48)
                    .opacity(usable ? 1 : 0.35)
                Text(kind.name).font(.caption.weight(.semibold)).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .modulaGlass(in: shape, interactive: usable, tint: index != nil ? app.appearance.liveAccent.opacity(0.22) : nil)
            .overlay(alignment: .topTrailing) {
                if let index {
                    Text("\(index + 1)")
                        .font(.caption2.weight(.bold)).foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(app.appearance.liveAccent))
                        .padding(6)
                } else if !usable {
                    Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.secondary).padding(8)
                }
            }
        }
        .buttonStyle(ModulaPressStyle(scale: 0.95, haptic: nil))
        .disabled(!usable)
        .accessibilityLabel(usable ? kind.name : "\(kind.name), Premium")
        .accessibilityAddTraits(index != nil ? .isSelected : [])
    }

    private func toggle(_ kind: ModulaMascotKind) {
        HapticEngine.shared.play(.selection)
        withAnimation(ModulaSurfaceMotion.animation(reduce: ModulaEffectGate.reduceMotion(systemReduceMotion))) {
            if let i = selection.firstIndex(of: kind) {
                selection.remove(at: i)
            } else if selection.count < ProfileShowcaseStore.slots {
                selection.append(kind)
            } else {
                selection.removeFirst()
                selection.append(kind)
            }
        }
    }
}

// MARK: - Progression (flagged)

/// Profile progression as Greenfield would serve it. There is no producer yet, so the profile passes
/// `nil` and nothing renders; the `profile.progression` flag also keeps it off.
struct ProfileProgression: Hashable, Sendable {
    struct Badge: Identifiable, Hashable, Sendable {
        let id: String
        let title: String
        let symbol: String
        let earnedAt: Date?
    }
    let level: Int
    /// 0...1 progress to the next level.
    let progress: Double
    let badges: [Badge]
}

struct ProfileProgressionCard: View {
    let progression: ProfileProgression
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var shown = false

    var body: some View {
        let accent = app.appearance.liveAccent
        let calm = ModulaEffectGate.reduceMotion(systemReduceMotion)
        HStack(spacing: 14) {
            ZStack {
                Circle().stroke(accent.opacity(0.18), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: shown || calm ? progression.progress : 0)
                    .stroke(accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(progression.level)").font(.headline.monospacedDigit())
            }
            .frame(width: 54, height: 54)
            .accessibilityElement()
            .accessibilityLabel("Level \(progression.level), \(Int(progression.progress * 100)) percent to next level")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(progression.badges) { badge in
                        Label(badge.title, systemImage: badge.symbol)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10).frame(height: 30)
                            .modulaGlass(in: Capsule(), interactive: false)
                            .opacity(badge.earnedAt == nil ? 0.45 : 1)
                    }
                }
            }
        }
        .padding(12)
        .modulaGlass(in: RoundedRectangle(cornerRadius: ModulaRadius.medium, style: .continuous), interactive: false)
        .onAppear { withAnimation(calm ? nil : .spring(response: 0.8, dampingFraction: 0.9)) { shown = true } }
    }
}
