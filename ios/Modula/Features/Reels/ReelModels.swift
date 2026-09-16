import Foundation
import Observation

typealias ReelID = String

struct ReelAudio: Hashable, Sendable {
    let title: String
    let artist: String?
}

struct Reel: Identifiable, Hashable, Sendable {
    let id: ReelID
    let postID: SocialPostID?
    let creator: SocialAuthor
    let media: MediaResource?
    let caption: String?
    let audio: ReelAudio?
    let posterColor: String?
    let engagement: PostEngagement
    let createdAt: Date

    var durationLabel: String? {
        guard let duration = media?.duration else { return nil }
        return "\(Int(duration.rounded())) seconds"
    }

    func asSocialPost() -> SocialPost {
        SocialPost(
            id: postID ?? id,
            author: creator,
            createdAt: createdAt,
            editedAt: nil,
            feed: "reels",
            text: caption,
            kind: media?.kind == .video ? .video : .media,
            visibility: .public,
            audience: "public",
            media: media.map {
                [SocialPostMedia(id: $0.id, url: $0.url, altText: $0.altText, kind: $0.kind.rawValue, aspectRatio: $0.dimensions?.aspectRatio)]
            } ?? [],
            link: nil,
            module: nil,
            glowColour: posterColor,
            engagement: engagement
        )
    }
}

struct ReelPage: Sendable, Equatable {
    var items: [Reel]
    var nextCursor: String?
}

struct ReelBackendCapabilities: Sendable, Equatable {
    var seedList = true
    var rankedFeed = false
    var videoPlayback = false
    var audioAttribution = false
    var captions = false
    var commentsViaPost = false
    var create = false

    static let production = ReelBackendCapabilities()

    enum Paths {
        static let seed = "/v1/reels"
        static func reel(_ id: String) -> String { "/v1/reels/\(escape(id))" }
        private static func escape(_ value: String) -> String {
            value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
        }
    }
}

enum ReelPayloadDecoder {
    static func page(from value: JSONValue) -> ReelPage {
        let items = (value["items"]?.array ?? value["reels"]?.array ?? value.array ?? []).compactMap(reel)
        return ReelPage(items: items, nextCursor: value["nextCursor"]?.string)
    }

    static func reel(_ value: JSONValue) -> Reel? {
        let id = value["id"]?.string
        guard let id else { return nil }
        let authorValue = value["author"]
        let creator: SocialAuthor
        if let authorValue, let person = MessagingPayloadDecoder.participant(authorValue) {
            creator = person.asAuthor
        } else if let name = authorValue?.string {
            creator = SocialAuthor(id: name, handle: name, displayName: name, avatarURL: nil)
        } else {
            creator = SocialAuthor(id: "unknown", handle: "", displayName: "Creator", avatarURL: nil)
        }
        let media = value["media"].flatMap { MediaPayloadDecoder.resource(from: $0, fallbackID: id) }
        let audio: ReelAudio?
        if let title = value["audio"]?["title"]?.string {
            audio = ReelAudio(title: title, artist: value["audio"]?["artist"]?.string)
        } else {
            audio = nil
        }
        let liked = value["liked"]?.bool ?? false
        return Reel(
            id: id,
            postID: value["postId"]?.string,
            creator: creator,
            media: media,
            caption: value["caption"]?.string ?? value["text"]?.string,
            audio: audio,
            posterColor: value["colour"]?.string ?? value["color"]?.string ?? value["source"]?.string,
            engagement: PostEngagement(
                liked: liked,
                saved: value["saved"]?.bool ?? false,
                reposted: false,
                viewerReaction: liked ? .like : nil,
                likeCount: value["likeCount"]?.int ?? 0,
                replyCount: value["replyCount"]?.int ?? 0,
                repostCount: 0,
                quoteCount: 0,
                reactionCount: value["likeCount"]?.int ?? 0
            ),
            createdAt: MessagingPayloadDecoder.decodeDate(value["createdAt"]?.string) ?? Date()
        )
    }
}

actor GreenfieldReelRepository {
    private let client: GreenfieldClient
    let capabilities: ReelBackendCapabilities
    private var memory: ReelPage?

    init(client: GreenfieldClient, capabilities: ReelBackendCapabilities = .production) {
        self.client = client
        self.capabilities = capabilities
    }

    func cached() -> ReelPage? { memory }

    func feed() async throws -> ReelPage {
        guard capabilities.seedList || capabilities.rankedFeed else {
            throw APIError.unavailable("Couldn't load this reel.")
        }
        let value: JSONValue = try await client.publicJSON("GET", path: ReelBackendCapabilities.Paths.seed)
        let page = ReelPayloadDecoder.page(from: value)
        memory = page
        return page
    }
}

@MainActor @Observable
final class ReelStore {
    private let repository: GreenfieldReelRepository
    let capabilities: ReelBackendCapabilities
    private(set) var items: [Reel] = []
    private(set) var loadState: MessagingLoadState = .idle
    private(set) var activeID: ReelID?
    var restoredID: ReelID?

    init(client: GreenfieldClient, capabilities: ReelBackendCapabilities = .production) {
        self.repository = GreenfieldReelRepository(client: client, capabilities: capabilities)
        self.capabilities = capabilities
    }

    func ingest(seed: [Reel]) {
        guard !seed.isEmpty else { return }
        items = seed
        loadState = .loaded
        if activeID == nil { activeID = seed.first?.id }
    }

    func loadIfNeeded() async {
        if !items.isEmpty { return }
        await refresh()
    }

    func refresh() async {
        loadState = items.isEmpty ? .loading : .refreshing
        do {
            let page = try await repository.feed()
            items = page.items
            loadState = .loaded
            if activeID == nil { activeID = page.items.first?.id }
        } catch {
            if let cached = await repository.cached(), !cached.items.isEmpty {
                items = cached.items
                loadState = .loaded
            } else {
                loadState = .failed("Couldn't load this reel.")
            }
        }
    }

    func activate(_ id: ReelID) {
        activeID = id
        restoredID = id
    }

    func reel(id: ReelID) -> Reel? { items.first { $0.id == id } }

    func index(of id: ReelID) -> Int? { items.firstIndex { $0.id == id } }

    #if DEBUG
    func installDebugReels(_ reels: [Reel]) {
        items = reels
        loadState = .loaded
        activeID = reels.first?.id
    }
    #endif
}

enum ReelFixtures {
    static let preview = Reel(
        id: "reel-preview",
        postID: nil,
        creator: SocialAuthor(id: "sophia", handle: "sophia.chen", displayName: "Sophia Chen", avatarURL: nil),
        media: nil,
        caption: "Preview-only reel. Not production data.",
        audio: nil,
        posterColor: "#369CAA",
        engagement: PostEngagement(
            liked: false, saved: false, reposted: false, viewerReaction: nil,
            likeCount: 12, replyCount: 3, repostCount: 0, quoteCount: 0, reactionCount: 12
        ),
        createdAt: Date(timeIntervalSince1970: 1_784_000_000)
    )
}
