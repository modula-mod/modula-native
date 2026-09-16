import Foundation

protocol PublishingRepository: Sendable {
    func publish(_ draft: CreationDraft) async throws -> SocialPost
}

struct GreenfieldPublishingRepository: PublishingRepository {
    var client: GreenfieldClient
    var capabilities: CreationCapabilities

    func publish(_ draft: CreationDraft) async throws -> SocialPost {
        guard capabilities.canPublish(draft.kind) else {
            throw APIError.unavailable(
                capabilities.unavailableReason[draft.kind] ?? "Publishing isn’t available yet."
            )
        }
        switch draft.kind {
        case .post:
            let body = CreationPayloadEncoder.textPostBody(from: draft)
            let value: JSONValue = try await client.authenticatedJSON("POST", path: "/v1/posts", body: body)
            let payload = value["post"] ?? value
            guard let post = SocialPayloadDecoder.post(payload) else {
                throw APIError.invalidResponse
            }
            return post
        case .story, .reel, .photo, .video, .link, .poll, .carousel, .audio, .movie:
            throw APIError.unavailable(
                capabilities.unavailableReason[draft.kind] ?? "Publishing isn’t available yet."
            )
        }
    }
}

struct MockPublishingRepository: PublishingRepository {
    enum Behavior: Sendable {
        case success(SocialPost)
        case failure
    }

    var behavior: Behavior

    func publish(_ draft: CreationDraft) async throws -> SocialPost {
        _ = draft
        switch behavior {
        case .success(let post):
            return post
        case .failure:
            throw APIError.rejected(500, "PUBLISH_FAILED")
        }
    }
}
