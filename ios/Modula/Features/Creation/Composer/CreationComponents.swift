import SwiftUI

// MARK: - Primary tool rail (redesign)

enum CreationPrimaryAction: String, Identifiable, Hashable, Sendable {
    case video
    case more

    var id: String { rawValue }

    var title: String {
        switch self {
        case .video: "Video"
        case .more: "More"
        }
    }

    var symbol: String {
        switch self {
        case .video: "video.fill"
        case .more: "ellipsis.circle.fill"
        }
    }
}

/// Bottom rail: shared Photo/Camera entry + Video + More. Link/Poll live in More
/// so they never sit as dead grey icons.
struct CreationComposerRail<VideoPicker: View>: View {
    var accent: Color
    @Binding var mediaStage: ComposeMediaStage
    var videoEnabled: Bool
    var glassNamespace: Namespace.ID
    @ViewBuilder var videoPicker: () -> VideoPicker
    var onMore: () -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ModulaGlassGroup(spacing: 10) {
            HStack(alignment: .bottom, spacing: 8) {
                ComposeMediaAttachEntry(
                    stage: $mediaStage,
                    accent: accent,
                    glassNamespace: glassNamespace,
                    idPrefix: "compose.media"
                )

                if videoEnabled {
                    videoPicker()
                        .accessibilityLabel("Video")
                        .accessibilityIdentifier("compose.tool.video")
                }

                Button(action: onMore) {
                    CreationToolChipLabel(
                        title: "More",
                        symbol: "ellipsis.circle.fill",
                        accent: accent,
                        enabled: true,
                        emphasized: false
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("More options")
                .accessibilityHint("Opens links, polls, files, and other options")
                .accessibilityIdentifier("compose.tool.more")
                .modulaGlassID("compose.rail.more", in: glassNamespace)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(alignment: .top) {
                    LinearGradient(
                        colors: [
                            Color.primary.opacity(scheme == .dark ? 0.16 : 0.05),
                            .clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 1)
                }
                .ignoresSafeArea(edges: .bottom)
        }
        .animation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.86), value: mediaStage)
    }
}

/// Legacy dock kept for Settings catalog / tests that still pass `CreationTool`.
struct CreationToolDock<PhotoPicker: View, VideoPicker: View>: View {
    var kind: CreationKind
    var capabilities: CreationCapabilities
    var developerMode: Bool
    var accent: Color
    @ViewBuilder var photoPicker: () -> PhotoPicker
    @ViewBuilder var videoPicker: () -> VideoPicker
    var onTool: (CreationTool) -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 6) {
            ForEach(CreationTool.allCases) { tool in
                if capabilities.toolVisible(tool, kind: kind, developerMode: developerMode) {
                    if tool == .photo && capabilities.toolEnabled(.photo) {
                        photoPicker()
                    } else if tool == .video && capabilities.toolEnabled(.video) {
                        videoPicker()
                    } else {
                        let enabled = capabilities.toolEnabled(tool)
                        Button { onTool(tool) } label: {
                            CreationToolChipLabel(
                                title: tool.title,
                                symbol: tool.symbol,
                                accent: accent,
                                enabled: enabled || developerMode,
                                emphasized: false
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(!developerMode && !enabled)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(alignment: .top) {
                    LinearGradient(
                        colors: [Color.primary.opacity(scheme == .dark ? 0.18 : 0.06), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 1)
                }
                .ignoresSafeArea(edges: .bottom)
        }
    }
}

/// Shared chip for Video / More and legacy dock labels.
struct CreationToolChipLabel: View {
    var title: String
    var symbol: String
    var accent: Color
    var enabled: Bool
    var emphasized: Bool = false

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(foreground)
                .frame(width: 44, height: 44)
                .modulaGlass(
                    in: Circle(),
                    interactive: enabled,
                    tint: enabled ? accent.opacity(emphasized ? 0.55 : 0.28) : nil,
                    prominent: emphasized && enabled,
                    specular: enabled
                )
            Text(title)
                .font(.caption2.weight(enabled ? .semibold : .regular))
                .foregroundStyle(enabled ? Color.primary.opacity(0.78) : Color.secondary.opacity(0.55))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(minWidth: 56, minHeight: 66)
        .opacity(enabled ? 1 : 0.72)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }

    private var foreground: Color {
        guard enabled else { return .secondary.opacity(scheme == .dark ? 0.55 : 0.45) }
        return emphasized ? accent : accent.opacity(scheme == .dark ? 0.95 : 0.88)
    }
}

// MARK: - More options sheet

enum CreationMoreOption: String, Identifiable, CaseIterable, Sendable {
    case files
    case link
    case poll
    case mentions
    case hashtags
    case schedule
    case contentWarning
    case location

    var id: String { rawValue }

    var title: String {
        switch self {
        case .files: "Files & audio"
        case .link: "Link"
        case .poll: "Poll"
        case .mentions: "Mentions"
        case .hashtags: "Hashtags"
        case .schedule: "Schedule"
        case .contentWarning: "Content warning"
        case .location: "Location"
        }
    }

    var symbol: String {
        switch self {
        case .files: "doc.fill"
        case .link: "link"
        case .poll: "chart.bar.fill"
        case .mentions: "at"
        case .hashtags: "number"
        case .schedule: "calendar.badge.clock"
        case .contentWarning: "exclamationmark.shield"
        case .location: "location.fill"
        }
    }

    var subtitle: String {
        switch self {
        case .files: "Attach PDFs, audio, or documents"
        case .link: "Add a URL to this post as text"
        case .poll: "Draft a poll as text until SocialPost polls ship"
        case .mentions: "Type @ to find people"
        case .hashtags: "Type # for topic suggestions"
        case .schedule: "Not available yet — drafts stay local"
        case .contentWarning: "Not on the publish contract yet"
        case .location: "Not on the SocialPost contract yet"
        }
    }
}

struct CreationMoreOptionsSheet: View {
    var capabilities: CreationCapabilities
    var accent: Color
    var onFiles: () -> Void
    var onLink: () -> Void
    var onPoll: () -> Void
    var onMentionsTip: () -> Void
    var onHashtagsTip: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let columns = [GridItem(.adaptive(minimum: 100, maximum: 160), spacing: 12)]

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    section("Add to post") {
                        tile(.files, enabled: capabilities.mediaUpload) { onFiles() }
                        tile(.link, enabled: true) { onLink() }
                        tile(.poll, enabled: true) { onPoll() }
                    }
                    section("Writing") {
                        tile(.mentions, enabled: true) { onMentionsTip() }
                        tile(.hashtags, enabled: true) { onHashtagsTip() }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 6)
                .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .modifier(MoreSheetBackground())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(32)
        .accessibilityIdentifier("compose.more.sheet")
    }

    private var header: some View {
        HStack {
            Text("More")
                .font(.title3.weight(.bold))
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button("Done") { dismiss() }
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .modulaGlass(in: Capsule(), interactive: true, specular: true)
                .buttonStyle(.plain)
                .accessibilityIdentifier("compose.more.done")
        }
        .padding(.horizontal, 18)
        .padding(.top, 22)
        .padding(.bottom, 12)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        let tiles = content()
        return VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 4)
            ModulaGlassGroup(spacing: 12) {
                LazyVGrid(columns: columns, spacing: 12) { tiles }
            }
        }
    }

    private func tile(_ option: CreationMoreOption, enabled: Bool, soon: Bool = false, action: @escaping () -> Void) -> some View {
        Button {
            HapticEngine.shared.play(.selection)
            dismiss()
            action()
        } label: {
            VStack(spacing: 8) {
                Image(systemName: option.symbol)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(soon ? Color.secondary : accent)
                    .frame(height: 28)
                Text(option.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(soon ? Color.secondary : Color.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.85)
                if soon {
                    Text("Soon")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(.secondary.opacity(0.14), in: Capsule())
                }
            }
            .frame(maxWidth: .infinity, minHeight: 96)
            .padding(.vertical, 6)
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .modulaGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous), interactive: enabled, tint: soon ? nil : accent.opacity(0.12), specular: !soon)
            .opacity(soon ? 0.55 : (enabled ? 1 : 0.7))
        }
        .buttonStyle(.plain)
        .disabled(soon || !enabled)
        .accessibilityLabel(option.title)
        .accessibilityHint(option.subtitle)
        .accessibilityIdentifier("compose.more.\(option.rawValue)")
    }
}

/// Liquid Glass sheet background on iOS 26; thin material fallback before that.
private struct MoreSheetBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.presentationBackground(.clear).background(Color.clear.glassEffect(.regular, in: .rect(cornerRadius: 32)).ignoresSafeArea())
        } else {
            content.presentationBackground(.ultraThinMaterial)
        }
    }
}

// MARK: - Suggestion rails

struct CreationSuggestionRail: View {
    var mentions: [ModulaComposerMention]
    var hashtags: [String]
    var accent: Color
    var onMention: (ModulaComposerMention) -> Void
    var onHashtag: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(mentions) { mention in
                    Button {
                        onMention(mention)
                    } label: {
                        HStack(spacing: 6) {
                            Text("@\(mention.handle)")
                                .font(.subheadline.weight(.semibold))
                            if !mention.displayName.isEmpty {
                                Text(mention.displayName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .modulaGlass(in: Capsule(), interactive: true, tint: accent.opacity(0.22), specular: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("compose.mention.\(mention.handle)")
                }
                ForEach(hashtags, id: \.self) { tag in
                    Button {
                        onHashtag(tag)
                    } label: {
                        Text("#\(tag)")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .modulaGlass(in: Capsule(), interactive: true, tint: accent.opacity(0.22), specular: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("compose.hashtag.\(tag)")
                }
            }
            .padding(.horizontal, 4)
        }
        .accessibilityIdentifier("compose.suggestions")
    }
}

// MARK: - Media grid

struct MediaAttachmentGrid: View {
    var media: [CreationMedia]
    var fileURL: (CreationMedia) -> URL
    var onMoveEarlier: (String) -> Void
    var onMoveLater: (String) -> Void
    var onRemove: (String) -> Void
    var onAltText: (String) -> Void
    var onRotate: (String) -> Void
    var reduceMotion: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(media.count == 1 ? "1 attachment" : "\(media.count) attachments")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("Hold for alt text, reorder, remove")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(media.enumerated()), id: \.element.id) { index, item in
                        mediaCard(item, index: index, count: media.count)
                            .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
                    }
                }
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.secondary.opacity(0.06))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("compose.media.grid")
    }

    private func mediaCard(_ item: CreationMedia, index: Int, count: Int) -> some View {
        let url = fileURL(item)
        return ZStack(alignment: .bottomLeading) {
            if item.kind == .image {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    default: Rectangle().fill(.secondary.opacity(0.15))
                    }
                }
                .frame(width: 168, height: 168).clipped()
            } else {
                VStack(spacing: 8) {
                    Image(systemName: symbol(item.kind)).font(.title)
                    Text(item.originalFilename ?? "Attachment").font(.caption).lineLimit(2).multilineTextAlignment(.center)
                    if let progress = item.uploadProgress, item.uploadState == .uploading {
                        ProgressView(value: progress).padding(.horizontal, 12)
                    }
                }
                .frame(width: 168, height: 168)
                .background(.secondary.opacity(0.10))
            }
            HStack {
                Text("\(index + 1)")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
                Spacer()
                Button {
                    onRemove(item.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.55))
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove attachment \(index + 1)")
            }
            .padding(8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.8)
        }
        .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.84), value: index)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label(item, index: index, count: count))
        .accessibilityHint("Actions available")
        .accessibilityAction(named: "Edit alt text") { onAltText(item.id) }
        .accessibilityAction(named: "Move earlier") { onMoveEarlier(item.id) }
        .accessibilityAction(named: "Move later") { onMoveLater(item.id) }
        .accessibilityAction(named: "Remove") { onRemove(item.id) }
        .contextMenu {
            Button("Description", systemImage: "text.below.photo") { onAltText(item.id) }
            if item.kind == .image {
                Button("Rotate", systemImage: "rotate.right") { onRotate(item.id) }
            }
            Button("Move Earlier", systemImage: "arrow.left") { onMoveEarlier(item.id) }
            Button("Move Later", systemImage: "arrow.right") { onMoveLater(item.id) }
            Button("Remove", systemImage: "trash", role: .destructive) { onRemove(item.id) }
        }
    }

    private func symbol(_ kind: CreationMedia.Kind) -> String {
        switch kind {
        case .image: "photo"
        case .video: "video"
        case .audio: "waveform"
        case .pdf: "doc.richtext"
        case .document, .unknown: "doc"
        }
    }

    private func label(_ item: CreationMedia, index: Int, count: Int) -> String {
        let alt = item.hasAltText ? item.altText : "Alt text not added"
        let name = item.originalFilename ?? "Attachment"
        let kind: String
        switch item.kind {
        case .image: kind = "Image"
        case .video: kind = "Video"
        case .audio: kind = "Audio"
        case .pdf: kind = "PDF document"
        case .document: kind = "Document"
        case .unknown: kind = "Attachment"
        }
        return "\(kind) \(index + 1) of \(count), \(name). \(alt)."
    }
}

struct AltTextEditor: View {
    @State var text: String
    var onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            TextField("Describe this photo", text: $text, axis: .vertical)
                .lineLimit(3...8)
                .accessibilityIdentifier("compose.altText")
            Text("Optional. Used by VoiceOver and server accessibility metadata when supported.")
                .foregroundStyle(.secondary)
        }
        .modulaSoftScrollEdge()
        .navigationTitle("Alt Text")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    onSave(text)
                    dismiss()
                }
            }
        }
    }
}

struct LinkPreviewEditor: View {
    var urlString: String
    var preview: LinkDraft?
    var editableMetadata: Bool
    var onChange: (String) -> Void
    var footerNote: String? = nil
    @State private var field: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("https://", text: $field)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .onChange(of: field, initial: false) { _, value in onChange(value) }
                .onAppear { field = urlString }
                .accessibilityIdentifier("compose.link.url")
            if let preview, preview.previewFromServer {
                VStack(alignment: .leading, spacing: 4) {
                    Text(preview.title ?? preview.domain ?? "Link")
                        .font(.headline)
                    if let description = preview.description {
                        Text(description).font(.footnote).foregroundStyle(.secondary)
                    }
                    if let domain = preview.domain {
                        Text(domain).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if editableMetadata {
                Text("Preview fields stay read-only until Greenfield returns them.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let footerNote {
                Text(footerNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct DraftStatusView: View {
    var saved: Bool
    var publishing: Bool

    var body: some View {
        Group {
            if publishing {
                Text("Publishing")
            } else if saved {
                Text("Draft saved")
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .accessibilityLabel(publishing ? "Publishing" : (saved ? "Draft saved" : ""))
        .accessibilityIdentifier("compose.draft.status")
    }
}

struct UploadProgressSurface: View {
    var fraction: Double?
    var preparing: Bool
    var state: CreationState

    var body: some View {
        Group {
            if preparing {
                HStack {
                    ProgressView()
                    Text("Preparing media")
                }
            } else if let fraction, state == .uploading {
                ProgressView(value: fraction)
                    .accessibilityValue("\(Int(fraction * 100)) percent")
            } else if state == .processing {
                HStack {
                    ProgressView()
                    Text("Processing")
                }
            }
        }
        .font(.footnote)
        .accessibilityIdentifier("compose.upload")
    }
}

/// Local poll draft that inserts as readable text (honest until pollPost is true).
struct CreationTextPollEditor: View {
    @State private var poll: PollDraft
    var maxOptions: Int
    var accent: Color
    var onInsert: (String) -> Void
    var onCancel: () -> Void

    init(maxOptions: Int, accent: Color, onInsert: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        _poll = State(initialValue: PollDraft.blank(optionLimit: maxOptions))
        self.maxOptions = maxOptions
        self.accent = accent
        self.onInsert = onInsert
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Local poll draft", systemImage: "chart.bar.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(accent)
            Text("Structured polls aren’t on the SocialPost contract yet. Insert as text so people can reply — this does not invent a poll API.")
                .font(.caption)
                .foregroundStyle(.secondary)
            PollEditor(poll: poll, maxOptions: maxOptions) { poll = $0 }
            HStack {
                Button("Cancel", action: onCancel)
                Spacer()
                Button("Insert as text") {
                    onInsert(Self.format(poll))
                }
                .fontWeight(.semibold)
                .disabled(!canInsert)
                .tint(accent)
            }
            .fontDesign(.default)
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityIdentifier("compose.poll.local")
    }

    private var canInsert: Bool {
        let options = poll.options.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return !poll.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && options.count >= PollDraft.minimumOptions
    }

    static func format(_ poll: PollDraft) -> String {
        let options = poll.options
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var lines = ["📊 \(poll.question.trimmingCharacters(in: .whitespacesAndNewlines))"]
        for (index, option) in options.enumerated() {
            lines.append("\(index + 1). \(option)")
        }
        lines.append("(Text poll — reply with a number. Native polls coming later.)")
        return lines.joined(separator: "\n")
    }
}
