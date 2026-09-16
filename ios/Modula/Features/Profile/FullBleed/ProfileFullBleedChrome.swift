import SwiftUI

struct ProfileFloatingChrome: View {
    var showsBack: Bool
    var onBack: () -> Void
    var onShare: () -> Void
    var moreMenu: () -> AnyView

    var body: some View {
        HStack {
            if showsBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 36, height: 36)
                }
                .modulaChrome(in: Circle(), opaque: false)
                .accessibilityLabel("Back")
                .accessibilityIdentifier("profile.back")
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .allowsHitTesting(true)
    }
}

enum ProfileFullBleedMetrics {
    static func coverHeight(sizeClass: UserInterfaceSizeClass?, safeAreaTop: CGFloat, accessibility: Bool) -> CGFloat {
        let base: CGFloat = sizeClass == .regular ? 320 : 286
        let adjusted = accessibility ? max(240, base - 24) : base
        return adjusted + safeAreaTop
    }
}
