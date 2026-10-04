import SwiftUI
import UIKit
import WebKit

// MARK: - Link routing

/// The post a link came from, so the browser can keep it in a bottom sheet with its actions.
struct ModulaBrowserSource {
    var post: SocialPost
    var onLike: () -> Void
    var onComment: () -> Void
    var onRepost: () -> Void
    var onSave: () -> Void
    var onShare: (() -> Void)?
}

private struct ModulaLinkSourceKey: EnvironmentKey {
    static var defaultValue: ModulaBrowserSource? { nil }
}

extension EnvironmentValues {
    var modulaLinkSource: ModulaBrowserSource? {
        get { self[ModulaLinkSourceKey.self] }
        set { self[ModulaLinkSourceKey.self] = newValue }
    }
}

@MainActor
enum ModulaLinkRouter {
    /// OpenURLAction body: web links open in the Modula browser (or hand off to their app).
    static func handle(_ url: URL, source: ModulaBrowserSource?) -> OpenURLAction.Result {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return .systemAction }
        open(url, source: source)
        return .handled
    }

    static func open(_ url: URL, source: ModulaBrowserSource?) {
        guard ModulaPreferences.openLinksInApp else {
            UIApplication.shared.open(url)
            return
        }
        // Universal links (YouTube, Spotify, Maps…) hand off to their installed app;
        // everything else stays in the Modula browser.
        UIApplication.shared.open(url, options: [.universalLinksOnly: true]) { opened in
            guard !opened else { return }
            Task { @MainActor in ModulaBrowserPresenter.shared.present(url, source: source) }
        }
    }
}

@MainActor
final class ModulaBrowserPresenter {
    static let shared = ModulaBrowserPresenter()
    weak var environment: AppEnvironment?

    func present(_ url: URL, source: ModulaBrowserSource?) {
        guard let environment, let top = Self.topViewController() else {
            UIApplication.shared.open(url)
            return
        }
        var host: UIViewController?
        let root = ModulaInAppBrowserView(initialURL: url, source: source) {
            host?.dismiss(animated: true)
        }
        .environment(environment)
        .tint(environment.appearance.accent.color)
        .preferredColorScheme(environment.appearance.colorScheme)
        let controller = UIHostingController(rootView: root)
        controller.modalPresentationStyle = .overFullScreen
        controller.view.backgroundColor = .clear
        host = controller
        top.present(controller, animated: true)
        HapticEngine.shared.play(.navigation)
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive } ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var top = scene?.windows.first(where: \.isKeyWindow)?.rootViewController ?? scene?.windows.first?.rootViewController
        while let presented = top?.presentedViewController, !presented.isBeingDismissed { top = presented }
        return top
    }
}

// MARK: - Web page model

@MainActor @Observable
fileprivate final class ModulaWebPage: NSObject, WKNavigationDelegate, WKUIDelegate {
    let webView: WKWebView
    var progress: Double = 0
    var isLoading = false
    var title: String?
    var url: URL
    var canGoBack = false
    var canGoForward = false
    var failure: String?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []

    init(url: URL) {
        self.url = url
        let configuration = WKWebViewConfiguration()
        // Reader-safe defaults: a private, non-persistent data store (no cookies or
        // site data shared with the app or kept after closing), no script-opened
        // windows, mobile content, fraudulent-site warnings on.
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.preferences.isFraudulentWebsiteWarningEnabled = true
        configuration.defaultWebpagePreferences.preferredContentMode = .mobile
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        configuration.dataDetectorTypes = []
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsLinkPreview = true
        webView.scrollView.contentInsetAdjustmentBehavior = .always
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        observations = [
            webView.observe(\.estimatedProgress, options: [.new]) { [weak self] view, _ in
                Task { @MainActor in self?.progress = view.estimatedProgress }
            },
            webView.observe(\.isLoading, options: [.new]) { [weak self] view, _ in
                Task { @MainActor in self?.isLoading = view.isLoading }
            },
            webView.observe(\.title, options: [.new]) { [weak self] view, _ in
                Task { @MainActor in self?.title = view.title }
            },
            webView.observe(\.url, options: [.new]) { [weak self] view, _ in
                Task { @MainActor in if let url = view.url { self?.url = url } }
            },
            webView.observe(\.canGoBack, options: [.new]) { [weak self] view, _ in
                Task { @MainActor in self?.canGoBack = view.canGoBack }
            },
            webView.observe(\.canGoForward, options: [.new]) { [weak self] view, _ in
                Task { @MainActor in self?.canGoForward = view.canGoForward }
            }
        ]
        webView.load(URLRequest(url: url))
    }

    var domain: String { (url.host ?? url.absoluteString).replacingOccurrences(of: "www.", with: "") }
    var isSecure: Bool { url.scheme?.lowercased() == "https" }

    func reload() {
        failure = nil
        if isLoading { webView.stopLoading() } else if webView.url == nil { webView.load(URLRequest(url: url)) } else { webView.reload() }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        guard let target = navigationAction.request.url, let scheme = target.scheme?.lowercased() else {
            decisionHandler(.cancel)
            return
        }
        if ["http", "https", "about", "blob", "data"].contains(scheme) {
            decisionHandler(.allow)
            return
        }
        // tel:, mailto:, maps:, app schemes: only on an explicit tap, handed to the system.
        let userInitiated = navigationAction.navigationType == .linkActivated
        decisionHandler(.cancel)
        if userInitiated { UIApplication.shared.open(target) }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in self.record(error) }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in self.record(error) }
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in self.failure = nil }
    }

    /// target=_blank links open in the same view instead of a hidden window.
    nonisolated func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil, let request = Optional(navigationAction.request) {
            Task { @MainActor in webView.load(request) }
        }
        return nil
    }

    private func record(_ error: Error) {
        let ns = error as NSError
        guard ns.code != NSURLErrorCancelled else { return }
        failure = ns.localizedDescription
    }
}

private struct ModulaWebViewRepresentable: UIViewRepresentable {
    let page: ModulaWebPage
    func makeUIView(context: Context) -> WKWebView { page.webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

// MARK: - Browser UI

struct ModulaInAppBrowserView: View {
    let initialURL: URL
    var source: ModulaBrowserSource?
    var onClose: () -> Void

    @State private var page: ModulaWebPage
    @State private var post: SocialPost?
    @State private var sheetExpanded = false
    @State private var sheetHidden = false
    @State private var dismissOffset: CGFloat = 0
    @State private var copied = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    init(initialURL: URL, source: ModulaBrowserSource?, onClose: @escaping () -> Void) {
        self.initialURL = initialURL
        self.source = source
        self.onClose = onClose
        _page = State(initialValue: ModulaWebPage(url: initialURL))
        _post = State(initialValue: source?.post)
    }

    private var motion: Animation {
        reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.38, dampingFraction: 0.86)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color(uiColor: .systemBackground).ignoresSafeArea()
            ModulaWebViewRepresentable(page: page)
                .ignoresSafeArea(edges: .bottom)
                .accessibilityIdentifier("browser.web")
            if let failure = page.failure {
                ContentUnavailableView {
                    Label("Couldn’t open this page", systemImage: "exclamationmark.triangle")
                } description: { Text(failure) } actions: {
                    Button("Try again") { page.reload() }
                }
                .background(Color(uiColor: .systemBackground))
            }
            progressBar
            pullHandle
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 8) {
                bottomBar
                    .padding(.horizontal, 12)
                    .padding(.bottom, post != nil && !sheetHidden ? 0 : 6)
                if let post, let source, !sheetHidden {
                    sourceSheet(post: post, source: source)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .offset(y: dismissOffset)
        .opacity(1 - Double(min(dismissOffset / 600, 0.5)))
        .animation(motion, value: sheetExpanded)
        .animation(motion, value: sheetHidden)
        .accessibilityIdentifier("browser")
    }

    // MARK: Chrome

    private var progressBar: some View {
        GeometryReader { proxy in
            Capsule()
                .fill(Color.accentColor)
                .frame(width: proxy.size.width * page.progress, height: 2.5)
                .opacity(page.isLoading && page.progress < 1 ? 1 : 0)
                .animation(.easeOut(duration: 0.2), value: page.progress)
        }
        .frame(height: 2.5)
        .accessibilityHidden(true)
    }

    /// Pull down from the top edge to dismiss (the page keeps its own scroll).
    private var pullHandle: some View {
        Color.clear
            .frame(height: 28)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .gesture(dismissDrag)
            .accessibilityHidden(true)
    }

    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in dismissOffset = max(0, value.translation.height) }
            .onEnded { value in
                if value.translation.height > 140 || value.predictedEndTranslation.height > 320 {
                    HapticEngine.shared.play(.navigation)
                    close()
                } else {
                    withAnimation(motion) { dismissOffset = 0 }
                }
            }
    }

    private var bottomBar: some View {
        ModulaGlassGroup(spacing: 10) {
            HStack(spacing: 10) {
                ModulaGlassIconButton(title: "Close", systemImage: "xmark", size: 46) { close() }
                    .accessibilityIdentifier("browser.close")
                domainPill
                ModulaGlassIconButton(
                    title: page.isLoading ? "Stop loading" : "Reload",
                    systemImage: page.isLoading ? "xmark.circle" : "arrow.clockwise",
                    size: 46
                ) {
                    page.reload()
                    HapticEngine.shared.play(.lightImpact)
                }
                .accessibilityIdentifier("browser.reload")
            }
        }
        .simultaneousGesture(dismissDrag)
    }

    private var domainPill: some View {
        HStack(spacing: 6) {
            if page.canGoBack {
                Button { page.webView.goBack() } label: {
                    Image(systemName: "chevron.backward").frame(width: 30, height: 46)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
            }
            Image(systemName: page.isSecure ? "lock.fill" : "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(page.isSecure ? Color.secondary : Color.orange)
                .accessibilityLabel(page.isSecure ? "Secure connection" : "Not secure")
            Text(page.domain)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity)
            if page.canGoForward {
                Button { page.webView.goForward() } label: {
                    Image(systemName: "chevron.forward").frame(width: 30, height: 46)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Forward")
            }
            Menu {
                ShareLink(item: page.url) { Label("Share", systemImage: "square.and.arrow.up") }
                Button { UIApplication.shared.open(page.url) } label: { Label("Open in browser", systemImage: "safari") }
                Button {
                    UIPasteboard.general.url = page.url
                    HapticEngine.shared.play(.success)
                } label: { Label("Copy link", systemImage: "link") }
                if source != nil, sheetHidden {
                    Button { sheetHidden = false } label: { Label("Show post", systemImage: "text.bubble") }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .rotationEffect(.degrees(90))
                    .frame(width: 36, height: 46)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("More")
            .accessibilityIdentifier("browser.menu")
        }
        .foregroundStyle(.primary)
        .padding(.leading, 14)
        .padding(.trailing, 4)
        .frame(height: 46)
        .modulaGlass(in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("browser.domain")
    }

    // MARK: Source post sheet

    private func sourceSheet(post: SocialPost, source: ModulaBrowserSource) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Capsule().fill(Color.secondary.opacity(0.4)).frame(width: 36, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, 6)
            HStack(spacing: 10) {
                ModulaAvatar(initials: post.author?.initials ?? "?", url: post.author?.avatarURL, size: 34)
                VStack(alignment: .leading, spacing: 0) {
                    Text(post.author?.displayName ?? "Post").font(.subheadline.weight(.semibold)).lineLimit(1)
                    if let handle = post.author?.handle {
                        Text("@\(handle)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Text("Modula")
                    .font(.headline.weight(.heavy))
                    .accessibilityHidden(true)
            }
            if let text = post.text, !text.isEmpty {
                if sheetExpanded {
                    ScrollView {
                        Text(text).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 260)
                } else {
                    Text(text).font(.subheadline).lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Group {
                PostActions(
                    post: post,
                    onLike: {
                        self.post?.liked.toggle()
                        self.post?.likeCount += (self.post?.liked == true) ? 1 : -1
                        source.onLike()
                    },
                    onComment: {
                        close()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { source.onComment() }
                    },
                    onRepost: {
                        self.post?.reposted.toggle()
                        source.onRepost()
                    },
                    onSave: {
                        self.post?.saved.toggle()
                        source.onSave()
                    },
                    onShare: source.onShare
                )
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22, style: .continuous)
                .fill(Color(uiColor: .systemBackground))
                .shadow(color: .black.opacity(0.12), radius: 12, y: -2)
                .ignoresSafeArea(edges: .bottom)
        }
        .contentShape(Rectangle())
        .onTapGesture { sheetExpanded.toggle() }
        .gesture(
            DragGesture(minimumDistance: 10)
                .onEnded { value in
                    if value.translation.height < -30 { sheetExpanded = true }
                    else if value.translation.height > 30 {
                        if sheetExpanded { sheetExpanded = false } else { sheetHidden = true }
                    }
                    HapticEngine.shared.play(.selection)
                }
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("browser.post")
        .accessibilityAction(named: sheetExpanded ? "Collapse post" : "Expand post") { sheetExpanded.toggle() }
    }

    private func close() {
        page.webView.stopLoading()
        onClose()
    }
}

// MARK: - Rich link card (Greenfield unfurl)

struct ModulaRichLinkCard: View {
    let url: URL
    var compact = false
    @State private var preview: ModulaLinkPreviewData?
    @State private var loaded = false
    @Environment(AppEnvironment.self) private var app
    @Environment(\.openURL) private var openURL

    var body: some View {
        Group {
            if let preview {
                Button { openURL(url) } label: { card(preview) }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(preview.title ?? preview.domain), from \(preview.domain)")
                    .accessibilityHint("Opens the link")
                    .accessibilityIdentifier("link.card")
            }
        }
        .task(id: url) {
            guard !loaded, !ModulaPreferences.dataSaver else { return }
            loaded = true
            preview = await ModulaLinkPreviewStore.shared.preview(for: url, client: app.client)
        }
    }

    private func card(_ preview: ModulaLinkPreviewData) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            if let imageURL = preview.imageURL {
                // X-style: large image, title as a dark caption chip, domain underneath.
                ModulaRemoteImage(url: imageURL, cacheKey: "link:\(imageURL.absoluteString)", maximumPixelSize: compact ? 480 : 900) { phase in
                    if case .success(let image) = phase { Image(uiImage: image).resizable().scaledToFill() } else { Color.primary.opacity(0.06) }
                }
                .frame(height: compact ? 130 : 200)
                .frame(maxWidth: .infinity)
                .clipped()
                .overlay(alignment: .bottomLeading) {
                    if let title = preview.title {
                        Text(title)
                            .font(.caption)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                            .padding(8)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.primary.opacity(0.12), lineWidth: 0.75))
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    if let title = preview.title {
                        Text(title).font(.subheadline.weight(.semibold)).lineLimit(2).foregroundStyle(.primary)
                    }
                    if let summary = preview.description {
                        Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.primary.opacity(0.12), lineWidth: 0.75))
            }
            Text("From \(preview.domain)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.leading, 12)
        }
        .contentShape(Rectangle())
    }
}
