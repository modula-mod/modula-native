import Foundation
import Observation

/// Canonical shared engagement state for a post visible across Home, Profile, Discover, and Detail.
@MainActor @Observable
final class PostStateStore {
    private(set) var posts: [SocialPostID: SocialPost] = [:]
    private(set) var deletedIDs: Set<SocialPostID> = []
    private(set) var locallyHiddenIDs: Set<SocialPostID> = []
    private(set) var revision: UInt64 = 0

    func upsert(_ post: SocialPost) {
        guard !deletedIDs.contains(post.id) else { return }
        if let existing = posts[post.id] {
            posts[post.id] = SocialPost(
                id: post.id,
                author: post.author ?? existing.author,
                createdAt: post.createdAt,
                editedAt: post.editedAt ?? existing.editedAt,
                feed: post.feed ?? existing.feed,
                text: post.text ?? existing.text,
                kind: post.kind == .unknown ? existing.kind : post.kind,
                visibility: post.visibility == .unknown ? existing.visibility : post.visibility,
                audience: post.audience ?? existing.audience,
                media: post.media.isEmpty ? existing.media : post.media,
                link: post.link ?? existing.link,
                module: post.module ?? existing.module,
                glowColour: post.glowColour ?? existing.glowColour,
                engagement: post.engagement,
                location: post.location ?? existing.location
            )
        } else {
            posts[post.id] = post
        }
        bump()
    }

    func upsert(contentsOf batch: [SocialPost]) {
        for post in batch { upsert(post) }
    }

    func post(id: SocialPostID) -> SocialPost? {
        guard !deletedIDs.contains(id) else { return nil }
        return posts[id]
    }

    func resolved(_ post: SocialPost) -> SocialPost {
        guard let cached = posts[post.id] else { return post }
        return post.mergingEngagement(from: cached)
    }

    func applyEngagement(postID: SocialPostID, _ mutate: (inout PostEngagement) -> Void) {
        guard var post = posts[postID] else { return }
        mutate(&post.engagement)
        posts[postID] = post
        bump()
    }

    func replaceEngagement(postID: SocialPostID, with engagement: PostEngagement) {
        guard var post = posts[postID] else { return }
        post.engagement = engagement
        posts[postID] = post
        bump()
    }

    func markDeleted(_ postID: SocialPostID) {
        deletedIDs.insert(postID)
        posts.removeValue(forKey: postID)
        bump()
    }

    func hideLocally(_ postID: SocialPostID) {
        locallyHiddenIDs.insert(postID)
        bump()
    }

    func unhide(_ postID: SocialPostID) {
        locallyHiddenIDs.remove(postID)
        bump()
    }

    func isHidden(_ postID: SocialPostID) -> Bool {
        deletedIDs.contains(postID) || locallyHiddenIDs.contains(postID)
    }

    func adjustReplyCount(postID: SocialPostID, delta: Int) {
        applyEngagement(postID: postID) { engagement in
            engagement.replyCount = max(0, engagement.replyCount + delta)
        }
    }

    private func bump() { revision &+= 1 }
}
