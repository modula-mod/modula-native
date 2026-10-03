import SwiftUI
import UIKit

/// One place that decides *how* a post is shared, following Settings → Sharing:
/// - "Copy link instead of opening sheet" copies the link and confirms with a banner.
/// - "Prefer system share sheet" opens the iOS share sheet.
/// - Otherwise Modula's own share sheet (send in Messages, copy, etc.) opens.
/// "Include @handle in share text" adds the author's handle to the shared text.
@MainActor
enum PostSharing {
    enum Method: Equatable { case copyLink, systemSheet, modulaSheet }

    static func method(
        copyAsLink: Bool = ModulaPreferences.shareCopiesLink,
        preferSystemSheet: Bool = ModulaPreferences.sharePrefersSystemSheet
    ) -> Method {
        if copyAsLink { return .copyLink }
        return preferSystemSheet ? .systemSheet : .modulaSheet
    }

    static func shareText(for post: SocialPost, includeHandle: Bool = ModulaPreferences.shareIncludesHandle) -> String {
        var lines: [String] = []
        if let text = post.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            lines.append(text.count > 180 ? String(text.prefix(177)) + "…" : text)
        }
        if includeHandle, let author = post.author, !author.handle.isEmpty {
            lines.append("— @\(author.handle) on Modula")
        }
        lines.append(post.shareURL.absoluteString)
        return lines.joined(separator: "\n")
    }

    static func share(_ post: SocialPost, app: AppEnvironment) {
        switch method() {
        case .copyLink:
            UIPasteboard.general.string = post.shareURL.absoluteString
            HapticEngine.shared.play(.lightImpact)
            app.navigation.flash("Link copied", symbol: "link")
        case .systemSheet:
            presentSystemSheet(items: [shareText(for: post)])
            HapticEngine.shared.play(.lightImpact)
        case .modulaSheet:
            app.navigation.presented = .universalShare(.post(
                id: post.id,
                authorName: post.author?.displayName,
                excerpt: post.text,
                hasMedia: !post.media.isEmpty
            ))
        }
        Task { await app.postActions.recordShare(post) }
    }

    static func presentSystemSheet(items: [Any]) {
        guard let presenter = topViewController() else { return }
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let popover = controller.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 1, height: 1)
            popover.permittedArrowDirections = []
        }
        presenter.present(controller, animated: true)
    }

    private static func topViewController() -> UIViewController? {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        var top = window?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
