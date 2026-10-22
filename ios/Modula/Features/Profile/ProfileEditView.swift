import SwiftUI

/// Edit Profile: a live, full-bleed preview of your real Profile header (tap the cover or
/// photo to change it) above glass section cards. Cancel / Save live in the nav bar.
struct ProfileEditView: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var confirmsDiscard = false
    @State private var confirmsLogOut = false
    @State private var mediaAction: ProfileMediaWorkspaceAction?
    @State private var mediaViewer: ModulaMediaViewerItem?
    @State private var showsAvatarOverlays = false
    @State private var mediaMenu: ProfileMediaKind?
    @FocusState private var focus: Field?

    private enum Field: Hashable { case name, headline, bio }
    private static let bioLimit = 160

    private var editing: ProfileEditingState { app.profile.editing }
    private var draft: ProfileEditDraft? { editing.draft }
    private var customization: ProfileCustomizationCapabilities { app.profile.customization }
    private var liveProfile: ModulaProfile? {
        app.profile.session(for: .me, handleHint: app.auth.account?.primaryHandle).profile
    }
    private var accent: Color { app.appearance.accent.color }
    private var spring: Animation? { reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.82) }
    private var canSave: Bool {
        editing.isDirty
            && editing.status != .saving
            && draft?.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                previewHeader

                VStack(alignment: .leading, spacing: 18) {
                    statusBanner
                    card("Profile") { identityRows }
                    card("About") { aboutRows }
                    card("Look") { lookRows }
                    if !(liveProfile?.links ?? []).isEmpty || customization.linksWritable {
                        card("Links") {
                            ProfileLinksEditor(links: liveProfile?.links ?? [], writable: customization.linksWritable)
                        }
                    }
                    card("Featured modules") { modulesRows }

                    Button(role: .destructive) {
                        confirmsLogOut = true
                    } label: {
                        Text("Log Out")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 50)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .modulaGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous), interactive: true)
                    .padding(.top, 8)
                    .confirmationDialog("Log out of Modula?", isPresented: $confirmsLogOut, titleVisibility: .visible) {
                        Button("Log Out", role: .destructive) {
                            Task {
                                await app.performSignOut()
                                app.navigation.close()
                            }
                        }
                        Button("Cancel", role: .cancel) {}
                    }
                }
                .padding(.horizontal, ModulaLayout.contentInset)
                .padding(.top, 18)
                .padding(.bottom, 40)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .ignoresSafeArea(edges: .top)
        .modulaCanvas()
        .navigationTitle("Edit Profile")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        // Legibility plate for Cancel/Save over the cover image.
        .overlay(alignment: .top) {
            LinearGradient(colors: [.black.opacity(0.45), .black.opacity(0.15), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 130)
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
        }
        .toolbar(.hidden, for: .tabBar)
        .interactiveDismissDisabled(editing.isDirty)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { attemptDismiss() }
                    .tint(.primary)
                    .accessibilityIdentifier("profile.edit.cancel")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    save()
                } label: {
                    if editing.status == .saving {
                        ProgressView().controlSize(.small).tint(.white)
                    } else {
                        Text("Save").fontWeight(.semibold)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .disabled(!canSave && editing.status != .saving)
                .animation(spring, value: canSave)
                .accessibilityIdentifier("profile.edit.save")
                .accessibilityLabel(editing.status == .saving ? "Saving" : "Save")
            }
        }
        .sensoryFeedback(.selection, trigger: mediaMenu)
        .confirmationDialog(mediaMenuTitle, isPresented: mediaMenuPresented, titleVisibility: .hidden, presenting: mediaMenu) { kind in
            Button(hasMedia(kind) ? "Change \(kind == .avatar ? "Photo" : "Cover")" : "Add \(kind == .avatar ? "Photo" : "Cover")") {
                mediaAction = .pick(kind)
            }
            if hasMedia(kind) {
                Button("View") { openViewer(kind) }
                Button(kind == .avatar ? "Edit" : "Reposition") { mediaAction = .cropExisting(kind) }
                Button("Remove", role: .destructive) { mediaAction = .remove(kind) }
            }
            if kind == .avatar {
                Button("Frames & Badges") { showsAvatarOverlays = true }
            }
            Button("Cancel", role: .cancel) {}
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
        .sheet(isPresented: $showsAvatarOverlays) {
            ProfileAvatarOverlayEditor()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .confirmationDialog("Unsaved changes", isPresented: $confirmsDiscard, titleVisibility: .visible) {
            Button("Save Changes") { save() }
            Button("Discard Changes", role: .destructive) {
                app.profile.discardEditing()
                app.navigation.close()
            }
            Button("Keep Editing", role: .cancel) {}
        }
        .accessibilityIdentifier("profile.edit")
    }

    // MARK: Live preview header

    private var previewHeader: some View {
        let avatarSize = ProfileIdentityMetrics.avatarSize(sizeClass: sizeClass)
        return VStack(alignment: .leading, spacing: 0) {
            ProfileCover(
                coverURL: liveProfile?.coverURL,
                coverColour: liveProfile?.coverColour,
                tint: accentPreview,
                pocketCenterX: ModulaLayout.contentInset + avatarSize / 2,
                pocketRadius: ProfileIdentityMetrics.carveRadius(avatarSize: avatarSize),
                onTap: { mediaMenu = .cover }
            )
            .overlay(alignment: .bottomTrailing) {
                editBadge(systemImage: "camera.fill", label: "Edit cover") { mediaMenu = .cover }
                    .padding(.trailing, ModulaLayout.contentInset)
                    .padding(.bottom, 44)
            }
            if let liveProfile {
                ProfileAvatarPocket(
                    profile: liveProfile.withPreviewIdentity(
                        displayName: draft?.displayName ?? liveProfile.displayName,
                        bio: draft?.bio ?? liveProfile.bio
                    ),
                    tint: accentPreview,
                    onTap: { mediaMenu = .avatar }
                )
                .overlay(alignment: .bottomLeading) {
                    editBadge(systemImage: "camera.fill", label: "Edit photo") { mediaMenu = .avatar }
                        .offset(x: ModulaLayout.contentInset + avatarSize - 30, y: -4)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(previewName)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(draft?.displayName.isEmpty == false ? Color.primary : Color.secondary)
                    .contentTransition(.opacity)
                if let handle = liveProfile?.handle {
                    Text("@\(handle)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let headline = draft?.headline, !headline.isEmpty, customization.headlineWritable {
                    Text(headline)
                        .font(.subheadline.weight(.medium))
                }
                if let bio = draft?.bio, !bio.isEmpty {
                    Text(bio)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, ModulaLayout.contentInset)
            .padding(.top, 10)
            .animation(spring, value: draft)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Live preview")
    }

    private var previewName: String {
        let name = draft?.displayName ?? ""
        return name.isEmpty ? "Your name" : name
    }

    private var accentPreview: Color? { draft?.accent?.color }

    private func editBadge(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(.black.opacity(0.45), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.7), lineWidth: 1.5))
        }
        .buttonStyle(ModulaPressStyle(scale: 0.9, haptic: nil))
        .accessibilityLabel(label)
    }

    // MARK: Sections

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 16)
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modulaGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous), interactive: false)
        }
    }

    private func row<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 48)
    }

    @ViewBuilder
    private var identityRows: some View {
        row("Name") {
            TextField("Display name", text: displayNameBinding)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.next)
                .focused($focus, equals: .name)
                .onSubmit { advanceFocus() }
                .accessibilityIdentifier("profile.edit.displayName")
        }
        if let handle = liveProfile?.handle {
            Divider()
            VStack(alignment: .leading, spacing: 2) {
                row("Username") {
                    HStack(spacing: 6) {
                        Text("@\(handle)")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text("Your username can be changed in Account settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 104)
                    .padding(.bottom, 8)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Username @\(handle), read only. Change it in Account settings.")
        }
        if customization.headlineWritable {
            Divider()
            row("Headline") {
                TextField("What you do", text: headlineBinding)
                    .submitLabel(.next)
                    .focused($focus, equals: .headline)
                    .onSubmit { advanceFocus() }
                    .accessibilityIdentifier("profile.edit.headline")
            }
        }
    }

    @ViewBuilder
    private var aboutRows: some View {
        VStack(alignment: .trailing, spacing: 4) {
            TextField("Write a short bio", text: bioBinding, axis: .vertical)
                .lineLimit(3...8)
                .focused($focus, equals: .bio)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("profile.edit.bio")
            let count = draft?.bio.count ?? 0
            Text("\(count)/\(Self.bioLimit)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(count >= Self.bioLimit ? Color.orange : Color.secondary)
                .contentTransition(.numericText())
                .accessibilityLabel("\(Self.bioLimit - count) characters left")
        }
        .padding(.vertical, 10)
        Divider()
        VStack(alignment: .leading, spacing: 8) {
            Text("Who can see your profile")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Picker("Visibility", selection: visibilityBinding) {
                ForEach([ProfileVisibility.public, .followers, .teams, .private], id: \.self) { value in
                    Text(value.displayTitle).tag(value)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("profile.edit.visibility")
        }
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var lookRows: some View {
        Button {
            showsAvatarOverlays = true
            HapticEngine.shared.play(.selection)
        } label: {
            HStack(spacing: 12) {
                framePreview
                VStack(alignment: .leading, spacing: 2) {
                    Text("Avatar frames & badges")
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text(frameSummary)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Color.primary.opacity(0.7))
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(minHeight: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("profile.edit.avatarOverlays")
        if customization.accentWritable || draft?.accent != nil {
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text("Accent")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ProfileAccentPicker(selection: accentBinding, writable: customization.accentWritable, showsTitle: false)
            }
            .padding(.vertical, 10)
        }
    }

    private var framePreview: some View {
        let store = ProfileAvatarOverlayStore.shared
        return ModulaDecoratedAvatar(
            size: 36,
            frame: ProfileAvatarFrame.frame(id: store.frameID),
            presence: .offline,
            badge: store.badge,
            customBadgeLabel: store.customBadgeLabel,
            customBadgeColor: Color(hex: store.customBadgeColorHex),
            showsBadgeChip: false
        ) {
            if let liveProfile {
                ProfileAvatarContent(profile: liveProfile, size: 36)
            } else {
                Circle().fill(accent.opacity(0.3))
            }
        }
        .frame(width: 48, height: 48)
    }

    private var frameSummary: String {
        let store = ProfileAvatarOverlayStore.shared
        let frame = ProfileAvatarFrame.frame(id: store.frameID)
        let parts = [store.badge?.title, frame.id == ProfileAvatarFrame.none.id ? nil : frame.title].compactMap { $0 }
        return parts.isEmpty ? "None" : parts.joined(separator: " · ")
    }

    private var modulesRows: some View {
        let installedIDs = app.catalogue.installedIDs
        let installed = app.catalogue.products.filter { installedIDs.contains($0.moduleId) }
        return FeaturedModulesEditor(
            featuredIDs: featuredBinding,
            installed: installed,
            writable: customization.featuredModulesWritable,
            accent: accent
        )
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var statusBanner: some View {
        if editing.status == .failed {
            Label(editing.error ?? "Couldn’t save your profile. Try again.", systemImage: "exclamationmark.triangle.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.red)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    // MARK: Bindings

    private var displayNameBinding: Binding<String> {
        Binding(
            get: { draft?.displayName ?? "" },
            set: { value in app.profile.updateEditingDraft { $0.displayName = value } }
        )
    }

    private var bioBinding: Binding<String> {
        Binding(
            get: { draft?.bio ?? "" },
            set: { value in
                let clamped = String(value.prefix(Self.bioLimit))
                app.profile.updateEditingDraft { $0.bio = clamped }
            }
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

    private var featuredBinding: Binding<[String]> {
        Binding(
            get: { draft?.featuredModuleIDs ?? liveProfile?.featuredModuleIds ?? [] },
            set: { value in app.profile.updateEditingDraft { $0.featuredModuleIDs = value } }
        )
    }

    // MARK: Actions

    private var mediaMenuPresented: Binding<Bool> {
        Binding(get: { mediaMenu != nil }, set: { if !$0 { mediaMenu = nil } })
    }

    private var mediaMenuTitle: String {
        mediaMenu == .cover ? "Cover photo" : "Profile photo"
    }

    private func hasMedia(_ kind: ProfileMediaKind) -> Bool {
        switch kind {
        case .avatar: liveProfile?.avatarURL != nil
        case .cover: liveProfile?.coverURL != nil
        }
    }

    private func advanceFocus() {
        switch focus {
        case .name: focus = customization.headlineWritable ? .headline : .bio
        case .headline: focus = .bio
        default: focus = nil
        }
    }

    private func save() {
        focus = nil
        Task {
            if await app.profile.saveEdits() {
                app.navigation.close()
            }
        }
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
        focus = nil
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
