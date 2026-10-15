import Foundation

/// Honest map of what Greenfield can publish today. Not a wishlist.
struct CreationCapabilities: Sendable, Equatable {
    var textPost = true
    var photoPost = false
    var carouselPost = false
    var videoPost = false
    var linkPost = false
    var linkPreview = false
    var pollPost = false
    var audioPost = false
    var moviePost = false
    var storyPhoto = false
    var storyText = false
    var reelPost = false
    var mentionsLookup = false
    var structuredMentions = false
    var topicsLookup = false
    var locationAttach = false
    var mediaUpload = false
    var backgroundUpload = false
    var scheduledPublish = false
    var serverDrafts = false
    var characterLimit: Int? = nil
    var maxMediaCount: Int? = nil
    var maxPollOptions: Int? = nil
    var maxPollDurationHours: Int? = nil
    var sensitiveMediaControls = false

    /// Production defaults from repository contracts. Live VPS re-audit may widen.
    static let production: CreationCapabilities = {
        var value = CreationCapabilities()
        value.photoPost = true
        value.carouselPost = true
        value.videoPost = true
        value.audioPost = true
        value.mediaUpload = true
        value.maxMediaCount = 10
        return value
    }()

    static let developerPreview: CreationCapabilities = {
        var value = CreationCapabilities()
        value.textPost = true
        return value
    }()

    func canPublish(_ kind: CreationKind) -> Bool {
        switch kind {
        case .post: textPost
        case .photo: photoPost
        case .video: videoPost
        case .link: linkPost
        case .poll: pollPost
        case .carousel: carouselPost
        case .audio: audioPost
        case .movie: moviePost
        case .story: storyPhoto || storyText
        case .reel: reelPost
        }
    }

    func toolVisible(_ tool: CreationTool, kind: CreationKind, developerMode: Bool) -> Bool {
        let enabled = toolEnabled(tool)
        if developerMode { return tool.applies(to: kind) }
        return enabled && tool.applies(to: kind)
    }

    func toolEnabled(_ tool: CreationTool) -> Bool {
        switch tool {
        case .photo: photoPost || storyPhoto
        case .video: videoPost || reelPost
        case .link: linkPost
        case .poll: pollPost
        case .more: mediaUpload
        }
    }

    var unavailableReason: [CreationKind: String] {
        [
            .photo: "Photo publishing needs a verified media upload contract.",
            .carousel: "Carousel publishing is off until multi-image upload is verified.",
            .video: "Video publishing needs a verified codec and upload contract.",
            .link: "Structured link posts wait on a Greenfield preview/write contract.",
            .poll: "Polls are not in the current SocialPost contract.",
            .audio: "Audio posts are not defined on Greenfield yet.",
            .movie: "Movie is a distinct future kind — not ordinary video upload.",
            .story: "Story publishing is not enabled on this client.",
            .reel: "Reel publishing waits on a verified Reels write path."
        ]
    }
}

enum CreationTool: String, CaseIterable, Identifiable, Sendable, Hashable {
    case photo
    case video
    case link
    case poll
    case more

    var id: String { rawValue }

    var title: String {
        switch self {
        case .photo: "Photo"
        case .video: "Video"
        case .link: "Link"
        case .poll: "Poll"
        case .more: "More"
        }
    }

    var symbol: String {
        switch self {
        case .photo: "photo.on.rectangle.angled"
        case .video: "video.fill"
        case .link: "link"
        case .poll: "chart.bar.fill"
        case .more: "ellipsis.circle"
        }
    }

    func applies(to kind: CreationKind) -> Bool {
        switch kind {
        case .post, .photo, .carousel, .link:
            return true
        case .poll:
            return self == .poll
        case .story:
            return self == .photo
        case .reel, .video:
            return self == .video
        case .audio, .movie:
            return self == .more
        }
    }
}
