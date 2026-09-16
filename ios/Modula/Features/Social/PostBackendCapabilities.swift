import Foundation

/// Honest capability map for post interactions. Only enable what Greenfield truth supports.
struct PostBackendCapabilities: Sendable, Equatable {
    var like = true
    var save = true
    var repost = true
    var shareReceipt = false
    /// Multi-value reaction HTTP beyond like toggle.
    var multiReactions = false
    var commentsList = true
    var commentsCreate = true
    /// DELETE `/v1/comments/:id` was not live-verified this closeout.
    var commentsDelete = false
    /// List returns top-level rows only (`parent_comment_id` null). Do not offer a reply composer.
    var commentReplies = false
    var editOwnPost = false
    var deleteOwnPost = false
    var likesList = false
    var reactionsList = false
    var sharesList = false
    var reportPost = false
    var reportComment = false
    var muteAuthor = true
    var notInterested = false
    var hideLocally = true

    /// Production defaults from repository contracts (N3C/N4A docs). Live VPS re-audit may widen.
    static let production = PostBackendCapabilities()

    /// Live-verified comment collection. List GET confirmed 2026-09-16 against api.modula.digital.
    enum CommentPaths {
        static func list(postID: String) -> String {
            "/v1/posts/\(escape(postID))/comments?limit=30"
        }

        static func create(postID: String) -> String {
            "/v1/posts/\(escape(postID))/comments"
        }

        static func delete(commentID: String) -> String {
            "/v1/comments/\(escape(commentID))"
        }

        private static func escape(_ value: String) -> String {
            value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
        }
    }
}
