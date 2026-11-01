import CryptoKit
import Foundation
import WebKit

/// What the GUBIC player loads. Files are always served from memory through the session scheme;
/// nothing is ever fetched from the network by the page.
struct GubicGameSource: Identifiable {
    let id: String
    let title: String
    let files: [String: Data]
    let capabilities: Set<String>
    /// True only for catalogue games: then sessions and achievements go to Greenfield.
    let serverBacked: Bool
    let localAchievements: [GubicAchievement]

    static var sample: GubicGameSource {
        GubicGameSource(id: GubicSampleGame.id, title: GubicSampleGame.title, files: GubicSampleGame.files,
                        capabilities: GubicSampleGame.capabilities, serverBacked: false,
                        localAchievements: GubicSampleGame.achievements)
    }
}

/// Serves one game's files from memory under `gubic://<session-origin>/`. Unlisted paths,
/// queries and fragments fail, so the page cannot reach anything but its own package.
/// Plain Swift type (not NSObject) so it stays out of the generated ObjC header; WebKit sees `makeWebKitHandler()`.
final class GubicSchemeHandler: @unchecked Sendable {
    static let scheme = "gubic"
    static let contentSecurityPolicy = "default-src 'none'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; media-src 'self' blob:; font-src 'self'; connect-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'"

    let origin: String
    private let files: [String: Data]
    private let lock = NSLock()
    private var closed = false

    init(files: [String: Data]) {
        self.files = files
        // A fresh random origin per play keeps games (and replays) isolated from each other.
        origin = SHA256.hash(data: Data(UUID().uuidString.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    var entryURL: URL { URL(string: "\(Self.scheme)://\(origin)/index.html")! }

    func allows(_ url: URL) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !closed, url.scheme == Self.scheme, url.host == origin, url.query == nil, url.fragment == nil else { return false }
        return files[String(url.path.dropFirst())] != nil
    }

    func close() { lock.lock(); closed = true; lock.unlock() }

    func makeWebKitHandler() -> any WKURLSchemeHandler { GubicWebKitSchemeHandler(owner: self) }

    func serve(_ task: WKURLSchemeTask) {
        guard let url = task.request.url, allows(url), let bytes = files[String(url.path.dropFirst())] else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let mime: String = switch url.pathExtension.lowercased() {
        case "html": "text/html"
        case "js", "mjs": "text/javascript"
        case "css": "text/css"
        case "json": "application/json"
        case "png": "image/png"
        case "jpg", "jpeg": "image/jpeg"
        case "webp": "image/webp"
        case "svg": "image/svg+xml"
        case "mp3": "audio/mpeg"
        case "ogg": "audio/ogg"
        case "wav": "audio/wav"
        case "woff2": "font/woff2"
        default: "application/octet-stream"
        }
        var headers = ["Content-Type": mime, "X-Content-Type-Options": "nosniff", "Referrer-Policy": "no-referrer", "Cache-Control": "no-store"]
        if mime == "text/html" {
            headers["Content-Security-Policy"] = Self.contentSecurityPolicy
            headers["Permissions-Policy"] = "camera=(), microphone=(), geolocation=(), accelerometer=(), gyroscope=(), magnetometer=()"
        }
        guard let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers) else {
            task.didFailWithError(URLError(.badServerResponse))
            return
        }
        task.didReceive(response)
        task.didReceive(bytes)
        task.didFinish()
    }

}

private final class GubicWebKitSchemeHandler: NSObject, WKURLSchemeHandler {
    let owner: GubicSchemeHandler
    init(owner: GubicSchemeHandler) { self.owner = owner }
    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) { owner.serve(task) }
    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}

/// A message from game code, validated before anything native happens.
enum GubicBridgeMessage: Equatable {
    case ready
    case score(Int)
    case achievement(String)
    case gameOver(Int)

    static let maximumBytes = 4096

    /// Parses `window.webkit.messageHandlers.gubic.postMessage(...)` bodies. Unknown types,
    /// undeclared capabilities, malformed keys and out-of-range numbers are dropped.
    static func parse(_ body: Any, capabilities: Set<String>) -> GubicBridgeMessage? {
        guard let object = body as? [String: Any], let type = object["type"] as? String,
              let data = try? JSONSerialization.data(withJSONObject: object), data.count <= maximumBytes else { return nil }
        switch type {
        case "ready":
            return capabilities.contains("lifecycle") ? .ready : nil
        case "score":
            guard capabilities.contains("score"), let value = (object["value"] as? NSNumber)?.doubleValue,
                  value.isFinite, value >= 0, value <= 1_000_000_000 else { return nil }
            return .score(Int(value))
        case "achievement":
            guard capabilities.contains("achievements"), let key = object["key"] as? String,
                  key.range(of: "^[a-z0-9][a-z0-9_.-]{0,63}$", options: .regularExpression) != nil else { return nil }
            return .achievement(key)
        case "gameOver":
            guard capabilities.contains("lifecycle") else { return nil }
            let value = (object["score"] as? NSNumber)?.doubleValue ?? 0
            return .gameOver(value.isFinite ? Int(max(0, min(value, 1_000_000_000))) : 0)
        default:
            return nil
        }
    }

    /// The frozen `window.gubic` API injected at document start in the main frame only.
    static func bootstrapScript(hello: [String: Any]) -> String {
        let helloJSON = (try? JSONSerialization.data(withJSONObject: hello)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return """
        (() => {
          const post = (m) => { try { window.webkit.messageHandlers.gubic.postMessage(m); } catch (_) {} };
          const hello = Object.freeze(\(helloJSON));
          const api = Object.freeze({
            version: 1,
            hello,
            ready: () => post({type: 'ready'}),
            reportScore: (value) => post({type: 'score', value: Number(value)}),
            unlockAchievement: (key) => post({type: 'achievement', key: String(key)}),
            gameOver: (detail) => post({type: 'gameOver', score: Number((detail && detail.score) || 0)}),
          });
          Object.defineProperty(window, 'gubic', {value: api, writable: false, configurable: false});
          for (const name of ['alert', 'confirm', 'prompt', 'open']) {
            try { Object.defineProperty(window, name, {value: () => undefined, writable: false, configurable: false}); } catch (_) {}
          }
          window.addEventListener('DOMContentLoaded', () => window.dispatchEvent(new CustomEvent('gubic:hello', {detail: hello})));
        })();
        """
    }
}

/// Fixed-window rate limiter per message type.
struct GubicBridgeRateLimiter {
    private var windows: [String: (start: Date, count: Int)] = [:]
    let limits: [String: Int] = ["score": 4, "achievement": 4, "ready": 2, "gameOver": 2]

    mutating func allow(_ type: String, now: Date = .now) -> Bool {
        let limit = limits[type] ?? 1
        if let window = windows[type], now.timeIntervalSince(window.start) < 1 {
            guard window.count < limit else { return false }
            windows[type] = (window.start, window.count + 1)
        } else {
            windows[type] = (now, 1)
        }
        return true
    }
}
