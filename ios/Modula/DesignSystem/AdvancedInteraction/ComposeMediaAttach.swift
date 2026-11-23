import PhotosUI
import SwiftUI
import UIKit

// MARK: - Shared Photo / Camera attach stage
//
// One media experience for post compose and comment compose: library pick + inline
// ModulaInlineCamera, with spring morph open/close and Reduce Motion fades.

enum ComposeMediaAttachMode: String, CaseIterable, Identifiable, Sendable {
    case library
    case camera

    var id: String { rawValue }

    var title: String {
        switch self {
        case .library: "Library"
        case .camera: "Camera"
        }
    }

    var symbol: String {
        switch self {
        case .library: "photo.on.rectangle.angled"
        case .camera: "camera.fill"
        }
    }
}

/// Binding-friendly presentation of the media stage (collapsed / library / camera).
enum ComposeMediaStage: Equatable, Sendable {
    case collapsed
    case library
    case camera

    var isExpanded: Bool { self != .collapsed }

    var mode: ComposeMediaAttachMode? {
        switch self {
        case .collapsed: nil
        case .library: .library
        case .camera: .camera
        }
    }

    static func expanding(_ mode: ComposeMediaAttachMode) -> ComposeMediaStage {
        switch mode {
        case .library: .library
        case .camera: .camera
        }
    }
}

/// Morphing Photo / Camera entry chips that expand into `ComposeMediaAttachStage`.
struct ComposeMediaAttachEntry: View {
    @Binding var stage: ComposeMediaStage
    var accent: Color
    var showsCamera: Bool = UIImagePickerController.isSourceTypeAvailable(.camera)
    var glassNamespace: Namespace.ID?
    var idPrefix: String = "compose.media"

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            entryChip(
                mode: .library,
                title: "Photo",
                symbol: "photo.on.rectangle.angled",
                emphasized: true
            )
            if showsCamera {
                entryChip(
                    mode: .camera,
                    title: "Camera",
                    symbol: "camera.fill",
                    emphasized: true
                )
            }
        }
    }

    private func entryChip(mode: ComposeMediaAttachMode, title: String, symbol: String, emphasized: Bool) -> some View {
        let selected = stage.mode == mode
        return Button {
            withAnimation(motion) {
                stage = stage == .expanding(mode) ? .collapsed : .expanding(mode)
            }
            HapticEngine.shared.play(.selection)
        } label: {
            VStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(accent)
                    .frame(width: 44, height: 44)
                    .modulaGlass(
                        in: Circle(),
                        interactive: true,
                        tint: accent.opacity(selected ? 0.72 : (emphasized ? 0.48 : 0.28)),
                        prominent: selected || emphasized,
                        specular: true
                    )
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.primary.opacity(0.82))
                    .lineLimit(1)
            }
            .frame(minWidth: 56, minHeight: 66)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(selected ? "Selected" : "Collapsed")
        .accessibilityHint(selected ? "Closes the media stage" : "Opens \(title.lowercased())")
        .accessibilityIdentifier("\(idPrefix).\(mode.rawValue)")
        .modifier(ComposeGlassIDIfNeeded(id: "\(idPrefix).chip.\(mode.rawValue)", namespace: glassNamespace))
    }

    private var motion: Animation {
        reduceMotion ? .easeOut(duration: 0.14) : .spring(response: 0.38, dampingFraction: 0.82)
    }
}

/// Rich media stage: library picker surface or inline camera (shared with comments).
struct ComposeMediaAttachStage: View {
    @Binding var stage: ComposeMediaStage
    var accent: Color
    var idPrefix: String = "compose.media"
    var height: CGFloat = 280
    var maxSelectionCount: Int = 10
    var matching: PHPickerFilter = .any(of: [.images, .videos])
    var cameraModes: [ModulaInlineCamera.Mode] = [.photo, .video]
    var onPhotosPicked: ([PhotosPickerItem]) -> Void
    var onCameraPhoto: (UIImage) -> Void
    var onCameraVideo: ((URL) -> Void)? = nil
    /// When set, the Library tab shows the in-app PhotoKit grid instead of the system picker.
    var photoLibrary: ModulaPhotoLibraryModel? = nil
    var onAssetsPicked: (([PHAsset]) -> Void)? = nil
    var allowsVideo = false
    var onVideoBlocked: (() -> Void)? = nil
    /// When set, the Camera tab opens the full-screen camera instead of the inline card.
    var onOpenCamera: (() -> Void)? = nil

    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var gridSelection: [String] = []
    @State private var gridExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Group {
            if let mode = stage.mode {
                VStack(spacing: 12) {
                    header(mode)
                    content(mode)
                }
                .padding(12)
                .frame(maxWidth: .infinity)
                .background {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(accent.opacity(scheme == .dark ? 0.10 : 0.05))
                }
                .modulaGlass(
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous),
                    interactive: false,
                    tint: accent.opacity(0.18),
                    specular: true
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(accent.opacity(0.28), lineWidth: 0.9)
                }
                .transition(reduceMotion ? .opacity : .asymmetric(
                    insertion: .scale(scale: 0.94, anchor: .bottom).combined(with: .opacity),
                    removal: .opacity
                ))
                .accessibilityIdentifier("\(idPrefix).stage")
            }
        }
        .animation(motion, value: stage)
        .sheet(isPresented: $gridExpanded) {
            if let photoLibrary {
                NavigationStack {
                    gridView(photoLibrary, expandable: false)
                        .padding(.horizontal, 2)
                        .navigationTitle("Library")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) { Button("Close") { gridExpanded = false } }
                        }
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            onPhotosPicked(items)
            pickerItems = []
            withAnimation(motion) { stage = .collapsed }
        }
    }

    private func header(_ mode: ComposeMediaAttachMode) -> some View {
        HStack(spacing: 10) {
            ForEach(ComposeMediaAttachMode.allCases.filter { modeFilter($0) }) { item in
                Button {
                    if item == .camera, let onOpenCamera {
                    onOpenCamera()
                } else {
                    withAnimation(motion) { stage = .expanding(item) }
                }
                    HapticEngine.shared.play(.selection)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: item.symbol)
                        Text(item.title)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(mode == item ? Color.white : Color.primary.opacity(0.78))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background {
                        if mode == item {
                            Capsule().fill(accent)
                        }
                    }
                    .modulaGlass(in: Capsule(), interactive: true, tint: mode == item ? nil : accent.opacity(0.16), specular: true)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(mode == item ? .isSelected : [])
                .accessibilityIdentifier("\(idPrefix).tab.\(item.rawValue)")
            }
            Spacer(minLength: 0)
            Button {
                withAnimation(motion) { stage = .collapsed }
                HapticEngine.shared.play(.selection)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .modulaGlass(in: Circle(), interactive: true, specular: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close media")
            .accessibilityIdentifier("\(idPrefix).close")
        }
    }

    @ViewBuilder
    private func content(_ mode: ComposeMediaAttachMode) -> some View {
        switch mode {
        case .library:
            librarySurface
        case .camera:
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                ModulaInlineCamera(
                    modes: cameraModes,
                    idPrefix: "\(idPrefix).camera",
                    height: height,
                    onPhoto: { image in
                        onCameraPhoto(image)
                        withAnimation(motion) { stage = .collapsed }
                    },
                    onVideo: { url in
                        onCameraVideo?(url)
                        withAnimation(motion) { stage = .collapsed }
                    },
                    onClose: { withAnimation(motion) { stage = .collapsed } }
                )
            } else {
                Text("Camera isn’t available on this device.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            }
        }
    }

    private func gridView(_ model: ModulaPhotoLibraryModel, expandable: Bool) -> some View {
        ModulaPhotoGrid(
            model: model,
            selection: $gridSelection,
            maxSelection: maxSelectionCount,
            accent: accent,
            showsCameraTile: UIImagePickerController.isSourceTypeAvailable(.camera),
            onCamera: {
                gridExpanded = false
                if let onOpenCamera { onOpenCamera() } else { withAnimation(motion) { stage = .expanding(.camera) } }
            },
            onExpand: expandable ? { gridExpanded = true } : nil,
            allowsVideo: allowsVideo,
            onVideoBlocked: onVideoBlocked,
            onAdd: {
                let ids = gridSelection
                let fetched = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
                var byID: [String: PHAsset] = [:]
                fetched.enumerateObjects { asset, _, _ in byID[asset.localIdentifier] = asset }
                onAssetsPicked?(ids.compactMap { byID[$0] })
                gridSelection = []
                gridExpanded = false
                withAnimation(motion) { stage = .collapsed }
                HapticEngine.shared.play(.success)
            }
        )
    }

    @ViewBuilder
    private var librarySurface: some View {
        if let photoLibrary, onAssetsPicked != nil {
            gridView(photoLibrary, expandable: true)
                .frame(height: height)
        } else {
            legacyLibrarySurface
        }
    }

    private var legacyLibrarySurface: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pick photos or videos. Modula only sees what you choose.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            PhotosPicker(
                selection: $pickerItems,
                maxSelectionCount: maxSelectionCount,
                matching: matching
            ) {
                ComposeMediaLibraryPickerLabel(accent: accent, maxSelectionCount: maxSelectionCount)
            }
            .accessibilityIdentifier("\(idPrefix).library.picker")
        }
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
    }

    private func modeFilter(_ mode: ComposeMediaAttachMode) -> Bool {
        if mode == .camera {
            return UIImagePickerController.isSourceTypeAvailable(.camera)
        }
        return true
    }

    private var motion: Animation {
        reduceMotion ? .easeOut(duration: 0.14) : .spring(response: 0.38, dampingFraction: 0.82)
    }
}

private struct ComposeMediaLibraryPickerLabel: View {
    var accent: Color
    var maxSelectionCount: Int

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "photo.stack.fill")
                .font(.title3.weight(.semibold))
            VStack(alignment: .leading, spacing: 2) {
                Text("Choose from Library")
                    .font(.body.weight(.semibold))
                Text(maxSelectionCount > 1 ? "Up to \(maxSelectionCount) items" : "One item")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .foregroundStyle(Color.primary)
        .padding(14)
        .background(accent.opacity(0.18), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(accent.opacity(0.35), lineWidth: 0.9)
        }
    }
}

private struct ComposeGlassIDIfNeeded: ViewModifier {
    var id: String
    var namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if let namespace {
            content.modulaGlassID(id, in: namespace)
        } else {
            content
        }
    }
}
