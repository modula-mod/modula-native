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

/// Serves one game's files from memory under `gubic://<random per play>/`.
/// That origin is stricter than the `modula-pkg://<packageId>/` name in §4.2;
/// the handler contract otherwise mirrors the spec. Unlisted paths, queries
/// and fragments fail, so the page cannot reach anything but its own package.
/// Plain Swift type (not NSObject) so it stays out of the generated ObjC header; WebKit sees `makeWebKitHandler()`.
final class GubicSchemeHandler: @unchecked Sendable {
    static let scheme = "gubic"
    // Exact §4.2 header CSP. 'self' is this play's gubic:// origin only.
    static let contentSecurityPolicy = WebGamePackageServe.headerContentSecurityPolicy
    static let resourceContentSecurityPolicy = WebGamePackageServe.headerContentSecurityPolicy

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
        guard !closed, let path = WebGamePackageServe.memberPath(of: url, scheme: Self.scheme, origin: origin) else {
            return false
        }
        return files[path] != nil
    }

    func close() { lock.lock(); closed = true; lock.unlock() }

    /// Only the entry document may occupy the main frame (the bridge bootstrap
    /// is injected there). Every other main-frame target, including other
    /// listed files such as SVG or HTML, every subframe and every new window
    /// is refused.
    func allowsNavigation(to url: URL, isMainFrame: Bool) -> Bool {
        isMainFrame && url.absoluteString == entryURL.absoluteString && allows(url)
    }

    func makeWebKitHandler() -> any WKURLSchemeHandler { GubicWebKitSchemeHandler(owner: self) }

    func serve(_ task: WKURLSchemeTask) {
        lock.lock()
        let open = !closed
        lock.unlock()
        WebGamePackageServe.serve(task, scheme: Self.scheme, origin: origin, files: files, isOpen: open)
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
