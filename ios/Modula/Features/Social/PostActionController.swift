import Foundation
import Observation

/// Owns post engagement mutations with optimistic UI, race coalescing, and shared state sync.
@MainActor @Observable
final class PostActionController {
    private let repository: GreenfieldPostRepository
    private let state: PostStateStore
    private var likeGeneration: [SocialPostID: UInt64] = [:]
    private var saveGeneration: [SocialPostID: UInt64] = [:]
    private var repostGeneration: [SocialPostID: UInt64] = [:]
    private(set) var lastError: String?
    let capabilities: PostBackendCapabilities

    init(client: GreenfieldClient, state: PostStateStore, capabilities: PostBackendCapabilities = .production) {
        self.repository = GreenfieldPostRepository(client: client, capabilities: capabilities)
        self.state = state
        self.capabilities = capabilities
    }

    func ingest(_ post: SocialPost) {
        state.upsert(post)
    }

    func ingest(_ posts: [SocialPost]) {
        state.upsert(contentsOf: posts)
    }

    func resolved(_ post: SocialPost) -> SocialPost {
        state.resolved(post)
    }

    func loadPost(id: SocialPostID) async throws -> SocialPost {
        let post = try await repository.post(id: id)
        state.upsert(post)
        return state.resolved(post)
    }

    func toggleLike(_ post: SocialPost) async {
        guard capabilities.like else { return }
        let current = state.resolved(post)
        let nextLiked = !current.liked
        let snapshot = current.engagement
        let generation = (likeGeneration[current.id] ?? 0) + 1
        likeGeneration[current.id] = generation

        state.applyEngagement(postID: current.id) { engagement in
            engagement.liked = nextLiked
            engagement.likeCount = max(0, engagement.likeCount + (nextLiked ? 1 : -1))
            if nextLiked {
                engagement.viewerReaction = .like
                engagement.reactionCount = max(engagement.reactionCount, engagement.likeCount)
            } else if engagement.viewerReaction == .like {
                engagement.viewerReaction = nil
                engagement.reactionCount = max(0, engagement.reactionCount - 1)
            }
        }

        do {
            if nextLiked {
                try await repository.like(postID: current.id)
            } else {
                try await repository.unlike(postID: current.id)
            }
            guard likeGeneration[current.id] == generation else { return }
            HapticEngine.shared.play(.lightImpact)
            lastError = nil
        } catch {
            guard likeGeneration[current.id] == generation else { return }
            state.replaceEngagement(postID: current.id, with: snapshot)
            lastError = (error as? APIError)?.userFacingMessage ?? "Could not update like."
            HapticEngine.shared.play(.failure)
        }
    }

    /// Commits a reaction. With like-only HTTP, non-like values are rejected unless multiReactions is enabled.
    func setReaction(_ post: SocialPost, reaction: SocialReaction?) async {
        let current = state.resolved(post)
        if let reaction, !capabilities.multiReactions, reaction != .like {
            lastError = "That reaction is not available yet."
            HapticEngine.shared.play(.warning)
            return
        }
        if reaction == nil || reaction == .like {
            if current.liked && reaction == nil {
                await toggleLike(current)
            } else if !current.liked && reaction == .like {
                await toggleLike(current)
            } else if current.liked && reaction == .like {
                // Already liked — treat as confirmation.
                HapticEngine.shared.play(.confirmation)
            } else {
                await toggleLike(current)
            }
            return
        }
        // Reserved for future multi-reaction HTTP.
        lastError = "That reaction is not available yet."
        HapticEngine.shared.play(.warning)
    }

    func toggleSave(_ post: SocialPost) async {
        guard capabilities.save else { return }
        let current = state.resolved(post)
        let nextSaved = !current.saved
        let snapshot = current.engagement
        let generation = (saveGeneration[current.id] ?? 0) + 1
        saveGeneration[current.id] = generation

        state.applyEngagement(postID: current.id) { $0.saved = nextSaved }

        do {
            if nextSaved {
                try await repository.save(postID: current.id)
            } else {
                try await repository.unsave(postID: current.id)
            }
            guard saveGeneration[current.id] == generation else { return }
            HapticEngine.shared.play(.saveComplete)
            lastError = nil
        } catch {
            guard saveGeneration[current.id] == generation else { return }
            state.replaceEngagement(postID: current.id, with: snapshot)
            lastError = (error as? APIError)?.userFacingMessage ?? "Could not update save."
            HapticEngine.shared.play(.failure)
        }
    }

    func toggleRepost(_ post: SocialPost) async {
        guard capabilities.repost else { return }
        let current = state.resolved(post)
        let next = !current.reposted
        let snapshot = current.engagement
        let generation = (repostGeneration[current.id] ?? 0) + 1
        repostGeneration[current.id] = generation

        state.applyEngagement(postID: current.id) { engagement in
            engagement.reposted = next
            engagement.repostCount = max(0, engagement.repostCount + (next ? 1 : -1))
        }

        do {
            if next {
                try await repository.repost(postID: current.id)
            } else {
                try await repository.unrepost(postID: current.id)
            }
            guard repostGeneration[current.id] == generation else { return }
            HapticEngine.shared.play(.confirmation)
            lastError = nil
        } catch {
            guard repostGeneration[current.id] == generation else { return }
            state.replaceEngagement(postID: current.id, with: snapshot)
            lastError = (error as? APIError)?.userFacingMessage ?? "Could not update repost."
            HapticEngine.shared.play(.failure)
        }
    }

    func recordShare(_ post: SocialPost) async {
        do {
            try await repository.recordShare(postID: post.id)
        } catch {
            // Share sheet already succeeded locally; receipt is best-effort.
        }
    }

    func deletePost(_ post: SocialPost) async -> Bool {
        do {
            try await repository.deletePost(postID: post.id)
            state.markDeleted(post.id)
            HapticEngine.shared.play(.success)
            lastError = nil
            return true
        } catch {
            lastError = (error as? APIError)?.userFacingMessage ?? "Could not delete post."
            HapticEngine.shared.play(.failure)
            return false
        }
    }

    func editPost(_ post: SocialPost, text: String) async -> SocialPost? {
        do {
            let updated = try await repository.editPost(postID: post.id, text: text)
            state.upsert(updated)
            HapticEngine.shared.play(.success)
            lastError = nil
            return state.resolved(updated)
        } catch {
            lastError = (error as? APIError)?.userFacingMessage ?? "Could not edit post."
            HapticEngine.shared.play(.failure)
            return nil
        }
    }

    func hideLocally(_ post: SocialPost) {
        state.hideLocally(post.id)
        HapticEngine.shared.play(.confirmation)
    }

    func clearError() { lastError = nil }
}
