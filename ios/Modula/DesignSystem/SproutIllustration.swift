import SwiftUI

/// Small Sprout poses for empty states, onboarding and module categories.
///
/// Each pose is a complete character with padding. Sticker grids and any image
/// whose subject runs off the canvas are not part of this set.
enum SproutIllustration: String, CaseIterable, Identifiable, Sendable {
    case finance
    case crypto
    case science
    case builder
    case rewards
    case modules
    case painter
    case doctor
    case ai

    var id: String { rawValue }

    var assetName: String {
        switch self {
        case .finance: "SproutFinance"
        case .crypto: "SproutCrypto"
        case .science: "SproutScience"
        case .builder: "SproutBuilder"
        case .rewards: "SproutRewards"
        case .modules: "SproutModules"
        case .painter: "SproutPainter"
        case .doctor: "SproutDoctor"
        case .ai: "SproutAI"
        }
    }

    /// Whole-word match. Substrings such as the "ai" inside "available" do not count.
    static func matching(text: String) -> SproutIllustration? {
        let tokens = Set(text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
        func has(_ words: Set<String>) -> Bool { !tokens.isDisjoint(with: words) }
        if has(["crypto", "bitcoin", "ethereum", "web3"]) { return .crypto }
        if has(["finance", "financial", "money", "wallet", "banking", "forex", "budget", "payout", "payouts"]) { return .finance }
        if has(["science", "scientific", "chemistry", "biology", "laboratory", "lab", "research"]) { return .science }
        if has(["health", "medical", "medicine", "doctor", "clinic", "wellness"]) { return .doctor }
        if has(["ai", "nodus", "intelligence"]) { return .ai }
        if has(["art", "artist", "design", "designer", "paint", "painter", "creative"]) { return .painter }
        if has(["reward", "rewards"]) { return .rewards }
        if has(["builder", "developer", "development"]) { return .builder }
        return nil
    }
}

/// One still illustration. It does not animate, so Reduce Motion has nothing to stop.
struct SproutIllustrationView: View {
    var illustration: SproutIllustration
    var height: CGFloat = 168

    var body: some View {
        Image(illustration.assetName)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(maxWidth: .infinity, maxHeight: height)
            .accessibilityHidden(true)
    }
}
