import SwiftUI

/// Glossy 2D Moliboo for empty states, the onboarding picker, Search and the Profile showcase.
///
/// Uses the public `ModulaMascotFigure` only (the figure itself is owned by the Moliboo stream).
/// The frame reserves the figure's full canvas plus its draw overscan, so ears, hats and tentacles are
/// never clipped. Premium kinds fall back to Pip unless entitled, so Premium stays gated.
struct MolibooEmptyArt: View {
    var kind: ModulaMascotKind? = nil
    var mood: MascotMood = .idle
    var size: CGFloat = 52
    /// Gentle idle loop. Frozen to a still pose under Reduce Motion (system or Modula's own).
    var animated = true
    @AppStorage(ModulaMascotSettings.kindKey) private var kindRaw = ModulaMascotKind.pip.rawValue
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    static func resolvedKind(_ raw: String) -> ModulaMascotKind {
        guard let k = ModulaMascotKind(rawValue: raw), MascotEntitlements.canUse(k) else { return .pip }
        return k
    }

    private var shown: ModulaMascotKind {
        if let kind, MascotEntitlements.canUse(kind) { return kind }
        return Self.resolvedKind(kindRaw)
    }

    var body: some View {
        let calm = ModulaEffectGate.reduceMotion(systemReduceMotion) || !animated
        let canvas = ModulaMascotFigure.canvas(size)
        let k = shown
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: calm)) { ctx in
            ModulaMascotFigure(
                kind: k,
                pose: calm ? .still(mood) : MascotPose(t: ctx.date.timeIntervalSinceReferenceDate, mood: mood, amp: 0.6),
                size: size
            )
        }
        .frame(width: canvas.width * ModulaMascotFigure.drawOverscan, height: canvas.height * 1.08)
        .accessibilityHidden(true)
    }
}

/// Mood that suits an empty state's context symbol, so the Moliboo "acts out" the empty state.
enum MolibooEmptyMood {
    static func mood(for symbol: String) -> MascotMood {
        let s = symbol.lowercased()
        if s.contains("magnifyingglass") || s.contains("search") { return .curious }
        if s.contains("exclamationmark") || s.contains("wifi") || s.contains("xmark") { return .sad }
        if s.contains("bell") || s.contains("tray") || s.contains("clock") { return .sleepy }
        if s.contains("person") || s.contains("bubble") || s.contains("heart") { return .wave }
        if s.contains("sparkles") || s.contains("star") { return .excited }
        return .idle
    }
}
