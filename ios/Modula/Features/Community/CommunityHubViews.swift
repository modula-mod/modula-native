import SwiftUI
import UIKit

struct CommunityRootView: View {
    let route: CommunityRoute

    var body: some View {
        Group {
            if CommunityAPIFeatureFlags.isEnabled {
                liveBody
            } else if CommunityFeatureFlags.isEnabled {
                localBody
            } else {
                CommunityUnavailableView()
            }
        }
        .modulaCanvas()
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier(accessibilityID)
    }

    private var navigationTitle: String {
        (CommunityAPIFeatureFlags.isEnabled || CommunityFeatureFlags.isEnabled) ? route.navigationTitle : CommunityCopy.title
    }

    @ViewBuilder private var liveBody: some View {
        switch route {
        case .modulaBuilders: CommunityBuildersView()
        case .settings: CommunitySettingsView()
        case .poll: CommunityPollView()
        case .event: CommunityEventView()
        default: CommunityHubView(route: route)
        }
    }

    @ViewBuilder private var localBody: some View {
        switch route {
        case .modulaBuilders: CommunityLocalBuildersView()
        case .settings: CommunityLocalSettingsView()
        case .poll: CommunityLocalPollView()
        case .event: CommunityLocalEventView()
        default: CommunityLocalHubView(route: route)
        }
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
    @State private var topic: String?
    @AppStorage("community.directory.sort") private var sortRaw = CommunityDirectorySort.relevant.rawValue

    private var scope: CommunityHubScope { route.hubScope ?? .forYou }
    private var sort: CommunityDirectorySort { CommunityDirectorySort(rawValue: sortRaw) ?? .relevant }
    private var accent: Color { app.appearance.liveAccent }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header.modulaAppear()
                search.modulaAppear(delay: 0.05)
                scopes.modulaAppear(delay: 0.1)
                scopeBody.modulaAppear(delay: 0.15)
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
        ModulaSegmentedControl("Community", selection: Binding(get: { scope }, set: { app.navigation.replaceTop(with: .community($0.route)) }),
                               options: CommunityHubScope.allCases, symbol: { $0.symbol },
                               identifier: { "community.scope.\($0.rawValue)" }) { $0.title }
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
            directoryHeader
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
        var list: [CommunitySummary]
        switch scope {
        case .forYou:
            let featured = app.communities.communities.filter(\.featured)
            list = featured.isEmpty ? app.communities.communities : featured
        default:
            list = app.communities.communities
        }
        if scope == .topics, let topic { list = list.filter { $0.category == topic } }
        // Client-side order over the loaded page (the directory endpoint has no sort parameter).
        switch sort {
        case .relevant: break
        case .members: list.sort { $0.memberCount > $1.memberCount }
        case .active: list.sort { ($0.recentActivityAt ?? .distantPast) > ($1.recentActivityAt ?? .distantPast) }
        case .name: list.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        return list
    }

    private var directoryHeader: some View {
        let count = visibleCommunities.count
        return HStack(spacing: 8) {
            Text("\(count) \(count == 1 ? "community" : "communities")")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
            Spacer(minLength: 8)
            Menu {
                Picker("Sort", selection: Binding(get: { sort }, set: { v in withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { sortRaw = v.rawValue } })) {
                    ForEach(CommunityDirectorySort.allCases) { option in
                        Label(option.title, systemImage: option.symbol).tag(option)
                    }
                }
            } label: {
                Label(sort.title, systemImage: "arrow.up.arrow.down")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 36)
                    .modulaGlass(in: Capsule(), interactive: true)
            }
            .accessibilityLabel("Sort communities, \(sort.title)")
            .accessibilityIdentifier("community.sort")
        }
        .animation(.snappy, value: count)
    }

    private var categoryRail: some View {
        let categories = Array(Set(app.communities.communities.map(\.category))).sorted()
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories, id: \.self) { category in
                    let on = topic == category
                    Button {
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) { topic = on ? nil : category }
                        HapticEngine.shared.play(.selection)
                    } label: {
                        HStack(spacing: 5) {
                            if on { Image(systemName: "checkmark").font(.caption.weight(.bold)).transition(.scale.combined(with: .opacity)) }
                            Text(category).font(.subheadline.weight(.semibold)).fixedSize()
                        }
                        .foregroundStyle(on ? Color.modulaOnPrimary : .primary)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 40)
                        .background { if on { Capsule().fill(Color.modulaPrimaryFill) } }
                        .contentShape(Capsule())
                    }
                    .buttonStyle(ModulaPressStyle(scale: 0.95, haptic: nil))
                    .modulaGlass(in: Capsule(), interactive: true, specular: true)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
        .modulaHorizontalRail()
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
    @State private var confirmLeave = false
    @State private var showRules = false
    @State private var memberQuery = ""
    @State private var memberFilter: CommunityMemberFilter = .all

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
            CommunityInfoRow(symbol: "person.3", tint: accent, title: community.summary.memberCount == 1 ? "1 member" : "\(community.summary.memberCount) members", subtitle: memberSubtitle(community.summary.membership))
            Divider().padding(.leading, 64)
            CommunityInfoRow(symbol: "calendar", tint: accent, title: app.communities.events.count == 1 ? "1 event" : "\(app.communities.events.count) events", subtitle: "Server-persisted community schedule")
            Divider().padding(.leading, 64)
            Button { showRules = true } label: {
                HStack(spacing: 0) {
                    CommunityInfoRow(symbol: "list.bullet.clipboard", tint: accent, title: "Rules & guidelines",
                                     subtitle: community.postingPolicy == .moderators ? "Moderators post · tap to read" : "Members post · tap to read")
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary).padding(.trailing, 14)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("community.rules.open")
        }
        .modulaGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous), interactive: false, specular: true)
        .sheet(isPresented: $showRules) {
            CommunityRulesSheet(community: community, attachmentsAllowed: app.communities.settings?.allowAttachments)
                .presentationDetents([.medium, .large])
                .modulaSheetStyle()
        }
    }

    private var tabs: some View {
        ModulaSegmentedControl("Builders", selection: $tab, options: CommunityBuildersTab.allCases, symbol: { $0.symbol },
                               identifier: { "community.builders.tab.\($0.rawValue)" }) { $0.title }
    }

    @ViewBuilder
    private func tabBody(_ community: CommunityDetails) -> some View {
        switch tab {
        case .feed:
            if app.communities.capabilities.canPost {
                postComposer
            }
            if app.communities.posts.isEmpty {
                ModulaEmptyState(title: CommunityCopy.postsEmpty, message: "Posts from members show up here.", symbol: "text.bubble")
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
                ModulaEmptyState(title: CommunityCopy.eventsEmpty, message: "Upcoming events will be listed here.", symbol: "calendar")
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
                ModulaEmptyState(title: CommunityCopy.membersEmpty, message: "Members appear here once they join.", symbol: "person.2")
            } else {
                let shown = CommunityMemberFilter.apply(app.communities.members, filter: memberFilter, query: memberQuery)
                ModulaSearchField(text: $memberQuery, prompt: "Search members")
                    .accessibilityIdentifier("community.members.search")
                HStack(spacing: 8) {
                    ForEach(CommunityMemberFilter.allCases) { f in
                        ModulaChip(title: f.title(count: CommunityMemberFilter.apply(app.communities.members, filter: f, query: "").count),
                                   selected: memberFilter == f) {
                            withAnimation(.snappy(duration: 0.22)) { memberFilter = f }
                        }
                    }
                    Spacer(minLength: 0)
                }
                if shown.isEmpty {
                    Text(memberQuery.isEmpty ? "No one in this group yet." : "No loaded members match “\(memberQuery)”.")
                        .font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 20)
                }
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, member in
                    CommunityMemberRow(member: member) {
                        app.navigation.push(.profile(member.profile.routeID, .overview))
                    }
                    .modulaAppear(delay: Double(min(index, 8)) * 0.035)
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
                .foregroundStyle(Color.modulaOnPrimary)
                .modulaPrimaryCTA()
                .disabled(postText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || app.communities.actionInProgress)
                .accessibilityIdentifier("community.post.send")
            }
        }
    }

    private func membershipButton(_ community: CommunityDetails) -> some View {
        let isMember = community.summary.membership == .active
        return Group {
            if isMember {
                // Leaving is a secondary action and asks first (members lose posting/voting).
                Button { confirmLeave = true } label: {
                    Group {
                        if app.communities.actionInProgress { ProgressView() }
                        else { Label("Joined", systemImage: "checkmark") }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.modulaSecondaryWide)
                .accessibilityHint("Double-tap to leave this community")
            } else {
                Button {
                    Task {
                        await app.communities.join(signedIn: app.auth.isSignedIn)
                        HapticEngine.shared.play(app.communities.actionError == nil ? .success : .failure)
                    }
                } label: {
                    Group {
                        if app.communities.actionInProgress { ProgressView().tint(Color.modulaOnPrimary) }
                        else { Text(membershipTitle(community.summary.membership)) }
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity).frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.modulaOnPrimary)
                .modulaPrimaryCTA()
            }
        }
        .animation(.snappy, value: isMember)
        .confirmationDialog("Leave \(community.summary.name)?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Leave community", role: .destructive) {
                Task {
                    await app.communities.leave()
                    HapticEngine.shared.play(app.communities.actionError == nil ? .success : .failure)
                }
            }
        } message: {
            Text("You can join again any time.")
        }
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
                        HStack(spacing: 6) {
                            Text(member.profile.displayName).font(.headline)
                            if member.role == .owner || member.role == .admin || member.role == .moderator {
                                Label(member.role.rawValue.capitalized, systemImage: member.role == .owner ? "crown.fill" : "shield.lefthalf.filled")
                                    .font(.caption2.weight(.bold))
                                    .padding(.horizontal, 7).padding(.vertical, 2)
                                    .background(Capsule().fill(Color.primary.opacity(0.08)))
                            }
                        }
                        Text(member.joinedAt.map { "@\(member.profile.handle) · joined \($0.formatted(.dateTime.month(.abbreviated).year()))" } ?? "@\(member.profile.handle) · \(member.role.rawValue.capitalized)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { UIPasteboard.general.string = "@" + member.profile.handle; HapticEngine.shared.play(.success) } label: {
                Label("Copy handle", systemImage: "at")
            }
        }
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

struct CommunityUnavailableView: View {
    var body: some View {
        ModulaEmptyState(
            title: CommunityCopy.title,
            message: "\(CommunityCopy.comingSoon). \(CommunityCopy.noRoutes)",
            symbol: "person.3"
        )
    }
}

#if DEBUG
struct CommunityDeveloperEntry: View {
    @Environment(AppEnvironment.self) private var app
    @State private var shellEnabled = CommunityFeatureFlags.isEnabled
    @State private var apiEnabled = CommunityAPIFeatureFlags.isEnabled

    var body: some View {
        Toggle("Community shell", isOn: $shellEnabled)
            .onChange(of: shellEnabled) { _, value in
                CommunityFeatureFlags.setEnabled(value)
            }
            .accessibilityIdentifier("developer.community.toggle")
        Toggle("GreenField community APIs", isOn: $apiEnabled)
            .onChange(of: apiEnabled) { _, value in
                CommunityAPIFeatureFlags.setEnabled(value)
            }
            .accessibilityIdentifier("developer.community.api.toggle")
        if shellEnabled || apiEnabled {
            Button("Open Community") {
                app.navigation.open(.community(.hub))
            }
            .accessibilityIdentifier("developer.community.open")
        }
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
                Text(message).font(.subheadline).foregroundStyle(Color.modulaOnPrimary.opacity(0.88)).fixedSize(horizontal: false, vertical: true)
                Button {
                    action()
                    HapticEngine.shared.play(.navigation)
                } label: {
                    HStack(spacing: 6) { Text(cta); Image(systemName: "arrow.right") }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16).frame(height: 44)
                        .modulaPrimaryCTA()
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


/// Directory order (applied to the loaded page on device).
enum CommunityDirectorySort: String, CaseIterable, Identifiable {
    case relevant, members, active, name
    var id: Self { self }
    var title: String {
        switch self {
        case .relevant: "Relevant"
        case .members: "Most members"
        case .active: "Recently active"
        case .name: "A–Z"
        }
    }
    var symbol: String {
        switch self {
        case .relevant: "sparkles"
        case .members: "person.3"
        case .active: "clock"
        case .name: "textformat"
        }
    }
}


// MARK: - Members filter + rules sheet

enum CommunityMemberFilter: String, CaseIterable, Identifiable {
    case all, staff, members
    var id: String { rawValue }
    func title(count: Int) -> String {
        switch self {
        case .all: "All \(count)"
        case .staff: "Staff \(count)"
        case .members: "Members \(count)"
        }
    }
    /// Filters the loaded page(s) of members; staff (owner, admins, moderators) sort first.
    static func apply(_ members: [CommunityMember], filter: CommunityMemberFilter, query: String) -> [CommunityMember] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let isStaff: (CommunityMember) -> Bool = { [.owner, .admin, .moderator].contains($0.role) }
        let rank: (CommunityRole) -> Int = { r in
            switch r { case .owner: 0; case .admin: 1; case .moderator: 2; case .member: 3; case .restricted: 4 }
        }
        return members.filter { m in
            switch filter {
            case .all: true
            case .staff: isStaff(m)
            case .members: !isStaff(m)
            }
        }
        .filter { q.isEmpty || $0.profile.displayName.lowercased().contains(q) || $0.profile.handle.lowercased().contains(q) }
        .enumerated()
        .sorted { (rank($0.element.role), $0.offset) < (rank($1.element.role), $1.offset) }
        .map(\.element)
    }
}

/// Rules built from the community's real policies, plus Modula's community guidelines (which apply everywhere).
struct CommunityRulesSheet: View {
    let community: CommunityDetails
    let attachmentsAllowed: Bool?
    @Environment(\.dismiss) private var dismiss

    private var communityRules: [(String, String, String)] {
        var rules: [(String, String, String)] = [
            (community.membershipPolicy == .approval ? "person.badge.clock" : "person.badge.plus",
             community.membershipPolicy == .approval ? "Membership needs approval" : "Anyone can join",
             community.membershipPolicy == .approval ? "Moderators review each request before you can take part." : "Join to post, vote and RSVP."),
            (community.postingPolicy == .moderators ? "megaphone" : "text.bubble",
             community.postingPolicy == .moderators ? "Only moderators post" : "Members can post",
             community.postingPolicy == .moderators ? "Members can read and react; posts come from the team." : "Keep posts on topic for \(community.summary.name)."),
            (community.summary.visibility == .private ? "lock" : "globe",
             community.summary.visibility == .private ? "Private space" : "Public space",
             community.summary.visibility == .private ? "Posts are only visible to members." : "Anyone can read posts here."),
        ]
        if let attachmentsAllowed {
            rules.append((attachmentsAllowed ? "paperclip" : "paperclip.badge.ellipsis",
                          attachmentsAllowed ? "Photos and files allowed" : "Text only",
                          attachmentsAllowed ? "Share images and files that fit the topic." : "Attachments are turned off in this community."))
        }
        return rules
    }

    private static let guidelines: [(String, String, String)] = [
        ("hand.raised", "Be kind", "No harassment, hate or threats."),
        ("checkmark.seal", "Be genuine", "No spam, scams or impersonation."),
        ("lock.shield", "Respect privacy", "Don’t share other people’s personal information."),
        ("flag", "Report, don’t retaliate", "Use Report on posts that break these rules."),
    ]

    var body: some View {
        NavigationStack {
            List {
                Section(community.summary.name) {
                    ForEach(Array(communityRules.enumerated()), id: \.offset) { i, r in row(r).modulaAppear(delay: Double(i) * 0.04) }
                }
                Section {
                    ForEach(Array(Self.guidelines.enumerated()), id: \.offset) { i, r in row(r).modulaAppear(delay: 0.12 + Double(i) * 0.04) }
                } header: { Text("Modula community guidelines") } footer: {
                    Text("Moderators can remove posts or members that break these rules.")
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Rules")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .accessibilityIdentifier("community.rules.sheet")
    }

    private func row(_ r: (String, String, String)) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: r.0).font(.body.weight(.semibold)).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(r.1).font(.subheadline.weight(.semibold))
                Text(r.2).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
