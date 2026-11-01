import SwiftUI

struct CommunitySettingsView: View {
    @Environment(AppEnvironment.self) private var app
    @State private var settings = CommunityLocalSettings.load()

    private var accent: Color { app.appearance.liveAccent }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(CommunityCopy.settingsFootnote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                identity
                section("Identity", footnote: "Shown only on this device") {
                    field("Community name", prompt: "Name people would see", text: $settings.displayName)
                    field("Description", prompt: "A short summary", text: $settings.summary, axis: .vertical)
                    comingSoonRow("Community icon", symbol: "photo")
                    comingSoonRow("Cover image", symbol: "photo.on.rectangle")
                }
                section("Analytics", footnote: CommunityCopy.analyticsUnavailable) {
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
                .modulaAccentCTA()
                .accessibilityIdentifier("community.settings.save")
            }
            .padding(.horizontal, ModulaLayout.contentInset)
            .padding(.vertical, 12)
        }
        .modulaSoftScrollEdge()
    }

    private var identity: some View {
        CommunityPanel {
            HStack(spacing: 12) {
                CommunityMark()
                VStack(alignment: .leading, spacing: 4) {
                    Text(settings.shownName)
                        .font(.headline)
                    Text(CommunityCopy.buildersStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func section<Content: View>(_ title: String, footnote: String, @ViewBuilder content: @escaping () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ModulaSectionHeader(title: title, subtitle: footnote)
            CommunityPanel { content() }
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
            app.navigation.flash(CommunityCopy.comingSoon, symbol: "clock")
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .frame(width: 28)
                    .foregroundStyle(accent)
                Text(title)
                    .font(.body)
                Spacer()
                Text(CommunityCopy.comingSoon)
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
        app.navigation.flash(CommunityCopy.savedOnDevice, symbol: "checkmark.circle")
    }
}

struct CommunityPollView: View {
    @Environment(AppEnvironment.self) private var app
    @State private var postID = ""
    @State private var rows: [CommunityPollRow] = []
    @State private var lookedUp = false
    @State private var loading = false
    @State private var message: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                CommunityPanel {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Community poll")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                        Text("No community poll feed")
                            .font(.title2.bold())
                        Text(CommunityCopy.pollFootnote)
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
                    .modulaAccentCTA()
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
                    CommunityPanel {
                        Text("This post has no comment polls.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(rows) { row in
                    CommunityPanel {
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

struct CommunityEventView: View {
    @Environment(AppEnvironment.self) private var app
    @State private var settings = CommunityLocalSettings.load()

    private var accent: Color { app.appearance.liveAccent }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ZStack(alignment: .bottomLeading) {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(LinearGradient(colors: [accent.opacity(0.9), Color.orange.opacity(0.55)], startPoint: .top, endPoint: .bottom))
                        .frame(height: 180)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("COMMUNITY EVENT")
                            .font(.caption.weight(.bold))
                        Text(CommunityCopy.comingSoon)
                            .font(.title.bold())
                    }
                    .foregroundStyle(.white)
                    .padding(18)
                }
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 2) {
                        Text("—")
                            .font(.title2.bold())
                        Text("Date")
                            .font(.caption2.weight(.semibold))
                    }
                    .frame(width: 64, height: 64)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Not scheduled")
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Not scheduled")
                            .font(.title3.bold())
                        Text(CommunityCopy.eventFootnote)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 10) {
                    CommunityComingSoonButton(title: "Join event")
                    ShareLink(item: CommunityCopy.eventShareText) {
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
                CommunityPanel {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Time isn’t set", systemImage: "clock")
                        Label("No place or link yet", systemImage: "globe")
                        Label(settings.interestedOnDevice ? "You’re interested on this device" : "Headcount isn’t available", systemImage: "person.2")
                    }
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
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
