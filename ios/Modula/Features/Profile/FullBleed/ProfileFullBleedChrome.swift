import SwiftUI
import UIKit

struct ProfileFloatingChrome: View {
    var showsBack: Bool
    var scrollProgress: CGFloat = 0
    var onBack: () -> Void
    var onShare: () -> Void
    var moreActions: [ModulaContextAction]
    var onMore: (ModulaContextAction) -> Void

    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var opaque: Bool {
        reduceTransparency || app.appearance.contrastTransparency == .reduceTransparency
    }

    var body: some View {
        FloatingHeroControls {
            if showsBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .modulaChrome(in: Circle(), opaque: opaque)
                .accessibilityLabel("Back")
                .accessibilityIdentifier("profile.back")
            } else {
                Color.clear.frame(width: 44, height: 44)
                    .accessibilityHidden(true)
            }
        } trailing: {
            // The only Share/More capsule on Profile — never duplicated in progressive header.
            ProfileShareMoreCapsule(
                onShare: onShare,
                moreActions: moreActions,
                onMore: onMore
            )
        }
        // Parent ignores top safe area so the cover can full-bleed — chrome must
        // clear the status bar / Dynamic Island itself.
        .padding(.top, ProfileFullBleedMetrics.windowSafeAreaTop)
    }
}

enum ProfileFullBleedMetrics {
    /// Cinematic full-bleed cover. Includes status-bar / Dynamic Island inset so media
    /// truly reaches the physical top edge under `.ignoresSafeArea(edges: .top)`.
    static func coverHeight(sizeClass: UserInterfaceSizeClass?, safeAreaTop: CGFloat, accessibility: Bool) -> CGFloat {
        let base: CGFloat = sizeClass == .regular ? 372 : 338
        let adjusted = accessibility ? max(260, base - 28) : base
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
