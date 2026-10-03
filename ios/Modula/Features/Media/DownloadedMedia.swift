import Foundation
import QuickLook
import SwiftUI
import UniformTypeIdentifiers

struct DownloadedMedia: Identifiable, Hashable, Sendable {
    var id: String { filename }
    let filename: String
    let url: URL
    let title: String
    let kind: String
    let bytes: Int64
    let savedAt: Date

    var symbol: String {
        switch kind {
        case "image": "photo"
        case "video": "film"
        case "audio", "voice": "waveform"
        case "pdf": "doc.richtext"
        default: "doc"
        }
    }
}

/// Small JSON index beside the downloaded files so the Downloads page can show a
/// real name and kind. Files without an entry (older downloads) are still listed.
struct DownloadedMediaIndex: Sendable {
    struct Entry: Codable, Sendable { var title: String?; var kind: String; var mimeType: String?; var savedAt: Date }
    static let indexFilename = "downloads-index.json"

    let store: PrivateFileStore

    private func read() -> [String: Entry] {
        guard let data = try? store.loadData(filename: Self.indexFilename) else { return [:] }
        return (try? JSONDecoder().decode([String: Entry].self, from: data)) ?? [:]
    }

    private func write(_ index: [String: Entry]) {
        guard let data = try? JSONEncoder().encode(index) else { return }
        try? store.saveData(data, filename: Self.indexFilename)
    }

    func record(filename: String, title: String?, kind: String, mimeType: String?, at date: Date = Date()) {
        var index = read()
        index[filename] = Entry(title: title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank, kind: kind, mimeType: mimeType, savedAt: date)
        write(index)
    }

    func list() -> [DownloadedMedia] {
        let index = read()
        let directory = store.directoryURL
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]) else { return [] }
        return files.compactMap { url -> DownloadedMedia? in
            let name = url.lastPathComponent
            guard name != Self.indexFilename, let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true else { return nil }
            let entry = index[name]
            let kind = entry?.kind ?? Self.kind(forExtension: url.pathExtension)
            return DownloadedMedia(
                filename: name,
                url: url,
                title: entry?.title ?? Self.fallbackTitle(kind: kind, ext: url.pathExtension),
                kind: kind,
                bytes: Int64(values.fileSize ?? 0),
                savedAt: entry?.savedAt ?? values.contentModificationDate ?? .distantPast
            )
        }
        .sorted { $0.savedAt > $1.savedAt }
    }

    func remove(filename: String) throws {
        guard filename != Self.indexFilename, !filename.contains("/") else { return }
        try store.remove(filename: filename)
        var index = read()
        index[filename] = nil
        write(index)
    }

    func removeAll() throws -> Int64 {
        let items = list()
        for item in items { try store.remove(filename: item.filename) }
        try store.remove(filename: Self.indexFilename)
        return items.reduce(0) { $0 + $1.bytes }
    }

    static func kind(forExtension ext: String) -> String {
        guard let type = UTType(filenameExtension: ext.lowercased()) else { return "file" }
        if type.conforms(to: .image) { return "image" }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return "video" }
        if type.conforms(to: .audio) { return "audio" }
        if type.conforms(to: .pdf) { return "pdf" }
        return "file"
    }

    static func fallbackTitle(kind: String, ext: String) -> String {
        let label = switch kind {
        case "image": "Photo"
        case "video": "Video"
        case "audio", "voice": "Audio"
        case "pdf": "PDF"
        default: "File"
        }
        return ext.isEmpty ? label : "\(label) (.\(ext.lowercased()))"
    }
}

private extension String {
    var nilIfBlank: String? { isEmpty ? nil : self }
}

// MARK: - Settings → Data & Storage → Downloads

struct MediaDownloadsView: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var items: [DownloadedMedia] = []
    @State private var loaded = false
    @State private var preview: URL?
    @State private var confirmClear = false
    @State private var message: String?

    private var totalBytes: Int64 { items.reduce(0) { $0 + $1.bytes } }

    var body: some View {
        List {
            if loaded && items.isEmpty {
                ModulaEmptyState(title: "No downloads", message: "Photos, videos, audio and files you open from posts and messages are kept here for offline viewing.", symbol: "arrow.down.to.line")
                    .listRowBackground(Color.clear)
            } else {
                Section {
                    LabeledContent("On this iPhone", value: ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file))
                    LabeledContent("Items", value: items.count.formatted())
                } footer: {
                    Text("Downloads are private to Modula, excluded from iCloud backup, and re-download when you open them again.")
                }
                Section("Files") {
                    ForEach(items) { item in
                        Button { preview = item.url } label: { row(item) }
                            .buttonStyle(.plain)
                            .swipeActions {
                                Button("Delete", role: .destructive) { Task { await delete(item) } }
                            }
                            .contextMenu {
                                ShareLink(item: item.url) { Label("Share", systemImage: "square.and.arrow.up") }
                                Button("Delete", systemImage: "trash", role: .destructive) { Task { await delete(item) } }
                            }
                            .accessibilityAction(named: Text("Delete")) { Task { await delete(item) } }
                    }
                }
                Section {
                    Button("Delete All Downloads", role: .destructive) { confirmClear = true }
                        .disabled(items.isEmpty)
                }
            }
            if let message {
                Text(message).font(.footnote).foregroundStyle(.secondary).listRowBackground(Color.clear)
            }
        }
        .animation(ModulaMotion.animation(.contentTransition, personality: app.appearance.motion, reduceMotion: reduceMotion), value: items)
        .modulaSoftScrollEdge()
        .navigationTitle("Downloads")
        .navigationBarTitleDisplayMode(.inline)
        .quickLookPreview($preview)
        .task { await reload() }
        .refreshable { await reload() }
        .confirmationDialog("Delete all downloads?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Delete \(ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file))", role: .destructive) { Task { await clear() } }
        } message: {
            Text("They’ll download again when you open them.")
        }
    }

    private func row(_ item: DownloadedMedia) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.symbol)
                .font(.title3)
                .foregroundStyle(app.appearance.accent.color)
                .frame(width: 36, height: 36)
                .background(app.appearance.accent.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.subheadline.weight(.medium)).lineLimit(1)
                Text("\(ByteCountFormatter.string(fromByteCount: item.bytes, countStyle: .file)) · \(item.savedAt.formatted(.relative(presentation: .named)))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens a preview")
    }

    private func reload() async {
        items = await app.attachmentDownloads.listDownloads()
        loaded = true
    }

    private func delete(_ item: DownloadedMedia) async {
        do {
            try await app.attachmentDownloads.removeDownload(item)
            HapticEngine.shared.play(.confirmation)
            message = nil
        } catch {
            message = "Couldn’t delete \(item.title)."
        }
        await reload()
    }

    private func clear() async {
        do {
            let freed = try await app.attachmentDownloads.removeAllDownloads()
            message = "Freed \(ByteCountFormatter.string(fromByteCount: freed, countStyle: .file))."
            HapticEngine.shared.play(.success)
        } catch {
            message = "Some downloads couldn’t be deleted."
        }
        await reload()
    }
}
