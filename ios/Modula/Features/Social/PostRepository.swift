import Foundation

protocol PostRepository: Sendable {
    func post(id: SocialPostID) async throws -> SocialPost
    func like(postID: SocialPostID) async throws
    func unlike(postID: SocialPostID) async throws
    func save(postID: SocialPostID) async throws
    func unsave(postID: SocialPostID) async throws
    func repost(postID: SocialPostID) async throws
    func unrepost(postID: SocialPostID) async throws
    func recordShare(postID: SocialPostID) async throws
    func comments(postID: SocialPostID, cursor: String?) async throws -> CommentPage
    func createComment(postID: SocialPostID, text: String, parentID: SocialCommentID?) async throws -> SocialComment
    func deleteComment(commentID: SocialCommentID) async throws
    func editPost(postID: SocialPostID, text: String) async throws -> SocialPost
    func deletePost(postID: SocialPostID) async throws
}

actor GreenfieldPostRepository: PostRepository {
    private let client: GreenfieldClient
    let capabilities: PostBackendCapabilities

    init(client: GreenfieldClient, capabilities: PostBackendCapabilities = .production) {
        self.client = client
        self.capabilities = capabilities
    }

    func post(id: SocialPostID) async throws -> SocialPost {
        let value = try await client.json("GET", path: "/v1/posts/\(Self.pathEscaped(id))")
        let payload = value["post"] ?? value
        guard let post = SocialPayloadDecoder.post(payload) else {
            throw APIError.invalidResponse
        }
        return post
    }

    func like(postID: SocialPostID) async throws {
        let _: JSONValue = try await client.authenticatedJSON(
            "POST",
            path: "/v1/posts/\(Self.pathEscaped(postID))/like",
            body: .object([:])
        )
    }

    func unlike(postID: SocialPostID) async throws {
        let _: JSONValue = try await client.authenticatedJSON(
            "DELETE",
            path: "/v1/posts/\(Self.pathEscaped(postID))/like",
            body: nil
        )
    }

    func setReaction(postID: SocialPostID, reaction: SocialReaction?) async throws -> JSONValue {
        try await client.authenticatedJSON(
            reaction == nil ? "DELETE" : "PUT",
            path: "/v1/posts/\(Self.pathEscaped(postID))/reaction",
            body: reaction.map { .object(["type": .string($0.rawValue)]) }
        )
    }

    func replies(commentID: SocialCommentID, postID: SocialPostID) async throws -> [SocialComment] {
        let value = try await client.json("GET", path: "/v1/comments/\(Self.pathEscaped(commentID))/replies")
        return SocialPayloadDecoder.commentPage(from: value, postID: postID).items
    }

    func save(postID: SocialPostID) async throws {
        let _: JSONValue = try await client.authenticatedJSON(
            "POST",
            path: "/v1/posts/\(Self.pathEscaped(postID))/save",
            body: .object([:])
        )
    }

    func unsave(postID: SocialPostID) async throws {
        let _: JSONValue = try await client.authenticatedJSON(
            "DELETE",
            path: "/v1/posts/\(Self.pathEscaped(postID))/save",
            body: nil
        )
    }

    func repost(postID: SocialPostID) async throws {
        let _: JSONValue = try await client.authenticatedJSON(
            "POST",
            path: "/v1/posts/\(Self.pathEscaped(postID))/repost",
            body: .object([:])
        )
    }

    func unrepost(postID: SocialPostID) async throws {
        let _: JSONValue = try await client.authenticatedJSON(
            "DELETE",
            path: "/v1/posts/\(Self.pathEscaped(postID))/repost",
            body: nil
        )
    }

    func recordShare(postID: SocialPostID) async throws {
        guard capabilities.shareReceipt else { return }
        let _: JSONValue = try await client.authenticatedJSON(
            "POST",
            path: "/v1/posts/\(Self.pathEscaped(postID))/share",
            body: .object([:])
        )
    }

    func comments(postID: SocialPostID, cursor: String?) async throws -> CommentPage {
        guard capabilities.commentsList else {
            throw APIError.unavailable("Comments are not available yet.")
        }
        var path = PostBackendCapabilities.CommentPaths.list(postID: postID)
        if let cursor, let encoded = cursor.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            path += "&cursor=\(encoded)"
        }
        let value: JSONValue = try await client.json("GET", path: path)
        return SocialPayloadDecoder.commentPage(from: value, postID: postID)
    }

    func createComment(postID: SocialPostID, text: String, parentID: SocialCommentID?) async throws -> SocialComment {
        guard capabilities.commentsCreate else {
            throw APIError.unavailable("Commenting is not available yet.")
        }
        let body: [String: JSONValue] = ["text": .string(text)]
        let path = parentID.map { "/v1/comments/\(Self.pathEscaped($0))/replies" }
            ?? PostBackendCapabilities.CommentPaths.create(postID: postID)
        let value: JSONValue = try await client.authenticatedJSON(
            "POST",
            path: path,
            body: .object(body)
        )
        let payload = value["comment"] ?? value
        if let decoded = SocialPayloadDecoder.comment(payload, fallbackPostID: postID) {
            return decoded
        }
        // Optimistic identity if envelope is acknowledgment-only.
        return SocialComment(
            id: value["id"]?.string ?? UUID().uuidString,
            postID: postID,
            author: nil,
            createdAt: Date(),
            editedAt: nil,
            text: text,
            parentID: parentID,
            replyCount: 0,
            liked: false,
            likeCount: 0,
            isPending: false
        )
    }

    func deleteComment(commentID: SocialCommentID) async throws {
        guard capabilities.commentsDelete else {
            throw APIError.unavailable("Deleting comments is not available yet.")
        }
        let _: JSONValue = try await client.authenticatedJSON(
            "DELETE",
            path: PostBackendCapabilities.CommentPaths.delete(commentID: commentID),
            body: nil
        )
    }

    func editPost(postID: SocialPostID, text: String) async throws -> SocialPost {
        guard capabilities.editOwnPost else {
            throw APIError.unavailable("Editing posts is not available yet.")
        }
        let value: JSONValue = try await client.authenticatedJSON(
            "PATCH",
            path: "/v1/posts/\(Self.pathEscaped(postID))",
            body: .object(["text": .string(text)])
        )
        let payload = value["post"] ?? value
        guard let post = SocialPayloadDecoder.post(payload) else {
            throw APIError.invalidResponse
        }
        return post
    }

    func deletePost(postID: SocialPostID) async throws {
        guard capabilities.deleteOwnPost else {
            throw APIError.unavailable("Deleting posts is not available yet.")
        }
        let _: JSONValue = try await client.authenticatedJSON(
            "DELETE",
            path: "/v1/posts/\(Self.pathEscaped(postID))",
            body: nil
        )
    }

    nonisolated private static func pathEscaped(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }
}

extension APIError {
    static func unavailable(_ message: String) -> APIError {
        .rejected(501, "UNAVAILABLE")
    }
}
