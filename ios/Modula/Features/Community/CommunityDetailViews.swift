import SwiftUI

struct CommunitySettingsView: View {
    @Environment(AppEnvironment.self) private var app
    @State private var draft: CommunitySettingsDraft?

    private var canManage: Bool { app.communities.capabilities.canManage }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if !app.auth.isSignedIn {
                    ModulaEmptyState(title: "Sign in required", message: "Sign in to manage community preferences.", symbol: "person.crop.circle")
                } else if app.communities.contentState.isLoading && draft == nil {
                    ProgressView("Loading settings…")
                        .frame(maxWidth: .infinity).padding(.vertical, 40)
                } else if let binding = Binding($draft) {
                    settingsForm(binding)
                } else {
                    ModulaEmptyState(
                        title: "Settings unavailable",
                        message: app.communities.contentState.message ?? "Join this community to manage its settings.",
                        symbol: "gearshape"
                    )
                }
            }
            .padding(.horizontal, ModulaLayout.contentInset)
            .padding(.vertical, 12)
        }
        .modulaSoftScrollEdge()
        .task { await app.communities.loadBuildersIfNeeded(signedIn: app.auth.isSignedIn) }
        .task(id: app.communities.settings?.version) { synchronizeDraft() }
    }

    @ViewBuilder
    private func settingsForm(_ draft: Binding<CommunitySettingsDraft>) -> some View {
        if let message = app.communities.actionError {
            CommunityStateBanner(message: message, symbol: "exclamationmark.triangle")
        }
        identity
        if !canManage {
            CommunityStateBanner(
                message: "Your server role allows notification preferences only. Administrator settings are read-only.",
                symbol: "lock"
            )
        }
        section("Identity", footnote: canManage ? "Published to GreenField" : "Administrator only") {
            field("Community name", prompt: "Community name", text: draft.name)
            field("Description", prompt: "A short summary", text: draft.description, axis: .vertical)
        }
        .disabled(!canManage)
        section("Membership", footnote: canManage ? "Server-enforced policy" : "Administrator only") {
            Picker("Community type", selection: draft.visibility) {
                Text("Public").tag(CommunityVisibility.public)
                Text("Private").tag(CommunityVisibility.private)
            }
            .pickerStyle(.segmented)
            Picker("Join policy", selection: draft.membershipPolicy) {
                Text("Open").tag(CommunityMembershipPolicy.open)
                Text("Approval").tag(CommunityMembershipPolicy.approval)
            }
            .pickerStyle(.segmented)
            Toggle("Invite links", isOn: draft.inviteLinksEnabled)
        }
        .disabled(!canManage)
        section("Posting", footnote: canManage ? "Server-enforced policy" : "Administrator only") {
            Picker("Who can post", selection: draft.postingPolicy) {
                Text("Members").tag(CommunityPostingPolicy.members)
                Text("Moderators").tag(CommunityPostingPolicy.moderators)
            }
            .pickerStyle(.segmented)
            Toggle("Allow file attachments", isOn: draft.allowAttachments)
            Toggle("Reactions", isOn: draft.reactionsEnabled)
            Toggle("Featured posts", isOn: draft.featuredPostsEnabled)
        }
        .disabled(!canManage)
        section("Moderation", footnote: canManage ? "Applied by GreenField" : "Administrator only") {
            field("Blocked words", prompt: "Comma-separated words", text: draft.blockedWords, axis: .vertical)
        }
        .disabled(!canManage)
        section("Notifications", footnote: "Your membership preferences") {
            Toggle("Mentions", isOn: draft.notifyMentions)
            Toggle("Weekly digest", isOn: draft.weeklyDigest)
            Toggle("Event reminders", isOn: draft.eventReminders)
        }
        Button {
            Task {
                guard let value = self.draft else { return }
                if await app.communities.saveSettings(value) {
                    synchronizeDraft()
                    HapticEngine.shared.play(.success)
                    app.navigation.flash("Community settings saved", symbol: "checkmark.circle")
                } else {
                    HapticEngine.shared.play(.failure)
                }
            }
        } label: {
            Group {
                if app.communities.actionInProgress { ProgressView() } else { Text("Save") }
            }
            .font(.headline)
            .frame(maxWidth: .infinity).frame(minHeight: 48)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .modulaAccentCTA()
        .disabled(app.communities.actionInProgress)
        .accessibilityIdentifier("community.settings.save")
    }

    private var identity: some View {
        CommunityPanel {
            HStack(spacing: 12) {
                CommunityMark()
                VStack(alignment: .leading, spacing: 4) {
                    Text(app.communities.selectedCommunity?.summary.name ?? CommunityCopy.buildersTitle)
                        .font(.headline)
                    Text(app.communities.selectedCommunity?.summary.viewerRole?.rawValue.capitalized ?? "Community member")
                        .font(.caption).foregroundStyle(.secondary)
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
            Text(title).font(.subheadline.weight(.semibold))
            TextField(prompt, text: text, axis: axis).textFieldStyle(.roundedBorder)
        }
        .padding(.vertical, 4)
    }

    private func synchronizeDraft() {
        guard let community = app.communities.selectedCommunity,
              let settings = app.communities.settings else { return }
        draft = CommunitySettingsDraft(community: community, settings: settings)
    }
}

struct CommunityPollView: View {
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                CommunityPanel {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("COMMUNITY POLLS").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                        Text(app.communities.selectedCommunity?.summary.name ?? CommunityCopy.buildersTitle)
                            .font(.title2.bold())
                        Text("Vote results and your selected option come from GreenField.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                if let message = app.communities.actionError {
                    CommunityStateBanner(message: message, symbol: "exclamationmark.triangle")
                }
                if app.communities.contentState.isLoading && app.communities.polls.isEmpty {
                    ProgressView("Loading polls…").frame(maxWidth: .infinity).padding(.vertical, 36)
                } else if app.communities.polls.isEmpty {
                    ModulaEmptyState(title: "No polls", message: CommunityCopy.pollsEmpty, symbol: "chart.bar")
                } else {
                    ForEach(app.communities.polls) { poll in
                        pollCard(poll)
                        if poll.id == app.communities.polls.last?.id, app.communities.pollsNextCursor != nil {
                            ProgressView().task { await app.communities.loadMorePolls() }
                        }
                    }
                }
            }
            .padding(.horizontal, ModulaLayout.contentInset)
            .padding(.vertical, 12)
        }
        .modulaSoftScrollEdge()
        .refreshable { await app.communities.refreshSelected(signedIn: app.auth.isSignedIn) }
        .task { await app.communities.loadBuildersIfNeeded(signedIn: app.auth.isSignedIn) }
    }

    private func pollCard(_ poll: CommunityPoll) -> some View {
        CommunityPanel {
            VStack(alignment: .leading, spacing: 12) {
                Text(poll.question).font(.headline)
                ForEach(poll.options.sorted { $0.position < $1.position }) { option in
                    let selected = poll.viewerOptionID == option.id
                    Button {
                        Task {
                            await app.communities.vote(pollID: poll.id, optionID: option.id)
                            HapticEngine.shared.play(app.communities.actionError == nil ? .success : .failure)
                        }
                    } label: {
                        HStack {
                            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            Text(option.text)
                            Spacer()
                            if let count = option.voteCount { Text("\(count)").foregroundStyle(.secondary) }
                        }
                        .font(.subheadline.weight(selected ? .semibold : .regular))
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .disabled(
                        poll.closed || poll.status != "open" || app.communities.actionInProgress
                            || !app.communities.capabilities.canVoteAndRSVP
                            || (poll.viewerOptionID != nil && !poll.allowVoteChanges)
                    )
                    .accessibilityIdentifier("community.poll.option.\(option.id)")
                }
                HStack {
                    Text(poll.closed ? "Closed" : "Closes \(poll.closesAt.formatted(date: .abbreviated, time: .shortened))")
                    Spacer()
                    if let total = poll.totalVotes { Text("\(total) votes") }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct CommunityEventView: View {
    @Environment(AppEnvironment.self) private var app

    private var accent: Color { app.appearance.liveAccent }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ZStack(alignment: .bottomLeading) {
                    Image("SceneMoonLake")
                        .resizable().scaledToFill()
                        .frame(height: 230).frame(maxWidth: .infinity).clipped()
                        .accessibilityHidden(true)
                    LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("COMMUNITY EVENTS")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 10).frame(height: 24)
                            .modulaGlass(in: Capsule(), interactive: false)
                        Text(app.communities.selectedCommunity?.summary.name ?? CommunityCopy.buildersTitle)
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(.white).padding(18)
                }
                .frame(height: 230)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(.white.opacity(0.25), lineWidth: 0.8))
                .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
                if let message = app.communities.actionError {
                    CommunityStateBanner(message: message, symbol: "exclamationmark.triangle")
                }
                if app.communities.contentState.isLoading && app.communities.events.isEmpty {
                    ProgressView("Loading events…").frame(maxWidth: .infinity).padding(.vertical, 36)
                } else if app.communities.events.isEmpty {
                    ModulaEmptyState(title: "No events", message: CommunityCopy.eventsEmpty, symbol: "calendar")
                } else {
                    ForEach(app.communities.events) { event in
                        eventCard(event)
                        if event.id == app.communities.events.last?.id, app.communities.eventsNextCursor != nil {
                            ProgressView().task { await app.communities.loadMoreEvents() }
                        }
                    }
                }
            }
            .padding(.horizontal, ModulaLayout.contentInset)
            .padding(.vertical, 12)
        }
        .modulaSoftScrollEdge()
        .refreshable { await app.communities.refreshSelected(signedIn: app.auth.isSignedIn) }
        .task { await app.communities.loadBuildersIfNeeded(signedIn: app.auth.isSignedIn) }
        .accessibilityIdentifier("community.event.screen")
    }

    private func eventCard(_ event: CommunityEvent) -> some View {
        CommunityPanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 2) {
                        Text(event.startsAt.formatted(.dateTime.day()))
                            .font(.title2.bold())
                        Text(event.startsAt.formatted(.dateTime.month(.abbreviated)).uppercased())
                            .font(.caption2.weight(.semibold))
                    }
                    .frame(width: 64, height: 64)
                    .modulaGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous), interactive: false, specular: true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(event.title).font(.title3.bold())
                        Text(event.startsAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.subheadline).foregroundStyle(.secondary)
                        Text(event.location.name ?? locationLabel(event.location.type))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !event.description.isEmpty {
                    Text(event.description).font(.subheadline).foregroundStyle(.secondary)
                }
                HStack(spacing: 10) {
                    responseButton("Going", response: .going, event: event)
                    responseButton("Interested", response: .interested, event: event)
                    ShareLink(item: event.location.onlineURL?.absoluteString ?? "\(event.title) — \(event.startsAt.formatted(date: .abbreviated, time: .shortened))") {
                        Image(systemName: "square.and.arrow.up").frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .modulaGlass(in: Circle(), interactive: true, specular: true)
                    .accessibilityLabel("Share event")
                }
                HStack {
                    Label("\(event.goingCount) going", systemImage: "person.2")
                    Spacer()
                    Text("\(event.interestedCount) interested")
                }
                .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func responseButton(_ title: String, response: CommunityEventResponse, event: CommunityEvent) -> some View {
        let selected = event.viewerResponse == response
        return Button {
            Task {
                await app.communities.respond(eventID: event.id, response: selected ? nil : response)
                HapticEngine.shared.play(app.communities.actionError == nil ? .success : .failure)
            }
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12).frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .foregroundStyle(selected ? Color.white : Color.primary)
        .modulaGlass(in: Capsule(), interactive: true, tint: selected ? accent : nil, prominent: selected, specular: true)
        .disabled(
            event.status != "scheduled" || app.communities.actionInProgress
                || !app.communities.capabilities.canVoteAndRSVP
        )
        .accessibilityIdentifier("community.event.\(response.rawValue).\(event.id)")
    }

    private func locationLabel(_ type: String) -> String {
        switch type {
        case "online": "Online"
        case "inPerson": "In person"
        default: "To be announced"
        }
    }
}

struct CommunityInfoRow: View {
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
