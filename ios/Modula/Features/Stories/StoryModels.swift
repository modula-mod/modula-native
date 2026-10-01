import Foundation
import Observation
import OSLog

typealias StoryID = String

enum StoryRingState: String, Hashable, Sendable {
    case unseen
    case seen
    case own
}

enum StoryKind: String, Hashable, Sendable {
    case image
    case text
    case video
    case unknown

    init(parsing raw: String?) {
        switch (raw ?? "").lowercased() {
        case "image", "photo": self = .image
        case "text": self = .text
        case "video": self = .video
        default: self = .unknown
        }
    }
}

struct StoryItem: Identifiable, Hashable, Sendable {
    let id: StoryID
    let author: ConversationParticipant
    let createdAt: Date
    let expiresAt: Date?
    let kind: StoryKind
    let media: MediaResource?
    let text: String?
    let background: String?
    let seen: Bool
    let isOwn: Bool
    let viewerCount: Int?

    var ring: StoryRingState {
        if isOwn { return .own }
        return seen ? .seen : .unseen
    }
}

struct StoryGroup: Identifiable, Hashable, Sendable {
    let id: String
    let author: ConversationParticipant
    var items: [StoryItem]
    var isOwn: Bool
    var reportedRing: StoryRingState? = nil

    var ring: StoryRingState {
        if let reportedRing { return reportedRing }
        if isOwn { return .own }
        return items.contains(where: { !$0.seen }) ? .unseen : .seen
    }

    var representative: StoryItem? { items.first }
    var isComposerPlaceholder: Bool { id.hasPrefix("add:") || (isOwn && items.isEmpty) }
}

struct StoryBackendCapabilities: Sendable, Equatable {
    var list = false
    var create = false
    var viewers = false
    var reply = false
    var react = false
    var privacy = false
    var video = false

    static let production = StoryBackendCapabilities(list: true, create: true)

    enum Paths {
        static let rail = "/v1/stories/rail"
        static func group(_ id: String) -> String { "/v1/stories/\(escape(id))" }
        static let create = "/v1/stories"
        static func viewed(_ id: String) -> String { "/v1/stories/items/\(escape(id))/viewed" }

        private static func escape(_ value: String) -> String {
            value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
        }
    }
}

enum StoryPayloadDecoder {
    static func rail(from value: JSONValue) -> [StoryGroup] {
        let items = value["items"]?.array ?? value["groups"]?.array ?? []
        return items.compactMap(railEntry)
    }

    static func groups(from value: JSONValue) -> [StoryGroup] {
        if value["groupId"] != nil { return [value].compactMap(group) }
        let items = value["items"]?.array ?? value["groups"]?.array ?? value["stories"]?.array ?? []
        return items.compactMap(group)
    }

    static func railEntry(_ value: JSONValue) -> StoryGroup? {
        let groupId = value["groupId"]?.string ?? value["id"]?.string
        guard let groupId else { return nil }
        let author = author(from: value, fallbackID: groupId)
        let isOwn = value["isOwner"]?.bool ?? value["isOwn"]?.bool ?? false
        return StoryGroup(
            id: groupId,
            author: author,
            items: [],
            isOwn: isOwn,
            reportedRing: ringState(value["ringState"]?.string, isOwn: isOwn)
        )
    }

    static func group(_ value: JSONValue) -> StoryGroup? {
        let author = value["author"].flatMap(MessagingPayloadDecoder.participant)
            ?? author(from: value, fallbackID: value["groupId"]?.string ?? value["id"]?.string ?? "unknown")
        let items = (value["items"]?.array ?? [value]).compactMap { item($0, author: author, isOwn: value["isOwner"]?.bool ?? value["isOwn"]?.bool ?? false) }
        let groupId = value["groupId"]?.string ?? value["id"]?.string ?? items.first?.author.id
        guard let groupId, author.id != "unknown" || !items.isEmpty else { return nil }
        let isOwn = value["isOwner"]?.bool ?? items.first?.isOwn ?? false
        return StoryGroup(
            id: groupId,
            author: author,
            items: items,
            isOwn: isOwn,
            reportedRing: ringState(value["ringState"]?.string, isOwn: isOwn)
        )
    }

    static func item(_ value: JSONValue) -> StoryItem? {
        item(value, author: value["author"].flatMap(MessagingPayloadDecoder.participant), isOwn: value["isOwn"]?.bool ?? false)
    }

    static func item(_ value: JSONValue, author: ConversationParticipant?, isOwn: Bool) -> StoryItem? {
        let id = value["itemId"]?.string ?? value["id"]?.string
        guard let id else { return nil }
        let resolvedAuthor = author ?? value["author"].flatMap(MessagingPayloadDecoder.participant) ?? ConversationParticipant(
            id: "unknown", handle: "", displayName: "Member", avatarURL: nil
        )
        let mediaURL = url(value["mediaUrl"]?.string ?? value["url"]?.string)
        let media = value["media"].flatMap { MediaPayloadDecoder.resource(from: $0, fallbackID: id) }
            ?? mediaURL.map { MediaResource(id: id, kind: StoryKind(parsing: value["mediaKind"]?.string ?? value["kind"]?.string) == .video ? .video : .image, url: $0) }
        let kind = StoryKind(parsing: value["mediaKind"]?.string ?? value["kind"]?.string ?? value["type"]?.string)
        return StoryItem(
            id: id,
            author: resolvedAuthor,
            createdAt: MessagingPayloadDecoder.decodeDate(value["createdAt"]?.string) ?? Date(),
            expiresAt: MessagingPayloadDecoder.decodeDate(value["expiresAt"]?.string),
            kind: kind == .unknown && media != nil ? .image : kind,
            media: media,
            text: value["caption"]?.string ?? value["text"]?.string,
            background: value["background"]?.string ?? value["colour"]?.string,
            seen: value["viewed"]?.bool ?? value["seen"]?.bool ?? false,
            isOwn: value["isOwn"]?.bool ?? isOwn,
            viewerCount: value["viewerCount"]?.int
        )
    }

    private static func author(from value: JSONValue, fallbackID: String) -> ConversationParticipant {
        ConversationParticipant(
            id: value["ownerProfileId"]?.string ?? value["ownerActorId"]?.string ?? fallbackID,
            handle: value["handle"]?.string ?? "",
            displayName: value["displayName"]?.string ?? value["handle"]?.string ?? "Member",
            avatarURL: url(value["avatarUrl"]?.string ?? value["avatarUri"]?.string)
        )
    }

    private static func ringState(_ raw: String?, isOwn: Bool) -> StoryRingState {
        switch (raw ?? "").lowercased() {
        case "unviewed", "partial", "unseen": .unseen
        case "viewed", "seen": .seen
        case "owner", "uploading", "failed", "own": .own
        default: isOwn ? .own : .unseen
        }
    }

    private static func url(_ raw: String?) -> URL? {
        guard let raw, !raw.isEmpty else { return nil }
        return URL(string: raw)
    }
}

enum StoryGrouping {
    static func groups(from items: [StoryItem]) -> [StoryGroup] {
        var order: [String] = []
        var buckets: [String: [StoryItem]] = [:]
        for item in items {
            let key = item.author.id
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(item)
        }
        return order.compactMap { key in
            guard let items = buckets[key], let first = items.first else { return nil }
            return StoryGroup(id: key, author: first.author, items: items, isOwn: first.isOwn)
        }
    }
}

@Observable
final class StoryProgressEngine {
    let durations: [TimeInterval]
    private(set) var index = 0
    private(set) var progress: Double = 0
    private(set) var isPaused = false
    var isAppActive = true

    init(count: Int, duration: TimeInterval = 5) {
        self.durations = Array(repeating: max(duration, 0.5), count: max(count, 1))
    }

    init(durations: [TimeInterval]) {
        self.durations = durations.isEmpty ? [5] : durations
    }

    var segmentCount: Int { durations.count }

    func tick(_ delta: TimeInterval) -> StoryProgressEvent {
        guard !isPaused, isAppActive, index < durations.count else { return .none }
        let duration = durations[index]
        progress += delta / duration
        if progress >= 1 {
            progress = 0
            if index + 1 < durations.count {
                index += 1
                return .advanced
            }
            return .finished
        }
        return .none
    }

    func pause() { isPaused = true }
    func resume() { isPaused = false }

    func next() -> StoryProgressEvent {
        progress = 0
        if index + 1 < durations.count {
            index += 1
            return .advanced
        }
        return .finished
    }

    func previous() -> StoryProgressEvent {
        progress = 0
        if index > 0 {
            index -= 1
            return .advanced
        }
        return .none
    }

    func reset(to newIndex: Int = 0) {
        index = min(max(newIndex, 0), durations.count - 1)
        progress = 0
    }
}

enum StoryProgressEvent: Equatable {
    case none
    case advanced
    case finished
}

/// Request-size contract for inline story media. Both Greenfield edges
/// (`ops/nginx/api.modula.digital.conf`, `scripts/n1/nginx-native-n1.conf`) set
/// `client_max_body_size 1m` (1,048,576 B); prod accepted a 1,013,426 B body and
/// rejected 1,066,758 B with an HTML 413.
enum StoryUploadBudget {
    static let proxyBodyLimitBytes = 1_048_576
    /// Keep ~48 KiB of headroom under the proxy limit.
    static let maximumBodyBytes = 1_000_000
    /// JSON keys, numbers, visibility and punctuation.
    static let envelopeOverheadBytes = 1_024

    /// Largest raw image that base64-encodes (4/3) into the remaining body budget,
    /// allowing ~2% for `JSONEncoder` escaping `/` inside the base64 text.
    static func imageByteBudget(captionByteCount: Int) -> Int {
        let available = maximumBodyBytes - envelopeOverheadBytes - captionByteCount * 2
        return max(0, Int(Double(available) * 0.75 / 1.02))
    }
}

struct StoryBackendRepository: Sendable {
    let capabilities: StoryBackendCapabilities
    private let client: GreenfieldClient

    init(client: GreenfieldClient, capabilities: StoryBackendCapabilities = .production) {
        self.client = client
        self.capabilities = capabilities
    }

    func rail() async throws -> [StoryGroup] {
        guard capabilities.list else { throw APIError.unavailable("Stories aren’t available.") }
        let value: JSONValue = try await client.json("GET", path: StoryBackendCapabilities.Paths.rail)
        return StoryPayloadDecoder.rail(from: value)
    }

    func group(id: String) async throws -> StoryGroup {
        guard capabilities.list else { throw APIError.unavailable("Stories aren’t available.") }
        let value: JSONValue = try await client.json("GET", path: StoryBackendCapabilities.Paths.group(id))
        guard let group = StoryPayloadDecoder.group(value) else { throw APIError.invalidResponse }
        return group
    }

    func create(image: PreparedImage, caption: String?, visibility: String = "public") async throws -> StoryGroup {
        guard capabilities.create else { throw APIError.unavailable("Story publishing isn’t available.") }
        let body = try await Self.uploadableBody(image: image, caption: caption, visibility: visibility)
        let value: JSONValue = try await client.authenticatedJSON(
            "POST",
            path: StoryBackendCapabilities.Paths.create,
            body: body
        )
        guard let group = StoryPayloadDecoder.group(value) else { throw APIError.invalidResponse }
        return group
    }

    /// Greenfield's `POST /v1/stories` only accepts the media inline as base64 (there is
    /// no attachment/upload reference for stories), and nginx in front of every host caps
    /// request bodies at 1 MiB. Fit the JPEG to a byte budget and verify the *encoded*
    /// JSON size (base64 is 4/3 and `JSONEncoder` escapes `/`) before sending, so the
    /// request never reaches the proxy's HTML 413.
    static func uploadableBody(image: PreparedImage, caption: String?, visibility: String) async throws -> JSONValue {
        let trimmedCaption = caption?.trimmingCharacters(in: .whitespacesAndNewlines)
        var budget = StoryUploadBudget.imageByteBudget(captionByteCount: trimmedCaption?.utf8.count ?? 0)
        for _ in 0..<4 {
            let fitted: PreparedImage
            if image.data.count <= budget {
                fitted = image
            } else {
                fitted = try await MediaPreparation.jpegFitting(image.data, maxBytes: budget)
            }
            let body = requestBody(image: fitted, caption: trimmedCaption, visibility: visibility)
            let encodedSize = try JSONEncoder().encode(body).count
            if encodedSize <= StoryUploadBudget.maximumBodyBytes {
                if fitted.data.count != image.data.count {
                    ModulaLog.network.notice(
                        "story media fitted \(image.data.count, privacy: .public)B \(image.width, privacy: .public)px → \(fitted.data.count, privacy: .public)B \(fitted.width, privacy: .public)x\(fitted.height, privacy: .public); body \(encodedSize, privacy: .public)B"
                    )
                }
                return body
            }
            budget = Int(Double(budget) * 0.9)
        }
        throw APIError.rejected(413, "PAYLOAD_TOO_LARGE")
    }

    static func requestBody(image: PreparedImage, caption: String?, visibility: String) -> JSONValue {
        var body: [String: JSONValue] = [
            "mediaKind": .string("image"),
            "base64": .string(image.data.base64EncodedString()),
            "contentType": .string(image.mimeType),
            "width": .number(Double(image.width)),
            "height": .number(Double(image.height)),
            "visibility": .string(visibility)
        ]
        if let caption, !caption.isEmpty {
            body["caption"] = .string(caption)
        }
        return .object(body)
    }

    func markViewed(itemID: StoryID) async throws {
        guard capabilities.list else { return }
        _ = try await client.authenticatedJSON(
            "POST",
            path: StoryBackendCapabilities.Paths.viewed(itemID),
            body: .object([:])
        )
    }
}

@MainActor @Observable
final class StoryStore {
    private let repository: StoryBackendRepository
    let capabilities: StoryBackendCapabilities
    private(set) var groups: [StoryGroup] = []
    private(set) var loadState: MessagingLoadState = .idle
    private(set) var actionError: String?

    func setActionError(_ message: String?) { actionError = message }

    init(client: GreenfieldClient, capabilities: StoryBackendCapabilities = .production) {
        self.repository = StoryBackendRepository(client: client, capabilities: capabilities)
        self.capabilities = capabilities
    }

    var trayGroups: [StoryGroup] { groups }

    func loadIfNeeded() async {
        guard capabilities.list else {
            loadState = .loaded
            return
        }
        guard loadState == .idle else { return }
        await refresh()
    }

    func refresh() async {
        guard capabilities.list else {
            loadState = .loaded
            return
        }
        loadState = groups.isEmpty ? .loading : .refreshing
        do {
            groups = try await repository.rail()
            loadState = .loaded
            actionError = nil
        } catch {
            loadState = groups.isEmpty ? .failed("Stories aren’t available.") : .loaded
            actionError = "Stories aren’t available."
        }
    }

    func group(containing storyID: StoryID) -> StoryGroup? {
        groups.first { group in group.items.contains { $0.id == storyID } || group.id == storyID }
    }

    func hydrate(groupID: String) async -> StoryGroup? {
        guard !groupID.hasPrefix("add:") else { return groups.first(where: { $0.id == groupID }) }
        do {
            let loaded = try await repository.group(id: groupID)
            upsert(loaded)
            return loaded
        } catch {
            actionError = "This story isn’t available."
            return groups.first(where: { $0.id == groupID })
        }
    }

    func destination(for group: StoryGroup) async -> AppRoute? {
        if group.isComposerPlaceholder {
            return capabilities.create ? .stories(.create) : nil
        }
        let loaded = group.items.isEmpty ? await hydrate(groupID: group.id) : group
        guard let loaded else { return nil }
        let item = loaded.items.first(where: { !$0.seen }) ?? loaded.items.first
        return item.map { .stories(.story($0.id)) }
    }

    func publish(image: PreparedImage, caption: String?, visibility: String = "public") async -> Bool {
        guard capabilities.create else { return false }
        do {
            let group = try await repository.create(image: image, caption: caption, visibility: visibility)
            upsert(group)
            actionError = nil
            return true
        } catch let api as APIError {
            ModulaLog.network.error("story publish failed: \(api.diagnosticDescription, privacy: .public)")
            actionError = api.userFacingMessage
            return false
        } catch MediaPreparationError.exceedsByteBudget {
            ModulaLog.network.error("story publish failed: media could not meet the upload budget")
            actionError = "This photo is too detailed to share as a story. Try a different photo."
            return false
        } catch let url as URLError {
            ModulaLog.network.error("story publish failed: URLError \(url.code.rawValue, privacy: .public)")
            actionError = url.code == .timedOut
                ? "Sharing took too long. Check your connection and try again."
                : "Couldn’t reach Modula. Check your connection and try again."
            return false
        } catch {
            ModulaLog.network.error("story publish failed: \(String(describing: type(of: error)), privacy: .public)")
            actionError = "Couldn’t share your story. Try again."
            return false
        }
    }

    func markSeen(storyID: StoryID) {
        applySeen(storyID: storyID)
        Task {
            try? await repository.markViewed(itemID: storyID)
        }
    }

    private func applySeen(storyID: StoryID) {
        groups = groups.map { group in
            var copy = group
            copy.items = group.items.map { item in
                guard item.id == storyID else { return item }
                return StoryItem(
                    id: item.id,
                    author: item.author,
                    createdAt: item.createdAt,
                    expiresAt: item.expiresAt,
                    kind: item.kind,
                    media: item.media,
                    text: item.text,
                    background: item.background,
                    seen: true,
                    isOwn: item.isOwn,
                    viewerCount: item.viewerCount
                )
            }
            if copy.items.contains(where: { $0.id == storyID }), !copy.isOwn {
                copy.reportedRing = copy.items.contains(where: { !$0.seen }) ? .unseen : .seen
            }
            return copy
        }
    }

    private func upsert(_ group: StoryGroup) {
        if let index = groups.firstIndex(where: { $0.id == group.id || ($0.isOwn && group.isOwn) }) {
            groups[index] = group
        } else if group.isOwn {
            groups.insert(group, at: 0)
        } else {
            groups.append(group)
        }
    }

    #if DEBUG
    func installDebugGroups(_ items: [StoryGroup]) {
        groups = items
        loadState = .loaded
    }
    #endif
}

enum StoryFixtures {
    static let now = Date(timeIntervalSince1970: 1_784_000_000)

    static let unseen = StoryItem(
        id: "story-sophia",
        author: MessagingFixtures.sophia,
        createdAt: now.addingTimeInterval(-3_600),
        expiresAt: now.addingTimeInterval(82_800),
        kind: .text,
        media: nil,
        text: "Shipping native messaging.",
        background: "#369CAA",
        seen: false,
        isOwn: false,
        viewerCount: nil
    )

    static let seen = StoryItem(
        id: "story-marcus",
        author: MessagingFixtures.marcus,
        createdAt: now.addingTimeInterval(-7_200),
        expiresAt: now.addingTimeInterval(79_200),
        kind: .image,
        media: MediaResource(id: "media-marcus", kind: .image, url: nil, altText: "Studio light"),
        text: nil,
        background: "#7656D6",
        seen: true,
        isOwn: false,
        viewerCount: nil
    )

    static let own = StoryItem(
        id: "story-me",
        author: MessagingFixtures.me,
        createdAt: now.addingTimeInterval(-1_200),
        expiresAt: now.addingTimeInterval(85_200),
        kind: .text,
        media: nil,
        text: "Your story",
        background: "#4E8B67",
        seen: true,
        isOwn: true,
        viewerCount: 27
    )

    static var groups: [StoryGroup] {
        StoryGrouping.groups(from: [own, unseen, seen])
    }
}
