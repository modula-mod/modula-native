import Foundation
import Observation
import UIKit

@MainActor @Observable
final class ProfileStore {
    private let repository: GreenfieldProfileRepository
    private let client: GreenfieldClient
    private let posts: PostStateStore?
    private(set) var sessions: [String: ProfileSessionState] = [:]
    private(set) var actionError: String?
    private(set) var editing = ProfileEditingState()
    private(set) var visitorPreviewActive = false
    private(set) var mediaBusy = false
    private(set) var tabBarAvatar: UIImage?
    let customization = ProfileCustomizationCapabilities.production

    var ownProfile: ModulaProfile? { sessions["me"]?.profile ?? sessions.first(where: { $0.key.hasPrefix("me") })?.value.profile }

    init(client: GreenfieldClient, posts: PostStateStore? = nil) {
        self.client = client
        self.repository = GreenfieldProfileRepository(client: client)
        self.posts = posts
    }

    func refreshTabBarAvatar(account: GreenfieldAccount?, accent: UIColor) async {
        let profile = ownProfile ?? session(for: .me, handleHint: account?.primaryHandle).profile
        var photo: UIImage?
        if let url = profile?.avatarURL {
            tabBarAvatar = ProfileTabAvatarRenderer.status(symbol: "person.crop.circle", accent: accent)
            if let cached = ProfileTabAvatarRenderer.cachedPhoto(for: url) {
                photo = cached
            } else if let data = try? await client.mediaData(from: url),
                      let image = await Task.detached(priority: .utility, operation: {
                          ModulaRemoteImageDecoder.downsample(data: data, maximumPixelSize: 192)
                      }).value {
                ProfileTabAvatarRenderer.storePhoto(image, for: url)
                photo = image
            } else {
                tabBarAvatar = ProfileTabAvatarRenderer.status(symbol: "exclamationmark", accent: accent)
                return
            }
        }
        tabBarAvatar = ProfileTabAvatarRenderer.image(
            photo: photo,
            initials: ProfileTabAvatarRenderer.initials(profile: profile, account: account),
            accent: accent
        )
    }

    func session(for identity: ProfileIdentity, handleHint: String? = nil) -> ProfileSessionState {
        sessions[sessionKey(identity, handleHint: handleHint)] ?? ProfileSessionState()
    }

    func loadIfNeeded(
        _ identity: ProfileIdentity,
        handleHint: String?,
        accountHandle: String?,
        catalogue: [CatalogueProduct]
    ) async {
        let key = sessionKey(identity, handleHint: handleHint ?? accountHandle)
        var state = sessions[key] ?? ProfileSessionState()
        if let cached = await repository.cachedProfile(key: cacheLookupKey(identity, handleHint: handleHint ?? accountHandle)) {
            state.profile = cached
            state.loadState = .loaded
            sessions[key] = state
            await refresh(identity, handleHint: handleHint, accountHandle: accountHandle, catalogue: catalogue, background: true)
            return
        }
        guard state.loadState == .idle || state.profile == nil else { return }
        await refresh(identity, handleHint: handleHint, accountHandle: accountHandle, catalogue: catalogue, background: false)
    }

    func refresh(
        _ identity: ProfileIdentity,
        handleHint: String?,
        accountHandle: String?,
        catalogue: [CatalogueProduct],
        background: Bool = false
    ) async {
        let key = sessionKey(identity, handleHint: handleHint ?? accountHandle)
        var state = sessions[key] ?? ProfileSessionState()
        let hasContent = state.profile != nil
        if !background {
            state.loadState = hasContent ? .refreshing : .loading
            state.lastError = nil
            sessions[key] = state
        }
        do {
            let resolvedHint = handleHint ?? accountHandle
            let profile = try await repository.profile(identity, handleHint: identity == .me ? accountHandle : resolvedHint)
            state.profile = profile
            state.loadState = .loaded
            state.lastError = nil
            state.lastRefresh = Date()
            sessions[key] = state
            actionError = nil

            // Overview preview only — not full posts pagination.
            if state.overviewPreviewPosts.isEmpty || !background {
                if let page = try? await repository.posts(identity, handle: profile.handle, cursor: nil) {
                    state.overviewPreviewPosts = Array(page.items.prefix(3))
                    var posts = state.posts
                    if posts.items.isEmpty {
                        posts.items = page.items
                        posts.nextCursor = page.nextCursor
                        posts.hasMore = page.hasMore
                        posts.loadState = .loaded
                        state.posts = posts
                    }
                    sessions[key] = state
                }
            }
            let modules = await repository.modules(featuredIDs: profile.featuredModuleIds, catalogue: catalogue)
            state.modules.items = modules.items
            state.modules.loadState = .loaded
            sessions[key] = state
        } catch ProfileRepositoryError.notFound {
            if hasContent {
                state.loadState = .loaded
                sessions[key] = state
                actionError = "Profile could not be refreshed."
            } else {
                state.loadState = .notFound
                state.profile = nil
                sessions[key] = state
            }
        } catch let api as APIError {
            if case .rejected(_, let code) = api, code == "NOT_FOUND" || code == "FORBIDDEN" {
                state.loadState = hasContent ? .loaded : .unavailable
                if !hasContent { state.profile = nil }
                sessions[key] = state
                if hasContent { actionError = api.userFacingMessage }
                return
            }
            if hasContent {
                // Cached profile stays on screen; a transient refresh failure isn't worth a toast.
                state.loadState = .loaded
                state.lastError = api.userFacingMessage
                sessions[key] = state
            } else {
                state.loadState = .failed(api.userFacingMessage)
                state.lastError = api.userFacingMessage
                sessions[key] = state
            }
        } catch {
            // Pull-to-refresh used to cancel its own request (the refresh task is torn down
            // when the view re-renders), which surfaced as a bogus "Unable to load profile."
            // Cancellation and transient failures over cached content are silent.
            let cancelled = error is CancellationError || (error as? URLError)?.code == .cancelled
            #if DEBUG
            print("[Profile] refresh failed (\(cancelled ? "cancelled" : "error")): \(error)")
            #endif
            let message = "Unable to load profile."
            if hasContent || cancelled {
                state.loadState = hasContent ? .loaded : .idle
                sessions[key] = state
            } else {
                state.loadState = .failed(message)
                sessions[key] = state
            }
        }
    }

    func loadPostsIfNeeded(_ identity: ProfileIdentity, handle: String) async {
        let key = sessionKey(identity, handleHint: handle)
        var state = sessions[key] ?? ProfileSessionState()
        guard state.posts.loadState == .idle || state.posts.items.isEmpty else { return }
        await refreshPosts(identity, handle: handle)
    }

    func refreshPosts(_ identity: ProfileIdentity, handle: String) async {
        let key = sessionKey(identity, handleHint: handle)
        var state = sessions[key] ?? ProfileSessionState()
        let hasContent = !state.posts.items.isEmpty
        state.posts.loadState = hasContent ? .refreshing : .loading
        sessions[key] = state
        do {
            let page = try await repository.posts(identity, handle: handle, cursor: nil)
            posts?.upsert(contentsOf: page.items)
            state.posts.items = page.items.map { posts?.resolved($0) ?? $0 }
            state.posts.nextCursor = page.nextCursor
            state.posts.hasMore = page.hasMore
            state.posts.loadState = .loaded
            state.posts.lastError = nil
            state.overviewPreviewPosts = Array(page.items.prefix(3))
            sessions[key] = state
        } catch {
            state.posts.loadState = hasContent ? .loaded : .failed("Unable to load posts.")
            sessions[key] = state
            if hasContent { actionError = "Unable to refresh posts." }
        }
    }

    func loadMorePosts(_ identity: ProfileIdentity, handle: String) async {
        let key = sessionKey(identity, handleHint: handle)
        var state = sessions[key] ?? ProfileSessionState()
        guard state.posts.hasMore, let cursor = state.posts.nextCursor else { return }
        do {
            let page = try await repository.posts(identity, handle: handle, cursor: cursor)
            posts?.upsert(contentsOf: page.items)
            let seen = Set(state.posts.items.map(\.id))
            state.posts.items.append(contentsOf: page.items.filter { !seen.contains($0.id) }.map { posts?.resolved($0) ?? $0 })
            state.posts.nextCursor = page.nextCursor
            state.posts.hasMore = page.hasMore
            sessions[key] = state
        } catch {
            actionError = "Unable to load more posts."
        }
    }

    func loadModulesIfNeeded(
        _ identity: ProfileIdentity,
        handle: String,
        featuredIDs: [String],
        catalogue: [CatalogueProduct]
    ) async {
        let key = sessionKey(identity, handleHint: handle)
        var state = sessions[key] ?? ProfileSessionState()
        guard state.modules.loadState == .idle || state.modules.items.isEmpty else { return }
        state.modules.loadState = .loading
        sessions[key] = state
        let page = await repository.modules(featuredIDs: featuredIDs, catalogue: catalogue)
        state.modules.items = page.items
        state.modules.loadState = .loaded
        sessions[key] = state
    }

    func loadFollowersIfNeeded(_ identity: ProfileIdentity, handle: String) async {
        let key = sessionKey(identity, handleHint: handle)
        var state = sessions[key] ?? ProfileSessionState()
        guard state.followers.loadState == .idle || state.followers.items.isEmpty else { return }
        await refreshPeople(\.followers, identity: identity, handle: handle) { try await repository.followers(handle: handle, cursor: $0) }
    }

    func loadFollowingIfNeeded(_ identity: ProfileIdentity, handle: String) async {
        let key = sessionKey(identity, handleHint: handle)
        var state = sessions[key] ?? ProfileSessionState()
        guard state.following.loadState == .idle || state.following.items.isEmpty else { return }
        await refreshPeople(\.following, identity: identity, handle: handle) { try await repository.following(handle: handle, cursor: $0) }
    }

    func follow(identity: ProfileIdentity, handleHint: String?, signedIn: Bool) async {
        guard signedIn else {
            actionError = "Sign in to follow."
            return
        }
        let key = sessionKey(identity, handleHint: handleHint)
        guard var state = sessions[key], var profile = state.profile, !profile.isFollowing else { return }
        let previous = profile
        profile.isFollowing = true
        profile = profile.withFollowerCount(profile.followerCount + 1)
        state.profile = profile
        sessions[key] = state
        patchPeople(matching: previous.id, handle: previous.handle) { $0.isFollowing = true }
        HapticEngine.shared.play(.lightImpact)
        do {
            let updated = try await repository.follow(profileID: previous.id, handle: previous.handle)
            state.profile = updated
            sessions[key] = state
            patchPeople(matching: updated.id, handle: updated.handle) {
                $0.isFollowing = updated.isFollowing
                $0 = updated
            }
            HapticEngine.shared.play(.followComplete)
        } catch {
            state.profile = previous
            sessions[key] = state
            patchPeople(matching: previous.id, handle: previous.handle) { $0.isFollowing = previous.isFollowing }
            actionError = "Could not follow."
            HapticEngine.shared.play(.failure)
        }
    }

    func unfollow(identity: ProfileIdentity, handleHint: String?) async {
        let key = sessionKey(identity, handleHint: handleHint)
        guard var state = sessions[key], var profile = state.profile, profile.isFollowing else { return }
        let previous = profile
        profile.isFollowing = false
        profile = profile.withFollowerCount(max(0, profile.followerCount - 1))
        state.profile = profile
        sessions[key] = state
        patchPeople(matching: previous.id, handle: previous.handle) { $0.isFollowing = false }
        HapticEngine.shared.play(.lightImpact)
        do {
            let updated = try await repository.unfollow(profileID: previous.id, handle: previous.handle)
            state.profile = updated
            sessions[key] = state
            patchPeople(matching: updated.id, handle: updated.handle) {
                $0.isFollowing = updated.isFollowing
                $0 = updated
            }
            HapticEngine.shared.play(.selection)
        } catch {
            state.profile = previous
            sessions[key] = state
            patchPeople(matching: previous.id, handle: previous.handle) { $0.isFollowing = previous.isFollowing }
            actionError = "Could not unfollow."
            HapticEngine.shared.play(.failure)
        }
    }

    /// Ensures a lightweight session exists so follow/unfollow can run from people lists.
    func seed(_ profile: ModulaProfile) {
        let key = sessionKey(.handle(profile.handle), handleHint: profile.handle)
        if sessions[key]?.profile != nil { return }
        var state = sessions[key] ?? ProfileSessionState()
        state.profile = profile
        if state.loadState == .idle { state.loadState = .loaded }
        sessions[key] = state
    }

    func refreshFollowers(_ identity: ProfileIdentity, handle: String) async {
        await refreshPeople(\.followers, identity: identity, handle: handle) {
            try await repository.followers(handle: handle, cursor: $0)
        }
    }

    func refreshFollowing(_ identity: ProfileIdentity, handle: String) async {
        await refreshPeople(\.following, identity: identity, handle: handle) {
            try await repository.following(handle: handle, cursor: $0)
        }
    }

    func block(identity: ProfileIdentity, handleHint: String?) async {
        let key = sessionKey(identity, handleHint: handleHint)
        guard let profile = sessions[key]?.profile else { return }
        do {
            try await repository.block(profileID: profile.id)
            var state = sessions[key] ?? ProfileSessionState()
            state.loadState = .unavailable
            state.profile = nil
            sessions[key] = state
            HapticEngine.shared.play(.mediumImpact)
        } catch {
            actionError = "Could not block this profile."
            HapticEngine.shared.play(.failure)
        }
    }

    func mute(identity: ProfileIdentity, handleHint: String?) async {
        let key = sessionKey(identity, handleHint: handleHint)
        guard let profile = sessions[key]?.profile else { return }
        do {
            try await repository.mute(profileID: profile.id)
            HapticEngine.shared.play(.mediumImpact)
        } catch {
            actionError = "Could not mute this profile."
            HapticEngine.shared.play(.failure)
        }
    }

    /// Mute by profile id without requiring a loaded profile session
    /// (e.g. "Mute Author" from a post).
    @discardableResult
    func mute(profileID: ProfileID) async -> Bool {
        do {
            try await repository.mute(profileID: profileID)
            HapticEngine.shared.play(.mediumImpact)
            return true
        } catch {
            actionError = "Could not mute this profile."
            HapticEngine.shared.play(.failure)
            return false
        }
    }

    /// Follow by id + handle without a loaded profile session (e.g. from a post's author menu).
    @discardableResult
    func follow(profileID: ProfileID, handle: String) async -> Bool {
        do {
            _ = try await repository.follow(profileID: profileID, handle: handle)
            HapticEngine.shared.play(.followComplete)
            return true
        } catch {
            actionError = "Could not follow."
            HapticEngine.shared.play(.failure)
            return false
        }
    }

    @discardableResult
    func block(profileID: ProfileID) async -> Bool {
        do {
            try await repository.block(profileID: profileID)
            HapticEngine.shared.play(.mediumImpact)
            return true
        } catch {
            actionError = "Could not block this profile."
            HapticEngine.shared.play(.failure)
            return false
        }
    }

    /// Profile report endpoint, used for "Report" on a post (no post-level report endpoint yet).
    @discardableResult
    func report(profileID: ProfileID, category: String, details: String?) async -> Bool {
        do {
            try await repository.report(profileID: profileID, category: category, details: details)
            HapticEngine.shared.play(.confirmation)
            return true
        } catch {
            actionError = "Could not submit report."
            HapticEngine.shared.play(.failure)
            return false
        }
    }

    func report(identity: ProfileIdentity, handleHint: String?, category: String, details: String? = nil) async {
        let key = sessionKey(identity, handleHint: handleHint)
        guard let profile = sessions[key]?.profile else { return }
        do {
            try await repository.report(profileID: profile.id, category: category, details: details)
            HapticEngine.shared.play(.confirmation)
            actionError = "Report submitted."
        } catch {
            actionError = "Could not submit report."
            HapticEngine.shared.play(.failure)
        }
    }

    func beginEditing(from profile: ModulaProfile) {
        // Keep an in-progress edit of the same profile (e.g. returning from the frames sheet).
        if let current = editing.draft, editing.status == .dirty, current.expectedVersion == profile.version {
            return
        }
        var draft = ProfileEditDraft.from(profile)
        var status: ProfileEditingState.Status = .idle
        // Restore an autosaved draft for this profile version (survives relaunch).
        if let data = UserDefaults.standard.data(forKey: Self.draftKey(profile)),
           let saved = try? JSONDecoder().decode(AutosavedDraft.self, from: data),
           saved.version == profile.version {
            draft.displayName = saved.displayName
            draft.bio = saved.bio
            draft.headline = saved.headline
            if draft != .from(profile) { status = .dirty }
        }
        editingKey = Self.draftKey(profile)
        editing = ProfileEditingState(draft: draft, status: status)
    }

    private struct AutosavedDraft: Codable {
        var version: Int?
        var displayName: String
        var bio: String
        var headline: String
    }

    private var editingKey: String?

    private static func draftKey(_ profile: ModulaProfile) -> String {
        "profile.edit.draft.\(profile.id)"
    }

    private func autosaveDraft() {
        guard let key = editingKey, let draft = editing.draft else { return }
        let saved = AutosavedDraft(version: draft.expectedVersion, displayName: draft.displayName, bio: draft.bio, headline: draft.headline)
        if let data = try? JSONEncoder().encode(saved) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func clearAutosavedDraft() {
        if let key = editingKey { UserDefaults.standard.removeObject(forKey: key) }
    }

    func updateEditingDraft(_ transform: (inout ProfileEditDraft) -> Void) {
        guard var draft = editing.draft else { return }
        let previous = draft
        transform(&draft)
        editing.draft = draft
        if draft != previous, editing.status != .saving {
            editing.status = .dirty
            editing.error = nil
            autosaveDraft()
        }
    }

    func discardEditing() {
        clearAutosavedDraft()
        editing = ProfileEditingState()
    }

    func saveEdits() async -> Bool {
        guard var draft = editing.draft else { return false }
        editing.status = .saving
        editing.error = nil
        draft.displayName = draft.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !draft.displayName.isEmpty else {
            editing.status = .failed
            editing.error = "Display name is required."
            return false
        }
        do {
            let profile = try await repository.updateMe(draft)
            editing.status = .saved
            clearAutosavedDraft()
            editing.draft = .from(profile)
            applyOwn(profile)
            HapticEngine.shared.play(.saveComplete)
            return true
        } catch let api as APIError {
            editing.status = .failed
            editing.error = api.userFacingMessage
            HapticEngine.shared.play(.failure)
            return false
        } catch {
            editing.status = .failed
            editing.error = "Could not save profile."
            HapticEngine.shared.play(.failure)
            return false
        }
    }

    /// First-run display-name persistence. Uses the same `updateMe` contract as
    /// the profile editor so version tokens and caches stay consistent.
    /// Returns a user-facing error message, or `nil` on success.
    func saveDisplayName(_ name: String, accountHandle: String?) async -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Display name is required." }
        do {
            let base: ModulaProfile
            if let own = ownProfile {
                base = own
            } else {
                base = try await repository.profile(.me, handleHint: accountHandle)
            }
            guard base.displayName != trimmed else {
                applyOwn(base)
                return nil
            }
            var draft = ProfileEditDraft.from(base)
            draft.displayName = trimmed
            let profile = try await repository.updateMe(draft)
            applyOwn(profile)
            return nil
        } catch let api as APIError {
            return api.userFacingMessage
        } catch {
            return "Could not save your display name."
        }
    }

    func rememberScroll(identity: ProfileIdentity, handleHint: String?, section: ProfileSection, offset: CGFloat) {
        let key = sessionKey(identity, handleHint: handleHint)
        var state = sessions[key] ?? ProfileSessionState()
        if let previous = state.scrollOffsets[section], abs(previous - offset) < 1 { return }
        state.scrollOffsets[section] = offset
        sessions[key] = state
    }

    func clearActionError() { actionError = nil }

    func setVisitorPreview(_ active: Bool) {
        visitorPreviewActive = active
    }

    func setMediaError(_ message: String?) {
        actionError = message
        if message != nil {
            HapticEngine.shared.play(.failure)
        }
    }

    func uploadMedia(_ kind: ProfileMediaKind, image: PreparedImage) async -> Bool {
        mediaBusy = true
        defer { mediaBusy = false }
        do {
            let profile = try await repository.uploadOwnMedia(kind: kind, image: image)
            applyOwn(profile)
            actionError = nil
            HapticEngine.shared.play(.saveComplete)
            return true
        } catch let api as APIError {
            actionError = api.userFacingMessage
            HapticEngine.shared.play(.failure)
            return false
        } catch {
            actionError = "Could not update \(kind.title.lowercased())."
            HapticEngine.shared.play(.failure)
            return false
        }
    }

    func removeMedia(_ kind: ProfileMediaKind) async -> Bool {
        mediaBusy = true
        defer { mediaBusy = false }
        do {
            let profile = try await repository.removeOwnMedia(kind: kind)
            applyOwn(profile)
            actionError = nil
            HapticEngine.shared.play(.saveComplete)
            return true
        } catch let api as APIError {
            actionError = api.userFacingMessage
            HapticEngine.shared.play(.failure)
            return false
        } catch {
            actionError = "Could not remove \(kind.title.lowercased())."
            HapticEngine.shared.play(.failure)
            return false
        }
    }

    private func applyOwn(_ profile: ModulaProfile) {
        // Media mutations increment the same profile version as text edits.
        // Keep unsaved fields, but rebase their optimistic concurrency token.
        editing.draft?.expectedVersion = profile.version
        let key = sessionKey(.me, handleHint: profile.handle)
        var state = sessions[key] ?? ProfileSessionState()
        state.profile = profile
        state.loadState = .loaded
        sessions[key] = state
        sessions["me"] = state
    }

    // MARK: - Private

    private func refreshPeople(
        _ keyPath: WritableKeyPath<ProfileSessionState, ProfileCollectionState<ModulaProfile>>,
        identity: ProfileIdentity,
        handle: String,
        fetch: (String?) async throws -> ProfilePeoplePage
    ) async {
        let key = sessionKey(identity, handleHint: handle)
        var state = sessions[key] ?? ProfileSessionState()
        var collection = state[keyPath: keyPath]
        let hasContent = !collection.items.isEmpty
        collection.loadState = hasContent ? .refreshing : .loading
        state[keyPath: keyPath] = collection
        sessions[key] = state
        do {
            let page = try await fetch(nil)
            collection.items = page.items
            collection.nextCursor = page.nextCursor
            collection.hasMore = page.hasMore
            collection.loadState = .loaded
            state[keyPath: keyPath] = collection
            sessions[key] = state
        } catch {
            collection.loadState = hasContent ? .loaded : .failed("Unable to load people.")
            state[keyPath: keyPath] = collection
            sessions[key] = state
        }
    }

    private func sessionKey(_ identity: ProfileIdentity, handleHint: String?) -> String {
        switch identity {
        case .me: "me"
        case .handle(let handle): handle.lowercased()
        case .id(let id): (handleHint ?? id).lowercased()
        }
    }

    private func cacheLookupKey(_ identity: ProfileIdentity, handleHint: String?) -> String {
        switch identity {
        case .me: handleHint.map { "me:\($0)" } ?? "me"
        case .handle(let handle): handle
        case .id(let id): handleHint ?? id
        }
    }

    private func patchPeople(matching id: ProfileID, handle: String, mutate: (inout ModulaProfile) -> Void) {
        for key in sessions.keys {
            var state = sessions[key]!
            var changed = false
            func patch(_ collection: inout ProfileCollectionState<ModulaProfile>) {
                guard let index = collection.items.firstIndex(where: { $0.id == id || $0.handle.caseInsensitiveCompare(handle) == .orderedSame }) else { return }
                mutate(&collection.items[index])
                changed = true
            }
            patch(&state.followers)
            patch(&state.following)
            if changed { sessions[key] = state }
        }
    }

    func ingestPublished(_ post: SocialPost) {
        posts?.upsert(post)
        for (key, var state) in sessions {
            let matchesAuthor = state.profile?.id == post.author?.id
                || state.profile?.handle.lowercased() == post.author?.handle.lowercased()
            guard key == "me" || matchesAuthor else { continue }
            if !state.posts.items.contains(where: { $0.id == post.id }) {
                state.posts.items.insert(post, at: 0)
            }
            if !state.overviewPreviewPosts.contains(where: { $0.id == post.id }) {
                state.overviewPreviewPosts.insert(post, at: 0)
                if state.overviewPreviewPosts.count > 3 {
                    state.overviewPreviewPosts = Array(state.overviewPreviewPosts.prefix(3))
                }
            }
            sessions[key] = state
        }
    }
}

struct ProfileEditingState: Equatable {
    var draft: ProfileEditDraft?
    var status: Status = .idle
    var error: String?

    enum Status: Equatable {
        case idle, dirty, saving, saved, failed
    }

    var isDirty: Bool {
        status == .dirty || status == .failed
    }
}

private extension ModulaProfile {
    func withFollowerCount(_ count: Int) -> ModulaProfile {
        ModulaProfile(
            id: id,
            handle: handle,
            displayName: displayName,
            kind: kind,
            avatarURL: avatarURL,
            coverURL: coverURL,
            coverColour: coverColour,
            bio: bio,
            headline: headline,
            pronouns: pronouns,
            location: location,
            website: website,
            languages: languages,
            presentation: presentation,
            coverFocalPoint: coverFocalPoint,
            followerCount: count,
            followingCount: followingCount,
            moduleCount: moduleCount,
            postCount: postCount,
            joinedAt: joinedAt,
            focusStatus: focusStatus,
            identityClaims: identityClaims,
            links: links,
            featuredModuleIds: featuredModuleIds,
            isFollowing: isFollowing,
            followsViewer: followsViewer,
            version: version,
            visibility: visibility
        )
    }
}
