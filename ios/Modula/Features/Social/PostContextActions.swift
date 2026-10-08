import SwiftUI
import UIKit

/// Ownership-aware post context actions built on ModulaContextAction primitives.
enum PostContextActions {
    static func menu(
        isOwn: Bool,
        saved: Bool,
        capabilities: PostBackendCapabilities = .production
    ) -> [ModulaContextAction] {
        // Same action set as the Liquid Glass PostMenuOverlay (accessibility / VoiceOver).
        if isOwn {
            var items: [ModulaContextAction] = [
                .init(id: "share", title: "Share", systemImage: "square.and.arrow.up"),
                .init(id: "copy-link", title: "Copy link", systemImage: "link"),
            ]
            if capabilities.save {
                items.append(.init(id: "save", title: saved ? "Saved" : "Save", systemImage: saved ? "bookmark.fill" : "bookmark"))
                items.append(.init(id: "save-collection", title: "Collection", systemImage: "rectangle.stack.badge.plus"))
            }
            items.append(.init(id: "interactions", title: "View Post Interactions", systemImage: "chart.bar"))
            if capabilities.editOwnPost { items.append(.init(id: "edit-post", title: "Edit post", systemImage: "pencil")) }
            if capabilities.deleteOwnPost {
                items.append(.init(id: "delete", title: "Delete post", systemImage: "trash", role: .destructive))
            }
            return items
        }
        return [
            .init(id: "share", title: "Share", systemImage: "square.and.arrow.up"),
            .init(id: "copy-link", title: "Copy link", systemImage: "link"),
            .init(id: "send-message", title: "Send in message", systemImage: "paperplane"),
            .init(id: "save", title: saved ? "Remove from Saved" : "Save", systemImage: saved ? "bookmark.fill" : "bookmark"),
            .init(id: "save-collection", title: "Add to collection", systemImage: "rectangle.stack.badge.plus"),
            .init(id: "not-interested", title: "Not interested in this post", systemImage: "eye.slash"),
            .init(id: "hide", title: "Hide post", systemImage: "rectangle.slash"),
            .init(id: "notify", title: "Turn on notifications", systemImage: "bell"),
            .init(id: "report", title: "Report post", systemImage: "flag", role: .destructive),
            .init(id: "spam", title: "Mark as spam", systemImage: "exclamationmark.octagon", role: .destructive),
            .init(id: "community-note", title: "Request Community Note", systemImage: "megaphone"),
        ]
    }

    /// Legacy helper kept for ImmersivePostContextPanel stubs; routes to the shared X set.
    static func immersivePanel(
        isOwn: Bool,
        saved: Bool,
        capabilities: PostBackendCapabilities = .production
    ) -> [ModulaContextAction] {
        menu(isOwn: isOwn, saved: saved, capabilities: capabilities)
    }

    /// X-style author section (@handle: Follow, Add to lists, Mute, Block).
    static func authorActions(capabilities: PostBackendCapabilities = .production) -> [ModulaContextAction] {
        var items: [ModulaContextAction] = [
            .init(id: "follow-author", title: "Follow", systemImage: "person.badge.plus"),
            .init(id: "lists-author", title: "Add to lists", systemImage: "list.bullet.rectangle")
        ]
        if capabilities.muteAuthor {
            items.append(.init(id: "mute-author", title: "Mute", systemImage: "speaker.slash"))
        }
        items.append(.init(id: "block-author", title: "Block", systemImage: "hand.raised", role: .destructive, accessibilityLabel: "Block author"))
        return items
    }

    static func railContextActions(
        saved: Bool,
        capabilities: PostBackendCapabilities = .production
    ) -> [ModulaContextAction] {
        // Same set as PostMenuOverlay — never the old light system-menu items.
        menu(isOwn: false, saved: saved, capabilities: capabilities)
    }

    static func commentMenu(
        isOwn: Bool,
        capabilities: PostBackendCapabilities = .production
    ) -> [ModulaContextAction] {
        if isOwn {
            var items: [ModulaContextAction] = [
                .init(id: "copy", title: "Copy", systemImage: "doc.on.doc")
            ]
            if capabilities.commentsDelete {
                items.append(.init(id: "delete", title: "Delete", systemImage: "trash", role: .destructive))
            }
            return items
        }
        var items: [ModulaContextAction] = [
            .init(id: "copy", title: "Copy", systemImage: "doc.on.doc")
        ]
        if capabilities.muteAuthor {
            items.append(.init(id: "mute-author", title: "Mute Author", systemImage: "speaker.slash"))
        }
        if capabilities.reportComment {
            items.append(.init(id: "report", title: "Report", systemImage: "exclamationmark.bubble", role: .destructive))
        }
        return items
    }
}


// MARK: - Post options (same visual language as tab-bar accessory Options Menu)

/// Shared post-options content for `Menu` / `contextMenu`.
/// Matches `ShellAccessoryHost.moreMenu`: native Liquid Glass card, accent-tinted SF Symbols.
/// Top level stays at 5–6 rows; everything else lives one level down in submenus.
/// Do not replace with a custom dark panel.
struct PostOptionsMenuContent: View {
    let post: SocialPost
    var isOwn: Bool
    var capabilities: PostBackendCapabilities = .production
    var onSelect: (String) -> Void

    private var handle: String? { post.author?.handle }

    var body: some View {
        Menu {
            Button("Share via…", systemImage: "square.and.arrow.up") { onSelect("share") }
            Button("Copy link", systemImage: "link") { onSelect("copy-link") }
            Button("Send in message", systemImage: "paperplane") { onSelect("send-message") }
        } label: {
            Label("Share", systemImage: "square.and.arrow.up")
        }

        if !isOwn || capabilities.save {
            Menu {
                Button(post.saved ? "Remove from Saved" : "Save", systemImage: post.saved ? "bookmark.slash" : "bookmark") {
                    onSelect("save")
                }
                Button("Add to collection…", systemImage: "rectangle.stack.badge.plus") { onSelect("save-collection") }
            } label: {
                Label(post.saved ? "Saved" : "Save", systemImage: post.saved ? "bookmark.fill" : "bookmark")
            }
        }

        if isOwn {
            Button("Post interactions", systemImage: "chart.bar") { onSelect("interactions") }
            if capabilities.editOwnPost {
                Button("Edit post", systemImage: "pencil") { onSelect("edit-post") }
            }
            if capabilities.deleteOwnPost {
                Section {
                    Button("Delete post", systemImage: "trash", role: .destructive) { onSelect("delete") }
                }
            }
        } else {
            if let handle {
                Menu {
                    Button("Follow", systemImage: "person.badge.plus") { onSelect("follow-author") }
                    if capabilities.muteAuthor {
                        Button("Mute", systemImage: "speaker.slash") { onSelect("mute-author") }
                    }
                    Button("Add to lists", systemImage: "list.bullet.rectangle") { onSelect("lists-author") }
                    Button("Block", systemImage: "hand.raised", role: .destructive) { onSelect("block-author") }
                } label: {
                    Label("@\(handle)", systemImage: "person.crop.circle")
                }
            }
            Menu {
                Button("Not interested in this post", systemImage: "eye.slash") { onSelect("not-interested") }
                Button("Hide post", systemImage: "rectangle.slash") { onSelect("hide") }
                Button("Turn on notifications", systemImage: "bell") { onSelect("notify") }
            } label: {
                Label("Not interested", systemImage: "eye.slash")
            }
            Section {
                Menu {
                    Button("Report post", systemImage: "flag", role: .destructive) { onSelect("report") }
                    Button("Mark as spam", systemImage: "exclamationmark.octagon", role: .destructive) { onSelect("spam") }
                    Button("Request Community Note", systemImage: "megaphone") { onSelect("community-note") }
                } label: {
                    Label("Report", systemImage: "flag")
                }
            }
        }
    }
}

/// "…" control that opens the same native Options-style Menu as the tab-bar accessory.
struct PostOptionsMenuButton<Label: View>: View {
    let post: SocialPost
    var isOwn: Bool
    var capabilities: PostBackendCapabilities = .production
    var onSelect: (String) -> Void
    @ViewBuilder var label: () -> Label
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        Menu {
            PostOptionsMenuContent(
                post: post,
                isOwn: isOwn,
                capabilities: capabilities,
                onSelect: { id in
                    // Nested Menu dismiss can race; hop to next turn like other shell Menus.
                    DispatchQueue.main.async { onSelect(id) }
                }
            )
        } label: {
            label()
        }
        .menuStyle(.button)
        .menuOrder(.fixed)
        .buttonStyle(.plain)
        .accessibilityLabel("More actions")
        .accessibilityHint("Shows post options")
    }
}


// MARK: - Liquid Glass post menu (morphs out of its source)

/// What the glass menu can call back into on the card that opened it.
struct PostMenuHooks {
    var onSave: () -> Void
    var onShare: () -> Void
    /// Non-nil only when on-device translation applies to this post.
    var onTranslate: (() -> Void)? = nil
    /// Host-specific handling (Home's edit/delete); everything else runs in `PostMenuExecutor`.
    var onContextAction: ((ModulaContextAction) -> Void)? = nil
}

struct PostMenuRequest: Identifiable {
    let id = UUID()
    let post: SocialPost
    let isOwn: Bool
    /// Global rect the panel grows out of: the "…" button, the rail touch, or the long-press point.
    let anchor: CGRect
    let hooks: PostMenuHooks
}

/// Single presenter for the post menu, drawn once above the whole shell (`PostMenuHost`).
/// Sources call `present`, then `track`/`release` while the opening finger stays down.
@MainActor @Observable
final class PostMenuCenter {
    static let shared = PostMenuCenter()

    private(set) var request: PostMenuRequest?
    /// "<panel>.<item>" under the finger.
    private(set) var highlighted: String?
    private(set) var tracking = false
    /// Which panel's rows the finger can land on ("main" / "user").
    @ObservationIgnored var activePanel = "main"
    @ObservationIgnored var itemFrames: [String: CGRect] = [:]
    @ObservationIgnored var onRelease: ((String) -> Void)?
    /// Video scrub / speed long-press set this so the card's long-press doesn't also open the menu.
    @ObservationIgnored var suppressLongPressUntil = Date.distantPast

    var isPresented: Bool { request != nil }
    var longPressSuppressed: Bool { Date() < suppressLongPressUntil }

    func present(_ request: PostMenuRequest, tracking: Bool = false) {
        guard self.request == nil else { return }
        itemFrames = [:]
        activePanel = "main"
        highlighted = nil
        self.tracking = tracking
        self.request = request
        HapticEngine.shared.play(.contextOpen)
    }

    /// Finger moved (global coordinates). Highlight + tick when it crosses onto a new row.
    func track(_ point: CGPoint) {
        guard request != nil, tracking else { return }
        let prefix = activePanel + "."
        let hit = itemFrames.first { $0.key.hasPrefix(prefix) && $0.value.contains(point) }?.key
        if hit != highlighted {
            highlighted = hit
            if hit != nil { HapticEngine.shared.play(.selection) }
        }
    }

    /// Finger lifted: pick the highlighted row; otherwise the menu stays open for taps.
    func release() {
        guard tracking else { return }
        tracking = false
        guard let key = highlighted else { return }
        highlighted = nil
        let id = key.split(separator: ".", maxSplits: 1).last.map(String.init) ?? key
        onRelease?(id)
    }

    func clearHighlight() { highlighted = nil }

    func finishClose() {
        request = nil
        highlighted = nil
        tracking = false
        itemFrames = [:]
        onRelease = nil
    }
}

/// Mount once at the root, above tabs and chrome.
struct PostMenuHost: View {
    /// Native Options-style Menu/contextMenu only — no custom dark morph overlay.
    var body: some View { EmptyView() }
}

private enum PostMenuStage: Equatable { case main, user, confirmReport, confirmBlock, confirmDelete }

private struct PostMenuOverlay: View {
    let request: PostMenuRequest
    let center: PostMenuCenter

    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @State private var progress: CGFloat = 0
    @State private var contentShown = false
    @State private var backdropShown = false
    @State private var stage: PostMenuStage = .main
    @State private var mainSize: CGSize = .zero
    @State private var userSize: CGSize = .zero
    @State private var dragOffset: CGSize = .zero
    @State private var closing = false
    @State private var dwell: Task<Void, Never>?
    @Namespace private var highlightSpace
    @AccessibilityFocusState private var focused: Bool

    private var calm: Bool { ModulaEffectGate.reduceMotion(systemReduceMotion) }
    private var opaque: Bool { systemReduceTransparency || app.appearance.contrastTransparency == .reduceTransparency }
    private let panelWidth: CGFloat = 292
    private var handle: String? { request.post.author?.handle }

    var body: some View {
        GeometryReader { geo in
            let origin = geo.frame(in: .global).origin
            let anchor = request.anchor.offsetBy(dx: -origin.x, dy: -origin.y)
            let target = targetRect(anchor: anchor, height: mainSize.height, bounds: geo.size)
            let p: CGFloat = calm ? 1 : progress
            let morph = Self.lerp(anchor, target, p)
            let radius = Self.lerp(min(anchor.width, anchor.height) / 2, 28, p)
            ZStack(alignment: .topLeading) {
                backdrop
                // Glass body: starts as the source's shape and grows into the panel.
                glassShape(radius: radius)
                    .frame(width: max(morph.width, 1), height: max(morph.height, 1))
                    .position(x: morph.midX, y: morph.midY)
                    .offset(dragOffset)
                    .opacity(calm ? (contentShown ? 1 : 0) : 1)
                mainContent
                    .frame(width: target.width)
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { measured($0) }
                    .scaleEffect(calm ? 1 : Self.lerp(0.86, 1, p), anchor: Self.unit(of: anchor, in: target))
                    .opacity(contentShown ? (stage == .user ? 0.4 : 1) : 0)
                    .blur(radius: stage == .user && !calm ? 1.5 : 0)
                    .frame(width: max(morph.width, 1), height: max(morph.height, 1), alignment: Self.alignment(anchor: anchor, target: target))
                    .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                    .position(x: morph.midX, y: morph.midY)
                    .offset(dragOffset)
                    .allowsHitTesting(stage != .user)
                if stage == .user {
                    userPanel
                        .frame(width: target.width)
                        .fixedSize(horizontal: false, vertical: true)
                        .onGeometryChange(for: CGSize.self) { $0.size } action: { userSize = $0 }
                        .background(glassShape(radius: 26))
                        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                        .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
                        .position(userPosition(target: target, bounds: geo.size))
                        .offset(dragOffset)
                        .transition(calm ? .opacity : .asymmetric(
                            insertion: .scale(scale: 0.6, anchor: .top).combined(with: .opacity).combined(with: .offset(y: -40)),
                            removal: .scale(scale: 0.8, anchor: .top).combined(with: .opacity)
                        ))
                }
            }
            .simultaneousGesture(swipeToDismiss)
        }
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
        .animation(calm ? .easeOut(duration: 0.15) : .snappy(duration: 0.16), value: center.highlighted)
        .onAppear {
            center.onRelease = { id in select(id) }
            withAnimation(.easeOut(duration: 0.2)) { backdropShown = true }
        }
        .onChange(of: center.highlighted) { _, key in
            // Dwell on @handle while dragging to open the nested panel.
            dwell?.cancel()
            guard key == "main.handle" else { return }
            dwell = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(420))
                guard !Task.isCancelled, center.highlighted == "main.handle" else { return }
                select("handle")
            }
        }
        .onChange(of: stage) { _, newStage in
            center.activePanel = newStage == .user ? "user" : "main"
            center.clearHighlight()
        }
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { close() }
    }

    // MARK: Pieces

    private var backdrop: some View {
        ZStack {
            if opaque {
                Color.black.opacity(0.5)
            } else {
                Rectangle().fill(.ultraThinMaterial)
                Color.black.opacity(0.22)
            }
        }
        .opacity(backdropShown ? 1 : 0)
        .contentShape(Rectangle())
        .onTapGesture { close() }
        .accessibilityLabel("Dismiss menu")
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private func glassShape(radius: CGFloat) -> some View {
        // Target: dark frosted Liquid Glass (never the light system Menu material).
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if opaque {
            shape.fill(Color(white: 0.11))
                .overlay(shape.strokeBorder(.white.opacity(0.14), lineWidth: 0.6))
        } else {
            ZStack {
                shape.fill(.ultraThinMaterial)
                shape.fill(
                    LinearGradient(
                        colors: [Color(white: 0.14).opacity(0.92), Color(white: 0.08).opacity(0.88)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                shape.fill(
                    LinearGradient(
                        colors: [.white.opacity(0.10), .clear],
                        startPoint: .top,
                        endPoint: UnitPoint(x: 0.5, y: 0.35)
                    )
                )
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(.white.opacity(0.16), lineWidth: 0.6))
            .shadow(color: .black.opacity(0.45), radius: 32, y: 16)
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        switch stage {
        case .main, .user: mainItems
        case .confirmReport: reportConfirm
        case .confirmBlock: blockConfirm
        case .confirmDelete: deleteConfirm
        }
    }

    private var caps: PostBackendCapabilities { app.postActions.capabilities }

    private var mainItems: some View {
        VStack(alignment: .leading, spacing: 0) {
            quickTiles
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .padding(.bottom, 2)
                .zIndex(1)
            // Soft top fade under the tile row (X progressive-blur feel).
            ZStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 0) {
                    if request.isOwn {
                        row("interactions", "View Post Interactions", "chart.bar")
                        if request.hooks.onTranslate != nil { row("translate", "Translate post", "translate") }
                        if caps.editOwnPost { row("edit-post", "Edit post", "pencil") }
                        if caps.deleteOwnPost { row("delete", "Delete post", "trash", destructive: true) }
                    } else {
                        row("not-interested", "Not interested in this post", "eye.slash")
                        row("interactions", "View Post Interactions", "chart.bar")
                        row("notify", "Turn on notifications", "bell")
                        row("hide", "Hide post", "rectangle.slash")
                        row("report", "Report post", "flag", destructive: true)
                        row("spam", "Mark as spam", "exclamationmark.circle")
                        row("community-note", "Request Community Note", "megaphone")
                        if let handle {
                            Divider().overlay(.white.opacity(0.14)).padding(.horizontal, 18).padding(.vertical, 3)
                            row("handle", "@\(handle)", nil, trailing: "chevron.right", emphasized: true)
                        }
                    }
                }
                LinearGradient(colors: [Color.black.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 18)
                    .allowsHitTesting(false)
            }
        }
        .padding(.bottom, 10)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Post actions")
    }

    private var quickTiles: some View {
        HStack(spacing: 6) {
            tile("share", "Share", "square.and.arrow.up")
            tile("copy-link", "Copy link", "link")
            tile("save", request.post.saved ? "Saved" : "Save", request.post.saved ? "bookmark.fill" : "bookmark")
            tile("save-collection", "Collection", "rectangle.stack.badge.plus")
        }
    }

    private var userPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { select("user-back") } label: {
                HStack {
                    Text("@\(handle ?? "")").font(.headline)
                    Spacer()
                    Image(systemName: "chevron.down").font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 20)
                .frame(minHeight: 56)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to post actions")
            Divider().overlay(.white.opacity(0.14)).padding(.horizontal, 18)
            row("follow-author", "Follow", "person.badge.plus", panel: "user")
            row("lists-author", "Add/remove from Lists", "list.bullet.rectangle", panel: "user")
            if caps.muteAuthor { row("mute-author", "Mute", "speaker.slash", panel: "user") }
            row("block-author", "Block", "nosign", destructive: true, panel: "user")
        }
        .padding(.bottom, 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Actions for @\(handle ?? "author")")
    }

    private var reportConfirm: some View {
        VStack(alignment: .leading, spacing: 0) {
            confirmHeader(symbol: "flag.fill", title: "Report post", message: "Why are you reporting this? @\(handle ?? "the author") won’t be told who reported it.")
            ForEach(Self.reportReasons, id: \.0) { reason in
                row("report:\(reason.0)", reason.1, nil)
            }
            row("cancel", "Cancel", nil, emphasized: true)
        }
        .padding(.bottom, 8)
    }

    private var blockConfirm: some View {
        VStack(alignment: .leading, spacing: 0) {
            confirmHeader(symbol: "nosign", title: "Block @\(handle ?? "author")?", message: "They won’t be able to follow you or see your posts, and you won’t see theirs.")
            row("block-confirmed", "Block", "nosign", destructive: true)
            row("cancel", "Cancel", nil, emphasized: true)
        }
        .padding(.bottom, 8)
    }

    private var deleteConfirm: some View {
        VStack(alignment: .leading, spacing: 0) {
            confirmHeader(symbol: "trash.fill", title: "Delete post?", message: "This can’t be undone.")
            row("delete-confirmed", "Delete", "trash", destructive: true)
            row("cancel", "Cancel", nil, emphasized: true)
        }
        .padding(.bottom, 8)
    }

    private func confirmHeader(symbol: String, title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Color.red)
                .symbolEffect(.bounce, value: stage)
            Text(title).font(.headline).foregroundStyle(.primary)
            Text(message).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 8)
        .accessibilityElement(children: .combine)
    }

    static let reportReasons: [(String, String)] = [
        ("spam", "Spam"),
        ("harassment", "Harassment or bullying"),
        ("hate", "Hate speech"),
        ("misinformation", "Misleading information"),
        ("violence", "Violence or threats"),
        ("other", "Something else"),
    ]

    private func row(_ id: String, _ title: String, _ symbol: String?, destructive: Bool = false, trailing: String? = nil, emphasized: Bool = false, panel: String = "main") -> some View {
        let key = "\(panel).\(id)"
        let lit = center.highlighted == key
        return Button { select(id) } label: {
            HStack(spacing: 14) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 19))
                        .frame(width: 26)
                        .symbolEffect(.bounce, value: lit)
                }
                Text(title)
                    .font(emphasized ? .body.weight(.semibold) : .body)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if let trailing {
                    Image(systemName: trailing).font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(destructive ? Color(red: 1, green: 0.33, blue: 0.3) : Color.primary)
            .padding(.horizontal, 20)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .contentShape(Rectangle())
            .background {
                if lit {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.white.opacity(0.14))
                        .padding(.horizontal, 8)
                        .matchedGeometryEffect(id: "highlight", in: highlightSpace)
                }
            }
        }
        .buttonStyle(PostMenuRowStyle())
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { center.itemFrames[key] = $0 }
        .onDisappear { center.itemFrames[key] = nil }
        .accessibilityLabel(title)
        .accessibilityAddTraits(lit ? .isSelected : [])
    }

    private func tile(_ id: String, _ title: String, _ symbol: String) -> some View {
        let key = "main.\(id)"
        let lit = center.highlighted == key
        return Button { select(id) } label: {
            VStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .medium))
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: lit)
                Text(title)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.white.opacity(lit ? 0.22 : 0.10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
                    )
            )
            .scaleEffect(lit && !calm ? 1.06 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(PostMenuRowStyle())
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { center.itemFrames[key] = $0 }
        .onDisappear { center.itemFrames[key] = nil }
        .accessibilityLabel(title)
    }

    // MARK: Behaviour

    private func select(_ id: String) {
        dwell?.cancel()
        let spring: Animation? = calm ? .easeOut(duration: 0.15) : .spring(response: 0.34, dampingFraction: 0.82)
        switch id {
        case "handle":
            HapticEngine.shared.play(.contextOpen)
            withAnimation(spring) { stage = .user }
        case "user-back":
            HapticEngine.shared.play(.selection)
            withAnimation(spring) { stage = .main }
        case "report":
            HapticEngine.shared.play(.warning)
            withAnimation(spring) { stage = .confirmReport }
        case "block-author":
            HapticEngine.shared.play(.warning)
            withAnimation(spring) { stage = .confirmBlock }
        case "delete":
            HapticEngine.shared.play(.warning)
            withAnimation(spring) { stage = .confirmDelete }
        case "cancel":
            HapticEngine.shared.play(.selection)
            withAnimation(spring) { stage = .main }
        default:
            HapticEngine.shared.play(id.hasPrefix("report:") || id == "block-confirmed" || id == "delete-confirmed" ? .warning : .confirmation)
            let request = request
            let app = app
            close { PostMenuExecutor.run(id, request: request, app: app) }
        }
    }

    private func close(then action: (() -> Void)? = nil) {
        guard !closing else { return }
        closing = true
        dwell?.cancel()
        withAnimation(calm ? .easeOut(duration: 0.15) : .spring(response: 0.3, dampingFraction: 0.9)) {
            progress = 0
            contentShown = false
            backdropShown = false
            dragOffset = .zero
            if stage == .user { stage = .main }
        } completion: {
            center.finishClose()
            action?()
        }
    }

    private func measured(_ size: CGSize) {
        let first = mainSize == .zero
        if first {
            mainSize = size
            // Grow out of the source once we know the panel's real height.
            Task { @MainActor in
                withAnimation(calm ? .easeOut(duration: 0.18) : .spring(response: 0.42, dampingFraction: 0.8)) { progress = 1 }
                withAnimation(calm ? .easeOut(duration: 0.18) : .easeOut(duration: 0.2).delay(0.06)) { contentShown = true }
                focused = true
            }
        } else {
            withAnimation(calm ? nil : .spring(response: 0.34, dampingFraction: 0.85)) { mainSize = size }
        }
    }

    private var swipeToDismiss: some Gesture {
        DragGesture(minimumDistance: 14)
            .onChanged { value in
                guard !center.tracking, !closing else { return }
                dragOffset = CGSize(width: value.translation.width * 0.25, height: value.translation.height * 0.45)
            }
            .onEnded { value in
                guard !center.tracking, !closing else { return }
                if abs(value.translation.height) > 70 || abs(value.translation.width) > 90
                    || abs(value.predictedEndTranslation.height) > 220 {
                    close()
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { dragOffset = .zero }
                }
            }
    }

    // MARK: Geometry

    private func targetRect(anchor: CGRect, height: CGFloat, bounds: CGSize) -> CGRect {
        let insets = Self.windowInsets
        let width = min(panelWidth, bounds.width - 24)
        let margin: CGFloat = 12
        var x = anchor.midX > bounds.width / 2 ? anchor.maxX - width + 4 : anchor.minX - 4
        x = min(max(x, margin), bounds.width - width - margin)
        let top = insets.top + 8
        let bottom = bounds.height - insets.bottom - 8
        let y: CGFloat
        if anchor.maxY + 8 + height <= bottom {
            y = anchor.maxY + 8
        } else if anchor.minY - 8 - height >= top {
            y = anchor.minY - 8 - height
        } else {
            y = max(top, bottom - height)
        }
        return CGRect(x: x, y: y, width: width, height: max(height, 1))
    }

    private func userPosition(target: CGRect, bounds: CGSize) -> CGPoint {
        let insets = Self.windowInsets
        let height = max(userSize.height, 1)
        let width = target.width
        let x = min(max(target.minX - 10, 12), bounds.width - width - 12) + width / 2
        var maxY = target.maxY + 16
        maxY = min(maxY, bounds.height - insets.bottom - 8)
        let y = max(insets.top + 8 + height / 2, maxY - height / 2)
        return CGPoint(x: x, y: y)
    }

    private static var windowInsets: UIEdgeInsets {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        return scene?.keyWindow?.safeAreaInsets ?? UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
    }

    private static func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }

    private static func lerp(_ a: CGRect, _ b: CGRect, _ t: CGFloat) -> CGRect {
        CGRect(x: lerp(a.minX, b.minX, t), y: lerp(a.minY, b.minY, t), width: lerp(a.width, b.width, t), height: lerp(a.height, b.height, t))
    }

    private static func unit(of anchor: CGRect, in target: CGRect) -> UnitPoint {
        guard target.width > 0, target.height > 0 else { return .center }
        return UnitPoint(
            x: min(max((anchor.midX - target.minX) / target.width, 0), 1),
            y: min(max((anchor.midY - target.minY) / target.height, 0), 1)
        )
    }

    private static func alignment(anchor: CGRect, target: CGRect) -> Alignment {
        let horizontal: HorizontalAlignment = anchor.midX > target.midX ? .trailing : .leading
        let vertical: VerticalAlignment = anchor.midY > target.midY ? .bottom : .top
        return Alignment(horizontal: horizontal, vertical: vertical)
    }
}

private struct PostMenuRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.white.opacity(configuration.isPressed ? 0.12 : 0))
                    .padding(.horizontal, 8)
            )
    }
}

/// Runs a picked menu item. Uses existing endpoints only; anything the server lacks is a toast.
@MainActor
enum PostMenuExecutor {
    static func run(_ id: String, request: PostMenuRequest, app: AppEnvironment) {
        let post = request.post
        let hooks = request.hooks
        switch id {
        case "share":
            hooks.onShare()
        case "copy-link":
            UIPasteboard.general.string = post.shareURL.absoluteString
            app.navigation.flash("Link copied", symbol: "link")
        case let value where value.hasPrefix("react:"):
            let reaction = SocialReaction(parsing: String(value.dropFirst("react:".count)))
            let current = app.posts.resolved(post)
            let active = current.viewerReaction ?? (current.liked ? .like : nil)
            let next: SocialReaction? = active == reaction ? nil : reaction
            if next != nil {
                ModulaMascotEvent.post(.like)
                ModulaHapticTexture.play(.like)
            }
            Task {
                await app.postActions.setReaction(current, reaction: next)
                app.home.syncVisibleEngagement()
            }
        case "send-message":
            // No "attach post to DM" endpoint yet: copy the link and open a new message.
            UIPasteboard.general.string = post.shareURL.absoluteString
            if app.messaging.capabilities.send {
                app.navigation.push(.messages(.new))
                app.navigation.flash("Link copied — paste it into your message", symbol: "paperplane")
            } else {
                app.navigation.flash("Link copied. Messaging is coming soon", symbol: "paperplane")
            }
        case "save":
            hooks.onSave()
        case "save-collection":
            app.navigation.presented = .collectionPicker(postID: post.id)
        case "translate":
            hooks.onTranslate?()
        case "interactions":
            let caps = app.postActions.capabilities
            if caps.reactionsList {
                app.navigation.push(.post(post.id, .reactions))
            } else if caps.likesList {
                app.navigation.push(.post(post.id, .likes))
            } else {
                app.navigation.flash("Post interactions are coming soon", symbol: "chart.bar")
            }
        case "notify":
            app.navigation.flash("Post notifications are coming soon", symbol: "bell.badge")
        case "community-note":
            app.navigation.flash("Community Notes are coming soon", symbol: "megaphone")
        case "lists-author":
            app.navigation.flash("Lists are coming soon", symbol: "list.bullet.rectangle")
        case "not-interested":
            hide(post, app: app)
            app.navigation.flash("You’ll see fewer posts like this", symbol: "eye.slash")
        case "hide":
            hide(post, app: app)
            app.navigation.flash("Post hidden", symbol: "eye.slash")
        case "report":
            report(post, category: "other", details: "Post \(post.id)", app: app, done: "Thanks, report sent")
        case "spam":
            report(post, category: "spam", details: "Post \(post.id) marked as spam", app: app, done: "Marked as spam")
        case let value where value.hasPrefix("report:"):
            let category = String(value.dropFirst("report:".count))
            report(post, category: category, details: "Post \(post.id)", app: app, done: "Thanks, report sent")
        case "follow-author":
            guard let author = post.author else { return }
            Task {
                if await app.profile.follow(profileID: author.id, handle: author.handle) {
                    HapticEngine.shared.play(.followComplete)
                    app.navigation.flash("Following @\(author.handle)", symbol: "person.badge.plus")
                }
            }
        case "mute-author":
            guard let author = post.author else { return }
            Task {
                if await app.profile.mute(profileID: author.id) {
                    app.navigation.flash("Muted @\(author.handle)", symbol: "speaker.slash")
                }
            }
        case "block-author":
            // Native Menu has no multi-stage confirm; block immediately with toast.
            fallthrough
        case "block-confirmed":
            guard let author = post.author else { return }
            Task {
                if await app.profile.block(profileID: author.id) {
                    hide(post, app: app)
                    app.navigation.flash("Blocked @\(author.handle)", symbol: "nosign")
                }
            }
        case "edit-post":
            if let host = hooks.onContextAction {
                host(ModulaContextAction(id: "edit-post", title: "Edit post"))
            } else {
                app.navigation.open(.post(post.id, .edit))
            }
        case "delete":
            fallthrough
        case "delete-confirmed":
            if let host = hooks.onContextAction {
                host(ModulaContextAction(id: "delete", title: "Delete post", role: .destructive))
            } else {
                Task {
                    if await app.postActions.deletePost(post) { app.home.syncVisibleEngagement() }
                }
            }
        default:
            break
        }
    }

    private static func hide(_ post: SocialPost, app: AppEnvironment) {
        app.postActions.hideLocally(post)
        app.home.syncVisibleEngagement()
    }

    /// Post reports ride the existing profile-report endpoint with the post id in details.
    private static func report(_ post: SocialPost, category: String, details: String, app: AppEnvironment, done: String) {
        guard let author = post.author else { return }
        Task {
            if await app.profile.report(profileID: author.id, category: category, details: details) {
                hide(post, app: app)
                app.navigation.flash(done, symbol: "checkmark.shield")
            }
        }
    }
}

// MARK: - Menu sources

/// Compatibility wrapper: same entry API as before, but opens the native Options-style Menu
/// (tab-bar accessory visual language) instead of the custom dark morph panel.
struct PostMenuButton<Label: View>: View {
    var makeRequest: (CGRect) -> PostMenuRequest
    @ViewBuilder var label: () -> Label
    @Environment(AppEnvironment.self) private var app
    @State private var frame: CGRect = .zero

    var body: some View {
        let request = makeRequest(frame == .zero ? CGRect(x: 0, y: 0, width: 44, height: 44) : frame)
        PostOptionsMenuButton(
            post: request.post,
            isOwn: request.isOwn,
            capabilities: app.postActions.capabilities,
            onSelect: { id in
                PostMenuExecutor.run(id, request: request, app: app)
            },
            label: label
        )
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
    }
}

/// Long-press uses the system context menu — same Liquid Glass card language as the
/// tab-bar accessory Options Menu (not a custom dark panel).
struct PostMenuLongPress: ViewModifier {
    var enabled: Bool = true
    var makeRequest: (CGRect) -> PostMenuRequest
    @Environment(AppEnvironment.self) private var app

    func body(content: Content) -> some View {
        let sample = makeRequest(.zero)
        let caps = app.postActions.capabilities
        let run: (String) -> Void = { id in
            DispatchQueue.main.async {
                PostMenuExecutor.run(id, request: makeRequest(.zero), app: app)
            }
        }
        // Live preview: the post lifts into a glass card; the reaction palette sits on
        // top of the menu, so the opening finger can slide straight onto a reaction
        // (iMessage tapback style) and lift to commit. Empty items (disabled) = no menu,
        // and the content keeps its identity either way.
        content.contextMenu {
            if enabled {
                if caps.like {
                    PostReactionPalette(
                        current: sample.post.viewerReaction ?? (sample.post.liked ? .like : nil),
                        reactions: caps.multiReactions ? SocialReaction.allCases : [.like],
                        onSelect: run
                    )
                }
                PostOptionsMenuContent(
                    post: sample.post,
                    isOwn: sample.isOwn,
                    capabilities: caps,
                    onSelect: run
                )
            }
        } preview: {
            PostLivePreview(post: app.posts.resolved(sample.post), accent: app.appearance.accent.color)
        }
    }
}

/// Horizontal reaction row at the top of the long-press menu. Uses the system palette
/// style so drag-to-select works like any other menu item.
struct PostReactionPalette: View {
    var current: SocialReaction?
    var reactions: [SocialReaction]
    var onSelect: (String) -> Void

    var body: some View {
        ControlGroup {
            ForEach(reactions, id: \.self) { reaction in
                Button {
                    onSelect("react:\(reaction.rawValue)")
                } label: {
                    Label(
                        current == reaction ? "Remove \(reaction.accessibilityName)" : reaction.accessibilityName,
                        systemImage: current == reaction ? "checkmark.circle.fill" : reaction.systemImage
                    )
                }
            }
        }
        .controlGroupStyle(.palette)
    }
}

/// Context-menu preview: a compact glass card of the post (author, text, first image,
/// engagement). Self-contained — no app environment needed in the preview host.
struct PostLivePreview: View {
    let post: SocialPost
    var accent: Color

    var body: some View {
        let media = post.media.first
        let imageURL = media.flatMap { $0.thumbnailURL ?? $0.previewURL ?? ($0.isVideo ? nil : $0.url) }
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Circle()
                    .fill(accent.gradient)
                    .frame(width: 34, height: 34)
                    .overlay {
                        Text(String((post.author?.displayName ?? "?").prefix(1)).uppercased())
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                    }
                VStack(alignment: .leading, spacing: 1) {
                    Text(post.author?.displayName ?? "Post")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    if let handle = post.author?.handle {
                        Text("@\(handle) · \(post.createdAt.formatted(.relative(presentation: .named)))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            if let text = post.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                Text(text)
                    .font(.callout)
                    .lineLimit(imageURL == nil ? 8 : 3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let imageURL {
                AsyncImage(url: imageURL) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        Rectangle().fill(accent.opacity(0.18))
                    }
                }
                .frame(height: 210)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    if media?.isVideo == true {
                        Image(systemName: "play.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(7)
                            .background(.ultraThinMaterial, in: Circle())
                            .padding(8)
                    }
                }
            }
            HStack(spacing: 14) {
                Label("\(max(post.likeCount, post.engagement.reactionCount))", systemImage: post.viewerReaction?.systemImage ?? (post.liked ? "heart.fill" : "heart"))
                    .foregroundStyle(post.liked || post.viewerReaction != nil ? accent : .secondary)
                Label("\(post.replyCount)", systemImage: "bubble.right")
                if post.saved { Label("Saved", systemImage: "bookmark.fill") }
                Spacer(minLength: 0)
            }
            .font(.caption.weight(.semibold).monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 330)
        .background {
            ZStack {
                Rectangle().fill(.regularMaterial)
                LinearGradient(colors: [accent.opacity(0.16), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0.06)], startPoint: .top, endPoint: .bottom), lineWidth: 0.8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

extension View {
    func postMenuLongPress(enabled: Bool = true, makeRequest: @escaping (CGRect) -> PostMenuRequest) -> some View {
        modifier(PostMenuLongPress(enabled: enabled, makeRequest: makeRequest))
    }
}
