import SwiftUI

struct CommunityRootView: View {
    let route: CommunityRoute

    var body: some View {
        Group {
            switch route {
            case .modulaBuilders: CommunityBuildersView()
            case .settings: CommunitySettingsView()
            case .poll: CommunityPollView()
            case .event: CommunityEventView()
            default: CommunityHubView(route: route)
            }
        }
        .modulaCanvas()
        .navigationTitle(route.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier(accessibilityID)
    }

    private var accessibilityID: String {
        switch route {
        case .modulaBuilders: "community.builders"
        case .settings: "community.settings"
        case .poll: "community.poll"
        case .event: "community.event"
        default: "community.hub"
        }
    }
}

struct CommunityHubView: View {
    let route: CommunityRoute
    @Environment(AppEnvironment.self) private var app
    @State private var query = ""

    private var scope: CommunityHubScope { route.hubScope ?? .forYou }
    private var accent: Color { app.appearance.liveAccent }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                search
                scopes
                scopeBody
            }
            .padding(.horizontal, ModulaLayout.contentInset)
            .padding(.bottom, 28)
        }
        .modulaSoftScrollEdge()
        .refreshable { await load(reset: true) }
        .task(id: scope) { await load(reset: true) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            ModulaWordmark(height: 22)
            Text(CommunityCopy.title)
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            Text(CommunityCopy.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    private var search: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(CommunityCopy.searchPrompt, text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { Task { await load(reset: true) } }
            if !query.isEmpty {
                Button {
                    query = ""
                    Task { await load(reset: true) }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear community search")
            }
        }
        .padding(.leading, 14)
        .modulaGlass(in: Capsule(), interactive: true, specular: true)
    }

    private var scopes: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            ModulaGlassGroup(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(CommunityHubScope.allCases) { item in
                        let selected = item == scope
                        Button {
                            guard item != scope else { return }
                            HapticEngine.shared.play(.selection)
                            app.navigation.replaceTop(with: .community(item.route))
                        } label: {
                            Label(item.title, systemImage: item.symbol)
                                .font(.subheadline.weight(.semibold))
                                .labelStyle(.titleAndIcon)
                                .padding(.horizontal, 12)
                                .frame(minHeight: 44)
                                .foregroundStyle(selected ? Color.white : Color.primary)
                        }
                        .buttonStyle(.plain)
                        .modulaGlass(in: Capsule(), interactive: true, tint: selected ? accent : nil, prominent: selected, specular: true)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                        .accessibilityIdentifier("community.scope.\(item.rawValue)")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var scopeBody: some View {
        if app.communities.directoryState.isLoading && app.communities.communities.isEmpty {
            ProgressView("Loading communities…")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 36)
        } else if app.communities.directoryState == .empty {
            ModulaEmptyState(
                title: "No communities found",
                message: query.isEmpty ? "There aren’t any communities in this view yet." : "Try another community name.",
                symbol: "person.3"
            )
        } else {
            if let message = app.communities.directoryState.message {
                CommunityStateBanner(message: message, symbol: stateSymbol(app.communities.directoryState))
            }
            if scope == .forYou, query.isEmpty {
                CommunityScenicCard(
                    scene: "SceneMeadow",
                    eyebrow: "COMMUNITIES",
                    title: "Build together",
                    message: "Find groups around the people and work that matter to you.",
                    accent: accent,
                    cta: "Explore"
                ) {
                    app.navigation.replaceTop(with: .community(.communities))
                }
            }
            if scope == .topics {
                categoryRail
            }
            LazyVStack(spacing: 12) {
                ForEach(visibleCommunities) { community in
                    CommunityDirectoryCard(community: community) { open(community) }
                        .task {
                            if community.id == visibleCommunities.last?.id, app.communities.directoryNextCursor != nil {
                                await load(reset: false)
                            }
                        }
                }
                if app.communities.directoryState.isLoading && !app.communities.communities.isEmpty {
                    ProgressView().padding()
                }
            }
        }
    }

    private var visibleCommunities: [CommunitySummary] {
        switch scope {
        case .forYou:
            let featured = app.communities.communities.filter(\.featured)
            return featured.isEmpty ? app.communities.communities : featured
        default:
            return app.communities.communities
        }
    }

    private var categoryRail: some View {
        let categories = Array(Set(app.communities.communities.map(\.category))).sorted()
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories, id: \.self) { category in
                    Text(category)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .frame(minHeight: 40)
                        .modulaGlass(in: Capsule(), interactive: false, specular: true)
                }
            }
        }
    }

    private func load(reset: Bool) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let scopeQuery: String? = {
            if !trimmed.isEmpty { return trimmed }
            if scope == .builders { return "builders" }
            return nil
        }()
        await app.communities.loadDirectory(
            query: scopeQuery,
            membership: scope == .following ? "joined" : nil,
            reset: reset
        )
    }

    private func open(_ community: CommunitySummary) {
        app.communities.select(community)
        app.navigation.push(.community(.modulaBuilders))
        HapticEngine.shared.play(.navigation)
    }

    private func stateSymbol(_ state: CommunityLoadState) -> String {
        switch state {
        case .offline(_): "wifi.slash"
        case .unauthorized(_): "person.crop.circle.badge.exclamationmark"
        default: "exclamationmark.triangle"
        }
    }
}

private struct CommunityDirectoryCard: View {
    let community: CommunitySummary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            CommunityPanel {
                HStack(spacing: 12) {
                    CommunityMark()
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(community.name).font(.headline)
                            if community.featured { Image(systemName: "star.fill").font(.caption) }
                        }
                        Text(community.description.isEmpty ? community.category : community.description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        HStack(spacing: 8) {
                            Label("\(community.memberCount)", systemImage: "person.2")
                            Text(community.membership == .active ? "Joined" : community.visibility.rawValue.capitalized)
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("community.open.\(community.id)")
    }
}

struct CommunityBuildersView: View {
    @Environment(AppEnvironment.self) private var app
    @State private var tab: CommunityBuildersTab = .feed
    @State private var postText = ""
    @State private var postIdempotencyKey = "community-post-\(UUID().uuidString.lowercased())"

    private var accent: Color { app.appearance.liveAccent }
    private var community: CommunityDetails? { app.communities.selectedCommunity }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if app.communities.contentState.isLoading && community == nil {
                    ProgressView("Loading community…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 48)
                } else if let community {
                    hero(community)
                    identity(community)
                    facts(community)
                    if let message = app.communities.contentState.message {
                        CommunityStateBanner(message: message, symbol: "wifi.slash")
                    }
                    if let message = app.communities.actionError {
                        CommunityStateBanner(message: message, symbol: "exclamationmark.triangle")
                    }
                    tabs
                    tabBody(community)
                    membershipButton(community)
                } else {
                    ModulaEmptyState(
                        title: "Community unavailable",
                        message: app.communities.contentState.message ?? "This community could not be found.",
                        symbol: "person.3"
                    )
                }
            }
            .padding(.horizontal, ModulaLayout.contentInset)
            .padding(.bottom, 28)
        }
        .modulaSoftScrollEdge()
        .refreshable { await app.communities.refreshSelected(signedIn: app.auth.isSignedIn) }
        .task { await app.communities.loadBuildersIfNeeded(signedIn: app.auth.isSignedIn) }
        .toolbar { buildersToolbar }
    }

    private func hero(_ community: CommunityDetails) -> some View {
        ZStack(alignment: .bottomLeading) {
            Image("SceneStudio")
                .resizable().scaledToFill()
                .frame(height: 190).frame(maxWidth: .infinity).clipped()
                .accessibilityHidden(true)
            LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 6) {
                Text(community.summary.category.uppercased())
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 10).frame(height: 24)
                    .modulaGlass(in: Capsule(), interactive: false)
                Text(community.summary.description.isEmpty ? community.summary.name : community.summary.description)
                    .font(.title3.bold())
                    .lineLimit(3)
            }
            .foregroundStyle(.white)
            .padding(18)
        }
        .frame(height: 190)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(.white.opacity(0.25), lineWidth: 0.8))
        .shadow(color: .black.opacity(0.15), radius: 14, y: 6)
        .accessibilityElement(children: .combine)
    }

    private func identity(_ community: CommunityDetails) -> some View {
        HStack(spacing: 12) {
            CommunityMark()
            VStack(alignment: .leading, spacing: 4) {
                Text(community.summary.name).font(.title3.bold())
                Text(community.summary.membership == .active ? roleLabel(community.summary.viewerRole) : "@\(community.summary.slug)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private func facts(_ community: CommunityDetails) -> some View {
        VStack(spacing: 0) {
            CommunityInfoRow(
                symbol: community.summary.visibility == .private ? "lock.fill" : "globe",
                tint: accent,
                title: community.summary.visibility == .private ? "Private community" : "Public community",
                subtitle: community.membershipPolicy == .approval ? "Membership requires approval" : "Open membership"
            )
            Divider().padding(.leading, 64)
            CommunityInfoRow(symbol: "person.3", tint: accent, title: "\(community.summary.memberCount) members", subtitle: memberSubtitle(community.summary.membership))
            Divider().padding(.leading, 64)
            CommunityInfoRow(symbol: "calendar", tint: accent, title: "\(app.communities.events.count) events", subtitle: "Server-persisted community schedule")
        }
        .modulaGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous), interactive: false, specular: true)
    }

    private var tabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            ModulaGlassGroup(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(CommunityBuildersTab.allCases) { item in
                        let selected = item == tab
                        Button {
                            tab = item
                            HapticEngine.shared.play(.selection)
                        } label: {
                            Label(item.title, systemImage: item.symbol)
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 12)
                                .frame(minHeight: 44)
                                .foregroundStyle(selected ? Color.white : Color.primary)
                        }
                        .buttonStyle(.plain)
                        .modulaGlass(in: Capsule(), interactive: true, tint: selected ? accent : nil, prominent: selected, specular: true)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                        .accessibilityIdentifier("community.builders.tab.\(item.rawValue)")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func tabBody(_ community: CommunityDetails) -> some View {
        switch tab {
        case .feed:
            if app.communities.capabilities.canPost {
                postComposer
            }
            if app.communities.posts.isEmpty {
                CommunityPanel { Text(CommunityCopy.postsEmpty).font(.subheadline).foregroundStyle(.secondary) }
            } else {
                ForEach(app.communities.posts) { item in
                    SharedFeedPostCard(post: item.post, identifierPrefix: "community")
                    Divider()
                    if item.id == app.communities.posts.last?.id, app.communities.postsNextCursor != nil {
                        ProgressView().task { await app.communities.loadMorePosts() }
                    }
                }
            }
        case .projects:
            CommunityPanel {
                Text("No projects have been published in this community.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        case .events:
            if app.communities.events.isEmpty {
                CommunityPanel { Text(CommunityCopy.eventsEmpty).font(.subheadline).foregroundStyle(.secondary) }
            } else {
                ForEach(app.communities.events) { event in
                    CommunityEventCard(event: event) {
                        app.navigation.push(.community(.event))
                    }
                    if event.id == app.communities.events.last?.id, app.communities.eventsNextCursor != nil {
                        ProgressView().task { await app.communities.loadMoreEvents() }
                    }
                }
            }
        case .members:
            if app.communities.members.isEmpty {
                CommunityPanel { Text(CommunityCopy.membersEmpty).font(.subheadline).foregroundStyle(.secondary) }
            } else {
                ForEach(app.communities.members) { member in
                    CommunityMemberRow(member: member) {
                        app.navigation.push(.profile(member.profile.routeID, .overview))
                    }
                    if member.id == app.communities.members.last?.id, app.communities.membersNextCursor != nil {
                        ProgressView().task { await app.communities.loadMoreMembers() }
                    }
                }
            }
        case .about:
            CommunityPanel {
                VStack(alignment: .leading, spacing: 8) {
                    Text(community.summary.name).font(.headline)
                    Text(community.summary.description.isEmpty ? "No description has been added." : community.summary.description)
                        .font(.subheadline).foregroundStyle(.secondary)
                    Label(community.postingPolicy == .members ? "Members can post" : "Moderators can post", systemImage: "text.bubble")
                        .font(.caption.weight(.semibold))
                }
            }
        }
    }

    private var postComposer: some View {
        CommunityPanel {
            VStack(alignment: .leading, spacing: 10) {
                Text("Create a post").font(.headline)
                TextField("Share with the community", text: $postText, axis: .vertical)
                    .lineLimit(2...6)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("community.post.text")
                Button {
                    Task {
                        if await app.communities.createPost(text: postText, idempotencyKey: postIdempotencyKey) {
                            postText = ""
                            postIdempotencyKey = "community-post-\(UUID().uuidString.lowercased())"
                            HapticEngine.shared.play(.success)
                        } else {
                            HapticEngine.shared.play(.failure)
                        }
                    }
                } label: {
                    Group {
                        if app.communities.actionInProgress { ProgressView() } else { Text("Post") }
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity).frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .modulaAccentCTA()
                .disabled(postText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || app.communities.actionInProgress)
                .accessibilityIdentifier("community.post.send")
            }
        }
    }

    private func membershipButton(_ community: CommunityDetails) -> some View {
        Button {
            Task {
                if community.summary.membership == .active {
                    await app.communities.leave()
                } else {
                    await app.communities.join(signedIn: app.auth.isSignedIn)
                }
                HapticEngine.shared.play(app.communities.actionError == nil ? .success : .failure)
            }
        } label: {
            Group {
                if app.communities.actionInProgress { ProgressView() }
                else { Text(membershipTitle(community.summary.membership)) }
            }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity).frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .modulaAccentCTA()
        .disabled(app.communities.actionInProgress || community.summary.membership == .pending || community.summary.viewerRole == .owner)
        .accessibilityIdentifier("community.builders.membership")
    }

    @ToolbarContentBuilder
    private var buildersToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 12) {
                Button { app.navigation.push(.community(.poll)) } label: { Image(systemName: "chart.bar") }
                    .accessibilityLabel("Community polls")
                if app.auth.isSignedIn {
                    Button { app.navigation.push(.community(.settings)) } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Community Settings")
                }
            }
        }
    }

    private func membershipTitle(_ membership: CommunityMembership) -> String {
        switch membership {
        case .active: "Leave community"
        case .pending: "Request pending"
        case .banned: "Unavailable"
        case .none: "Join community"
        }
    }

    private func memberSubtitle(_ membership: CommunityMembership) -> String {
        switch membership {
        case .active: "You are a member"
        case .pending: "Your request is pending"
        case .banned: "Membership unavailable"
        case .none: "Join to post, vote and RSVP"
        }
    }

    private func roleLabel(_ role: CommunityRole?) -> String {
        guard let role else { return "Member" }
        return role.rawValue.capitalized
    }
}

private struct CommunityMemberRow: View {
    let member: CommunityMember
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            CommunityPanel {
                HStack(spacing: 12) {
                    ModulaAvatar(initials: member.profile.initials, url: member.profile.avatarURL, size: 44, name: member.profile.displayName)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(member.profile.displayName).font(.headline)
                        Text("@\(member.profile.handle) · \(member.role.rawValue.capitalized)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct CommunityEventCard: View {
    let event: CommunityEvent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            CommunityPanel {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "calendar")
                        .font(.title2)
                        .frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(event.title).font(.headline)
                        Text(event.startsAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.subheadline).foregroundStyle(.secondary)
                        Text("\(event.goingCount) going · \(event.interestedCount) interested")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct CommunityStateBanner: View {
    let message: String
    let symbol: String

    var body: some View {
        CommunityPanel {
            Label(message, systemImage: symbol)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("community.state.message")
    }
}

struct CommunityMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.primary.opacity(0.9))
            ModulaUnitMark(style: .solid(.white)).padding(10)
        }
        .frame(width: 56, height: 56)
        .accessibilityHidden(true)
    }
}

struct CommunityPanel<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modulaGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous), interactive: false, specular: true)
    }
}

#if DEBUG
struct CommunityDeveloperEntry: View {
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        Button("Open Community") {
            app.navigation.open(.community(.hub))
        }
        .accessibilityIdentifier("developer.community.open")
    }
}
#endif

struct CommunityScenicCard: View {
    let scene: String
    let eyebrow: String
    let title: String
    let message: String
    let accent: Color
    var cta: String = "Find people"
    var action: () -> Void

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Image(scene).resizable().scaledToFill().accessibilityHidden(true)
            LinearGradient(colors: [.black.opacity(0.05), .black.opacity(0.65)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 8) {
                Text(eyebrow)
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 10).frame(height: 24)
                    .modulaGlass(in: Capsule(), interactive: false)
                Text(title).font(.system(size: 28, weight: .bold, design: .rounded))
                Text(message).font(.subheadline).foregroundStyle(.white.opacity(0.88)).fixedSize(horizontal: false, vertical: true)
                Button {
                    action()
                    HapticEngine.shared.play(.navigation)
                } label: {
                    HStack(spacing: 6) { Text(cta); Image(systemName: "arrow.right") }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16).frame(height: 44)
                        .modulaAccentCTA()
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .foregroundStyle(.white)
            .padding(18)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(.white.opacity(0.25), lineWidth: 0.8))
        .shadow(color: accent.opacity(0.2), radius: 16, y: 8)
    }
}
