import SwiftUI

struct PostDetailView: View {
    let postID: String
    var section: PostSection = .root
    @Environment(AppEnvironment.self) private var app
    @State private var post: SocialPost?
    @State private var loadError: String?
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if isLoading && post == nil {
                    skeleton
                } else if let loadError, post == nil {
                    ModulaErrorState(message: loadError) {
                        Task { await load() }
                    }
                    .padding(.top, 40)
                } else if let post {
                    PostCard(
                        post: post,
                        onOpenPost: {},
                        onOpenAuthor: {
                            if let author = post.author {
                                app.navigation.push(.profile(author.routeID, .overview))
                                HapticEngine.shared.play(.navigation)
                            }
                        },
                        onLike: {
                            Task { await toggleLike() }
                        },
                        onComment: {
                            app.navigation.open(.post(postID, .comments))
                        },
                        onRepost: {
                            Task { await toggleRepost() }
                        },
                        onSave: {
                            Task { await toggleSave() }
                        }
                    )
                    commentsPlaceholder
                }
            }
            .padding(.horizontal, ModulaLayout.contentInset)
            .padding(.bottom, 40)
        }
        .modulaCanvas()
        .navigationTitle(section == .comments ? "Comments" : "Post")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: postID) { await load() }
        .accessibilityIdentifier("native.post")
        .accessibilityValue(RouteSerializer.serialize(.post(postID, section)))
    }

    private var commentsPlaceholder: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Comments")
                .font(.headline)
            Text("Comment threads open here when routed. Create and list use Greenfield `/v1/comments`.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
        .accessibilityIdentifier("post.comments.placeholder")
    }

    private var skeleton: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Circle().fill(Color.primary.opacity(0.08)).frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 6) {
                    Capsule().fill(Color.primary.opacity(0.08)).frame(width: 120, height: 12)
                    Capsule().fill(Color.primary.opacity(0.06)).frame(width: 80, height: 10)
                }
            }
            RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)).frame(height: 72)
        }
        .redacted(reason: .placeholder)
        .padding(.top, 12)
    }

    private func load() async {
        isLoading = true
        loadError = nil
        do {
            let repository = GreenfieldHomeRepository(client: app.client)
            post = try await repository.post(id: postID)
            isLoading = false
        } catch let api as APIError {
            loadError = api.userFacingMessage
            isLoading = false
        } catch {
            loadError = "Unable to load this post."
            isLoading = false
        }
    }

    private func toggleLike() async {
        guard var current = post else { return }
        let next = !current.liked
        current.liked = next
        current.likeCount = max(0, current.likeCount + (next ? 1 : -1))
        post = current
        let repository = GreenfieldHomeRepository(client: app.client)
        do {
            if next { try await repository.like(postID: postID) }
            else { try await repository.unlike(postID: postID) }
            HapticEngine.shared.play(.selection)
        } catch {
            await load()
            HapticEngine.shared.play(.failure)
        }
    }

    private func toggleSave() async {
        guard var current = post else { return }
        let next = !current.saved
        current.saved = next
        post = current
        let repository = GreenfieldHomeRepository(client: app.client)
        do {
            if next { try await repository.save(postID: postID) }
            else { try await repository.unsave(postID: postID) }
            HapticEngine.shared.play(.selection)
        } catch {
            await load()
            HapticEngine.shared.play(.failure)
        }
    }

    private func toggleRepost() async {
        guard var current = post else { return }
        let next = !current.reposted
        current.reposted = next
        current.repostCount = max(0, current.repostCount + (next ? 1 : -1))
        post = current
        let repository = GreenfieldHomeRepository(client: app.client)
        do {
            if next { try await repository.repost(postID: postID) }
            else { try await repository.unrepost(postID: postID) }
            HapticEngine.shared.play(.confirmation)
        } catch {
            await load()
            HapticEngine.shared.play(.failure)
        }
    }
}
