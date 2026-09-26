import SwiftUI
import UniformTypeIdentifiers

#if DEBUG
struct NodusKnowledgeView: View {
    @Environment(AppEnvironment.self) private var app
    @State private var snapshot = NodusKnowledgeSnapshot()
    @State private var query = ""
    @State private var results: [NodusKnowledgeMatch] = []
    @State private var showingImporter = false
    @State private var showingTextEntry = false
    @State private var showingCollectionEntry = false
    @State private var collectionName = ""
    @State private var importCollectionID = NodusKnowledgeStore.myKnowledgeCollectionID
    @State private var status: String?

    var body: some View {
        List {
            if let status { Section { Text(status).font(.footnote).foregroundStyle(.secondary) } }
            Section("Collections") {
                ForEach(snapshot.collections) { collection in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Label(collection.name, systemImage: collection.isReadOnly ? "lock.fill" : "folder")
                            Spacer()
                            Text("\(snapshot.items.filter { $0.collectionID == collection.id }.count)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if let version = collection.version {
                            Text("\(version) · \(collection.sourceCommit?.prefix(8) ?? "—")")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                Button("New Collection", systemImage: "folder.badge.plus") { showingCollectionEntry = true }
            }
            Section("Knowledge") {
                if query.isEmpty {
                    ForEach(snapshot.items) { item in itemRow(item) }
                } else if results.isEmpty {
                    Text("No matching Knowledge").foregroundStyle(.secondary)
                } else {
                    ForEach(results) { match in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(match.item.title).font(.body.weight(.medium))
                            Text(match.chunk.text).font(.caption).foregroundStyle(.secondary).lineLimit(4)
                            Text("\(match.collection.name) · \(match.item.sourceName)\(match.chunk.location.map { " · \($0)" } ?? "")")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "Search Knowledge")
        .onChange(of: query) { _, value in Task { await search(value) } }
        .modulaSoftScrollEdge()
        .navigationTitle("Knowledge")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Add Text", systemImage: "text.badge.plus") { showingTextEntry = true }
                    Button("Import Markdown, TXT, PDF, or JSON", systemImage: "doc.badge.plus") { showingImporter = true }
                } label: { Image(systemName: "plus") }
            }
        }
        .task { await refresh() }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.plainText, .pdf, .json],
            allowsMultipleSelection: false
        ) { result in Task { await importFile(result) } }
        .sheet(isPresented: $showingTextEntry) {
            NodusTextKnowledgeSheet(collections: snapshot.collections.filter { !$0.isReadOnly }) { title, text, collectionID in
                Task {
                    do {
                        _ = try await app.nodusKnowledgeStore.add(
                            title: title, sourceType: .pastedText, sourceName: "Pasted text",
                            text: text, collectionID: collectionID
                        )
                        status = "Knowledge added locally"
                        await refresh()
                    } catch { status = error.localizedDescription }
                }
            }
        }
        .alert("New Collection", isPresented: $showingCollectionEntry) {
            TextField("Name", text: $collectionName)
            Button("Cancel", role: .cancel) { collectionName = "" }
            Button("Create") {
                let name = collectionName
                collectionName = ""
                Task { _ = try? await app.nodusKnowledgeStore.createCollection(name: name); await refresh() }
            }
        }
        .accessibilityIdentifier("nodus.knowledge")
    }

    private func itemRow(_ item: NodusKnowledgeItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(item.title).font(.body.weight(.medium))
                Spacer()
                Text(item.sourceType.rawValue.uppercased()).font(.caption2).foregroundStyle(.secondary)
            }
            Text(item.sourceName).font(.caption).foregroundStyle(.secondary)
            Text(item.text).font(.caption2).foregroundStyle(.secondary).lineLimit(3)
            if snapshot.collections.first(where: { $0.id == item.collectionID })?.isReadOnly != true {
                Button("Delete", role: .destructive) {
                    Task {
                        try? await app.nodusKnowledgeStore.deleteItem(id: item.id)
                        await refresh()
                    }
                }
                .font(.caption)
            }
        }
        .padding(.vertical, 2)
    }

    private func refresh() async {
        snapshot = await app.nodusKnowledgeStore.snapshot()
        if !query.isEmpty { await search(query) }
    }

    private func search(_ value: String) async {
        results = value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? [] : await app.nodusKnowledgeStore.search(value, topK: 20)
    }

    private func importFile(_ result: Result<[URL], any Error>) async {
        do {
            guard let url = try result.get().first else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            let extracted = try NodusKnowledgeImporter().extract(from: url)
            _ = try await app.nodusKnowledgeStore.add(
                title: extracted.title, sourceType: extracted.sourceType,
                sourceName: extracted.sourceName, text: extracted.text,
                collectionID: importCollectionID, locations: extracted.locations
            )
            status = "Imported \(extracted.sourceName)"
            await refresh()
        } catch {
            status = error.localizedDescription
        }
    }
}

private struct NodusTextKnowledgeSheet: View {
    let collections: [NodusKnowledgeCollection]
    let onSave: (String, String, UUID) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var text = ""
    @State private var collectionID = NodusKnowledgeStore.myKnowledgeCollectionID

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $title)
                Picker("Collection", selection: $collectionID) {
                    ForEach(collections) { Text($0.name).tag($0.id) }
                }
                TextField("Knowledge text", text: $text, axis: .vertical).lineLimit(6 ... 20)
            }
            .navigationTitle("Add Knowledge")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { onSave(title, text, collectionID); dismiss() }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .onAppear { if let first = collections.first { collectionID = first.id } }
    }
}
#endif
