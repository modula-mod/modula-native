import SwiftUI

struct ProfileEditView: View {
    @Environment(AppEnvironment.self) private var app
    @State private var confirmsDiscard = false
    @State private var mediaAction: ProfileMediaWorkspaceAction?
    @State private var mediaViewer: ModulaMediaViewerItem?

    private var editing: ProfileEditingState { app.profile.editing }
    private var draft: ProfileEditDraft? { editing.draft }
    private var liveProfile: ModulaProfile? {
        app.profile.session(for: .me, handleHint: app.auth.account?.primaryHandle).profile
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                previewHeader

                identitySection
                mediaSection
                aboutSection
                linksSection
                modulesSection
                presentationSection

                Text("Pronouns, location, website, links, headline, and profile accent stay capability-gated when Greenfield does not persist them.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)

                statusRow

                Button {
                    Task {
                        let ok = await app.profile.saveEdits()
                        if ok {
                            app.navigation.close()
                        }
                    }
                } label: {
                    Text(editing.status == .saving ? "Saving…" : editing.status == .saved ? "Saved" : "Save")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(app.appearance.accent.color)
                .disabled(editing.status == .saving || draft?.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true)
                .accessibilityIdentifier("profile.edit.save")
                .accessibilityLabel(editing.status == .saving ? "Saving" : "Save")
            }
            .padding(.horizontal, ModulaLayout.contentInset)
            .padding(.top, 12)
            .padding(.bottom, 40)
        }
        .modulaSoftScrollEdge()
        .modulaCanvas()
        .navigationTitle("Edit Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { attemptDismiss() }
                    .accessibilityIdentifier("profile.edit.cancel")
            }
        }
        .profileMediaWorkspace(profile: liveProfile, action: $mediaAction) { kind in
            openViewer(kind)
        }
        .fullScreenCover(item: $mediaViewer) { item in
            ModulaMediaViewer(
                title: item.title,
                url: item.url,
                accessibilityDescription: item.accessibilityDescription,
                allowsShare: item.allowsShare
            ) {
                mediaViewer = nil
            }
        }
        .confirmationDialog("Unsaved changes", isPresented: $confirmsDiscard, titleVisibility: .visible) {
            Button("Save Changes") {
                Task {
                    if await app.profile.saveEdits() {
                        app.navigation.close()
                    }
                }
            }
            Button("Discard", role: .destructive) {
                app.profile.discardEditing()
                app.navigation.close()
            }
            Button("Cancel", role: .cancel) {}
        }
        .accessibilityIdentifier("profile.edit")
    }

    private var previewHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProfileCover(
                coverURL: liveProfile?.coverURL,
                coverColour: liveProfile?.coverColour
            )
            if let liveProfile {
                ProfileAvatarPocket(profile: liveProfile.withPreviewIdentity(
                    displayName: draft?.displayName ?? liveProfile.displayName,
                    bio: draft?.bio ?? liveProfile.bio
                ))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(draft?.displayName.isEmpty == false ? (draft?.displayName ?? "") : "Display name")
                    .font(.title2.weight(.bold))
                if let handle = liveProfile?.handle {
                    Text("@\(handle)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text(draft?.bio ?? "")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            .padding(.horizontal, ModulaLayout.contentInset)
            .padding(.top, 8)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Live preview")
    }

    private var identitySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Identity")
                .font(.headline)
            field(title: "Display Name") {
                TextField("Display name", text: displayNameBinding)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("profile.edit.displayName")
            }
            if let handle = liveProfile?.handle {
                field(title: "Handle") {
                    Text("@\(handle)")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel("Handle @\(handle). Change handle in Account settings.")
                }
            }
            field(title: "Headline") {
                TextField("Headline", text: headlineBinding)
                    .disabled(!app.profile.customization.headlineWritable)
                    .accessibilityIdentifier("profile.edit.headline")
            }
            if !app.profile.customization.headlineWritable {
                Text("Headline is stored when Greenfield provides it. Editing waits on a write contract.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var mediaSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Media")
                .font(.headline)
            ProfileMediaEditorRow(
                kind: .avatar,
                url: liveProfile?.avatarURL,
                initials: liveProfile?.initials ?? "?",
                onView: { openViewer(.avatar) },
                onChange: { mediaAction = .pick(.avatar) },
                onEdit: { mediaAction = .cropExisting(.avatar) },
                onRemove: { mediaAction = .remove(.avatar) }
            )
            ProfileMediaEditorRow(
                kind: .cover,
                url: liveProfile?.coverURL,
                initials: liveProfile?.initials ?? "?",
                onView: { openViewer(.cover) },
                onChange: { mediaAction = .pick(.cover) },
                onEdit: { mediaAction = .cropExisting(.cover) },
                onRemove: { mediaAction = .remove(.cover) }
            )
        }
    }

    private var linksSection: some View {
        ProfileLinksEditor(links: liveProfile?.links ?? [], writable: app.profile.customization.linksWritable)
    }

    private var modulesSection: some View {
        FeaturedModulesEditor(
            featuredIDs: draft?.featuredModuleIDs ?? liveProfile?.featuredModuleIds ?? [],
            available: app.catalogue.products,
            writable: app.profile.customization.featuredModulesWritable
        )
    }

    private var presentationSection: some View {
        ProfileAccentPicker(
            selection: accentBinding,
            writable: app.profile.customization.accentWritable
        )
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("About")
                .font(.headline)
            field(title: "Bio") {
                TextField("Bio", text: bioBinding, axis: .vertical)
                    .lineLimit(4...10)
                    .frame(minHeight: 96, alignment: .topLeading)
                    .accessibilityIdentifier("profile.edit.bio")
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Visibility")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Picker("Visibility", selection: visibilityBinding) {
                    ForEach([ProfileVisibility.public, .followers, .teams, .private], id: \.self) { value in
                        Text(value.displayTitle).tag(value)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("profile.edit.visibility")
            }
        }
    }

    private func field<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(minHeight: 44, alignment: .leading)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        switch editing.status {
        case .saving:
            Label("Saving…", systemImage: "arrow.triangle.2.circlepath")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
        case .saved:
            Label("Saved", systemImage: "checkmark.circle.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(app.appearance.accent.color)
        case .failed:
            Label(editing.error ?? "Could not save profile.", systemImage: "exclamationmark.triangle.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.red)
        case .dirty:
            Text("Unsaved changes")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .idle:
            EmptyView()
        }
    }

    private var displayNameBinding: Binding<String> {
        Binding(
            get: { draft?.displayName ?? "" },
            set: { value in app.profile.updateEditingDraft { $0.displayName = value } }
        )
    }

    private var bioBinding: Binding<String> {
        Binding(
            get: { draft?.bio ?? "" },
            set: { value in app.profile.updateEditingDraft { $0.bio = value } }
        )
    }

    private var visibilityBinding: Binding<ProfileVisibility> {
        Binding(
            get: { draft?.visibility ?? .public },
            set: { value in app.profile.updateEditingDraft { $0.visibility = value } }
        )
    }

    private var headlineBinding: Binding<String> {
        Binding(
            get: { draft?.headline ?? "" },
            set: { value in app.profile.updateEditingDraft { $0.headline = value } }
        )
    }

    private var accentBinding: Binding<ProfileAccent?> {
        Binding(
            get: { draft?.accent },
            set: { value in app.profile.updateEditingDraft { $0.accent = value } }
        )
    }

    private func openViewer(_ kind: ProfileMediaKind) {
        guard let liveProfile else { return }
        switch kind {
        case .avatar:
            mediaViewer = ModulaMediaViewerItem(
                title: "Profile photo",
                url: liveProfile.avatarURL,
                accessibilityDescription: "\(liveProfile.displayName)'s profile photo"
            )
        case .cover:
            guard liveProfile.coverURL != nil else { return }
            mediaViewer = ModulaMediaViewerItem(
                title: "Cover photo",
                url: liveProfile.coverURL,
                accessibilityDescription: "\(liveProfile.displayName)'s cover photo"
            )
        }
    }

    private func attemptDismiss() {
        if editing.isDirty {
            confirmsDiscard = true
        } else {
            app.profile.discardEditing()
            app.navigation.close()
        }
    }
}

private extension ModulaProfile {
    func withPreviewIdentity(displayName: String, bio: String) -> ModulaProfile {
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
            followerCount: followerCount,
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
