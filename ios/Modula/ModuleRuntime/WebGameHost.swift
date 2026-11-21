import CryptoKit
import SwiftUI
import WebKit

/// Shared serve contract for the native html5 hosts, mirroring GUBIC platform
/// spec §4.2 (modula-latest PR #204). Origins stay native and stricter:
/// `modula-game://<sha256(account/module/digest)>/` on WebGameHost and
/// `gubic://<random per play>/` on the GUBIC player, not `modula-pkg://<packageId>/`.
enum WebGamePackageServe {
    /// Exact header CSP from docs/gubic/GUBIC-PLATFORM-SPEC.md §4.2.
    /// Applied to every handler response (200, 206, 404 and 416).
    static let headerContentSecurityPolicy = "default-src 'none'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; font-src 'self'; media-src 'self' blob:; connect-src 'self'; object-src 'none'; worker-src 'none'; child-src 'none'; frame-src 'none'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'"

    static let permissionsPolicy = "camera=(), microphone=(), geolocation=(), accelerometer=(), gyroscope=(), magnetometer=()"

    /// Percent-decoded once, then matched exactly to a manifest path.
    /// An encoded `/` (`%2F`) is never a separator and yields nil (404).
    /// Spaces and non-ASCII names decode and match the listed member.
    static func memberPath(of url: URL, scheme: String, origin: String) -> String? {
        guard url.scheme == scheme, url.host == origin else { return nil }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        if components.percentEncodedQuery != nil || components.percentEncodedFragment != nil { return nil }
        let encoded = components.percentEncodedPath
        if encoded.lowercased().contains("%2f") || encoded.contains("\\") { return nil }
        guard encoded.hasPrefix("/") else { return nil }
        let body = String(encoded.dropFirst())
        if body.isEmpty { return nil }
        var segments: [String] = []
        for raw in body.split(separator: "/", omittingEmptySubsequences: false) {
            if raw.isEmpty { return nil }
            guard let decoded = raw.removingPercentEncoding, !decoded.contains("/") , !decoded.contains("\\") else { return nil }
            if decoded == "." || decoded == ".." { return nil }
            segments.append(decoded)
        }
        let path = segments.joined(separator: "/")
        if path == "game.files.json" { return nil }
        return path
    }

    static func mimeType(forMemberPath path: String) -> String {
        switch URL(fileURLWithPath: path).pathExtension.lowercased() {
        case "html": return "text/html; charset=utf-8"
        case "js", "mjs": return "text/javascript; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "json": return "application/json"
        case "xml": return "application/xml"
        case "txt": return "text/plain; charset=utf-8"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "svg": return "image/svg+xml"
        case "mp3": return "audio/mpeg"
        case "ogg": return "audio/ogg"
        case "m4a": return "audio/mp4"
        case "wav": return "audio/wav"
        case "mp4": return "video/mp4"
        case "webm": return "video/webm"
        case "woff": return "font/woff"
        case "woff2": return "font/woff2"
        case "ttf": return "font/ttf"
        case "otf": return "font/otf"
        default: return "application/octet-stream"
        }
    }

    static func isHTML(_ mime: String?) -> Bool {
        guard let mime else { return false }
        return mime.lowercased().split(separator: ";").first?.trimmingCharacters(in: .whitespaces) == "text/html"
    }

    enum BytesReply {
        case complete
        case partial(Range<Int>)
        case unsatisfiable
    }

    /// A single `bytes=` range may be 206. Multi-range or malformed Range
    /// headers are ignored and the full file is returned with 200 (§4.2).
    /// An unsatisfiable single range is 416 with `Content-Range: bytes */N`.
    static func byteRange(header: String?, size: Int) -> BytesReply {
        guard let raw = header?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return .complete
        }
        guard raw.lowercased().hasPrefix("bytes=") else { return .complete }
        let spec = String(raw.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
        if spec.isEmpty || spec.contains(",") { return .complete }
        if spec.hasPrefix("-") {
            guard let suffix = Int(spec.dropFirst()), suffix > 0 else { return .complete }
            guard size > 0 else { return .unsatisfiable }
            let length = min(suffix, size)
            return .partial((size - length)..<size)
        }
        let parts = spec.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, let start = Int(parts[0]), start >= 0 else { return .complete }
        if parts[1].isEmpty {
            guard start < size else { return .unsatisfiable }
            return .partial(start..<size)
        }
        guard let end = Int(parts[1]), end >= start else { return .complete }
        guard start < size else { return .unsatisfiable }
        return .partial(start..<(min(end, size - 1) + 1))
    }

    /// Cookie and Authorization are ignored and never influence the response.
    /// GET only: every other method, and every path that is not a listed
    /// inventory member, is 404 with no Allow header.
    static func serve(_ task: WKURLSchemeTask, scheme: String, origin: String, files: [String: Data], isOpen: Bool) {
        guard let url = task.request.url else {
            task.didFailWithError(URLError(.badURL))
            return
        }
        let method = (task.request.httpMethod ?? "GET").uppercased()
        guard isOpen, method == "GET" else {
            finish(task, url: url, status: 404, mime: "text/plain; charset=utf-8", bytes: Data())
            return
        }
        guard let path = memberPath(of: url, scheme: scheme, origin: origin), let bytes = files[path] else {
            finish(task, url: url, status: 404, mime: "text/plain; charset=utf-8", bytes: Data())
            return
        }
        let mime = mimeType(forMemberPath: path)
        switch byteRange(header: task.request.value(forHTTPHeaderField: "Range"), size: bytes.count) {
        case .complete:
            finish(task, url: url, status: 200, mime: mime, bytes: bytes)
        case .partial(let range):
            let slice = bytes.subdata(in: range)
            finish(task, url: url, status: 206, mime: mime, bytes: slice, extra: [
                "Content-Range": "bytes \(range.lowerBound)-\(range.upperBound - 1)/\(bytes.count)",
            ])
        case .unsatisfiable:
            finish(task, url: url, status: 416, mime: mime, bytes: Data(), extra: [
                "Content-Range": "bytes */\(bytes.count)",
            ])
        }
    }

    static func finish(_ task: WKURLSchemeTask, url: URL, status: Int, mime: String, bytes: Data,
                       extra: [String: String] = [:]) {
        var headers = [
            "Content-Type": mime,
            "X-Content-Type-Options": "nosniff",
            "Referrer-Policy": "no-referrer",
            "Cache-Control": "no-store",
            "Cross-Origin-Resource-Policy": "same-origin",
            "Permissions-Policy": permissionsPolicy,
            "Content-Security-Policy": headerContentSecurityPolicy,
        ]
        for (name, value) in extra { headers[name] = value }
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                                             headerFields: headers) else {
            task.didFailWithError(URLError(.badServerResponse))
            return
        }
        task.didReceive(response)
        task.didReceive(bytes)
        task.didFinish()
    }
}


/// One host for every verified HTML5 game. Nothing in this view depends on a
/// particular JavaScript engine or game identity.
struct WebGameHost: View {
    let name: String
    let entry: URL
    let close: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @State private var paused = false
    @State private var processFailed = false
    @State private var webView: WKWebView?
    @State private var packageVerified = false
    @State private var documentReady = false
    @State private var loadingProgress = 0.0

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Button(action: close) { Label("Exit game", systemImage: "xmark") }
                        .accessibilityIdentifier("game.host.exit")
                    Spacer()
                    Text(name).lineLimit(1).font(.caption.weight(.semibold))
                    Spacer()
                    Button(action: { setPaused(!paused) }) {
                        Label(paused ? "Resume" : "Pause", systemImage: paused ? "play.fill" : "pause.fill")
                    }
                    .accessibilityIdentifier("game.host.pause")
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.black)
                WebGameSurface(entry: entry, processFailed: $processFailed, webView: $webView,
                               packageVerified: $packageVerified, documentReady: $documentReady,
                               loadingProgress: $loadingProgress)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if !documentReady && !processFailed {
                Color.black.ignoresSafeArea()
                VStack(spacing: 18) {
                    Image(systemName: "gamecontroller.fill")
                        .font(.system(size: 48))
                        .accessibilityHidden(true)
                    Text(name).font(.title2.bold()).multilineTextAlignment(.center)
                    Text(packageVerified ? "Verified game package" : "Verifying game package")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    ProgressView(value: loadingProgress)
                        .tint(.white)
                        .frame(maxWidth: 240)
                    Text(packageVerified ? "Loading game…" : "Checking installation…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Exit game", action: close)
                        .buttonStyle(.bordered)
                }
                .foregroundStyle(.white)
                .padding(32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("game.host.loading")
            }
            if processFailed {
                ContentUnavailableView {
                    Label("Game interrupted", systemImage: "exclamationmark.triangle")
                } description: {
                    Text("The web rendering process stopped. Reopen the verified game package to continue.")
                } actions: {
                    Button("Reopen") {
                        // reload() targets the current URL, which the entry-only
                        // navigation policy cancels once the game has changed its
                        // path. Load the entry URL through the same fail-closed
                        // path used on first open.
                        guard let webView,
                              let entryURL = (webView.navigationDelegate as? WebGameSurface.Coordinator)?.handler?.entryURL else { return }
                        processFailed = false
                        documentReady = false
                        WebGameSurface.loadGame(entryURL, in: webView) { success in
                            if !success { processFailed = true }
                        }
                    }
                    Button("Exit") { close() }
                }
                .foregroundStyle(.white)
                .background(.black)
            } else if paused {
                Color.black.opacity(0.72).ignoresSafeArea()
                VStack(spacing: 22) {
                    Text("Paused").font(.title.bold())
                        .accessibilityIdentifier("game.host.paused")
                    Button("Resume") { setPaused(false) }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("game.host.resume")
                    Button("Exit game") { close() }.buttonStyle(.bordered)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { setPaused(true) }
        }
        .onDisappear {
            webView?.stopLoading()
            webView?.setAllMediaPlaybackSuspended(true, completionHandler: nil)
            (webView?.navigationDelegate as? WebGameSurface.Coordinator)?.handler?.closeSession()
            webView?.loadHTMLString("", baseURL: nil)
            webView = nil
        }
    }

    private func setPaused(_ value: Bool) {
        paused = value
        let event = value ? "modula:pause" : "modula:resume"
        // One-way lifecycle notification. No native capability or account data
        // is made callable from the page.
        webView?.setAllMediaPlaybackSuspended(value, completionHandler: nil)
        webView?.evaluateJavaScript("window.dispatchEvent(new Event('\(event)'))")
    }
}

private struct WebGameSurface: UIViewRepresentable {
    let entry: URL
    @Binding var processFailed: Bool
    @Binding var webView: WKWebView?
    @Binding var packageVerified: Bool
    @Binding var documentReady: Bool
    @Binding var loadingProgress: Double

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let gameURL: URL?
        let configuration: WKWebViewConfiguration
        do {
            let handler = try VerifiedGameSchemeHandler(entry: entry)
            configuration = Self.configuration(handler: handler)
            context.coordinator.handler = handler
            gameURL = handler.entryURL
            DispatchQueue.main.async { packageVerified = true }
        } catch {
            configuration = WKWebViewConfiguration()
            gameURL = nil
            DispatchQueue.main.async { processFailed = true }
        }
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        view.isOpaque = false
        view.backgroundColor = .black
        view.scrollView.isScrollEnabled = false
        view.scrollView.contentInsetAdjustmentBehavior = .never
        let coordinator = context.coordinator
        coordinator.progressObservation = view.observe(\.estimatedProgress, options: [.initial, .new]) { [weak coordinator] _, change in
            guard let progress = change.newValue else { return }
            DispatchQueue.main.async { coordinator?.parent.loadingProgress = progress }
        }
        if let gameURL {
            // Fail closed: the game document loads only after the local-only
            // network rule list is installed on this view's content controller.
            Self.loadGame(gameURL, in: view) { loaded in
                if !loaded { DispatchQueue.main.async { processFailed = true } }
            }
        }
        DispatchQueue.main.async { webView = view }
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {}

    static func configuration(handler: VerifiedGameSchemeHandler) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.allowsInlineMediaPlayback = true
        // WebKit can leave denied device requests unresolved on custom schemes.
        // Resolve them as denied in every game frame; the native delegates below
        // remain the authority even if game JavaScript changes these functions.
        let denyDeviceAPIs = #"""
        (() => {
          const denied = () => Promise.reject(new DOMException('Permission denied', 'NotAllowedError'));
          const block = (target, name, value) => {
            if (!target) return;
            try { Object.defineProperty(target, name, {value, writable: false, configurable: false}); } catch (_) {}
          };
          const media = navigator.mediaDevices;
          block(media && Object.getPrototypeOf(media), 'getUserMedia', denied);
          block(media && Object.getPrototypeOf(media), 'getDisplayMedia', denied);
          block(media && Object.getPrototypeOf(media), 'enumerateDevices', () => Promise.resolve([]));
          block(media, 'getUserMedia', denied);
          block(media, 'getDisplayMedia', denied);
          block(media, 'enumerateDevices', () => Promise.resolve([]));
          const denyLocation = (_, error) => {
            if (typeof error === 'function') queueMicrotask(() => error({code: 1, PERMISSION_DENIED: 1, message: 'Permission denied'}));
          };
          const location = navigator.geolocation;
          const denyWatch = (...args) => { denyLocation(...args); return 0; };
          block(location && Object.getPrototypeOf(location), 'getCurrentPosition', denyLocation);
          block(location && Object.getPrototypeOf(location), 'watchPosition', denyWatch);
          block(location, 'getCurrentPosition', denyLocation);
          block(location, 'watchPosition', denyWatch);
          block(globalThis.DeviceMotionEvent, 'requestPermission', denied);
          block(globalThis.DeviceOrientationEvent, 'requestPermission', denied);
        })();
        """#
        configuration.userContentController.addUserScript(
            WKUserScript(source: denyDeviceAPIs, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        configuration.setURLSchemeHandler(handler, forURLScheme: VerifiedGameSchemeHandler.scheme)
        return configuration
    }

    /// Blocks every load that is not on the game's own custom scheme, beneath
    /// CSP. Compiled at runtime by WebKit; no third-party code.
    static let networkRuleListIdentifier = "digital.modula.web-game.local-only.v1"
    static let networkRules = #"""
    [{"trigger":{"url-filter":".*"},"action":{"type":"block"}},
     {"trigger":{"url-filter":"^modula-game://"},"action":{"type":"ignore-previous-rules"}},
     {"trigger":{"url-filter":"^data:"},"action":{"type":"ignore-previous-rules"}},
     {"trigger":{"url-filter":"^blob:"},"action":{"type":"ignore-previous-rules"}}]
    """#
    @MainActor private static var compiledNetworkRules: WKContentRuleList?

    /// Installs the local-only rule list on `controller`. Reports false, and
    /// installs nothing, when WebKit cannot compile it.
    @MainActor
    static func installNetworkRules(on controller: WKUserContentController,
                                    completion: @escaping @MainActor (Bool) -> Void) {
        if let compiledNetworkRules {
            controller.add(compiledNetworkRules)
            completion(true)
            return
        }
        Task { @MainActor in
            let list = try? await WKContentRuleListStore.default()?.compileContentRuleList(
                forIdentifier: networkRuleListIdentifier, encodedContentRuleList: networkRules)
            guard let list else { completion(false); return }
            compiledNetworkRules = list
            controller.add(list)
            completion(true)
        }
    }

    /// The only way a game document is loaded: never before the rule list is
    /// in place, and not at all if it could not be compiled.
    @MainActor
    static func loadGame(_ url: URL, in view: WKWebView, completion: @escaping @MainActor (Bool) -> Void) {
        installNetworkRules(on: view.configuration.userContentController) { [weak view] installed in
            guard installed, let view else { completion(false); return }
            view.load(URLRequest(url: url))
            completion(true)
        }
    }

    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        coordinator.progressObservation = nil
        view.stopLoading()
        coordinator.handler?.closeSession()
        view.navigationDelegate = nil
        view.uiDelegate = nil
        view.loadHTMLString("", baseURL: nil)
        view.removeFromSuperview()
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let parent: WebGameSurface
        var handler: VerifiedGameSchemeHandler?
        var progressObservation: NSKeyValueObservation?
        var onNavigationComplete: ((Error?) -> Void)?
        init(_ parent: WebGameSurface) { self.parent = parent }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            DispatchQueue.main.async { self.parent.documentReady = false }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            onNavigationComplete?(nil)
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 0.2)) { self.parent.documentReady = true }
            }
        }

        /// Only the verified entry document may occupy the main frame. Any other
        /// main-frame navigation (including to listed archive files such as SVG),
        /// every subframe navigation, and every new-window target is cancelled.
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let url = action.request.url, let handler,
                  action.targetFrame?.isMainFrame == true,
                  url.absoluteString == handler.entryURL.absoluteString,
                  handler.contains(url) else { return .cancel }
            return .allow
        }

        /// The main frame may only display the entry document as HTML. Anything
        /// WebKit cannot show inline (a download) or any other type is cancelled.
        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
            guard let handler, navigationResponse.isForMainFrame, navigationResponse.canShowMIMEType,
                  WebGamePackageServe.isHTML(navigationResponse.response.mimeType),
                  let url = navigationResponse.response.url,
                  url.absoluteString == handler.entryURL.absoluteString else { return .cancel }
            return .allow
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? { nil }

        // Downloaded games receive no device-data capability from the host.
        // WebKit otherwise prompts for these APIs when the delegate is absent.
        func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                     initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                     decisionHandler: @escaping (WKPermissionDecision) -> Void) {
            decisionHandler(.deny)
        }

        func webView(_ webView: WKWebView, requestDeviceOrientationAndMotionPermissionFor origin: WKSecurityOrigin,
                     initiatedByFrame frame: WKFrameInfo,
                     decisionHandler: @escaping (WKPermissionDecision) -> Void) {
            decisionHandler(.deny)
        }

        @available(iOS 27.0, *)
        func webView(_ webView: WKWebView, requestGeolocationPermissionFor origin: WKSecurityOrigin,
                     initiatedByFrame frame: WKFrameInfo,
                     decisionHandler: @escaping (WKPermissionDecision) -> Void) {
            decisionHandler(.deny)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            DispatchQueue.main.async { self.parent.processFailed = true }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            onNavigationComplete?(error)
            DispatchQueue.main.async { self.parent.processFailed = true }
        }
    }
}

/// Serves only bytes from one reverified content-addressed archive. A custom
/// origin makes CSP 'self' work for ES modules and styles without file:// origin
/// ambiguity. WebKit receives no local-file read grant or Native message bridge.
private final class VerifiedGameSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "modula-game"
    // Applied by the host on every HTML response, independent of any policy
    // declared by a downloadable package. This header (with the local-only
    // rule list) is the security boundary: it is never derived from, or
    // relaxed by, the document. A document meta CSP can only add restrictions,
    // because browsers enforce every policy present.
    // Exact §4.2 header CSP, including connect-src 'self' and font-src 'self'.
    // 'self' is this handler's per-package modula-game:// origin only.
    static let contentSecurityPolicy = WebGamePackageServe.headerContentSecurityPolicy
    static let resourceContentSecurityPolicy = WebGamePackageServe.headerContentSecurityPolicy
    let digest: String
    let origin: String
    let entryURL: URL
    private let files: [String: Data]
    private var runtimePin: WebRuntimeSessionPin?
    private var gamePin: WebGameSessionPin?
    private let sessionLock = NSLock()
    private var closed = false

    init(entry: URL) throws {
        let directory = entry.deletingLastPathComponent()
        digest = directory.lastPathComponent
        guard entry.lastPathComponent == "index.html", InstallDescriptorVerifier.isHex64(digest) else {
            throw WebGamePackageError.invalid("entry origin")
        }
        let slot = directory.deletingLastPathComponent().deletingLastPathComponent()
        let module = slot.deletingLastPathComponent()
        let account = module.deletingLastPathComponent()
        // An identical immutable archive may be owned by two different games.
        // Keep their browser origins distinct even when storage deduplicates it.
        let originIdentity = "\(account.lastPathComponent)/\(module.lastPathComponent)/\(digest)"
        origin = SHA256.hash(data: Data(originIdentity.utf8)).map { String(format: "%02x", $0) }.joined()
        let archive = try Data(contentsOf: slot.appendingPathComponent("game.tgz"))
        let package = try WebGamePackage(archive: archive, expectedSha256: digest)
        _ = try WebGamePackage.verifyInstalled(at: directory, expectedSha256: digest, trustedFiles: package.files)
        gamePin = WebGameSessionPin(module)
        var verifiedFiles = package.files
        var pin: WebRuntimeSessionPin?
        let metadata = try Data(contentsOf: slot.appendingPathComponent("release.json"))
        let json = try JSONDecoder().decode(JSONValue.self, from: metadata)
        if let runtimeDigest = json["runtimeSha256"]?.string {
            guard InstallDescriptorVerifier.isHex64(runtimeDigest) else {
                throw WebGamePackageError.invalid("runtime metadata")
            }
            pin = WebRuntimeSessionPin(runtimeDigest)
            let cacheRoot = account.deletingLastPathComponent()
            verifiedFiles["__runtime/engine.mjs"] = try SharedWebRuntimeStore(moduleCacheRoot: cacheRoot)
                .verifiedEngine(sha256: runtimeDigest)
        }
        files = verifiedFiles
        runtimePin = pin
        entryURL = URL(string: "\(Self.scheme)://\(origin)/index.html")!
    }

    func contains(_ url: URL) -> Bool {
        sessionLock.lock()
        let active = !closed
        sessionLock.unlock()
        guard active, let path = WebGamePackageServe.memberPath(of: url, scheme: Self.scheme, origin: origin) else {
            return false
        }
        return files[path] != nil
    }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        serve(task)
    }

    fileprivate func serve(_ task: WKURLSchemeTask) {
        sessionLock.lock()
        let open = !closed
        sessionLock.unlock()
        WebGamePackageServe.serve(task, scheme: Self.scheme, origin: origin, files: files, isOpen: open)
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}

    /// The view has stopped loading and left the screen. Release session pins
    /// immediately, and refuse any late WebKit resource request.
    func closeSession() {
        sessionLock.lock()
        closed = true
        runtimePin = nil
        gamePin = nil
        sessionLock.unlock()
    }
}

#if DEBUG
struct WebGameBrowserProbe {
    let browser: WKWebView
    // WKWebView's delegates are weak. Keep the exact production delegate alive.
    fileprivate let delegate: NSObject
    fileprivate let handler: VerifiedGameSchemeHandler

    @MainActor func close() {
        browser.stopLoading()
        handler.closeSession()
    }

    /// Loads through the production path: rule list first, then the document.
    @MainActor func load(_ url: URL) async -> Bool {
        await withCheckedContinuation { continuation in
            WebGameSurface.loadGame(url, in: browser) { continuation.resume(returning: $0) }
        }
    }
}

@MainActor
enum WebGameResourceProbe {
    static func entryURL(entry: URL) throws -> URL {
        try VerifiedGameSchemeHandler(entry: entry).entryURL
    }
    static func allows(entry: URL, request: URL) throws -> Bool {
        try VerifiedGameSchemeHandler(entry: entry).contains(request)
    }

    static func serve(entry: URL, task: WKURLSchemeTask) throws {
        try VerifiedGameSchemeHandler(entry: entry).serve(task)
    }

    /// Installs the production local-only rule list on any content controller.
    static func installNetworkRules(on controller: WKUserContentController) async -> Bool {
        await withCheckedContinuation { continuation in
            WebGameSurface.installNetworkRules(on: controller) { continuation.resume(returning: $0) }
        }
    }

    static var resourceContentSecurityPolicy: String { VerifiedGameSchemeHandler.resourceContentSecurityPolicy }
    static var htmlContentSecurityPolicy: String { VerifiedGameSchemeHandler.contentSecurityPolicy }

    static func browser(entry: URL, onNavigationComplete: @escaping (Error?) -> Void) throws -> WebGameBrowserProbe {
        let handler = try VerifiedGameSchemeHandler(entry: entry)
        let surface = WebGameSurface(entry: entry, processFailed: .constant(false),
                                     webView: .constant(nil), packageVerified: .constant(false),
                                     documentReady: .constant(false), loadingProgress: .constant(0))
        let delegate = WebGameSurface.Coordinator(surface)
        delegate.handler = handler
        delegate.onNavigationComplete = onNavigationComplete
        let browser = WKWebView(frame: .zero, configuration: WebGameSurface.configuration(handler: handler))
        browser.navigationDelegate = delegate
        browser.uiDelegate = delegate
        return WebGameBrowserProbe(browser: browser, delegate: delegate, handler: handler)
    }
}
#endif
