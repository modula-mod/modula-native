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
    /// Global frame of the post that was tapped; the browser drawer starts exactly there.
    var originFrame: CGRect? = nil
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

/// Where a link was tapped in a chat: the browser shows this instead of a post card.
struct ModulaChatLinkContext: Hashable, Sendable {
    var senderName: String?
    var chatTitle: String?
    var conversationID: String?

    /// Set by the bubble's openURL wrapper just before the chat's link inspector runs, so the
    /// inspector (attached above the bubbles) knows who sent the link.
    @MainActor static var lastSender: String?
}

private struct ModulaChatLinkContextKey: EnvironmentKey {
    static var defaultValue: ModulaChatLinkContext? { nil }
}

extension EnvironmentValues {
    var modulaChatLinkContext: ModulaChatLinkContext? {
        get { self[ModulaChatLinkContextKey.self] }
        set { self[ModulaChatLinkContextKey.self] = newValue }
    }
}

/// Bubble-level wrapper: records the sender, then hands the URL to the chat's handler.
struct ModulaChatLinkSenderModifier: ViewModifier {
    let sender: String?
    @Environment(\.openURL) private var parent

    func body(content: Content) -> some View {
        content.environment(\.openURL, OpenURLAction { url in
            ModulaChatLinkContext.lastSender = sender
            parent(url)
            return .handled
        })
    }
}

@MainActor
enum ModulaLinkRouter {
    /// OpenURLAction body: web links open in the Modula browser (or hand off to their app).
    static func handle(_ url: URL, source: ModulaBrowserSource?, chat: ModulaChatLinkContext? = nil) -> OpenURLAction.Result {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" || scheme == "modula" else { return .systemAction }
        open(url, source: source, chat: chat)
        return .handled
    }

    /// The one entry point for web links (posts, chats, bios, comments, notifications, Discover).
    static func open(_ url: URL, source: ModulaBrowserSource?, chat: ModulaChatLinkContext? = nil) {
        // Links to Modula itself open natively.
        if let navigation = ModulaBrowserPresenter.shared.environment?.navigation,
           navigation.open(path: url.absoluteString) {
            HapticEngine.shared.play(.navigation)
            return
        }
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            UIApplication.shared.open(url)
            return
        }
        // Settings → Links → "Open links in Modula" (default on).
        guard ModulaPreferences.openLinksInApp else {
            UIApplication.shared.open(url)
            return
        }
        // Universal links (YouTube, Spotify, Maps…) hand off to their installed app;
        // everything else stays in the Modula browser.
        UIApplication.shared.open(url, options: [.universalLinksOnly: true]) { opened in
            guard !opened else { return }
            Task { @MainActor in ModulaBrowserPresenter.shared.present(url, source: source, chat: chat) }
        }
    }
}

@MainActor
final class ModulaBrowserPresenter {
    static let shared = ModulaBrowserPresenter()
    weak var environment: AppEnvironment?

    func present(_ url: URL, source: ModulaBrowserSource?, chat: ModulaChatLinkContext? = nil) {
        guard let environment, let top = Self.topViewController() else {
            UIApplication.shared.open(url)
            return
        }
        var host: UIViewController?
        let root = ModulaInAppBrowserView(initialURL: url, source: source, chat: chat) {
            // The view animates its own post→drawer transition; UIKit just hosts it.
            host?.dismiss(animated: false)
        }
        .environment(environment)
        .tint(.primary)
        .preferredColorScheme(environment.appearance.colorScheme)
        let controller = UIHostingController(rootView: root)
        controller.modalPresentationStyle = .overFullScreen
        controller.view.backgroundColor = .clear
        // Menus are UIKit: without this they pick up the coral AccentColor (black/white rule).
        controller.view.tintColor = .label
        host = controller
        top.present(controller, animated: false)
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
    var zoom: CGFloat = 1
    var desktopSite = false
    /// Scrolling down hides the bottom controls; scrolling up (or reaching the top) shows them.
    var barsHidden = false
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private var lastOffsetY: CGFloat = 0

    func adjustZoom(_ delta: CGFloat?) {
        zoom = delta.map { min(max(zoom + $0, 0.5), 2.0) } ?? 1
        webView.pageZoom = zoom
        ModulaBrowserSiteZoom.set(zoom, for: url.host)
        HapticEngine.shared.play(.selection)
    }

    func setTrackerBlocking(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: "settings.links.blockTrackers")
        let controller = webView.configuration.userContentController
        controller.removeAllContentRuleLists()
        if on, let rules = ModulaBrowserWarmup.trackerRules { controller.add(rules) }
        reload()
    }

    /// Text size is remembered per domain.
    private func applySiteZoom() {
        let stored = ModulaBrowserSiteZoom.zoom(for: url.host)
        if abs(stored - zoom) > 0.01 || abs(webView.pageZoom - stored) > 0.01 {
            zoom = stored
            webView.pageZoom = stored
        }
    }

    @objc private func pullToRefresh(_ control: UIRefreshControl) {
        HapticEngine.shared.play(.lightImpact)
        failure = nil
        if webView.url == nil { webView.load(URLRequest(url: url)) } else { webView.reload() }
        control.endRefreshing()
    }

    private func trackScroll(_ y: CGFloat, atTop: Bool) {
        let delta = y - lastOffsetY
        lastOffsetY = y
        if atTop { if barsHidden { barsHidden = false }; return }
        if delta > 12, !barsHidden { barsHidden = true } else if delta < -12, barsHidden { barsHidden = false }
    }

    func setDesktopSite(_ enabled: Bool) {
        desktopSite = enabled
        webView.customUserAgent = enabled ? "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15" : nil
        webView.reload()
    }

    func presentFind() {
        webView.isFindInteractionEnabled = true
        webView.findInteraction?.presentFindNavigator(showingReplace: false)
    }

    func setBottomInset(_ inset: CGFloat) {
        guard abs(webView.scrollView.contentInset.bottom - inset) > 1 else { return }
        webView.scrollView.contentInset.bottom = inset
        webView.scrollView.verticalScrollIndicatorInsets.bottom = inset
    }

    /// Lightweight readability pass in the page; content renders natively (no page scripts run in reader).
    func extractReader() async -> ModulaReaderArticle? {
        guard let raw = try? await webView.evaluateJavaScript(Self.readerScript) as? String,
              let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["blocks"] as? [[String: String]] else { return nil }
        let blocks: [ModulaReaderArticle.Block] = items.compactMap { item in
            guard let kind = item["k"], let value = item["v"] else { return nil }
            switch kind {
            case "h": return .heading(value)
            case "q": return .quote(value)
            case "li": return .listItem(value)
            case "img": return URL(string: value).map { .image($0) }
            default: return .paragraph(value)
            }
        }
        guard blocks.filter({ if case .paragraph = $0 { true } else { false } }).count >= 2 else { return nil }
        return ModulaReaderArticle(title: (json["title"] as? String) ?? title ?? domain, byline: json["byline"] as? String, siteName: json["site"] as? String, blocks: blocks)
    }

    private static let readerScript = #"""
    (() => {
      const pick = () => {
        const c = document.querySelector('article') || document.querySelector('main') || document.querySelector('[role=main]');
        if (c) return c;
        let best = document.body, score = 0;
        document.querySelectorAll('div,section').forEach(el => {
          const s = Array.from(el.children).filter(x => x.tagName === 'P').reduce((a, p) => a + p.innerText.length, 0);
          if (s > score) { score = s; best = el; }
        });
        return best;
      };
      const root = pick(); const out = [];
      root.querySelectorAll('h1,h2,h3,p,blockquote,li,img').forEach(el => {
        if (el.closest('nav,footer,aside,form,script,style,button')) return;
        if (el.tagName === 'IMG') {
          const s = el.currentSrc || el.src;
          if (s && s.startsWith('http') && (el.naturalWidth || 0) >= 240) out.push({k: 'img', v: s});
          return;
        }
        if (el.parentElement && el.parentElement.closest('blockquote,li') && el.tagName === 'P') return;
        const t = (el.innerText || '').trim();
        if (!t) return;
        if (/^H[1-3]$/.test(el.tagName)) out.push({k: 'h', v: t});
        else if (el.tagName === 'BLOCKQUOTE') out.push({k: 'q', v: t});
        else if (el.tagName === 'LI') { if (t.length > 2 && t.length < 600) out.push({k: 'li', v: t}); }
        else if (t.length > 40 || out.length) out.push({k: 'p', v: t});
      });
      const meta = n => { const m = document.querySelector(`meta[property="${n}"],meta[name="${n}"]`); return m ? m.content : null; };
      return JSON.stringify({title: meta('og:title') || document.title, byline: meta('author'), site: meta('og:site_name'), blocks: out.slice(0, 500)});
    })()
    """#

    init(url: URL) {
        self.url = url
        let configuration = WKWebViewConfiguration()
        // Reader-safe defaults: a private, non-persistent data store (no cookies or
        // site data shared with the app or kept after closing), no script-opened
        // windows, mobile content, fraudulent-site warnings on.
        // Speed: one shared non-persistent store for every browser opened this session, so a second
        // visit reuses the web process' caches. Still nothing is written to disk or shared with the app.
        configuration.websiteDataStore = ModulaBrowserWarmup.sharedStore
        if let rules = ModulaBrowserWarmup.trackerRules, ModulaPreferences.bool("settings.links.blockTrackers", true) {
            configuration.userContentController.add(rules)
        }
        configuration.allowsPictureInPictureMediaPlayback = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.preferences.isFraudulentWebsiteWarningEnabled = true
        configuration.defaultWebpagePreferences.preferredContentMode = .mobile
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        configuration.dataDetectorTypes = []
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsLinkPreview = true
        webView.isFindInteractionEnabled = true
        webView.scrollView.contentInsetAdjustmentBehavior = .always
        webView.isOpaque = false
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        let refresh = UIRefreshControl()
        refresh.addTarget(self, action: #selector(pullToRefresh(_:)), for: .valueChanged)
        webView.scrollView.refreshControl = refresh
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
                Task { @MainActor in
                    guard let self, let url = view.url else { return }
                    let hostChanged = url.host != self.url.host
                    self.url = url
                    if hostChanged { self.applySiteZoom() }
                }
            },
            // Scroll KVO fires on the main thread; read it synchronously (no Task per frame).
            webView.scrollView.observe(\.contentOffset, options: [.new]) { [weak self] scroll, _ in
                MainActor.assumeIsolated {
                    let y = scroll.contentOffset.y
                    self?.trackScroll(y, atTop: y <= -scroll.adjustedContentInset.top + 4)
                }
            },
            webView.observe(\.canGoBack, options: [.new]) { [weak self] view, _ in
                Task { @MainActor in self?.canGoBack = view.canGoBack }
            },
            webView.observe(\.canGoForward, options: [.new]) { [weak self] view, _ in
                Task { @MainActor in self?.canGoForward = view.canGoForward }
            }
        ]
        applySiteZoom()
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
        Task { @MainActor in
            self.failure = nil
            if let url = webView.url { ModulaBrowserHistory.record(url, title: webView.title) }
        }
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

/// Layout for the post→drawer transition. progress 0 = the post where it was tapped, 1 = page open.
private struct BrowserDrawerLayout {
    var height: CGFloat
    var startY: CGFloat
    var compactTop: CGFloat
    func top(_ progress: CGFloat) -> CGFloat { startY + (compactTop - startY) * progress }
    var span: CGFloat { max(compactTop - startY, 1) }
}

struct ModulaInAppBrowserView: View {
    let initialURL: URL
    var source: ModulaBrowserSource?
    /// Opened from a chat: a slim context card instead of the post card.
    var chat: ModulaChatLinkContext? = nil
    var onClose: () -> Void

    @State private var page: ModulaWebPage
    @State private var post: SocialPost?
    @State private var progress: CGFloat = 0
    @State private var dragStart: CGFloat?
    @State private var dragVelocity: CGFloat = 0
    @State private var openSide = false
    @State private var warpActive = false
    @State private var snapshot: UIImage?
    @State private var drawerHeight: CGFloat = 0
    @State private var mediaHeight: CGFloat = 0
    @State private var reader: ModulaReaderArticle?
    @State private var readerLoading = false
    @State private var showHistory = false
    @State private var showModulaShare = false
    @State private var showReport = false
    @State private var safety: ModulaLinkSafety?
    @State private var safetyBypassed = false
    @State private var toast: String?
    @State private var fade: Double = 0
    @State private var opened = false
    /// Swipe-down-to-dismiss follows the finger.
    @State private var pullOffset: CGFloat = 0
    @State private var showAddress = false
    /// Post card minimised to a slim bar (swipe down on its handle / tap the chevron).
    @State private var drawerCollapsed = false
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(initialURL: URL, source: ModulaBrowserSource?, chat: ModulaChatLinkContext? = nil, onClose: @escaping () -> Void) {
        self.initialURL = initialURL
        self.source = source
        self.chat = chat
        self.onClose = onClose
        _page = State(initialValue: ModulaWebPage(url: initialURL))
        _post = State(initialValue: source?.post)
    }

    private var hasDrawer: Bool { post != nil && source != nil }

    var body: some View {
        GeometryReader { proxy in
            let safe = proxy.safeAreaInsets
            let height = proxy.size.height + safe.top + safe.bottom
            let layout = layout(height: height)
            let clamped = min(max(progress, 0), 1)
            let top = layout.top(progress)
            ZStack(alignment: .top) {
                // The app underneath (nav bar, tab bar) dims as the drawer travels down.
                Color.black.opacity(0.55 * clamped)
                    .allowsHitTesting(false)
                // Live page card: a fixed-size web view clipped to the region above the drawer.
                pageCard(height: height, top: top, progress: clamped, safeTop: safe.top) {
                    ModulaWebViewRepresentable(page: page)
                }
                // SwiftUI-only layer that carries the glass warp: a page snapshot (only while the
                // transition moves — shaders can't rasterise WKWebView) plus the drawer.
                ZStack(alignment: .top) {
                    if warpActive, !reduceMotion {
                        pageCard(height: height, top: top, progress: clamped, safeTop: safe.top) {
                            if let snapshot {
                                Image(uiImage: snapshot).resizable().frame(width: proxy.size.width, height: height)
                            } else {
                                Color(uiColor: .systemBackground)
                            }
                        }
                        .allowsHitTesting(false)
                    }
                    if let post, let source {
                        drawer(post: post, source: source, layout: layout, top: top, progress: clamped, safeBottom: safe.bottom)
                    }
                }
                .modifier(ModulaGlassWarp(
                    progress: progress,
                    velocity: dragVelocity,
                    startY: layout.startY,
                    compactTop: layout.compactTop,
                    enabled: warpActive && !reduceMotion
                ))
                // Opened from a chat: who shared it, and a way back. No post card.
                if !hasDrawer, let chat, clamped > 0.5, !page.barsHidden {
                    chatContextCard(chat)
                        .padding(.horizontal, 12)
                        .offset(y: height - safe.bottom - 62 - 52)
                        .transition(.opacity)
                }
                bottomBar
                    .padding(.horizontal, 12)
                    .offset(y: (hasDrawer ? top - 60 : height - safe.bottom - 62) + (page.barsHidden && !hasDrawer ? 120 : 0))
                    .opacity(hasDrawer ? Double(smooth(clamped, from: 0.55, to: 1)) : Double(clamped))
                    .allowsHitTesting(clamped > 0.9)
                    .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86), value: page.barsHidden)
                if let toast {
                    Text(toast)
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .modulaGlass(in: Capsule(), interactive: false)
                        .padding(.top, safe.top + 12)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .accessibilityAddTraits(.isStaticText)
                }
            }
            .frame(width: proxy.size.width, height: height, alignment: .top)
            // Pull-down-to-dismiss tracks the finger: the whole browser slides and shrinks a little.
            .offset(y: pullOffset)
            .scaleEffect(1 - min(pullOffset / 3000, 0.06), anchor: .top)
            .ignoresSafeArea()
            .onAppear { open(); ModulaBrowserWarmup.warm() }
            .onChange(of: Int(layout.compactTop)) { _, value in
                page.setBottomInset(hasDrawer ? max(0, height - CGFloat(value) - safe.bottom + 8) : 64)
            }
        }
        .opacity(reduceMotion ? fade : 1)
        .task {
            await checkSafety()
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--debug-browser-reader") {
                try? await Task.sleep(for: .seconds(4))
                await toggleReader()
            }
            #endif
        }
        .sheet(isPresented: $showAddress) {
            ModulaBrowserAddressSheet(url: page.url, title: page.title) { url in
                reader = nil
                page.webView.load(URLRequest(url: url))
            }
            .presentationDetents([.medium])
            .modulaSheetStyle()
        }
        .sheet(isPresented: $showHistory) {
            ModulaBrowserHistoryView { url in
                showHistory = false
                reader = nil
                page.webView.load(URLRequest(url: url))
            }
            .presentationDetents([.medium, .large])
            .modulaSheetStyle()
        }
        .sheet(isPresented: $showModulaShare) {
            Group {
                ModulaShareSheet(payload: .link(url: page.url, title: page.title))
            }
            .modulaSheetStyle()
        }
        .confirmationDialog("Report this link", isPresented: $showReport, titleVisibility: .visible) {
            Button("Spam") { Task { await report("spam", details: nil) } }
            Button("Scam or phishing") { Task { await report("other", details: "Scam or phishing") } }
            Button("Malware") { Task { await report("other", details: "Malware") } }
            Button("Harmful or illegal") { Task { await report("illegal-content", details: nil) } }
            Button("Privacy violation") { Task { await report("privacy", details: nil) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(page.domain)
        }
        .accessibilityIdentifier("browser")
        .accessibilityAction(.escape) { close() }
    }

    // MARK: Layout & transition

    private func layout(height: CGFloat) -> BrowserDrawerLayout {
        guard hasDrawer else { return BrowserDrawerLayout(height: height, startY: height * 0.35, compactTop: height) }
        let clamped = min(max(progress, 0), 1)
        let compact = max(drawerHeight - mediaHeight * (1 - clamped), 150)
        let origin = source?.originFrame?.minY ?? height * 0.5
        return BrowserDrawerLayout(height: height, startY: min(max(origin, 60), height - compact), compactTop: height - compact)
    }

    private func smooth(_ value: CGFloat, from a: CGFloat, to b: CGFloat) -> CGFloat {
        let t = min(max((value - a) / (b - a), 0), 1)
        return t * t * (3 - 2 * t)
    }

    private func open() {
        guard !opened else { return }
        opened = true
        if reduceMotion {
            progress = 1
            withAnimation(.easeOut(duration: 0.25)) { fade = 1 }
            return
        }
        // Let the drawer measure itself for one frame so it starts exactly over the post.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(40))
            settle(to: 1)
        }
    }

    private func close() {
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.2)) { fade = 0 } completion: { onClose() }
        } else {
            page.webView.stopLoading()
            settle(to: 0)
        }
    }

    /// Interruptible spring: a new drag simply takes over `progress` mid-flight.
    private func settle(to target: CGFloat, velocity: CGFloat = 0) {
        beginWarp {
            withAnimation(.spring(response: 0.46, dampingFraction: 0.84)) {
                progress = target
            } completion: {
                guard dragStart == nil else { return }
                warpActive = false
                dragVelocity = 0
                if target == 0 {
                    onClose()
                } else {
                    HapticEngine.shared.play(.lightImpact)
                }
            }
        }
    }

    private func beginWarp(_ then: @escaping () -> Void) {
        guard !reduceMotion, !reduceTransparency else { then(); return }
        if warpActive || page.webView.url == nil {
            warpActive = true
            then()
            return
        }
        page.webView.takeSnapshot(with: nil) { image, _ in
            snapshot = image
            warpActive = true
            then()
        }
    }

    private func rubberBand(_ distance: CGFloat, limit: CGFloat) -> CGFloat {
        limit * (1 - 1 / (distance / limit * 0.55 + 1))
    }

    private func drawerDrag(_ layout: BrowserDrawerLayout) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .global)
            .onChanged { value in
                if dragStart == nil {
                    dragStart = progress
                    if !warpActive { beginWarp {} }
                }
                var next = (dragStart ?? 1) + value.translation.height / layout.span
                if next > 1 { next = 1 + rubberBand((next - 1) * layout.span, limit: 80) / layout.span }
                if next < 0 { next = -rubberBand(-next * layout.span, limit: 60) / layout.span }
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    progress = next
                    dragVelocity = value.velocity.height
                }
                // Detent haptic when crossing between "post" and "page".
                let side = next > 0.5
                if side != openSide {
                    openSide = side
                    HapticEngine.shared.play(.dragThreshold)
                }
            }
            .onEnded { value in
                let projected = (dragStart ?? 1) + value.predictedEndTranslation.height / layout.span
                dragStart = nil
                settle(to: projected < 0.42 ? 0 : 1, velocity: value.velocity.height)
            }
    }

    // MARK: Page card

    private func pageCard<Content: View>(height: CGFloat, top: CGFloat, progress p: CGFloat, safeTop: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        let visible = max(min(top + 30, height), 0)
        return ZStack(alignment: .top) {
            Color(uiColor: .systemBackground)
            content()
            if let reader {
                ModulaReaderView(article: reader, scale: page.zoom, bottomInset: height - top) { self.reader = nil }
                    .transition(.opacity)
            }
            if let failure = page.failure {
                ContentUnavailableView {
                    Label("Couldn’t open this page", systemImage: "exclamationmark.triangle")
                } description: { Text(failure) } actions: {
                    Button("Try again") { page.reload() }
                }
                .background(Color(uiColor: .systemBackground))
            }
            if let safety, safety.level == .blocked, !safetyBypassed {
                blockedInterstitial(safety)
            }
            VStack(spacing: 0) {
                progressBar
                pullHandle
            }
            .padding(.top, safeTop)
        }
        .frame(height: height)
        .frame(height: visible, alignment: .top)
        .clipShape(RoundedRectangle(cornerRadius: 44, style: .continuous))
        .scaleEffect(0.94 + 0.06 * p, anchor: .top)
        .opacity(Double(min(1, 0.25 + p * 1.6)))
    }

    private var progressBar: some View {
        GeometryReader { proxy in
            Capsule()
                .fill(Color.primary)
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
            .gesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { value in
                        guard !reduceMotion else { return }
                        var t = Transaction(); t.disablesAnimations = true
                        withTransaction(t) { pullOffset = max(0, value.translation.height) }
                    }
                    .onEnded { value in
                        if value.translation.height > 120 || value.predictedEndTranslation.height > 300 {
                            HapticEngine.shared.play(.navigation)
                            if reduceMotion {
                                close()
                            } else {
                                withAnimation(.easeIn(duration: 0.2)) { pullOffset = 1400 } completion: { onClose() }
                            }
                        } else {
                            withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8)) { pullOffset = 0 }
                        }
                    }
            )
            .accessibilityHidden(true)
    }

    private func blockedInterstitial(_ verdict: ModulaLinkSafety) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.system(size: 52))
                .foregroundStyle(.red)
                .symbolEffect(.pulse, isActive: !reduceMotion)
            Text("This site has been flagged").font(.title3.bold())
            Text("Modula marked \(verdict.domain) as unsafe (\(verdict.reasons.first ?? "unsafe")). It may try to steal your information.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Go back") { close() }.buttonStyle(.modulaPrimary).tint(.red)
            Button("Continue anyway") {
                safetyBypassed = true
                page.webView.load(URLRequest(url: page.url))
            }
            .font(.footnote)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground))
        .accessibilityElement(children: .contain)
    }

    // MARK: Drawer (the source post)

    private func drawer(post: SocialPost, source: ModulaBrowserSource, layout: BrowserDrawerLayout, top: CGFloat, progress p: CGFloat, safeBottom: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Capsule().fill(Color.secondary.opacity(0.45)).frame(width: 36, height: 5)
                .frame(maxWidth: .infinity)
                .opacity(Double(p))
                // Once docked under the page: swipe down to a slim bar, up to expand.
                .highPriorityGesture(
                    DragGesture(minimumDistance: 10).onEnded { value in
                        guard p > 0.9 else { return }
                        let collapse = value.translation.height > 24
                        let expand = value.translation.height < -24
                        guard collapse != drawerCollapsed, collapse || expand else { return }
                        HapticEngine.shared.play(.selection)
                        withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86)) { drawerCollapsed = collapse }
                    },
                    including: p > 0.9 ? .all : .none
                )
            HStack(spacing: 10) {
                ModulaAvatar(initials: post.author?.initials ?? "?", url: post.author?.avatarURL, size: 38)
                VStack(alignment: .leading, spacing: 0) {
                    Text(post.author?.displayName ?? "Post").font(.subheadline.weight(.semibold)).lineLimit(1)
                    if let handle = post.author?.handle {
                        Text("@\(handle)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if p > 0.9 {
                    Button {
                        HapticEngine.shared.play(.selection)
                        withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86)) { drawerCollapsed.toggle() }
                    } label: {
                        Image(systemName: drawerCollapsed ? "chevron.up" : "chevron.down")
                            .font(.footnote.weight(.semibold))
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(drawerCollapsed ? "Expand post" : "Minimise post")
                } else {
                    ModulaWordmark(height: 16).accessibilityHidden(true)
                }
            }
            if !(drawerCollapsed && p > 0.9) {
            if let text = post.text, !text.isEmpty {
                Text(text).font(.subheadline).lineLimit(4).frame(maxWidth: .infinity, alignment: .leading)
            }
            // The link card folds away as the post turns into the compact sheet.
            ModulaRichLinkCard(url: initialURL)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { mediaHeight = $0 }
                .frame(height: mediaHeight * (1 - p), alignment: .top)
                .clipped()
                .opacity(Double(1 - p))
                .allowsHitTesting(false)
                .accessibilityHidden(p > 0.5)
            PostActions(
                post: post,
                onLike: {
                    self.post?.liked.toggle()
                    self.post?.likeCount += (self.post?.liked == true) ? 1 : -1
                    source.onLike()
                },
                onComment: {
                    close()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { source.onComment() }
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
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, safeBottom + 4)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { drawerHeight = $0 }
        .background(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: 24 * p, topTrailingRadius: 24 * p, style: .continuous)
                // Glass like the app's sheets once docked; solid with Reduce Transparency.
                .fill(reduceTransparency || p < 0.5 ? AnyShapeStyle(Color(uiColor: .systemBackground)) : AnyShapeStyle(.regularMaterial))
                .shadow(color: .black.opacity(0.2 * Double(p)), radius: 18, y: -4)
                // Below the post the drawer fills to the bottom edge as it opens (plus rubber-band room).
                .frame(height: drawerHeight + max(0, layout.height - top - drawerHeight + 120) * p)
        }
        .contentShape(Rectangle())
        .offset(y: top)
        .gesture(drawerDrag(layout))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("browser.post")
        .accessibilityAction(named: "Back to post") { close() }
    }

    // MARK: Bottom bar

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
                .symbolEffect(.rotate, value: page.isLoading)
                .accessibilityIdentifier("browser.reload")
            }
        }
    }

    private var domainPill: some View {
        HStack(spacing: 4) {
            if page.canGoBack {
                Button { page.webView.goBack() } label: {
                    Image(systemName: "chevron.backward").frame(width: 30, height: 46)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
                // Long-press: the back list.
                .contextMenu {
                    ForEach(Array(page.webView.backForwardList.backList.reversed().enumerated()), id: \.offset) { _, item in
                        Button(item.title?.isEmpty == false ? item.title! : (item.url.host ?? item.url.absoluteString)) { page.webView.go(to: item) }
                    }
                }
            }
            Image(systemName: lockSymbol)
                .font(.caption2)
                .foregroundStyle(lockColor)
                .accessibilityLabel(page.isSecure ? "Secure connection" : "Not secure")
            Button {
                HapticEngine.shared.play(.selection)
                showAddress = true
            } label: {
                VStack(spacing: 0) {
                    Text(reader != nil ? "Reader · \(page.domain)" : page.domain)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let title = page.title, !title.isEmpty, reader == nil {
                        Text(title)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .contentTransition(.opacity)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Address, \(page.domain)")
            .accessibilityHint("Shows the full address")
            if page.canGoForward {
                Button { page.webView.goForward() } label: {
                    Image(systemName: "chevron.forward").frame(width: 30, height: 46)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Forward")
                .contextMenu {
                    ForEach(Array(page.webView.backForwardList.forwardList.enumerated()), id: \.offset) { _, item in
                        Button(item.title?.isEmpty == false ? item.title! : (item.url.host ?? item.url.absoluteString)) { page.webView.go(to: item) }
                    }
                }
            }
            moreMenu
        }
        .foregroundStyle(.primary)
        .padding(.leading, 14)
        .padding(.trailing, 4)
        .frame(height: 46)
        .modulaGlass(in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("browser.domain")
    }

    private var lockSymbol: String {
        if safety?.level == .blocked { return "exclamationmark.shield.fill" }
        return page.isSecure ? "lock.fill" : "exclamationmark.triangle.fill"
    }

    private var lockColor: Color {
        if safety?.level == .blocked { return .red }
        return page.isSecure ? .secondary : .orange
    }

    private var moreMenu: some View {
        Menu {
            Section {
                Button { copyLink() } label: { Label("Copy link", systemImage: "link") }
                ShareLink(item: page.url) { Label("Share", systemImage: "square.and.arrow.up") }
                Button { showModulaShare = true } label: { Label("Share to Modula…", systemImage: "paperplane") }
                Button { UIApplication.shared.open(page.url) } label: { Label("Open in Safari", systemImage: "safari") }
                if let app = ModulaKnownApps.appName(for: page.url) {
                    Button {
                        UIApplication.shared.open(page.url, options: [.universalLinksOnly: true]) { opened in
                            if !opened { Task { @MainActor in HapticEngine.shared.play(.failure) } }
                        }
                    } label: { Label("Open in \(app)", systemImage: "arrow.up.forward.app") }
                }
            }
            Section {
                Button { Task { await toggleReader() } } label: {
                    Label(reader == nil ? "Reader" : "Exit reader", systemImage: reader == nil ? "doc.plaintext" : "doc.richtext")
                }
                Button { page.presentFind() } label: { Label("Find on page", systemImage: "text.magnifyingglass") }
                Menu {
                    Button { page.adjustZoom(+0.1) } label: { Label("Larger", systemImage: "textformat.size.larger") }
                    Button { page.adjustZoom(-0.1) } label: { Label("Smaller", systemImage: "textformat.size.smaller") }
                    Button { page.adjustZoom(nil) } label: { Label("Reset (\(Int((page.zoom * 100).rounded()))%)", systemImage: "arrow.counterclockwise") }
                } label: { Label("Text size", systemImage: "textformat.size") }
                Toggle(isOn: Binding(get: { page.desktopSite }, set: { page.setDesktopSite($0) })) {
                    Label("Desktop site", systemImage: "desktopcomputer")
                }
                Toggle(isOn: Binding(
                    get: { ModulaPreferences.bool("settings.links.blockTrackers", true) },
                    set: { page.setTrackerBlocking($0); HapticEngine.shared.play(.selection) }
                )) {
                    Label("Block trackers", systemImage: "hand.raised")
                }
            }
            Section {
                if source != nil {
                    Button { toggleSavePost() } label: {
                        Label(post?.saved == true ? "Remove from saved" : "Save post", systemImage: post?.saved == true ? "bookmark.slash" : "bookmark")
                    }
                } else {
                    Button { showModulaShare = true } label: { Label("Save to Collection…", systemImage: "bookmark") }
                }
                Button { showHistory = true } label: { Label("History", systemImage: "clock.arrow.circlepath") }
                Button(role: .destructive) { showReport = true } label: { Label("Report link", systemImage: "exclamationmark.bubble") }
            }
        } label: {
            Image(systemName: "ellipsis")
                .rotationEffect(.degrees(90))
                .frame(width: 36, height: 46)
                .contentShape(Rectangle())
        }
        // Neutral icons (black/white); only "Report link" keeps the destructive red.
        .tint(.primary)
        .accessibilityLabel("More")
        .accessibilityIdentifier("browser.menu")
    }

    /// Chat-opened links: who shared it and in which chat. Tap closes back to the chat.
    private func chatContextCard(_ chat: ModulaChatLinkContext) -> some View {
        Button {
            HapticEngine.shared.play(.navigation)
            close()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 0) {
                    Text(chat.senderName.map { "Shared by \($0)" } ?? "Shared in a chat")
                        .font(.footnote.weight(.semibold))
                        .lineLimit(1)
                    if let title = chat.chatTitle, !title.isEmpty, title != chat.senderName {
                        Text(title).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Text("Back to chat").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .frame(height: 42)
            .modulaGlass(in: Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .accessibilityIdentifier("browser.chatContext")
    }

    // MARK: Actions

    private func show(_ message: String) {
        ModulaToastCenter.shared.show(message, symbol: "checkmark.circle")
    }

    private func copyLink() {
        UIPasteboard.general.url = page.url
        HapticEngine.shared.play(.success)
        show("Link copied")
    }

    private func toggleSavePost() {
        guard let source else { return }
        post?.saved.toggle()
        source.onSave()
        HapticEngine.shared.play(.success)
        show(post?.saved == true ? "Saved to your Modula saved items" : "Removed from saved")
    }

    private func toggleReader() async {
        if reader != nil {
            withAnimation(.easeInOut(duration: 0.2)) { reader = nil }
            return
        }
        readerLoading = true
        defer { readerLoading = false }
        if let article = await page.extractReader() {
            withAnimation(.easeInOut(duration: 0.25)) { reader = article }
            HapticEngine.shared.play(.selection)
        } else {
            show("Reader isn’t available for this page")
        }
    }

    private func checkSafety() async {
        let encoded = initialURL.absoluteString.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        if let value = try? await app.client.authenticatedJSON("GET", path: "/v1/link-safety?url=\(encoded)") {
            let verdict = ModulaLinkSafety(
                level: ModulaLinkSafety.Level(rawValue: value["level"]?.string ?? "ok") ?? .ok,
                reasons: value["reasons"]?.array?.compactMap(\.string) ?? [],
                domain: value["domain"]?.string ?? page.domain
            )
            safety = verdict
            if verdict.level == .blocked {
                page.webView.stopLoading()
                HapticEngine.shared.play(.failure)
            }
        }
        if initialURL.scheme?.lowercased() == "http", safety?.level != .blocked {
            show("Not secure: this site doesn’t use encryption")
        }
    }

    private func report(_ category: String, details: String?) async {
        var body: [String: JSONValue] = [
            "targetType": .string("other"),
            "targetId": .string(String(page.url.absoluteString.prefix(500))),
            "category": .string(category)
        ]
        body["details"] = .string([details, "Link: \(page.url.absoluteString)"].compactMap { $0 }.joined(separator: " — "))
        do {
            let _: JSONValue = try await app.client.authenticatedJSON("POST", path: "/v1/reports", body: .object(body))
            HapticEngine.shared.play(.success)
            show("Thanks, we’ll review this link")
        } catch {
            HapticEngine.shared.play(.failure)
            show("Couldn’t send report. Sign in and try again.")
        }
    }
}

// MARK: - Glass warp (Metal)

/// Lens refraction + chromatic fringe along the moving seam; animates with progress, zero when idle.
private struct ModulaGlassWarp: ViewModifier, @MainActor Animatable {
    var progress: CGFloat
    var velocity: CGFloat
    var startY: CGFloat
    var compactTop: CGFloat
    var enabled: Bool

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let clamped = min(max(progress, 0), 1)
        let seam = startY + (compactTop - startY) * progress
        let motion = Double(sin(.pi * clamped)) * 0.75 + min(abs(Double(velocity)) / 2400, 0.45)
        let strength = enabled ? Float(min(motion, 1)) : 0
        content.visualEffect { view, proxy in
            view.layerEffect(
                ShaderLibrary.modulaGlassWarp(.float2(proxy.size), .float(Float(seam)), .float(strength), .float(26)),
                maxSampleOffset: CGSize(width: 24, height: 32),
                isEnabled: strength > 0.002
            )
        }
    }
}

// MARK: - Safety, reader, history

struct ModulaLinkSafety: Equatable {
    enum Level: String { case ok, warning, blocked }
    var level: Level
    var reasons: [String]
    var domain: String
}

struct ModulaReaderArticle: Equatable {
    enum Block: Hashable {
        case heading(String), paragraph(String), quote(String), listItem(String), image(URL)
    }
    var title: String
    var byline: String?
    var siteName: String?
    var blocks: [Block]
}

/// Reader: native typography, persisted theme / font / size, reading time, neutral colours.
private struct ModulaReaderView: View {
    let article: ModulaReaderArticle
    let scale: CGFloat
    let bottomInset: CGFloat
    var onClose: () -> Void
    @ScaledMetric private var bodySize: CGFloat = 19
    @AppStorage("browser.reader.theme") private var themeRaw = ReaderTheme.auto.rawValue
    @AppStorage("browser.reader.font") private var fontRaw = ReaderFont.serif.rawValue
    @AppStorage("browser.reader.size") private var sizeStep = 0.0
    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: Double = 0

    enum ReaderTheme: String, CaseIterable, Identifiable {
        case auto, paper, gray, night
        var id: String { rawValue }
        var title: String {
            switch self { case .auto: "Auto"; case .paper: "Paper"; case .gray: "Gray"; case .night: "Night" }
        }
        /// Neutral backgrounds only (no tinted sepia): off-white, light gray, near-black.
        func background(_ scheme: ColorScheme) -> Color {
            switch self {
            case .auto: Color(uiColor: .systemBackground)
            case .paper: Color(white: 0.975)
            case .gray: Color(white: 0.90)
            case .night: Color(white: 0.07)
            }
        }
        var scheme: ColorScheme? {
            switch self { case .auto: nil; case .paper, .gray: .light; case .night: .dark }
        }
    }

    enum ReaderFont: String, CaseIterable, Identifiable {
        case serif, sans, rounded
        var id: String { rawValue }
        var title: String { switch self { case .serif: "Serif"; case .sans: "Sans"; case .rounded: "Rounded" } }
        var design: Font.Design { switch self { case .serif: .serif; case .sans: .default; case .rounded: .rounded } }
    }

    private var theme: ReaderTheme { ReaderTheme(rawValue: themeRaw) ?? .auto }
    private var design: Font.Design { (ReaderFont(rawValue: fontRaw) ?? .serif).design }
    /// Reader size: its own steps (−3…+5, ~8% each) on top of Dynamic Type and the site's text size.
    private var size: CGFloat { bodySize * scale * (1 + CGFloat(sizeStep) * 0.08) }

    private var wordCount: Int {
        article.blocks.reduce(0) { total, block in
            switch block {
            case .heading(let t), .paragraph(let t), .quote(let t), .listItem(let t):
                total + t.split(whereSeparator: { $0.isWhitespace }).count
            case .image: total
            }
        }
    }
    private var readingMinutes: Int { max(1, Int((Double(wordCount) / 230).rounded())) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: size * 0.85) {
                header
                ForEach(Array(article.blocks.enumerated()), id: \.offset) { _, block in
                    blockView(block)
                }
                Text("End of article")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)
            }
            .textSelection(.enabled)
            .padding(.horizontal, 24)
            .padding(.top, 72)
            .padding(.bottom, bottomInset + 40)
            .frame(maxWidth: 660, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .onScrollGeometryChange(for: Double.self) { geo in
            let range = max(geo.contentSize.height - geo.containerSize.height, 1)
            let fraction = Double(min(max((geo.contentOffset.y + geo.contentInsets.top) / range, 0), 1))
            return (fraction * 50).rounded() / 50
        } action: { _, value in
            progress = value
        }
        .overlay(alignment: .top) { readerChrome }
        .background(theme.background(systemScheme).ignoresSafeArea())
        .foregroundStyle(.primary)
        .tint(.primary)
        .environment(\.colorScheme, theme.scheme ?? systemScheme)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: themeRaw)
        .accessibilityIdentifier("browser.reader")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let site = article.siteName, !site.isEmpty {
                Text(site.uppercased())
                    .font(.caption.weight(.semibold))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
            }
            Text(article.title)
                .font(.system(size: size * 1.55, weight: .bold, design: design))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                if let byline = article.byline, !byline.isEmpty {
                    Text(byline).lineLimit(1)
                    Text("·")
                }
                Text("\(readingMinutes) min read")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)
            Rectangle().fill(Color.primary.opacity(0.12)).frame(height: 1).padding(.top, 6)
        }
    }

    @ViewBuilder
    private func blockView(_ block: ModulaReaderArticle.Block) -> some View {
        switch block {
        case .heading(let text):
            Text(text)
                .font(.system(size: size * 1.2, weight: .semibold, design: design))
                .padding(.top, size * 0.5)
                .accessibilityAddTraits(.isHeader)
        case .paragraph(let text):
            Text(text)
                .font(.system(size: size, design: design))
                .lineSpacing(size * 0.42)
                .foregroundStyle(Color.primary.opacity(0.9))
        case .quote(let text):
            Text(text)
                .font(.system(size: size * 1.05, design: design))
                .italic()
                .lineSpacing(size * 0.35)
                .foregroundStyle(.secondary)
                .padding(.leading, 14)
                .overlay(alignment: .leading) { Capsule().fill(Color.primary.opacity(0.25)).frame(width: 3) }
        case .listItem(let text):
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("•").foregroundStyle(.secondary)
                Text(text).lineSpacing(size * 0.35)
            }
            .font(.system(size: size, design: design))
        case .image(let url):
            ModulaRemoteImage(url: url, cacheKey: "reader:\(url.absoluteString)", maximumPixelSize: 1200) { phase in
                if case .success(let image) = phase { Image(uiImage: image).resizable().scaledToFit() } else { Color.primary.opacity(0.05).frame(height: 180) }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.vertical, 4)
        }
    }

    /// Thin reading-progress line + an "Aa" menu (theme, font, size) and exit.
    private var readerChrome: some View {
        VStack(spacing: 0) {
            GeometryReader { proxy in
                Rectangle()
                    .fill(Color.primary.opacity(0.55))
                    .frame(width: proxy.size.width * progress, height: 2)
            }
            .frame(height: 2)
            HStack {
                Spacer()
                Menu {
                    Section("Text size") {
                        Button { step(-1) } label: { Label("Smaller", systemImage: "textformat.size.smaller") }
                            .disabled(sizeStep <= -3)
                        Button { step(+1) } label: { Label("Larger", systemImage: "textformat.size.larger") }
                            .disabled(sizeStep >= 5)
                        if sizeStep != 0 { Button { sizeStep = 0; HapticEngine.shared.play(.selection) } label: { Label("Default size", systemImage: "arrow.counterclockwise") } }
                    }
                    Picker("Font", selection: $fontRaw) {
                        ForEach(ReaderFont.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    Picker("Theme", selection: $themeRaw) {
                        ForEach(ReaderTheme.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    Divider()
                    Button { onClose() } label: { Label("Exit reader", systemImage: "doc.richtext") }
                } label: {
                    Image(systemName: "textformat.size")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 40, height: 40)
                        .modulaGlass(in: Circle())
                }
                .tint(.primary)
                .accessibilityLabel("Reader settings")
                .accessibilityIdentifier("browser.reader.settings")
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .padding(.top, 56)
    }

    private func step(_ delta: Double) {
        sizeStep = min(max(sizeStep + delta, -3), 5)
        HapticEngine.shared.play(.selection)
    }
}

/// Local, private history of pages opened in the in-app browser (never synced or sent anywhere).
enum ModulaBrowserHistory {
    struct Entry: Codable, Hashable, Identifiable {
        var url: URL
        var title: String?
        var visitedAt: Date
        var id: String { url.absoluteString }
    }

    private static let key = "browser.history.v1"

    static func load() -> [Entry] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
    }

    static func record(_ url: URL, title: String?) {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }
        var items = load().filter { $0.url != url }
        items.insert(Entry(url: url, title: title, visitedAt: .now), at: 0)
        if let data = try? JSONEncoder().encode(Array(items.prefix(150))) { UserDefaults.standard.set(data, forKey: key) }
    }

    static func clear() { UserDefaults.standard.removeObject(forKey: key) }
}

private struct ModulaBrowserHistoryView: View {
    var onOpen: (URL) -> Void
    @State private var entries = ModulaBrowserHistory.load()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if entries.isEmpty {
                    ContentUnavailableView("No history yet", systemImage: "clock", description: Text("Pages you open in Modula stay on this device only."))
                }
                ForEach(entries) { entry in
                    Button { onOpen(entry.url) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.title?.isEmpty == false ? entry.title! : (entry.url.host ?? entry.url.absoluteString)).lineLimit(1)
                            Text("\(entry.url.host ?? "") · \(entry.visitedAt.formatted(.relative(presentation: .named)))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .destructiveAction) {
                    Button("Clear", role: .destructive) {
                        ModulaBrowserHistory.clear()
                        entries = []
                        HapticEngine.shared.play(.success)
                    }
                    .disabled(entries.isEmpty)
                }
            }
        }
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
    @Environment(\.modulaChatLinkContext) private var chatContext

    /// In a chat the preview card goes straight to the browser (with the chat context);
    /// elsewhere it follows the surrounding openURL (post source etc.).
    private func openCard() {
        if let chatContext { ModulaLinkRouter.open(url, source: nil, chat: chatContext) } else { openURL(url) }
    }

    var body: some View {
        Group {
            if let preview {
                Button { openCard() } label: { card(preview) }
                    .buttonStyle(.plain)
                    // Long-press peek with link actions.
                    .contextMenu {
                        Button { openCard() } label: { Label("Open", systemImage: "arrow.up.forward.app") }
                        Button { UIApplication.shared.open(url) } label: { Label("Open in Safari", systemImage: "safari") }
                        Button { UIPasteboard.general.url = url } label: { Label("Copy link", systemImage: "link") }
                        ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") }
                    } preview: {
                        ModulaLinkPeek(preview: preview)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(preview.title ?? preview.domain), from \(preview.domain)")
                    .accessibilityHint("Opens the link")
                    .accessibilityIdentifier("link.card")
            }
        }
        .task(id: url) {
            // Speed: a link on screen spins up the web processes so the tap opens instantly.
            if ModulaPreferences.openLinksInApp { ModulaBrowserWarmup.warm() }
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

/// Context-menu preview for a link card: large image, title, description and domain.
private struct ModulaLinkPeek: View {
    let preview: ModulaLinkPreviewData
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let imageURL = preview.imageURL {
                ModulaRemoteImage(url: imageURL, cacheKey: "link:\(imageURL.absoluteString)", maximumPixelSize: 1000) { phase in
                    if case .success(let image) = phase { Image(uiImage: image).resizable().scaledToFill() } else { Color.primary.opacity(0.06) }
                }
                .frame(width: 320, height: 180)
                .clipped()
            }
            VStack(alignment: .leading, spacing: 4) {
                if let title = preview.title { Text(title).font(.headline).lineLimit(2) }
                if let summary = preview.description { Text(summary).font(.subheadline).foregroundStyle(.secondary).lineLimit(3) }
                Label(preview.domain, systemImage: "globe").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .frame(width: 320)
        .background(Color(uiColor: .systemBackground))
    }
}


// MARK: - Warm-up, tracker blocking, per-site text size

/// Speed: the first WKWebView in a process pays for spinning up the WebContent/Networking
/// processes. `warm()` (called when a link card or browser entry appears) does that early with a
/// throwaway view on the shared store; the tracker rule list compiles once in the background.
@MainActor
enum ModulaBrowserWarmup {
    static let sharedStore: WKWebsiteDataStore = .nonPersistent()
    private(set) static var trackerRules: WKContentRuleList?
    private static var warmView: WKWebView?
    private static var warmed = false

    /// Settings → Links → "Clear browsing data": history, cookies/caches of this session's
    /// shared store, and remembered per-site text sizes.
    static func clearBrowsingData() async {
        ModulaBrowserHistory.clear()
        UserDefaults.standard.removeObject(forKey: "browser.siteZoom.v1")
        await sharedStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
    }

    static func warm() {
        guard !warmed else { return }
        warmed = true
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = sharedStore
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: configuration)
        view.loadHTMLString("<html></html>", baseURL: nil)
        warmView = view
        compileTrackerRules()
        // Drop the throwaway view once its processes are up.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            warmView = nil
        }
    }

    /// A small, cheap block list of well-known ad/tracker hosts (third-party loads only).
    private static func compileTrackerRules() {
        let hosts = [
            "doubleclick.net", "googlesyndication.com", "googleadservices.com", "google-analytics.com",
            "googletagmanager.com", "adservice.google.com", "facebook.net", "connect.facebook.net",
            "scorecardresearch.com", "quantserve.com", "taboola.com", "outbrain.com", "criteo.com",
            "adnxs.com", "amazon-adsystem.com", "moatads.com", "hotjar.com", "chartbeat.com",
            "pubmatic.com", "rubiconproject.com", "openx.net", "casalemedia.com", "adsrvr.org"
        ]
        let rules = hosts.map { host -> [String: Any] in
            ["trigger": ["url-filter": "^https?://([a-z0-9-]+\\.)*\(NSRegularExpression.escapedPattern(for: host))", "load-type": ["third-party"]],
             "action": ["type": "block"]]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: rules), let json = String(data: data, encoding: .utf8) else { return }
        WKContentRuleListStore.default()?.compileContentRuleList(forIdentifier: "modula.trackers.v1", encodedContentRuleList: json) { list, _ in
            Task { @MainActor in trackerRules = list }
        }
    }
}

enum ModulaBrowserSiteZoom {
    private static let key = "browser.siteZoom.v1"
    static func zoom(for host: String?) -> CGFloat {
        guard let host else { return 1 }
        let all = UserDefaults.standard.dictionary(forKey: key) as? [String: Double] ?? [:]
        return CGFloat(all[host.replacingOccurrences(of: "www.", with: "")] ?? 1)
    }
    static func set(_ zoom: CGFloat, for host: String?) {
        guard let host else { return }
        var all = UserDefaults.standard.dictionary(forKey: key) as? [String: Double] ?? [:]
        let id = host.replacingOccurrences(of: "www.", with: "")
        if abs(zoom - 1) < 0.01 { all[id] = nil } else { all[id] = Double(zoom) }
        if all.count > 200, let drop = all.keys.first(where: { $0 != id }) { all[drop] = nil }
        UserDefaults.standard.set(all, forKey: key)
    }
}

/// Full address: see, copy, edit and go.
private struct ModulaBrowserAddressSheet: View {
    let url: URL
    let title: String?
    var onGo: (URL) -> Void
    @State private var text: String
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    init(url: URL, title: String?, onGo: @escaping (URL) -> Void) {
        self.url = url
        self.title = title
        self.onGo = onGo
        _text = State(initialValue: url.absoluteString)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                if let title, !title.isEmpty {
                    Text(title).font(.headline).lineLimit(2)
                }
                TextField("Address", text: $text, axis: .vertical)
                    .font(.callout.monospaced())
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .focused($focused)
                    .onSubmit(go)
                    .padding(12)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                HStack {
                    Button("Copy", systemImage: "doc.on.doc") {
                        UIPasteboard.general.string = text
                        HapticEngine.shared.play(.success)
                    }
                    .buttonStyle(.modulaSecondary)
                    Button("Go", systemImage: "arrow.right", action: go)
                        .buttonStyle(.modulaPrimary)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .navigationTitle("Address")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .tint(.primary)
    }

    private func go() {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.contains("://") { value = "https://" + value }
        guard let target = URL(string: value), let scheme = target.scheme?.lowercased(), scheme == "http" || scheme == "https", target.host != nil else {
            HapticEngine.shared.play(.failure)
            return
        }
        onGo(target)
        dismiss()
    }
}


/// Hosts whose links usually have an installed app (offered as "Open in …"; universal links only,
/// so nothing happens if the app isn't installed).
enum ModulaKnownApps {
    static func appName(for url: URL) -> String? {
        guard let host = url.host?.lowercased().replacingOccurrences(of: "www.", with: "") else { return nil }
        let table: [(String, String)] = [
            ("youtube.com", "YouTube"), ("youtu.be", "YouTube"), ("m.youtube.com", "YouTube"),
            ("open.spotify.com", "Spotify"), ("music.apple.com", "Music"), ("podcasts.apple.com", "Podcasts"),
            ("maps.apple.com", "Maps"), ("apps.apple.com", "App Store"), ("x.com", "X"), ("twitter.com", "X"),
            ("instagram.com", "Instagram"), ("tiktok.com", "TikTok"), ("reddit.com", "Reddit"),
            ("github.com", "GitHub"), ("linkedin.com", "LinkedIn"), ("amazon.com", "Amazon"), ("amazon.co.uk", "Amazon")
        ]
        return table.first(where: { host == $0.0 || host.hasSuffix("." + $0.0) })?.1
    }
}
