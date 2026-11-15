import AVFoundation
import SafariServices
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
        applyContentPolicies(for: url, force: true)
        reload()
    }

    /// Installed extensions that match this site but haven't been allowed or declined here yet.
    var extensionPrompt: [BrowserExtensionManifest] = []
    @ObservationIgnored private var policyKey = ""

    /// One place that owns the content controller: tracker rules + the extensions allowed on this
    /// site (rule lists and CSS). Rebuilt only when the host or the active set changes.
    func applyContentPolicies(for target: URL, force: Bool = false) {
        let extensions = ModulaBrowserExtensions.shared
        let trackers = ModulaPreferences.bool("settings.links.blockTrackers", true)
        let active = extensions.active(for: target).map { $0.id + "@" + $0.version }
        let key = (target.host ?? "") + "|" + active.joined(separator: ",") + "|" + (trackers ? "t" : "")
        extensionPrompt = extensions.needsPrompt(for: target)
        guard force || key != policyKey else { return }
        policyKey = key
        let controller = webView.configuration.userContentController
        controller.removeAllContentRuleLists()
        controller.removeAllUserScripts()
        if trackers, let rules = ModulaBrowserWarmup.trackerRules { controller.add(rules) }
        extensions.apply(to: controller, url: target)
    }

    /// Answer to the per-site permission card.
    func decideExtension(_ manifest: BrowserExtensionManifest, allow: Bool) {
        guard let host = url.host else { return }
        ModulaBrowserExtensions.shared.setDecision(manifest.id, host: host, allow ? .allowed : .denied)
        applyContentPolicies(for: url, force: true)
        if allow { reload() }
    }

    func scrollToTop() {
        let scroll = webView.scrollView
        scroll.setContentOffset(CGPoint(x: 0, y: -scroll.adjustedContentInset.top), animated: true)
        barsHidden = false
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
        applyContentPolicies(for: url)
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
            // Extensions are per site: rebuild rules/CSS before a main-frame load to a new host.
            if navigationAction.targetFrame?.isMainFrame == true, ["http", "https"].contains(scheme) {
                applyContentPolicies(for: target)
            }
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
    @State private var showQR = false
    @State private var showExtensions = false
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
                if let manifest = page.extensionPrompt.first, clamped > 0.9, reader == nil {
                    extensionPromptCard(manifest)
                        .padding(.horizontal, 12)
                        .padding(.top, safe.top + 56)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
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
            .task {
                // Hidden unless the server advertises browser extensions.
                await ModulaBrowserExtensions.shared.probeIfNeeded(client: app.client)
                page.applyContentPolicies(for: page.url)
            }
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
        .background { browserShortcuts }
        // "Always use Reader on <site>": open Reader once a page from that site finishes loading.
        .onChange(of: page.isLoading) { _, loading in
            guard !loading, reader == nil, !readerLoading, page.failure == nil,
                  ModulaReaderAutoDomains.contains(page.domain) else { return }
            Task { await toggleReader() }
        }

        .sheet(isPresented: $showExtensions, onDismiss: { page.applyContentPolicies(for: page.url, force: true) }) {
            ModulaBrowserExtensionsView(currentHost: page.url.host)
                .presentationDetents([.medium, .large])
                .modulaSheetStyle()
        }
        .sheet(isPresented: $showQR) {
            ModulaBrowserQRSheet(url: page.url, title: page.title)
                .presentationDetents([.medium])
                .modulaSheetStyle()
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
                ModulaReaderView(article: reader, scale: page.zoom, bottomInset: height - top, domain: page.domain,
                                 tweaks: ModulaBrowserExtensions.shared.readerTweaks(for: page.url)) { self.reader = nil }
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
                // Long-press: scroll to top, or reload bypassing the cache.
                .contextMenu {
                    Button { page.scrollToTop() } label: { Label("Scroll to top", systemImage: "arrow.up.to.line") }
                    Button { page.webView.reloadFromOrigin(); HapticEngine.shared.play(.lightImpact) } label: {
                        Label("Reload from server", systemImage: "arrow.clockwise.circle")
                    }
                }
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
            // VoiceOver rotor actions on the address element.
            .accessibilityAction(named: "Back") { if page.canGoBack { page.webView.goBack() } }
            .accessibilityAction(named: "Forward") { if page.canGoForward { page.webView.goForward() } }
            .accessibilityAction(named: "Reload") { page.reload() }
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
        // Swipe the address pill sideways: back / forward.
        .simultaneousGesture(
            DragGesture(minimumDistance: 24).onEnded { value in
                guard abs(value.translation.width) > 70, abs(value.translation.height) < 40 else { return }
                if value.translation.width > 0, page.canGoBack { page.webView.goBack() }
                else if value.translation.width < 0, page.canGoForward { page.webView.goForward() }
                else { return }
                HapticEngine.shared.play(.selection)
            }
        )
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

    /// Per-site permission: "Allow <extension> on <site>?" Asked once per site; changeable in Extensions.
    private func extensionPromptCard(_ manifest: BrowserExtensionManifest) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "puzzlepiece.extension").font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text("Allow \(manifest.name) on \(page.domain)?").font(.subheadline.weight(.semibold)).lineLimit(2)
                Text("It can change how this site looks and what it loads.").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button("Not now") { page.decideExtension(manifest, allow: false); HapticEngine.shared.play(.selection) }
                .buttonStyle(.modulaSecondary)
            Button("Allow") { page.decideExtension(manifest, allow: true); HapticEngine.shared.play(.success) }
                .buttonStyle(.modulaPrimary)
        }
        .padding(12)
        .modulaGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous), interactive: false)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("browser.extension.prompt")
    }

    private func runPageAction(_ action: BrowserExtensionManifest.PageAction) {
        switch action.kind {
        case .shareToModula:
            showModulaShare = true
        case .openURL:
            guard let template = action.urlTemplate,
                  let target = ModulaBrowserExtensions.fill(template, page: page.url, title: page.title) else {
                HapticEngine.shared.play(.failure); return
            }
            reader = nil
            page.webView.load(URLRequest(url: target))
        }
        HapticEngine.shared.play(.selection)
    }

    private var moreMenu: some View {
        Menu {
            Section {
                Button { copyLink() } label: { Label("Copy link", systemImage: "link") }
                ShareLink(item: page.url) { Label("Share", systemImage: "square.and.arrow.up") }
                Button { showModulaShare = true } label: { Label("Share to Modula…", systemImage: "paperplane") }
                Button { UIApplication.shared.open(page.url) } label: { Label("Open in Safari", systemImage: "safari") }
                Button { copyMarkdownLink() } label: { Label("Copy as Markdown", systemImage: "text.badge.plus") }
                Button { addToReadingList() } label: { Label("Add to Reading List", systemImage: "eyeglasses") }
                Button { printPage() } label: { Label("Print…", systemImage: "printer") }
                Button { showQR = true } label: { Label("QR code", systemImage: "qrcode") }
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
            if ModulaBrowserExtensions.shared.enabled {
                Section("Extensions") {
                    ForEach(ModulaBrowserExtensions.shared.pageActions(for: page.url)) { action in
                        Button { runPageAction(action) } label: {
                            Label(action.title, systemImage: action.symbol ?? "puzzlepiece.extension")
                        }
                    }
                    Button { showExtensions = true } label: { Label("Extensions…", systemImage: "puzzlepiece.extension") }
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

    private func copyMarkdownLink() {
        let title = (page.title?.isEmpty == false ? page.title! : page.domain).replacingOccurrences(of: "]", with: "\\]")
        UIPasteboard.general.string = "[\(title)](\(page.url.absoluteString))"
        HapticEngine.shared.play(.success)
        show("Markdown link copied")
    }

    /// Safari Reading List (on-device; no Modula server involved).
    private func addToReadingList() {
        guard SSReadingList.supportsURL(page.url), let list = SSReadingList.default() else {
            show("Can't add this page to Reading List")
            return
        }
        do {
            try list.addItem(with: page.url, title: page.title, previewText: nil)
            HapticEngine.shared.play(.success)
            show("Added to Reading List")
        } catch {
            HapticEngine.shared.play(.failure)
            show("Couldn't add to Reading List")
        }
    }

    private func printPage() {
        let info = UIPrintInfo(dictionary: nil)
        info.outputType = .general
        info.jobName = page.title ?? page.domain
        let printer = UIPrintInteractionController.shared
        printer.printInfo = info
        printer.printFormatter = page.webView.viewPrintFormatter()
        _ = printer.present(animated: true, completionHandler: nil)
    }

    /// Hardware keyboard: ⌘W close, ⌘R reload, ⌘[ / ⌘] back/forward, ⌘L address, ⌘F find, ⇧⌘R reader.
    private var browserShortcuts: some View {
        Group {
            Button("Close") { close() }.keyboardShortcut("w", modifiers: .command)
            Button("Reload") { page.reload() }.keyboardShortcut("r", modifiers: .command)
            Button("Back") { if page.canGoBack { page.webView.goBack() } }.keyboardShortcut("[", modifiers: .command)
            Button("Forward") { if page.canGoForward { page.webView.goForward() } }.keyboardShortcut("]", modifiers: .command)
            Button("Address") { showAddress = true }.keyboardShortcut("l", modifiers: .command)
            Button("Find on page") { page.presentFind() }.keyboardShortcut("f", modifiers: .command)
            Button("Reader") { Task { await toggleReader() } }.keyboardShortcut("r", modifiers: [.command, .shift])
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
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
    var domain: String = ""
    /// Reader tweaks from an active browser extension (font, hide images); user settings otherwise.
    var tweaks: BrowserExtensionManifest.ReaderTweaks? = nil
    var onClose: () -> Void
    @State private var autoReader = false
    @ScaledMetric private var bodySize: CGFloat = 19
    @AppStorage("browser.reader.theme") private var themeRaw = ReaderTheme.auto.rawValue
    @AppStorage("browser.reader.font") private var fontRaw = ReaderFont.serif.rawValue
    @AppStorage("browser.reader.size") private var sizeStep = 0.0
    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: Double = 0
    @State private var speaker = ModulaReaderSpeaker()

    /// Plain text of the article (title, then blocks), for Listen / Copy / Share.
    private var plainText: String {
        var parts = [article.title]
        for block in article.blocks {
            switch block {
            case .heading(let t), .paragraph(let t), .quote(let t): parts.append(t)
            case .listItem(let t): parts.append("• " + t)
            case .image: break
            }
        }
        return parts.joined(separator: "\n\n")
    }

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
    private var design: Font.Design { (ReaderFont(rawValue: tweaks?.font ?? fontRaw) ?? ReaderFont(rawValue: fontRaw) ?? .serif).design }
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
        .onDisappear { speaker.stop() }
        .onAppear { autoReader = ModulaReaderAutoDomains.contains(domain) }
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
            if tweaks?.hideImages != true {
                ModulaRemoteImage(url: url, cacheKey: "reader:\(url.absoluteString)", maximumPixelSize: 1200) { phase in
                    if case .success(let image) = phase { Image(uiImage: image).resizable().scaledToFit() } else { Color.primary.opacity(0.05).frame(height: 180) }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.vertical, 4)
            }
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
                    if !domain.isEmpty {
                        Toggle(isOn: Binding(get: { autoReader }, set: { on in
                            autoReader = on
                            ModulaReaderAutoDomains.set(on, for: domain)
                            HapticEngine.shared.play(.selection)
                        })) {
                            Label("Always use Reader on \(domain)", systemImage: "doc.plaintext")
                        }
                    }
                    Section {
                        Button { speaker.toggle(plainText) } label: {
                            Label(speaker.speaking ? "Stop listening" : "Listen", systemImage: speaker.speaking ? "stop.fill" : "headphones")
                        }
                        Button {
                            UIPasteboard.general.string = plainText
                            HapticEngine.shared.play(.success)
                            ModulaToastCenter.shared.show("Article copied", symbol: "doc.on.doc")
                        } label: { Label("Copy article text", systemImage: "doc.on.doc") }
                        ShareLink(item: plainText) { Label("Share article text", systemImage: "square.and.arrow.up") }
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

    static func remove(_ ids: Set<String>) {
        let items = load().filter { !ids.contains($0.id) }
        if let data = try? JSONEncoder().encode(items) { UserDefaults.standard.set(data, forKey: key) }
    }
}

private struct ModulaBrowserHistoryView: View {
    var onOpen: (URL) -> Void
    @State private var entries = ModulaBrowserHistory.load()
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    /// Search by title or address (local only).
    private var shown: [ModulaBrowserHistory.Entry] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return entries }
        return entries.filter { ($0.title ?? "").localizedCaseInsensitiveContains(q) || $0.url.absoluteString.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        NavigationStack {
            List {
                if entries.isEmpty {
                    ContentUnavailableView("No history yet", systemImage: "clock", description: Text("Pages you open in Modula stay on this device only."))
                } else if shown.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
                ForEach(shown) { entry in
                    Button { onOpen(entry.url) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.title?.isEmpty == false ? entry.title! : (entry.url.host ?? entry.url.absoluteString)).lineLimit(1)
                            Text("\(entry.url.host ?? "") · \(entry.visitedAt.formatted(.relative(presentation: .named)))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            ModulaBrowserHistory.remove([entry.id])
                            entries.removeAll { $0.id == entry.id }
                            HapticEngine.shared.play(.selection)
                        } label: { Label("Delete", systemImage: "trash") }
                    }
                    .contextMenu {
                        Button { UIPasteboard.general.url = entry.url } label: { Label("Copy link", systemImage: "link") }
                        ShareLink(item: entry.url) { Label("Share", systemImage: "square.and.arrow.up") }
                    }
                }
            }
            .searchable(text: $query, prompt: "Search history")
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
    @State private var history = ModulaBrowserHistory.load()

    private var suggestions: [ModulaBrowserHistory.Entry] {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2, q != url.absoluteString else { return [] }
        return Array(history.lazy.filter {
            $0.url != url && (($0.title ?? "").localizedCaseInsensitiveContains(q) || $0.url.absoluteString.localizedCaseInsensitiveContains(q))
        }.prefix(5))
    }

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
                    if UIPasteboard.general.hasURLs || UIPasteboard.general.hasStrings {
                        Button("Paste and go", systemImage: "doc.on.clipboard") {
                            if let pasted = UIPasteboard.general.url?.absoluteString ?? UIPasteboard.general.string {
                                text = pasted
                                go()
                            }
                        }
                        .buttonStyle(.modulaSecondary)
                    }
                    Button("Go", systemImage: "arrow.right", action: go)
                        .buttonStyle(.modulaPrimary)
                }
                // Local history matches as you type (this device only).
                if !suggestions.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("History").font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.bottom, 6)
                        ForEach(suggestions) { entry in
                            Button {
                                onGo(entry.url)
                                dismiss()
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "clock").font(.footnote).foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(entry.title?.isEmpty == false ? entry.title! : (entry.url.host ?? entry.url.absoluteString)).lineLimit(1)
                                        Text(entry.url.absoluteString).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
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


/// Reader "Listen": on-device speech for the extracted article text.
@MainActor @Observable
final class ModulaReaderSpeaker: NSObject, AVSpeechSynthesizerDelegate {
    private(set) var speaking = false
    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func toggle(_ text: String) {
        if synthesizer.isSpeaking {
            stop()
            return
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.prefersAssistiveTechnologySettings = true
        synthesizer.speak(utterance)
        speaking = true
        HapticEngine.shared.play(.selection)
    }

    func stop() {
        guard synthesizer.isSpeaking || speaking else { return }
        synthesizer.stopSpeaking(at: .immediate)
        speaking = false
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.speaking = false }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.speaking = false }
    }
}


/// Page address as a QR code (generated on device), e.g. to open it on another phone.
private struct ModulaBrowserQRSheet: View {
    let url: URL
    let title: String?
    @State private var image: UIImage?

    var body: some View {
        VStack(spacing: 14) {
            Group {
                if let image {
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                } else {
                    ProgressView()
                }
            }
            .frame(width: 220, height: 220)
            .padding(16)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .accessibilityLabel("QR code for \(url.host ?? url.absoluteString)")
            Text(title?.isEmpty == false ? title! : (url.host ?? "Page"))
                .font(.headline)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Text(url.absoluteString)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
            if let image {
                ShareLink(item: Image(uiImage: image), preview: SwiftUI.SharePreview("QR code", image: Image(uiImage: image))) {
                    Label("Share QR code", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.modulaSecondary)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .task { image = ModulaProfileCodeView.qrImage(for: url.absoluteString) }
    }
}


/// Sites the user asked to always open in Reader (this device only).
enum ModulaReaderAutoDomains {
    private static let key = "browser.reader.autoDomains"
    static func contains(_ domain: String) -> Bool {
        !domain.isEmpty && (UserDefaults.standard.stringArray(forKey: key) ?? []).contains(domain)
    }
    static func set(_ on: Bool, for domain: String) {
        var all = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
        if on { all.insert(domain) } else { all.remove(domain) }
        UserDefaults.standard.set(Array(all).sorted(), forKey: key)
    }
}

// MARK: - Browser extensions (declarative modules, manifest-only v1)

/// A published "browser_extension" module. Manifest-only: no arbitrary JavaScript. Everything it can
/// do is declared data that the native host interprets (see /workspace/BROWSER-EXTENSIONS.md).
struct BrowserExtensionManifest: Codable, Equatable, Identifiable, Sendable {
    struct PageAction: Codable, Hashable, Identifiable, Sendable {
        enum Kind: String, Codable, Sendable { case openURL = "open_url", shareToModula = "share_to_modula" }
        var id: String
        var title: String
        var symbol: String?
        var kind: Kind
        /// For open_url: https template with {url}, {host}, {title} placeholders (percent-encoded on fill).
        var urlTemplate: String?
    }
    struct ReaderTweaks: Codable, Hashable, Sendable {
        var hideImages: Bool?
        /// "serif" | "sans" | "rounded"
        var font: String?
    }

    var id: String
    var name: String
    var version: String
    var publisherName: String?
    var summary: String?
    /// Host patterns: "example.com", "*.example.com" or "*" (all sites, still per-site permission).
    var matches: [String]
    /// WKContentRuleList JSON (array of {trigger, action}); compiled natively, never executed.
    var blockRules: JSONValue?
    /// Plain CSS inserted as a <style> element by a fixed native template.
    var css: String?
    var pageActions: [PageAction]?
    var reader: ReaderTweaks?
    /// Registry review + signing (verified by the server before it is listed; the client also
    /// refuses anything not approved or unsigned).
    var reviewStatus: String?
    var signature: String?

    func matches(host: String) -> Bool {
        let host = host.lowercased()
        return matches.contains { raw in
            let pattern = raw.lowercased()
            if pattern == "*" { return true }
            if pattern.hasPrefix("*.") {
                let base = String(pattern.dropFirst(2))
                return host == base || host.hasSuffix("." + base)
            }
            return host == pattern || host == "www." + pattern
        }
    }

    var isTrusted: Bool { reviewStatus == "approved" && !(signature ?? "").isEmpty }
}

/// Native host for browser extensions. Hidden entirely unless the server advertises the capability.
@MainActor @Observable
final class ModulaBrowserExtensions {
    static let shared = ModulaBrowserExtensions()

    enum SiteDecision: String, Codable { case allowed, denied }

    /// `GET /v1/browser-extensions/capabilities` → `{ "enabled": true, "schemaVersion": 1 }`.
    private(set) var enabled = false
    private(set) var catalog: [BrowserExtensionManifest] = []
    private(set) var installedIDs: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "browser.extensions.installed") ?? [])
    /// extensionID → host → decision. Per-site permission (asked once) and per-site toggle.
    private(set) var siteDecisions: [String: [String: SiteDecision]] = ModulaBrowserExtensions.loadDecisions()
    @ObservationIgnored private var probed = false
    @ObservationIgnored private var compiled: [String: WKContentRuleList] = [:]

    static let capabilitiesPath = "/v1/browser-extensions/capabilities"
    static let catalogPath = "/v1/browser-extensions"

    func probeIfNeeded(client: GreenfieldClient?) async {
        guard !probed, let client else { return }
        probed = true
        guard let caps = try? await client.json("GET", path: Self.capabilitiesPath),
              caps["enabled"]?.bool == true, (caps["schemaVersion"]?.int ?? 1) <= 1 else { return }
        enabled = true
        await refreshCatalog(client: client)
    }

    func refreshCatalog(client: GreenfieldClient) async {
        guard enabled, let value = try? await client.json("GET", path: Self.catalogPath) else { return }
        let items = value["items"]?.array ?? value.array ?? []
        let decoded: [BrowserExtensionManifest] = items.compactMap { item in
            guard let data = try? JSONEncoder().encode(item) else { return nil }
            return try? JSONDecoder().decode(BrowserExtensionManifest.self, from: data)
        }
        catalog = decoded.filter(\.isTrusted)
        await compileRules()
    }

    func resetForAccountChange() { probed = false; enabled = false; catalog = [] }

    // MARK: Install / permissions

    func isInstalled(_ id: String) -> Bool { installedIDs.contains(id) }

    func setInstalled(_ id: String, _ on: Bool) {
        if on { installedIDs.insert(id) } else { installedIDs.remove(id); siteDecisions[id] = nil; saveDecisions() }
        UserDefaults.standard.set(Array(installedIDs).sorted(), forKey: "browser.extensions.installed")
        Task { await compileRules() }
    }

    func decision(_ id: String, host: String) -> SiteDecision? { siteDecisions[id]?[Self.siteKey(host)] }

    func setDecision(_ id: String, host: String, _ decision: SiteDecision?) {
        var hosts = siteDecisions[id] ?? [:]
        hosts[Self.siteKey(host)] = decision
        siteDecisions[id] = hosts.isEmpty ? nil : hosts
        saveDecisions()
    }

    /// Installed, trusted extensions that match this host.
    func candidates(for host: String) -> [BrowserExtensionManifest] {
        guard enabled, !host.isEmpty else { return [] }
        return catalog.filter { installedIDs.contains($0.id) && $0.matches(host: host) }
    }

    /// Extensions allowed to run on this page (permission granted, not a sensitive page).
    func active(for url: URL) -> [BrowserExtensionManifest] {
        guard let host = url.host, !Self.isSensitive(url) else { return [] }
        return candidates(for: host).filter { decision($0.id, host: host) == .allowed }
    }

    /// Installed extensions that match but haven't been asked about on this site yet.
    func needsPrompt(for url: URL) -> [BrowserExtensionManifest] {
        guard let host = url.host, !Self.isSensitive(url) else { return [] }
        return candidates(for: host).filter { decision($0.id, host: host) == nil }
    }

    // MARK: Applying to a web view

    /// Content rules + CSS for the extensions active on `url`. Called by `ModulaWebPage` whenever
    /// its policies are rebuilt (load, host change, toggles).
    func apply(to controller: WKUserContentController, url: URL) {
        for ext in active(for: url) {
            if let list = compiled[ext.id + "@" + ext.version] { controller.add(list) }
            if let css = ext.css, !css.isEmpty, css.utf8.count < 64_000 {
                controller.addUserScript(Self.styleScript(css: css, id: ext.id))
            }
        }
    }

    func readerTweaks(for url: URL) -> BrowserExtensionManifest.ReaderTweaks? {
        active(for: url).compactMap(\.reader).first
    }

    /// Page actions of the extensions active on this page; ids are namespaced by extension.
    func pageActions(for url: URL) -> [BrowserExtensionManifest.PageAction] {
        active(for: url).flatMap { ext in
            (ext.pageActions ?? []).prefix(4).map { action in
                var action = action
                action.id = ext.id + "." + action.id
                return action
            }
        }
    }

    /// Fills an https URL template; nothing else is allowed.
    static func fill(_ template: String, page: URL, title: String?) -> URL? {
        func enc(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=?+#"))) ?? "" }
        let filled = template
            .replacingOccurrences(of: "{url}", with: enc(page.absoluteString))
            .replacingOccurrences(of: "{host}", with: enc(page.host ?? ""))
            .replacingOccurrences(of: "{title}", with: enc(title ?? ""))
        guard let url = URL(string: filled), url.scheme?.lowercased() == "https", url.host != nil else { return nil }
        return url
    }

    // MARK: Safety

    /// Never inject on sign-in or payment pages: known auth/payment hosts and login-like paths here;
    /// pages with a password field are also skipped by the injected style template itself.
    static func isSensitive(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return true }
        let hosts = ["accounts.google.com", "appleid.apple.com", "idmsa.apple.com", "login.microsoftonline.com",
                     "login.live.com", "auth0.com", "okta.com", "paypal.com", "stripe.com", "checkout.stripe.com",
                     "pay.google.com", "klarna.com", "adyen.com", "braintreegateway.com", "squareup.com",
                     "modula.digital"]
        if hosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) { return true }
        let prefixes = ["login.", "auth.", "accounts.", "account.", "signin.", "sso.", "secure.", "pay.", "checkout.", "billing."]
        if prefixes.contains(where: { host.hasPrefix($0) }) { return true }
        let path = url.path.lowercased()
        let words = ["/login", "/signin", "/sign-in", "/auth", "/oauth", "/checkout", "/payment", "/billing", "/account/security", "/2fa"]
        return words.contains { path.contains($0) }
    }

    /// Fixed template: inserts one <style> with the manifest's CSS (as a JSON string literal), and
    /// does nothing on pages that contain a password or card field. Runs in an isolated content world.
    private static func styleScript(css: String, id: String) -> WKUserScript {
        let cssLiteral = (try? String(data: JSONEncoder().encode(css), encoding: .utf8)) ?? "\"\""
        let idLiteral = (try? String(data: JSONEncoder().encode("modula-ext-" + id), encoding: .utf8)) ?? "\"modula-ext\""
        let source = """
        (function(){
          if (document.querySelector('input[type=password], input[autocomplete~="cc-number"], input[autocomplete~="one-time-code"]')) return;
          if (document.getElementById(\(idLiteral))) return;
          var s = document.createElement('style'); s.id = \(idLiteral); s.textContent = \(cssLiteral);
          (document.head || document.documentElement).appendChild(s);
        })();
        """
        return WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient)
    }

    // MARK: Storage / compile

    private func compileRules() async {
        guard let store = WKContentRuleListStore.default() else { return }
        for ext in catalog where installedIDs.contains(ext.id) {
            let key = ext.id + "@" + ext.version
            guard compiled[key] == nil, let rules = ext.blockRules, case .array(let array) = rules, !array.isEmpty, array.count <= 5_000,
                  let data = try? JSONEncoder().encode(rules), let json = String(data: data, encoding: .utf8) else { continue }
            if let list = try? await store.compileContentRuleList(forIdentifier: "modula.ext." + key, encodedContentRuleList: json) {
                compiled[key] = list
            }
        }
    }

    private static func siteKey(_ host: String) -> String {
        host.lowercased().replacingOccurrences(of: "www.", with: "")
    }

    private static func loadDecisions() -> [String: [String: SiteDecision]] {
        guard let data = UserDefaults.standard.data(forKey: "browser.extensions.sites"),
              let value = try? JSONDecoder().decode([String: [String: SiteDecision]].self, from: data) else { return [:] }
        return value
    }

    private func saveDecisions() {
        if let data = try? JSONEncoder().encode(siteDecisions) { UserDefaults.standard.set(data, forKey: "browser.extensions.sites") }
    }
}

/// Extensions manager: install / remove, and each extension's per-site permissions.
struct ModulaBrowserExtensionsView: View {
    /// When opened from the browser: the current site, for the quick "on this site" toggles.
    var currentHost: String?
    @State private var store = ModulaBrowserExtensions.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if !store.enabled {
                    ContentUnavailableView("Extensions aren’t available", systemImage: "puzzlepiece.extension",
                                           description: Text("Browser extensions appear here when Modula offers them."))
                } else if store.catalog.isEmpty {
                    ContentUnavailableView("No extensions yet", systemImage: "puzzlepiece.extension",
                                           description: Text("Reviewed extensions from the Modula registry will be listed here."))
                }
                if let host = currentHost, store.enabled {
                    let here = store.candidates(for: host)
                    if !here.isEmpty {
                        Section("On \(host)") {
                            ForEach(here) { ext in
                                Toggle(isOn: Binding(
                                    get: { store.decision(ext.id, host: host) == .allowed },
                                    set: { store.setDecision(ext.id, host: host, $0 ? .allowed : .denied); HapticEngine.shared.play(.selection) }
                                )) { Label(ext.name, systemImage: "puzzlepiece.extension") }
                            }
                        }
                    }
                }
                ForEach(store.catalog) { ext in
                    Section {
                        Toggle(isOn: Binding(get: { store.isInstalled(ext.id) }, set: { store.setInstalled(ext.id, $0); HapticEngine.shared.play(.selection) })) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ext.name).font(.body.weight(.semibold))
                                Text([ext.publisherName, "v\(ext.version)"].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        if let summary = ext.summary, !summary.isEmpty {
                            Text(summary).font(.footnote).foregroundStyle(.secondary)
                        }
                        Text(capabilitiesLine(ext)).font(.caption).foregroundStyle(.secondary)
                        if store.isInstalled(ext.id), let sites = store.siteDecisions[ext.id], !sites.isEmpty {
                            ForEach(sites.keys.sorted(), id: \.self) { site in
                                HStack {
                                    Text(site)
                                    Spacer()
                                    Text(sites[site] == .allowed ? "Allowed" : "Off").foregroundStyle(.secondary)
                                }
                                .font(.subheadline)
                                .swipeActions {
                                    Button("Forget", role: .destructive) { store.setDecision(ext.id, host: site, nil) }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Extensions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task {
                await store.probeIfNeeded(client: ModulaBrowserPresenter.shared.environment?.client)
            }
        }
        .tint(.primary)
    }

    private func capabilitiesLine(_ ext: BrowserExtensionManifest) -> String {
        var parts: [String] = []
        if ext.blockRules != nil { parts.append("Blocks content") }
        if !(ext.css ?? "").isEmpty { parts.append("Restyles pages") }
        if !(ext.pageActions ?? []).isEmpty { parts.append("Menu actions") }
        if ext.reader != nil { parts.append("Reader tweaks") }
        let sites = ext.matches.contains("*") ? "all sites (asks per site)" : ext.matches.prefix(3).joined(separator: ", ")
        return (parts.isEmpty ? "No permissions" : parts.joined(separator: " · ")) + " — " + sites
    }
}
