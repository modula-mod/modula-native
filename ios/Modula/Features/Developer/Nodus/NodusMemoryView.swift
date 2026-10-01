import SwiftUI
import UIKit

#if DEBUG
struct NodusMemoryView: View {
    @Environment(AppEnvironment.self) private var app
    @State private var snapshot = NodusMemorySnapshot()
    @State private var query = ""
    @State private var showingAdd = false
    @State private var editing: NodusMemoryItem?
    @State private var confirmingClear = false
    @State private var status: String?

    var body: some View {
        List {
            if let status { Section { Text(status).font(.footnote).foregroundStyle(.secondary) } }
            if !snapshot.suggestions.isEmpty {
                Section("Suggested Memories") {
                    ForEach(snapshot.suggestions) { suggestion in
                        VStack(alignment: .leading, spacing: 7) {
                            Text(suggestion.text)
                            Text("Suggested · confirmation required").font(.caption).foregroundStyle(.secondary)
                            HStack {
                                Button("Add") { Task { _ = try? await app.nodusMemoryStore.approveSuggestion(id: suggestion.id); await refresh() } }
                                    .buttonStyle(.bordered).controlSize(.small)
                                Button("Edit & Add") {
                                    editing = NodusMemoryItem(
                                        id: suggestion.id, scope: suggestion.scope,
                                        conversationID: suggestion.conversationID, kind: suggestion.kind,
                                        text: suggestion.text, source: .suggestion,
                                        createdAt: suggestion.createdAt, updatedAt: suggestion.createdAt,
                                        confirmedAt: suggestion.createdAt, active: true,
                                        sensitivity: suggestion.sensitivity
                                    )
                                }
                                .buttonStyle(.bordered).controlSize(.small)
                                Button("Reject", role: .destructive) {
                                    Task { try? await app.nodusMemoryStore.rejectSuggestion(id: suggestion.id); await refresh() }
                                }
                                .buttonStyle(.bordered).controlSize(.small)
                            }
                        }
                    }
                }
            }
            Section("Memory") {
                if activeItems.isEmpty {
                    Text("No stored Memory").foregroundStyle(.secondary)
                }
                ForEach(activeItems) { item in
                    memoryRow(item)
                }
            }
            if !archivedItems.isEmpty {
                Section("Archived") {
                    ForEach(archivedItems) { item in
                        memoryRow(item)
                    }
                }
            }
            Section {
                Text("Memory is local contextual information. It is not model training data and is retrieved in bounded relevant sets.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Clear All Memory", role: .destructive) { confirmingClear = true }
            }
        }
        .searchable(text: $query, prompt: "Search Memory")
        .modulaSoftScrollEdge()
        .navigationTitle("Memory")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .task { await refresh() }
        .sheet(isPresented: $showingAdd) {
            NodusMemoryEditor(item: nil) { text, kind, scope in
                Task {
                    do {
                        _ = try await app.nodusMemoryStore.add(text: text, kind: kind, scope: scope)
                        status = "Memory added with confirmation"
                        await refresh()
                    } catch { status = error.localizedDescription }
                }
            }
        }
        .sheet(item: $editing) { item in
            NodusMemoryEditor(item: item) { text, kind, _ in
                Task {
                    if snapshot.suggestions.contains(where: { $0.id == item.id }) {
                        _ = try? await app.nodusMemoryStore.approveSuggestion(id: item.id, editedText: text)
                    } else {
                        try? await app.nodusMemoryStore.edit(id: item.id, text: text, kind: kind)
                    }
                    await refresh()
                }
            }
        }
        .alert("Clear all Memory?", isPresented: $confirmingClear) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) { Task { try? await app.nodusMemoryStore.clear(); await refresh() } }
        } message: {
            Text("This permanently removes confirmed Memory and pending suggestions. Chats and Knowledge are unaffected.")
        }
        .accessibilityIdentifier("nodus.memory")
    }

    private var matchingItems: [NodusMemoryItem] {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return snapshot.items.filter { clean.isEmpty || $0.text.lowercased().contains(clean) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private var activeItems: [NodusMemoryItem] { matchingItems.filter(\.active) }
    private var archivedItems: [NodusMemoryItem] { matchingItems.filter { !$0.active } }

    private func memoryRow(_ item: NodusMemoryItem) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(item.text).foregroundStyle(item.active ? .primary : .secondary)
            Text("\(item.kind.displayName) · \(item.scope.rawValue.capitalized) · \(item.active ? "Active" : "Archived")")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button("Delete", systemImage: "trash", role: .destructive) {
                Task { try? await app.nodusMemoryStore.delete(id: item.id); await refresh() }
            }
            if item.active {
                Button("Archive", systemImage: "archivebox") {
                    Task { try? await app.nodusMemoryStore.setActive(id: item.id, active: false); await refresh() }
                }
                .tint(.indigo)
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if !item.active {
                Button("Restore", systemImage: "arrow.uturn.backward") {
                    Task { try? await app.nodusMemoryStore.setActive(id: item.id, active: true); await refresh() }
                }
                .tint(.green)
            }
        }
        .contextMenu {
            Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = item.text }
            Button("Edit", systemImage: "pencil") { editing = item }
            Button(item.active ? "Archive" : "Restore", systemImage: item.active ? "archivebox" : "arrow.uturn.backward") {
                Task { try? await app.nodusMemoryStore.setActive(id: item.id, active: !item.active); await refresh() }
            }
            Button("Delete", systemImage: "trash", role: .destructive) {
                Task { try? await app.nodusMemoryStore.delete(id: item.id); await refresh() }
            }
        }
        .accessibilityIdentifier("nodus.memory.item")
    }

    private func refresh() async { snapshot = await app.nodusMemoryStore.snapshot() }
}

private struct NodusMemoryEditor: View {
    let item: NodusMemoryItem?
    let onSave: (String, NodusMemoryKind, NodusMemoryScope) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var kind = NodusMemoryKind.preference
    @State private var scope = NodusMemoryScope.global

    var body: some View {
        NavigationStack {
            Form {
                TextField("What should Nodus remember?", text: $text, axis: .vertical).lineLimit(3 ... 10)
                Picker("Kind", selection: $kind) {
                    ForEach(NodusMemoryKind.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                Picker("Scope", selection: $scope) {
                    Text("Global").tag(NodusMemoryScope.global)
                    if item?.conversationID != nil { Text("Conversation").tag(NodusMemoryScope.conversation) }
                }
                Text("Credentials, tokens, precise location, financial secrets, and highly sensitive personal data are never suggested automatically.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .navigationTitle(item == nil ? "Add Memory" : "Edit Memory")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(text, kind, scope); dismiss() }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .onAppear {
            if let item { text = item.text; kind = item.kind; scope = item.scope }
        }
    }
}
#endif
