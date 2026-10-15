import SwiftUI
import UIKit

struct ProfileFloatingChrome: View {
    var showsBack: Bool
    var scrollProgress: CGFloat = 0
    var onBack: () -> Void
    var onShare: () -> Void
    var moreActions: [ModulaContextAction]
    var onMore: (ModulaContextAction) -> Void

    var body: some View {
        FloatingHeroControls {
            if showsBack {
                FloatingHeroButton(title: "Back", symbol: "chevron.left", action: onBack)
                    .accessibilityIdentifier("profile.back")
            } else {
                Color.clear
                    .frame(width: ModulaChromeMetrics.iconHit, height: ModulaChromeMetrics.iconHit)
                    .accessibilityHidden(true)
            }
        } trailing: {
            // The only Share/More capsule on Profile — same ModulaTopTrailingChrome metrics/band.
            ModulaShareMoreCapsule(
                onShare: onShare,
                moreActions: moreActions,
                onMore: onMore,
                shareAccessibilityLabel: "Share Profile",
                shareAccessibilityIdentifier: "profile.share",
                moreAccessibilityIdentifier: "profile.more",
                capsuleAccessibilityIdentifier: "profile.share-more.capsule"
            )
        }
        // Parent ignores top safe area so the cover can full-bleed — chrome must
        // clear the status bar / Dynamic Island itself (same band as Home/Product Hub).
        .padding(.top, ProfileFullBleedMetrics.windowSafeAreaTop)
    }
}

enum ProfileFullBleedMetrics {
    /// Cinematic full-bleed cover. Includes status-bar / Dynamic Island inset so media
    /// truly reaches the physical top edge under `.ignoresSafeArea(edges: .top)`.
    static func coverHeight(sizeClass: UserInterfaceSizeClass?, safeAreaTop: CGFloat, accessibility: Bool) -> CGFloat {
        let base: CGFloat = sizeClass == .regular ? 300 : 256
        let adjusted = accessibility ? base - 28 : base
        return adjusted + max(0, safeAreaTop)
    }

    @MainActor
    static var windowSafeAreaTop: CGFloat {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap { $0.windows }
        let window = windows.first(where: { $0.isKeyWindow }) ?? windows.first
        return window?.safeAreaInsets.top ?? 59
    }
}
