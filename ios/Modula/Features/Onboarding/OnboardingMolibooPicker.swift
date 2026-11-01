import SwiftUI

/// Onboarding step: choose your first Moliboo from the free starters.
///
/// Writes the same `ModulaMascotSettings.kindKey` the rest of the app reads, so the choice shows up
/// immediately in empty states, the composer and Home. Premium kinds are not offered here.
/// Psychology: endowment effect (a companion you picked feels like yours), and a small,
/// curated set avoids choice overload (Hick's law).
struct OnboardingMolibooPicker: View {
    @AppStorage(ModulaMascotSettings.kindKey) private var kindRaw = ModulaMascotKind.pip.rawValue
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    static let starters: [ModulaMascotKind] = [.pip, .moss, .nimbus, .mochi, .sprout, .echo, .orbit, .wisp]
        .filter { !$0.isPremium }

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 12)]

    var body: some View {
        let calm = ModulaEffectGate.reduceMotion(systemReduceMotion)
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(Self.starters) { kind in
                    let selected = kind.rawValue == kindRaw
                    Button {
                        HapticEngine.shared.play(.selection)
                        withAnimation(ModulaSurfaceMotion.animation(reduce: calm)) { kindRaw = kind.rawValue }
                    } label: {
                        VStack(spacing: 4) {
                            MolibooEmptyArt(kind: kind, mood: selected ? .happy : .idle, size: 30, animated: selected)
                                .frame(height: 66)
                            Text(kind.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .modulaGlass(
                            in: RoundedRectangle(cornerRadius: ModulaRadius.medium + 2, style: .continuous),
                            interactive: true,
                            tint: selected ? app.appearance.liveAccent.opacity(0.35) : nil
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: ModulaRadius.medium + 2, style: .continuous)
                                .strokeBorder(selected ? app.appearance.liveAccent : .clear, lineWidth: 2)
                        }
                        .scaleEffect(selected && !calm ? 1.03 : 1)
                    }
                    .buttonStyle(ModulaPressStyle(scale: 0.95, haptic: nil))
                    .accessibilityLabel("\(kind.name). \(kind.personality)")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityIdentifier("onboarding.moliboo.\(kind.rawValue)")
                }
            }
            if let chosen = ModulaMascotKind(rawValue: kindRaw) {
                Text(chosen.personality)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.85))
                    .contentTransition(.opacity)
                    .accessibilityHidden(true)
            }
        }
    }
}
