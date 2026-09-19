import Foundation
import Observation

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

    var ring: StoryRingState {
        if isOwn { return .own }
        return items.contains(where: { !$0.seen }) ? .unseen : .seen
    }

    var representative: StoryItem? { items.first }
}

struct StoryBackendCapabilities: Sendable, Equatable {
    var list = false
    var create = false
    var viewers = false
    var reply = false
    var react = false
    var privacy = false
    var video = false

    static let production = StoryBackendCapabilities()

    enum Paths {
        static let groups = "/v1/stories"
        static func story(_ id: String) -> String { "/v1/stories/\(escape(id))" }
        static let create = "/v1/stories"
        static func viewers(_ id: String) -> String { "/v1/stories/\(escape(id))/viewers" }

        private static func escape(_ value: String) -> String {
            value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
        }
    }
}

enum StoryPayloadDecoder {
    static func groups(from value: JSONValue) -> [StoryGroup] {
        let items = value["items"]?.array ?? value["groups"]?.array ?? value["stories"]?.array ?? []
        return items.compactMap(group)
    }

    static func group(_ value: JSONValue) -> StoryGroup? {
        let items = (value["items"]?.array ?? [value]).compactMap(item)
        guard let first = items.first else { return nil }
        return StoryGroup(
            id: value["id"]?.string ?? first.author.id,
            author: first.author,
            items: items,
            isOwn: first.isOwn
        )
    }

    static func item(_ value: JSONValue) -> StoryItem? {
        let id = value["id"]?.string
        guard let id else { return nil }
        let author = value["author"].flatMap(MessagingPayloadDecoder.participant) ?? ConversationParticipant(
            id: "unknown", handle: "", displayName: "Member", avatarURL: nil
        )
        let kind = StoryKind(parsing: value["kind"]?.string ?? value["type"]?.string)
        let media = value["media"].flatMap { MediaPayloadDecoder.resource(from: $0, fallbackID: id) }
        return StoryItem(
            id: id,
            author: author,
            createdAt: MessagingPayloadDecoder.decodeDate(value["createdAt"]?.string) ?? Date(),
            expiresAt: MessagingPayloadDecoder.decodeDate(value["expiresAt"]?.string),
            kind: kind == .unknown && media != nil ? .image : kind,
            media: media,
            text: value["text"]?.string,
            background: value["background"]?.string ?? value["colour"]?.string,
            seen: value["seen"]?.bool ?? false,
            isOwn: value["isOwn"]?.bool ?? false,
            viewerCount: value["viewerCount"]?.int
        )
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

struct StoryBackendRepository: Sendable {
    let capabilities: StoryBackendCapabilities
    private let client: GreenfieldClient

    init(client: GreenfieldClient, capabilities: StoryBackendCapabilities = .production) {
        self.client = client
        self.capabilities = capabilities
    }

    func groups() async throws -> [StoryGroup] {
        guard capabilities.list else { throw APIError.unavailable("Story isn't available.") }
        let value: JSONValue = try await client.json("GET", path: StoryBackendCapabilities.Paths.groups)
        return StoryPayloadDecoder.groups(from: value)
    }
}

@MainActor @Observable
final class StoryStore {
    private let repository: StoryBackendRepository
    let capabilities: StoryBackendCapabilities
    private(set) var groups: [StoryGroup] = []
    private(set) var loadState: MessagingLoadState = .idle
    private(set) var actionError: String?

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
            groups = try await repository.groups()
            loadState = .loaded
        } catch {
            loadState = groups.isEmpty ? .failed("Story isn't available.") : .loaded
            actionError = "Story isn't available."
        }
    }

    func group(containing storyID: StoryID) -> StoryGroup? {
        groups.first { group in group.items.contains { $0.id == storyID } }
    }

    func markSeen(storyID: StoryID) {
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
            return copy
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
