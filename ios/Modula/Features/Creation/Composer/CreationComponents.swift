import SwiftUI

// MARK: - Tool dock

struct CreationToolDock<PhotoPicker: View, VideoPicker: View>: View {
    var kind: CreationKind
    var capabilities: CreationCapabilities
    var developerMode: Bool
    var accent: Color
    @ViewBuilder var photoPicker: () -> PhotoPicker
    @ViewBuilder var videoPicker: () -> VideoPicker
    var onTool: (CreationTool) -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Settings → Keyboard → "Swipe between composer tools": the dock scrolls
        // sideways (paging by tool) instead of squeezing every tool into one row.
        Group {
            if ModulaPreferences.composerToolSwipe {
                ScrollView(.horizontal, showsIndicators: false) {
                    dock.scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
            } else {
                dock
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(alignment: .top) {
                    LinearGradient(
                        colors: [
                            Color.primary.opacity(scheme == .dark ? 0.18 : 0.06),
                            .clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 1)
                }
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private var dock: some View {
        HStack(spacing: 6) {
            ForEach(CreationTool.allCases) { tool in
                if capabilities.toolVisible(tool, kind: kind, developerMode: developerMode) {
                    if tool == .photo && capabilities.toolEnabled(.photo) {
                        photoPicker()
                            .accessibilityLabel("Photo")
                            .accessibilityIdentifier("compose.tool.photo")
                    } else if tool == .video && capabilities.toolEnabled(.video) {
                        videoPicker()
                            .accessibilityLabel("Video")
                            .accessibilityIdentifier("compose.tool.video")
                    } else {
                        let enabled = capabilities.toolEnabled(tool)
                        Button {
                            onTool(tool)
                        } label: {
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
                        .accessibilityLabel(tool.title)
                        .accessibilityHint(enabled ? "Adds \(tool.title.lowercased())" : "Unavailable")
                        .accessibilityIdentifier("compose.tool.\(tool.rawValue)")
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: kind)
        .accessibilityElement(children: .contain)
        .accessibilitySortPriority(40)
    }
}

/// Shared chip for Photo / Camera / Video pickers and Link / Poll / More buttons.
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
                .frame(width: 40, height: 40)
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
        .frame(minWidth: 52, minHeight: 64)
        .opacity(enabled ? 1 : 0.72)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }

    private var foreground: Color {
        guard enabled else { return .secondary.opacity(scheme == .dark ? 0.55 : 0.45) }
        return emphasized ? accent : accent.opacity(scheme == .dark ? 0.95 : 0.88)
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
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(media.enumerated()), id: \.element.id) { index, item in
                    mediaCard(item, index: index, count: media.count)
                }
            }
        }
        .accessibilityElement(children: .contain)
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
                .frame(width: 148, height: 148).clipped()
            } else {
                VStack(spacing: 8) {
                    Image(systemName: symbol(item.kind)).font(.title)
                    Text(item.originalFilename ?? "Attachment").font(.caption).lineLimit(2).multilineTextAlignment(.center)
                    if let progress = item.uploadProgress, item.uploadState == .uploading {
                        ProgressView(value: progress).padding(.horizontal, 12)
                    }
                }
                .frame(width: 148, height: 148)
                .background(.secondary.opacity(0.10))
            }
            Text("\(index + 1)")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: index)
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
        }
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
