import SwiftUI

// Local-first Community shell, kept beside the live API views so that when
// CommunityAPIFeatureFlags is off the surface matches main (debug preview or
// the unavailable state). Types are prefixed CommunityLocal* to avoid clashes.

struct CommunityLocalHubView: View {
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
        .toolbar { hubToolbar }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            ModulaWordmark(height: 22)
            Text(CommunityLocalCopy.title)
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            Text(CommunityLocalCopy.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(CommunityLocalCopy.preview)
                .font(.caption.weight(.semibold))
                .foregroundStyle(accent)
        }
        .task { await app.discover.loadIfNeeded(.trending) }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    private var search: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(CommunityLocalCopy.searchPrompt, text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit { openSearch() }
                Button(action: openSearch) {
                    Image(systemName: "arrow.right")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Search")
            }
            .padding(.leading, 14)
            .modulaGlass(in: Capsule(), interactive: true, specular: true)
            Text(CommunityLocalCopy.searchFootnote)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
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
        switch scope {
        case .forYou:
            CommunityLocalScenicCard(
                scene: "SceneMeadow",
                eyebrow: "FEATURED",
                title: "Share your space",
                message: "Communities are coming to Modula. Start with people and topics that are already here.",
                accent: accent
            ) {
                app.navigation.open(.discover(.people))
            }
            if let topics = app.discover.trending.dashboard?.topics, !topics.isEmpty {
                DiscoverTopicRail(topics: Array(topics.prefix(8))) { topic in
                    app.navigation.open(.search(.root(topic.query)))
                }
            } else {
                section("Trending", message: "Topics will show up here when communities exist.")
            }
            buildersLink
            section("Posts", message: CommunityLocalCopy.postsEmpty)
            pollLink
        case .following:
            section("Following", message: "People you follow already appear on Home. There is no community following feed.")
            eventLink
        case .communities:
            section("Communities", message: "No communities to join yet.")
            buildersLink
        case .topics:
            section("Topics", message: "No topics yet. Hashtags in posts stay on Search.")
        case .creators:
            section("Creators", message: "No creator directory yet.")
        case .builders:
            buildersLink
            section("Projects", message: "Builder projects aren’t a catalogue yet.")
        case .events:
            eventLink
            section("Events", message: CommunityLocalCopy.eventFootnote)
        }
    }

    private var buildersLink: some View {
        Button {
            app.navigation.push(.community(.modulaBuilders))
        } label: {
            CommunityLocalPanel {
                HStack(spacing: 12) {
                    CommunityLocalMark()
                    VStack(alignment: .leading, spacing: 4) {
                        Text(CommunityLocalCopy.buildersTitle)
                            .font(.headline)
                        Text(CommunityLocalCopy.buildersStatus)
                            .font(.subheadline)
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
        .accessibilityLabel(CommunityLocalCopy.buildersTitle)
        .accessibilityIdentifier("community.open.builders")
    }

    private var eventLink: some View {
        Button {
            app.navigation.push(.community(.event))
        } label: {
            CommunityLocalPanel {
                HStack(spacing: 12) {
                    Image(systemName: "calendar")
                        .font(.title2)
                        .foregroundStyle(accent)
                        .frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Community events")
                            .font(.headline)
                        Text(CommunityLocalCopy.comingSoon)
                            .font(.subheadline)
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
        .accessibilityIdentifier("community.open.event")
    }

    private var pollLink: some View {
        Button {
            app.navigation.push(.community(.poll))
        } label: {
            CommunityLocalPanel {
                HStack(spacing: 12) {
                    Image(systemName: "chart.bar")
                        .font(.title2)
                        .foregroundStyle(accent)
                        .frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Polls")
                            .font(.headline)
                        Text("Look up a comment poll on a post.")
                            .font(.subheadline)
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
        .accessibilityIdentifier("community.open.poll")
    }

    private func section(_ title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ModulaSectionHeader(title: title)
            CommunityLocalPanel {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ToolbarContentBuilder
    private var hubToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                app.navigation.push(.community(.settings))
            } label: {
                Image(systemName: "gearshape")
            }
            .accessibilityLabel("Community Settings")
            .accessibilityIdentifier("community.open.settings")
        }
    }

    private func openSearch() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        app.navigation.open(.search(.root(trimmed.isEmpty ? nil : trimmed)))
    }
}

struct CommunityLocalBuildersView: View {
    @Environment(AppEnvironment.self) private var app
    @State private var tab: CommunityBuildersTab = .feed
    @State private var settings = CommunityLocalSettings.load()

    private var accent: Color { app.appearance.liveAccent }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                hero
                identity
                VStack(spacing: 0) {
                    CommunityLocalInfoRow(symbol: settings.isPrivate ? "lock.fill" : "globe", tint: accent, title: settings.isPrivate ? "Private community" : "Public community", subtitle: "Your setting on this iPhone")
                    Divider().padding(.leading, 64)
                    CommunityLocalInfoRow(symbol: "person.3", tint: .purple, title: "Members", subtitle: "No member list until communities are on the server")
                    Divider().padding(.leading, 64)
                    CommunityLocalInfoRow(symbol: "calendar", tint: .blue, title: "Events", subtitle: "None scheduled")
                }
                .modulaGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous), interactive: false, specular: true)
                tabs
                tabBody
            }
            .padding(.horizontal, ModulaLayout.contentInset)
            .padding(.bottom, 28)
        }
        .modulaSoftScrollEdge()
        .toolbar { buildersToolbar }
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            Image("SceneStudio")
                .resizable()
                .scaledToFill()
                .frame(height: 190)
                .frame(maxWidth: .infinity)
                .clipped()
                .accessibilityHidden(true)
            LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 6) {
                Text("MODULA BUILDERS")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 10).frame(height: 24)
                    .modulaGlass(in: Capsule(), interactive: false)
                Text("Build together when this community exists.")
                    .font(.title3.bold())
                    .fixedSize(horizontal: false, vertical: true)
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

    private var identity: some View {
        HStack(spacing: 12) {
            CommunityLocalMark()
            VStack(alignment: .leading, spacing: 4) {
                Text(settings.shownName)
                    .font(.title3.bold())
                Text(CommunityLocalCopy.buildersStatus)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
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
    private var tabBody: some View {
        switch tab {
        case .feed:
            CommunityLocalPanel {
                VStack(alignment: .leading, spacing: 8) {
                    Text(CommunityLocalCopy.postsEmpty)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(CommunityLocalCopy.noRoutes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        case .projects:
            CommunityLocalPanel {
                Text("Projects aren’t listed yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        case .events:
            Button {
                app.navigation.push(.community(.event))
            } label: {
                CommunityLocalPanel {
                    Label("Community events", systemImage: "calendar")
                        .font(.headline)
                    Text(CommunityLocalCopy.comingSoon)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
        case .members:
            CommunityLocalPanel {
                Text(CommunityLocalCopy.membersEmpty)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        case .about:
            CommunityLocalPanel {
                VStack(alignment: .leading, spacing: 8) {
                    Text(CommunityLocalCopy.buildersTitle)
                        .font(.headline)
                    Text("A place for people building on Modula, once communities exist on the server.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(CommunityLocalCopy.noRoutes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        CommunityLocalComingSoonButton(title: "Join")
            .accessibilityIdentifier("community.builders.join")
    }

    @ToolbarContentBuilder
    private var buildersToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 12) {
                Button {
                    app.navigation.push(.community(.poll))
                } label: {
                    Image(systemName: "chart.bar")
                }
                .accessibilityLabel("Community poll")
                Button {
                    app.navigation.push(.community(.settings))
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Community Settings")
            }
        }
    }
}

struct CommunityLocalMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(red: 0.09, green: 0.11, blue: 0.14))
            ModulaUnitMark(style: .solid(.white))
                .padding(10)
        }
        .frame(width: 56, height: 56)
        .accessibilityHidden(true)
    }
}

struct CommunityLocalPanel<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modulaGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous), interactive: false, specular: true)
    }
}

struct CommunityLocalComingSoonButton: View {
    var title: String
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        Button {
            app.navigation.flash(CommunityLocalCopy.comingSoon, symbol: "clock")
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .modulaPrimaryCTA()
        .accessibilityHint(CommunityLocalCopy.comingSoon)
    }
}


struct CommunityLocalScenicCard: View {
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

struct CommunityLocalSettingsView: View {
    @Environment(AppEnvironment.self) private var app
    @State private var settings = CommunityLocalSettings.load()

    private var accent: Color { app.appearance.liveAccent }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(CommunityLocalCopy.settingsFootnote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                identity
                section("Identity", footnote: "Shown only on this device") {
                    field("Community name", prompt: "Name people would see", text: $settings.displayName)
                    field("Description", prompt: "A short summary", text: $settings.summary, axis: .vertical)
                    comingSoonRow("Community icon", symbol: "photo")
                    comingSoonRow("Cover image", symbol: "photo.on.rectangle")
                }
                section("Analytics", footnote: CommunityLocalCopy.analyticsUnavailable) {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        analytic("Member growth")
                        analytic("Posts")
                        analytic("Replies")
                        analytic("Engagement")
                    }
                }
                section("Membership", footnote: "Not published") {
                    Picker("Community type", selection: $settings.isPrivate) {
                        Text("Public").tag(false)
                        Text("Private").tag(true)
                    }
                    .pickerStyle(.segmented)
                    Toggle("Join approval", isOn: $settings.joinApproval)
                    Toggle("Invite links", isOn: $settings.inviteLinks)
                }
                section("Posting", footnote: "Not published") {
                    Picker("Who can post", selection: $settings.adminsOnlyPosting) {
                        Text("Everyone").tag(false)
                        Text("Admins").tag(true)
                    }
                    .pickerStyle(.segmented)
                    Toggle("Allow file attachments", isOn: $settings.allowAttachments)
                    Toggle("Reactions", isOn: $settings.reactions)
                    Toggle("Featured posts", isOn: $settings.featuredPosts)
                }
                section("Moderation", footnote: "No moderation queue yet") {
                    comingSoonRow("Admins", symbol: "person.2.badge.gearshape")
                    comingSoonRow("Community rules", symbol: "list.bullet.rectangle")
                    comingSoonRow("Auto filters", symbol: "line.3.horizontal.decrease")
                    comingSoonRow("Report queue", symbol: "flag")
                }
                section("Notifications", footnote: "On this device") {
                    Toggle("Mentions", isOn: $settings.notifyMentions)
                    Toggle("Weekly digest", isOn: $settings.weeklyDigest)
                    Toggle("Event reminders", isOn: $settings.eventReminders)
                }
                section("Safety", footnote: "On this device") {
                    field("Blocked words", prompt: "Words to hide locally", text: $settings.blockedWords, axis: .vertical)
                    comingSoonRow("Archived members", symbol: "person.crop.circle.badge.minus")
                }
                Button(action: save) {
                    Text("Save")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 48)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .modulaPrimaryCTA()
                .accessibilityIdentifier("community.settings.save")
            }
            .padding(.horizontal, ModulaLayout.contentInset)
            .padding(.vertical, 12)
        }
        .modulaSoftScrollEdge()
    }

    private var identity: some View {
        CommunityLocalPanel {
            HStack(spacing: 12) {
                CommunityLocalMark()
                VStack(alignment: .leading, spacing: 4) {
                    Text(settings.shownName)
                        .font(.headline)
                    Text(CommunityLocalCopy.buildersStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func section<Content: View>(_ title: String, footnote: String, @ViewBuilder content: @escaping () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ModulaSectionHeader(title: title, subtitle: footnote)
            CommunityLocalPanel { content() }
        }
    }

    private func field(_ title: String, prompt: String, text: Binding<String>, axis: Axis = .horizontal) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            TextField(prompt, text: text, axis: axis)
                .textFieldStyle(.roundedBorder)
        }
        .padding(.vertical, 4)
    }

    private func analytic(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("—")
                .font(.title3.weight(.semibold))
                .accessibilityLabel("Not available")
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func comingSoonRow(_ title: String, symbol: String) -> some View {
        Button {
            app.navigation.flash(CommunityLocalCopy.comingSoon, symbol: "clock")
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .frame(width: 28)
                    .foregroundStyle(accent)
                Text(title)
                    .font(.body)
                Spacer()
                Text(CommunityLocalCopy.comingSoon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
    }

    private func save() {
        settings.save()
        HapticEngine.shared.play(.success)
        app.navigation.flash(CommunityLocalCopy.savedOnDevice, symbol: "checkmark.circle")
    }
}

struct CommunityLocalPollView: View {
    @Environment(AppEnvironment.self) private var app
    @State private var postID = ""
    @State private var rows: [CommunityPollRow] = []
    @State private var lookedUp = false
    @State private var loading = false
    @State private var message: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                CommunityLocalPanel {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Community poll")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                        Text("No community poll feed")
                            .font(.title2.bold())
                        Text(CommunityLocalCopy.pollFootnote)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Post id", text: $postID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("community.poll.postID")
                    Button(action: { Task { await load() } }) {
                        Group {
                            if loading {
                                ProgressView()
                            } else {
                                Text("Look up comment polls")
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .modulaPrimaryCTA()
                    .disabled(loading || !CommunityPollListing.acceptsPostID(postID))
                    .accessibilityIdentifier("community.poll.load")
                    if !app.auth.isSignedIn {
                        Text("Sign in to vote. Looking up comments does not require a vote.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if let message {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("community.poll.message")
                }
                if lookedUp && rows.isEmpty && message == nil {
                    CommunityLocalPanel {
                        Text("This post has no comment polls.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(rows) { row in
                    CommunityLocalPanel {
                        VStack(alignment: .leading, spacing: 8) {
                            if !row.comment.text.isEmpty {
                                Text(row.comment.text)
                                    .font(.subheadline)
                            }
                            CommentPollView(poll: row.poll) { option in
                                Task { await vote(row, option: option) }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, ModulaLayout.contentInset)
            .padding(.vertical, 12)
        }
        .modulaSoftScrollEdge()
    }

    private func load() async {
        let id = postID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard CommunityPollListing.acceptsPostID(id) else { return }
        loading = true
        message = nil
        defer { loading = false }
        do {
            let repository = GreenfieldPostRepository(client: app.client)
            let page = try await repository.comments(postID: id, cursor: nil)
            rows = CommunityPollListing.rows(in: page.items)
            lookedUp = true
        } catch {
            rows = []
            lookedUp = true
            message = (error as? APIError)?.userFacingMessage ?? "Couldn’t load comments."
        }
    }

    private func vote(_ row: CommunityPollRow, option: Int?) async {
        guard app.auth.isSignedIn else {
            message = "Sign in to Modula to vote."
            return
        }
        let id = postID.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let repository = GreenfieldPostRepository(client: app.client)
            let fresh = try await repository.voteCommentPoll(commentID: row.comment.id, postID: id, option: option)
            if let fresh, let poll = fresh.media.compactMap(\.poll).first,
               let index = rows.firstIndex(where: { $0.id == row.id }) {
                rows[index] = CommunityPollRow(comment: fresh, poll: poll)
            }
            message = nil
            HapticEngine.shared.play(.success)
        } catch {
            message = (error as? APIError)?.userFacingMessage ?? "Couldn’t vote."
            HapticEngine.shared.play(.failure)
        }
    }
}

struct CommunityLocalEventView: View {
    @Environment(AppEnvironment.self) private var app
    @State private var settings = CommunityLocalSettings.load()

    private var accent: Color { app.appearance.liveAccent }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ZStack(alignment: .bottomLeading) {
                    Image("SceneMoonLake")
                        .resizable()
                        .scaledToFill()
                        .frame(height: 230)
                        .frame(maxWidth: .infinity)
                        .clipped()
                        .accessibilityHidden(true)
                    LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("COMMUNITY EVENT")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 10).frame(height: 24)
                            .modulaGlass(in: Capsule(), interactive: false)
                        Text(CommunityLocalCopy.comingSoon)
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(.white)
                    .padding(18)
                }
                .frame(height: 230)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(.white.opacity(0.25), lineWidth: 0.8))
                .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 2) {
                        Text("—")
                            .font(.title2.bold())
                        Text("Date")
                            .font(.caption2.weight(.semibold))
                    }
                    .frame(width: 64, height: 64)
                    .modulaGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous), interactive: false, specular: true)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Not scheduled")
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Not scheduled")
                            .font(.title3.bold())
                        Text(CommunityLocalCopy.eventFootnote)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 10) {
                    CommunityLocalComingSoonButton(title: "Join event")
                    ShareLink(item: CommunityLocalCopy.eventShareText) {
                        Image(systemName: "square.and.arrow.up")
                            .frame(width: 48, height: 48)
                    }
                    .buttonStyle(.plain)
                    .modulaGlass(in: Circle(), interactive: true, specular: true)
                    .accessibilityLabel("Share")
                    Button {
                        settings.interestedOnDevice.toggle()
                        settings.save()
                        HapticEngine.shared.play(.selection)
                        app.navigation.flash(settings.interestedOnDevice ? "Interested on this device" : "Interest cleared on this device", symbol: "bookmark")
                    } label: {
                        Image(systemName: settings.interestedOnDevice ? "bookmark.fill" : "bookmark")
                            .frame(width: 48, height: 48)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(settings.interestedOnDevice ? accent : Color.primary)
                    .modulaGlass(in: Circle(), interactive: true, tint: settings.interestedOnDevice ? accent : nil, specular: true)
                    .accessibilityLabel("Interested on this device")
                    .accessibilityValue(settings.interestedOnDevice ? "On" : "Off")
                    .accessibilityIdentifier("community.event.interest")
                }
                VStack(spacing: 0) {
                    CommunityLocalInfoRow(symbol: "clock", tint: accent, title: "Time isn’t set", subtitle: "Shown in your time zone once scheduled")
                    Divider().padding(.leading, 64)
                    CommunityLocalInfoRow(symbol: "globe", tint: .blue, title: "No place or link yet", subtitle: "Access details arrive with community events")
                    Divider().padding(.leading, 64)
                    CommunityLocalInfoRow(symbol: "person.2", tint: .purple, title: settings.interestedOnDevice ? "You’re interested on this device" : "Headcount isn’t available", subtitle: "No attendee route yet")
                }
                .modulaGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous), interactive: false, specular: true)
                VStack(alignment: .leading, spacing: 8) {
                    ModulaSectionHeader(title: "About this event")
                    Text("Workshops and calls need a community events endpoint. Until then this page stays empty of dates, hosts and headcounts.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Toggle("Remind me on this device", isOn: $settings.eventReminders)
                    .onChange(of: settings.eventReminders) { _, _ in
                        settings.save()
                    }
            }
            .padding(.horizontal, ModulaLayout.contentInset)
            .padding(.vertical, 12)
        }
        .modulaSoftScrollEdge()
        .accessibilityIdentifier("community.event.screen")
    }
}


/// Reference event info row: tinted icon tile, bold title, secondary detail.
struct CommunityLocalInfoRow: View {
    let symbol: String
    let tint: Color
    let title: String
    let subtitle: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 40, height: 40)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 64)
        .accessibilityElement(children: .combine)
    }
}
