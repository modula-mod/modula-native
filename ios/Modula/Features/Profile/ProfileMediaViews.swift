import PhotosUI
import SwiftUI
import UIKit

enum ProfileMediaKind: String, Sendable {
    case avatar
    case cover

    var title: String {
        switch self {
        case .avatar: "Profile Photo"
        case .cover: "Cover Photo"
        }
    }

    var cropTitle: String {
        switch self {
        case .avatar: "Edit Photo"
        case .cover: "Reposition Cover"
        }
    }
}

enum ProfileMediaWorkspaceAction: Identifiable {
    case pick(ProfileMediaKind)
    case cropExisting(ProfileMediaKind)
    case remove(ProfileMediaKind)

    var id: String {
        switch self {
        case .pick(let kind): "pick.\(kind.rawValue)"
        case .cropExisting(let kind): "crop.\(kind.rawValue)"
        case .remove(let kind): "remove.\(kind.rawValue)"
        }
    }

    var kind: ProfileMediaKind {
        switch self {
        case .pick(let kind), .cropExisting(let kind), .remove(let kind): kind
        }
    }
}

struct ProfileMediaWorkspace: ViewModifier {
    let profile: ModulaProfile?
    @Binding var action: ProfileMediaWorkspaceAction?
    var onView: (ProfileMediaKind) -> Void

    @Environment(AppEnvironment.self) private var app
    @State private var cropSession: ProfileMediaCropSession?
    @State private var showsLibrary = false
    @State private var showsCamera = false
    @State private var libraryItem: PhotosPickerItem?
    @State private var activeKind: ProfileMediaKind = .avatar

    func body(content: Content) -> some View {
        content
            .confirmationDialog(pickerTitle, isPresented: pickerPresented, titleVisibility: .visible) {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button("Take Photo") { showsCamera = true }
                }
                Button("Choose from Library") { showsLibrary = true }
                if canViewCurrent {
                    Button("View") { onView(currentKind) }
                }
                Button("Cancel", role: .cancel) { action = nil }
            }
            .confirmationDialog(removeTitle, isPresented: removePresented, titleVisibility: .visible) {
                Button("Remove \(currentKind.title)", role: .destructive) {
                    Task {
                        _ = await app.profile.removeMedia(currentKind)
                        action = nil
                    }
                }
                Button("Cancel", role: .cancel) { action = nil }
            }
            .photosPicker(isPresented: $showsLibrary, selection: $libraryItem, matching: .images)
            .onChange(of: libraryItem) { _, item in
                guard let item else { return }
                Task { await loadPickerItem(item) }
            }
            .fullScreenCover(item: $cropSession) { session in
                ProfileMediaCropper(session: session) { cropSession = nil }
            }
            .fullScreenCover(isPresented: $showsCamera) {
                ProfileCameraPicker { data in
                    showsCamera = false
                    if let data {
                        Task { await beginCrop(data: data, kind: currentKind) }
                    }
                    else { action = nil }
                }
            }
            .onChange(of: action?.id) { _, _ in
                handleAction()
            }
            .overlay(alignment: .bottom) {
                if app.profile.mediaBusy {
                    Label("Updating \(currentKind.title)…", systemImage: "arrow.triangle.2.circlepath")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.bottom, 12)
                        .accessibilityIdentifier("profile.media.progress")
                } else if let message = app.profile.actionError {
                    HStack(spacing: 10) {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.primary)
                        Button("Dismiss") { app.profile.clearActionError() }
                            .font(.footnote.weight(.semibold))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 12)
                    .accessibilityIdentifier("profile.media.error")
                }
            }
    }

    private var currentKind: ProfileMediaKind { action?.kind ?? activeKind }

    private var pickerTitle: String {
        switch currentKind {
        case .avatar: "Profile Photo"
        case .cover: "Cover Photo"
        }
    }

    private var removeTitle: String { "Remove \(currentKind.title)?" }

    private var pickerPresented: Binding<Bool> {
        Binding(
            get: {
                if case .pick = action { return true }
                return false
            },
            set: { if !$0, cropSession == nil, !showsLibrary, !showsCamera { action = nil } }
        )
    }

    private var removePresented: Binding<Bool> {
        Binding(
            get: {
                if case .remove = action { return true }
                return false
            },
            set: { if !$0 { action = nil } }
        )
    }

    private var canViewCurrent: Bool {
        switch currentKind {
        case .avatar: profile?.avatarURL != nil
        case .cover: profile?.coverURL != nil
        }
    }

    private func handleAction() {
        guard let action else { return }
        activeKind = action.kind
        switch action {
        case .pick:
            break
        case .cropExisting(let kind):
            Task { await beginCropExisting(kind) }
        case .remove:
            break
        }
    }

    private func loadPickerItem(_ item: PhotosPickerItem) async {
        defer {
            libraryItem = nil
            showsLibrary = false
        }
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            app.profile.setMediaError("Couldn't open that photo.")
            action = nil
            return
        }
        await beginCrop(data: data, kind: currentKind)
    }

    private func beginCropExisting(_ kind: ProfileMediaKind) async {
        let url: URL?
        switch kind {
        case .avatar: url = profile?.avatarURL
        case .cover: url = profile?.coverURL
        }
        guard let url else {
            action = .pick(kind)
            return
        }
        do {
            let data = try await app.client.mediaData(from: url)
            await beginCrop(data: data, kind: kind)
        } catch {
            app.profile.setMediaError("Couldn't load the current photo.")
            action = nil
        }
    }

    private func beginCrop(data: Data, kind: ProfileMediaKind) async {
        do {
            let prepared = try await MediaPreparation.jpegStrippingMetadata(data, maxPixel: kind == .avatar ? 2048 : 2400)
            guard let image = UIImage(data: prepared.data) else {
                throw MediaPreparationError.unsupported
            }
            cropSession = ProfileMediaCropSession(kind: kind, image: image, originalData: prepared.data)
        } catch {
            app.profile.setMediaError("That photo isn't supported.")
            action = nil
        }
    }
}

private struct ProfileMediaCropSession: Identifiable {
    let id = UUID()
    let kind: ProfileMediaKind
    let image: UIImage
    let originalData: Data
}

private struct ProfileMediaCropper: View {
    let session: ProfileMediaCropSession
    var onDismiss: () -> Void

    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var saving = false

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let viewport = viewportSize(in: proxy.size)
                ZStack {
                    Color.black.ignoresSafeArea()
                    imageLayer(viewport: viewport)
                        .frame(width: viewport.width, height: viewport.height)
                        .clipped()
                        .overlay(Rectangle().stroke(.white.opacity(0.35), lineWidth: 1))
                    VStack {
                        Spacer()
                        if let message = app.profile.actionError {
                            Label(message, systemImage: "exclamationmark.triangle.fill")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(.red.opacity(0.78), in: Capsule())
                                .padding(.bottom, 10)
                                .accessibilityIdentifier("profile.media.crop.error")
                        }
                        Text(session.kind == .avatar ? "Drag and pinch to frame your photo." : "Drag and pinch to reposition the cover.")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.78))
                            .padding(.bottom, 18)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle(session.kind.cropTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onDismiss)
                        .disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Saving…" : "Save") {
                        Task { await save() }
                    }
                    .disabled(saving)
                    .accessibilityIdentifier("profile.media.crop.save")
                }
            }
        }
        .statusBarHidden(true)
        .accessibilityIdentifier("profile.media.crop")
    }

    private func imageLayer(viewport: CGSize) -> some View {
        return Image(uiImage: session.image)
            .resizable()
            .scaledToFill()
            .scaleEffect(scale)
            .offset(offset)
            .frame(width: viewport.width, height: viewport.height)
            .contentShape(Rectangle())
            .gesture(dragGesture)
            .simultaneousGesture(pinchGesture)
            .onTapGesture(count: 2) {
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    if scale > 1.05 {
                        scale = 1
                        lastScale = 1
                        offset = .zero
                        lastOffset = .zero
                    } else {
                        scale = 2
                        lastScale = 2
                    }
                }
            }
            .accessibilityHidden(true)
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                offset = CGSize(width: lastOffset.width + value.translation.width, height: lastOffset.height + value.translation.height)
            }
            .onEnded { _ in
                lastOffset = offset
            }
    }

    private var pinchGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                guard !reduceMotion else { return }
                scale = min(max(lastScale * value, 1), 4)
            }
            .onEnded { _ in
                lastScale = scale
            }
    }

    private func viewportSize(in size: CGSize) -> CGSize {
        let aspect = cropAspect
        let width = min(size.width, size.height * aspect)
        let height = width / aspect
        return CGSize(width: width, height: min(height, size.height))
    }

    private var cropAspect: CGFloat {
        switch session.kind {
        case .avatar:
            return 1
        case .cover:
            let width = UIScreen.main.bounds.width
            let height = ProfileFullBleedMetrics.coverHeight(
                sizeClass: nil,
                safeAreaTop: ProfileFullBleedMetrics.windowSafeAreaTop,
                accessibility: false
            )
            return width / max(height, 1)
        }
    }

    private func fillScale(viewport: CGSize) -> CGFloat {
        let imageSize = session.image.size
        guard imageSize.width > 0, imageSize.height > 0 else { return 1 }
        return max(viewport.width / imageSize.width, viewport.height / imageSize.height)
    }

    private func save() async {
        saving = true
        defer { saving = false }
        app.profile.setMediaError(nil)
        let imageSize = session.image.size
        let screen = UIScreen.main.bounds.size
        let viewport = viewportSize(in: screen)
        let fill = fillScale(viewport: viewport)
        let displayed = CGSize(width: imageSize.width * fill * scale, height: imageSize.height * fill * scale)
        let origin = CGPoint(
            x: (viewport.width - displayed.width) / 2 + offset.width,
            y: (viewport.height - displayed.height) / 2 + offset.height
        )
        let visible = CGRect(origin: .zero, size: viewport)
        let imageX = (visible.minX - origin.x) / max(displayed.width, 1)
        let imageY = (visible.minY - origin.y) / max(displayed.height, 1)
        let imageW = visible.width / max(displayed.width, 1)
        let imageH = visible.height / max(displayed.height, 1)
        let normalized = CGRect(x: imageX, y: imageY, width: imageW, height: imageH)
        let maxPixel: CGFloat = session.kind == .avatar ? 1024 : 1600
        do {
            let prepared = try await MediaPreparation.cropJPEG(
                session.originalData,
                normalizedRect: normalized,
                maxPixel: maxPixel
            )
            let ok = await app.profile.uploadMedia(session.kind, image: prepared)
            if ok { onDismiss() }
        } catch {
            app.profile.setMediaError("Couldn't crop that photo.")
        }
    }
}

private struct ProfileCameraPicker: UIViewControllerRepresentable {
    var onComplete: (Data?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onComplete: onComplete) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onComplete: (Data?) -> Void
        init(onComplete: @escaping (Data?) -> Void) { self.onComplete = onComplete }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onComplete(nil)
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let image = (info[.editedImage] ?? info[.originalImage]) as? UIImage
            onComplete(image?.jpegData(compressionQuality: 0.92))
        }
    }
}

extension View {
    func profileMediaWorkspace(
        profile: ModulaProfile?,
        action: Binding<ProfileMediaWorkspaceAction?>,
        onView: @escaping (ProfileMediaKind) -> Void
    ) -> some View {
        modifier(ProfileMediaWorkspace(profile: profile, action: action, onView: onView))
    }
}

struct ProfileMediaEditorRow: View {
    let kind: ProfileMediaKind
    let url: URL?
    let initials: String
    var onView: () -> Void
    var onChange: () -> Void
    var onEdit: () -> Void
    var onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(kind.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                thumbnail
                VStack(alignment: .leading, spacing: 8) {
                    Button(url == nil ? "Add" : "Change", action: onChange)
                    if url != nil {
                        Button("View", action: onView)
                        Button(kind == .cover ? "Reposition" : "Edit", action: onEdit)
                        Button("Remove", role: .destructive, action: onRemove)
                    }
                }
                .buttonStyle(.borderless)
                Spacer()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("profile.edit.media.\(kind.rawValue)")
    }

    @ViewBuilder
    private var thumbnail: some View {
        switch kind {
        case .avatar:
            ModulaAvatar(initials: initials, url: url, size: 64)
        case .cover:
            Group {
                if let url {
                    ModulaRemoteImage(url: url, cacheKey: "profile-cover-thumbnail:\(url.path)", maximumPixelSize: 480) { phase in
                        switch phase {
                        case .success(let image):
                            Image(uiImage: image).resizable().scaledToFill()
                        default:
                            Color.primary.opacity(0.08)
                        }
                    }
                } else {
                    Color.primary.opacity(0.08)
                        .overlay {
                            Image(systemName: "photo")
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .frame(width: 96, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}
