import SwiftUI
import WebKit

/// Full-screen GUBIC player: a sandboxed WKWebView running an HTML5/Phaser package with the
/// `window.gubic` bridge. Sessions and achievements go to Greenfield only for catalogue games.
struct GubicPlayerView: View {
    let source: GubicGameSource
    let store: GubicStore
    var lobbyId: String? = nil
    let close: () -> Void

    @Environment(AppEnvironment.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var paused = false
    @State private var score = 0
    @State private var toast: String?
    @State private var processFailed = false
    @State private var sessionId: String?
    @State private var sessionNote: String?
    @State private var controller = GubicWebController()

    private var accent: Color { app.appearance.liveAccent }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            GubicWebSurface(source: source, reduceMotion: reduceMotion, handle: app.auth.account?.primaryHandle,
                            controller: controller, onMessage: handle, onProcessFailed: { processFailed = true })
                .ignoresSafeArea(edges: .bottom)
                .padding(.top, 60)
                .accessibilityIdentifier("gubic.player.surface")
            topBar
            if let toast {
                Label(toast, systemImage: "trophy.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, ModulaSpacing.lg).frame(height: 44)
                    .modulaGlass(in: Capsule(), interactive: false, tint: accent.opacity(0.35))
                    .padding(.top, 72)
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                    .accessibilityIdentifier("gubic.player.toast")
            }
            if paused || processFailed { overlay }
        }
        .statusBarHidden()
        .toolbar(.hidden, for: .tabBar)
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: scenePhase) { _, phase in if phase != .active { setPaused(true) } }
        .task { await beginSession() }
        .task(id: sessionId) { await heartbeatLoop() }
        .onDisappear { controller.tearDown(); endSession() }
    }

    private var topBar: some View {
        HStack(spacing: ModulaSpacing.sm) {
            Button { close() } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                .accessibilityLabel("Exit game").accessibilityIdentifier("gubic.player.exit")
                .modulaGlass(in: Circle(), interactive: true, tint: accent.opacity(0.3))
            VStack(alignment: .leading, spacing: 0) {
                Text(source.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(sessionNote ?? "Score \(score)").font(.caption).foregroundStyle(.white.opacity(0.75)).lineLimit(1)
                    .accessibilityIdentifier("gubic.player.score")
            }
            Spacer()
            Button { setPaused(!paused) } label: { Image(systemName: paused ? "play.fill" : "pause.fill").frame(width: 44, height: 44) }
                .accessibilityLabel(paused ? "Resume" : "Pause").accessibilityIdentifier("gubic.player.pause")
                .modulaGlass(in: Circle(), interactive: true, tint: accent.opacity(0.3))
        }
        .foregroundStyle(.white)
        .tint(accent)
        .padding(.horizontal, ModulaSpacing.md)
        .padding(.top, 6)
    }

    private var overlay: some View {
        VStack(spacing: ModulaSpacing.md) {
            Text(processFailed ? "Game interrupted" : "Paused").font(.title2.bold())
            if processFailed {
                Text("The game's web process stopped. Reopen it to continue.").font(.subheadline).multilineTextAlignment(.center)
            }
            ModulaButton(title: processFailed ? "Reopen" : "Resume", symbol: processFailed ? "arrow.clockwise" : "play.fill") {
                if processFailed { processFailed = false; controller.reload() } else { setPaused(false) }
            }
            Button("Exit game") { close() }
                .font(.headline).foregroundStyle(accent).frame(minHeight: 44)
        }
        .foregroundStyle(.white)
        .padding(ModulaSpacing.xl)
        .frame(maxWidth: 360)
        .modulaGlass(in: RoundedRectangle(cornerRadius: ModulaRadius.xl, style: .continuous), interactive: false)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.55).ignoresSafeArea())
    }

    private func setPaused(_ value: Bool) {
        paused = value
        controller.dispatch(value ? "gubic:pause" : "gubic:resume", suspendMedia: value)
    }

    private func handle(_ message: GubicBridgeMessage) {
        switch message {
        case .ready: break
        case .score(let value): score = value
        case .gameOver(let value):
            score = value
            HapticEngine.shared.play(.selection)
        case .achievement(let key): unlock(key)
        }
    }

    private func unlock(_ key: String) {
        if source.serverBacked {
            guard let sessionId else { return }
            Task {
                if let result = try? await store.unlock(sessionId: sessionId, key: key), result.new {
                    show("\(result.title) · \(result.points) pts")
                }
            }
        } else if let local = source.localAchievements.first(where: { $0.key == key }) {
            // Bundled sample: preview only, never recorded on the server.
            show("\(local.title) · preview, not recorded")
        }
    }

    private func show(_ text: String) {
        withAnimation(reduceMotion ? nil : .snappy) { toast = text }
        HapticEngine.shared.play(.selection)
        Task {
            try? await Task.sleep(for: .seconds(2.4))
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { if toast == text { toast = nil } }
        }
    }

    private func beginSession() async {
        guard source.serverBacked else {
            sessionNote = "Bundled sample · progress isn't saved"
            return
        }
        do {
            sessionId = try await store.startSession(gameId: source.id, lobbyId: lobbyId)
        } catch {
            sessionNote = "Playing offline · session not recorded"
        }
    }

    private func heartbeatLoop() async {
        guard let sessionId else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(60))
            if Task.isCancelled { break }
            await store.heartbeat(sessionId: sessionId)
        }
    }

    private func endSession() {
        guard let sessionId else { return }
        let store = store
        Task { await store.endSession(sessionId: sessionId) }
    }
}

/// Owns the live web view so SwiftUI state changes never rebuild the game.
@MainActor
final class GubicWebController {
    fileprivate weak var webView: WKWebView?
    fileprivate var handler: GubicSchemeHandler?

    func dispatch(_ event: String, suspendMedia: Bool) {
        webView?.setAllMediaPlaybackSuspended(suspendMedia, completionHandler: nil)
        webView?.evaluateJavaScript("window.dispatchEvent(new Event('\(event)'))")
    }

    func reload() { webView?.reload() }

    func tearDown() {
        handler?.close()
        webView?.stopLoading()
        webView?.configuration.userContentController.removeAllScriptMessageHandlers()
        webView?.loadHTMLString("", baseURL: nil)
    }
}

private struct GubicWebSurface: UIViewRepresentable {
    let source: GubicGameSource
    let reduceMotion: Bool
    let handle: String?
    let controller: GubicWebController
    let onMessage: (GubicBridgeMessage) -> Void
    let onProcessFailed: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let handler = GubicSchemeHandler(files: source.files)
        context.coordinator.handler = handler
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.setURLSchemeHandler(handler, forURLScheme: GubicSchemeHandler.scheme)
        var hello: [String: Any] = [
            "bridgeVersion": 1, "reduceMotion": reduceMotion,
            "locale": Locale.current.identifier, "capabilities": source.capabilities.sorted(),
        ]
        hello["player"] = source.capabilities.contains("player.profile") ? (handle.map { ["handle": $0] } ?? NSNull()) : NSNull()
        let content = configuration.userContentController
        content.addUserScript(WKUserScript(source: GubicBridgeMessage.bootstrapScript(hello: hello), injectionTime: .atDocumentStart, forMainFrameOnly: true))
        content.addUserScript(WKUserScript(source: Self.denyDeviceAPIs, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        content.add(WeakMessageHandler(context.coordinator), name: "gubic")
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        view.isOpaque = false
        view.backgroundColor = .black
        view.scrollView.isScrollEnabled = false
        view.scrollView.contentInsetAdjustmentBehavior = .never
        view.isInspectable = false
        controller.webView = view
        controller.handler = handler
        view.load(URLRequest(url: handler.entryURL))
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) { context.coordinator.parent = self }

    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        coordinator.handler?.close()
        view.stopLoading()
        view.configuration.userContentController.removeAllScriptMessageHandlers()
        view.navigationDelegate = nil
        view.uiDelegate = nil
    }

    static let denyDeviceAPIs = #"""
    (() => {
      const denied = () => Promise.reject(new DOMException('Permission denied', 'NotAllowedError'));
      const block = (t, n, v) => { if (!t) return; try { Object.defineProperty(t, n, {value: v, writable: false, configurable: false}); } catch (_) {} };
      const media = navigator.mediaDevices;
      for (const target of [media, media && Object.getPrototypeOf(media)]) {
        block(target, 'getUserMedia', denied); block(target, 'getDisplayMedia', denied);
        block(target, 'enumerateDevices', () => Promise.resolve([]));
      }
      const geo = navigator.geolocation;
      const deny = (_, err) => { if (typeof err === 'function') queueMicrotask(() => err({code: 1, message: 'Permission denied'})); };
      for (const target of [geo, geo && Object.getPrototypeOf(geo)]) { block(target, 'getCurrentPosition', deny); block(target, 'watchPosition', (...a) => { deny(...a); return 0; }); }
      block(globalThis.DeviceMotionEvent, 'requestPermission', denied);
      block(globalThis.DeviceOrientationEvent, 'requestPermission', denied);
    })();
    """#

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        var parent: GubicWebSurface
        var handler: GubicSchemeHandler?
        private var limiter = GubicBridgeRateLimiter()

        init(_ parent: GubicWebSurface) { self.parent = parent }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.frameInfo.isMainFrame,
                  message.frameInfo.securityOrigin.protocol == GubicSchemeHandler.scheme,
                  message.frameInfo.securityOrigin.host == handler?.origin,
                  let parsed = GubicBridgeMessage.parse(message.body, capabilities: parent.source.capabilities) else { return }
            let type: String = switch parsed {
            case .ready: "ready"
            case .score: "score"
            case .achievement: "achievement"
            case .gameOver: "gameOver"
            }
            guard limiter.allow(type) else { return }
            parent.onMessage(parsed)
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url, handler?.allows(url) == true else { return decisionHandler(.cancel) }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? { nil }

        func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping @MainActor (WKPermissionDecision) -> Void) {
            decisionHandler(.deny)
        }

        func webView(_ webView: WKWebView, requestDeviceOrientationAndMotionPermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, decisionHandler: @escaping @MainActor (WKPermissionDecision) -> Void) {
            decisionHandler(.deny)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { parent.onProcessFailed() }
    }
}

/// WKUserContentController retains its handlers strongly; this breaks the cycle.
private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}
