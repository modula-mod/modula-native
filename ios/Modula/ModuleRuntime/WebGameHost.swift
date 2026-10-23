import SwiftUI
import WebKit

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
                    Button("Reopen") { processFailed = false; webView?.reload() }
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
            webView?.loadHTMLString("", baseURL: nil)
            webView = nil
        }
    }

    private func setPaused(_ value: Bool) {
        paused = value
        let event = value ? "modula:pause" : "modula:resume"
        // One-way lifecycle notification. No native capability or account data
        // is made callable from the page.
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
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.allowsInlineMediaPlayback = true
        let gameURL: URL?
        do {
            let handler = try VerifiedGameSchemeHandler(entry: entry)
            configuration.setURLSchemeHandler(handler, forURLScheme: VerifiedGameSchemeHandler.scheme)
            context.coordinator.handler = handler
            gameURL = handler.entryURL
            DispatchQueue.main.async { packageVerified = true }
        } catch {
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
        if let gameURL { view.load(URLRequest(url: gameURL)) }
        DispatchQueue.main.async { webView = view }
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {}

    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        coordinator.progressObservation = nil
        view.stopLoading()
        view.navigationDelegate = nil
        view.uiDelegate = nil
        view.loadHTMLString("", baseURL: nil)
        view.removeFromSuperview()
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let parent: WebGameSurface
        var handler: VerifiedGameSchemeHandler?
        var progressObservation: NSKeyValueObservation?
        init(_ parent: WebGameSurface) { self.parent = parent }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            DispatchQueue.main.async { self.parent.documentReady = false }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 0.2)) { self.parent.documentReady = true }
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let url = action.request.url, let handler,
                  url.scheme == VerifiedGameSchemeHandler.scheme,
                  url.host == handler.digest,
                  handler.contains(url) else { return .cancel }
            return .allow
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? { nil }

        // Downloaded games receive no device-data capability from the host.
        // WebKit otherwise prompts for these APIs when the delegate is absent.
        func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                     initiatedBy frame: WKFrameInfo, type: WKMediaCaptureType,
                     decisionHandler: @escaping (WKPermissionDecision) -> Void) {
            decisionHandler(.deny)
        }

        func webView(_ webView: WKWebView, requestDeviceOrientationAndMotionPermissionFor origin: WKSecurityOrigin,
                     initiatedBy frame: WKFrameInfo,
                     decisionHandler: @escaping (WKPermissionDecision) -> Void) {
            decisionHandler(.deny)
        }

        @available(iOS 27.0, *)
        func webView(_ webView: WKWebView, requestGeolocationPermissionFor origin: WKSecurityOrigin,
                     initiatedBy frame: WKFrameInfo,
                     decisionHandler: @escaping (WKPermissionDecision) -> Void) {
            decisionHandler(.deny)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            DispatchQueue.main.async { self.parent.processFailed = true }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async { self.parent.processFailed = true }
        }
    }
}

/// Serves only bytes from one reverified content-addressed archive. A custom
/// origin makes CSP 'self' work for ES modules and styles without file:// origin
/// ambiguity. WebKit receives no local-file read grant or Native message bridge.
private final class VerifiedGameSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "modula-game"
    // Applied by the host on the HTML response, independent of any policy
    // declared by a downloadable package.
    private static let contentSecurityPolicy = "default-src 'none'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self' data:; media-src 'self' data:; connect-src 'none'; object-src 'none'; frame-src 'none'; worker-src 'none'; base-uri 'none'; form-action 'none'"
    let digest: String
    let entryURL: URL
    private let files: [String: Data]

    init(entry: URL) throws {
        let directory = entry.deletingLastPathComponent()
        digest = directory.lastPathComponent
        guard entry.lastPathComponent == "index.html", InstallDescriptorVerifier.isHex64(digest) else {
            throw WebGamePackageError.invalid("entry origin")
        }
        let slot = directory.deletingLastPathComponent().deletingLastPathComponent()
        let archive = try Data(contentsOf: slot.appendingPathComponent("game.tgz"))
        let package = try WebGamePackage(archive: archive, expectedSha256: digest)
        _ = try WebGamePackage.verifyInstalled(at: directory, expectedSha256: digest, trustedFiles: package.files)
        files = package.files
        entryURL = URL(string: "\(Self.scheme)://\(digest)/index.html")!
    }

    func contains(_ url: URL) -> Bool {
        guard url.scheme == Self.scheme, url.host == digest else { return false }
        let path = String(url.path.dropFirst())
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath == "/" + path
            && files[path] != nil
            && url.query == nil && url.fragment == nil
    }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        serve(task)
    }

    fileprivate func serve(_ task: WKURLSchemeTask) {
        guard let url = task.request.url, contains(url),
              let bytes = files[String(url.path.dropFirst())] else {
            task.didFailWithError(WebGamePackageError.invalid("unlisted resource"))
            return
        }
        let mime: String
        switch url.pathExtension.lowercased() {
        case "html": mime = "text/html"
        case "js", "mjs": mime = "text/javascript"
        case "css": mime = "text/css"
        case "json": mime = "application/json"
        case "png": mime = "image/png"
        case "jpg", "jpeg": mime = "image/jpeg"
        case "webp": mime = "image/webp"
        case "svg": mime = "image/svg+xml"
        case "mp3": mime = "audio/mpeg"
        case "ogg": mime = "audio/ogg"
        case "wav": mime = "audio/wav"
        default: mime = "application/octet-stream"
        }
        var headers = ["Content-Type": mime, "X-Content-Type-Options": "nosniff",
                       "Referrer-Policy": "no-referrer", "Cache-Control": "no-store"]
        if mime == "text/html" { headers["Content-Security-Policy"] = Self.contentSecurityPolicy }
        guard let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers) else {
            task.didFailWithError(WebGamePackageError.invalid("resource response"))
            return
        }
        task.didReceive(response)
        task.didReceive(bytes)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}

#if DEBUG
@MainActor
enum WebGameResourceProbe {
    static func allows(entry: URL, request: URL) throws -> Bool {
        try VerifiedGameSchemeHandler(entry: entry).contains(request)
    }

    static func serve(entry: URL, task: WKURLSchemeTask) throws {
        try VerifiedGameSchemeHandler(entry: entry).serve(task)
    }

    static func browser(entry: URL) throws -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.setURLSchemeHandler(try VerifiedGameSchemeHandler(entry: entry),
                                          forURLScheme: VerifiedGameSchemeHandler.scheme)
        return WKWebView(frame: .zero, configuration: configuration)
    }
}
#endif
