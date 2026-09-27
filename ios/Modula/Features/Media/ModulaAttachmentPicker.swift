import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Native source picker for draft attachments. It creates protected local copies and
/// returns the same attachment contract used by posts, messages, and future modules.
struct ModulaAttachmentPicker: View {
    var onPick: @MainActor (ModulaAttachment) -> Void
    var onFailure: @MainActor (String) -> Void

    @State private var photoSelection: PhotosPickerItem?
    @State private var showsFileImporter = false
    private let draftFiles = PrivateFileStore(domain: .draftMedia)

    var body: some View {
        HStack(spacing: ModulaSpacing.xs) {
            PhotosPicker(selection: $photoSelection, matching: .any(of: [.images, .videos])) {
                Label("Photos", systemImage: "photo.on.rectangle")
                    .frame(minHeight: ModulaLayout.minimumTouch)
            }
            .buttonStyle(.bordered)
            .accessibilityHint("Selects a photo or video for a local draft preview")

            Button("Files", systemImage: "folder") { showsFileImporter = true }
                .buttonStyle(.bordered)
                .frame(minHeight: ModulaLayout.minimumTouch)
        }
        .onChange(of: photoSelection) { _, item in
            guard let item else { return }
            Task { await importPhoto(item) }
        }
        .fileImporter(
            isPresented: $showsFileImporter,
            allowedContentTypes: [.image, .movie, .pdf, .audio, .text, .rtf, .archive, .data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task { await importFile(url) }
            case .failure(let error):
                onFailure(error.localizedDescription)
            }
        }
    }

    @MainActor
    private func importPhoto(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw AttachmentPickerError.unreadable
            }
            let type = item.supportedContentTypes.first
            let id = UUID().uuidString
            let ext = type?.preferredFilenameExtension ?? "data"
            let filename = "\(id).\(ext)"
            try draftFiles.saveData(data, filename: filename)
            let kind = AttachmentKind.resolve(mimeType: type?.preferredMIMEType, filename: filename)
            onPick(ModulaAttachment(
                id: id, kind: kind, remoteURL: nil, localFileURL: draftFiles.url(filename: filename),
                mimeType: type?.preferredMIMEType, filename: filename, byteSize: Int64(data.count)
            ))
        } catch {
            onFailure(error.localizedDescription)
        }
        photoSelection = nil
    }

    @MainActor
    private func importFile(_ source: URL) async {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        do {
            let values = try source.resourceValues(forKeys: [.contentTypeKey, .fileSizeKey])
            let type = values.contentType
            let id = UUID().uuidString
            let storedName = "\(id)-\(source.lastPathComponent)"
            let local = try draftFiles.saveFile(at: source, filename: storedName)
            let kind = AttachmentKind.resolve(mimeType: type?.preferredMIMEType, filename: source.lastPathComponent)
            onPick(ModulaAttachment(
                id: id, kind: kind, remoteURL: nil, localFileURL: local,
                mimeType: type?.preferredMIMEType, filename: source.lastPathComponent,
                byteSize: values.fileSize.map(Int64.init)
            ))
        } catch {
            onFailure(error.localizedDescription)
        }
    }
}

private enum AttachmentPickerError: LocalizedError {
    case unreadable
    var errorDescription: String? { "The selected item could not be read." }
}
