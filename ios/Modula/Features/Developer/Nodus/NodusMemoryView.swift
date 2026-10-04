import SwiftUI
import UIKit

// Ships in Release behind NodusChatFeature; developer-only affordances stay behind
// NodusChatPresentation.developerWorkspace and the DEBUG-only Developer settings routes.
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
                Section {
                    NodusSuggestionCardStack(
                        suggestions: snapshot.suggestions,
                        onAdd: { suggestion in
                            Task { _ = try? await app.nodusMemoryStore.approveSuggestion(id: suggestion.id); await refresh() }
                        },
                        onEdit: { suggestion in
                            editing = NodusMemoryItem(
                                id: suggestion.id, scope: suggestion.scope,
                                conversationID: suggestion.conversationID, kind: suggestion.kind,
                                text: suggestion.text, source: .suggestion,
                                createdAt: suggestion.createdAt, updatedAt: suggestion.createdAt,
                                confirmedAt: suggestion.createdAt, active: true,
                                sensitivity: suggestion.sensitivity
                            )
                        },
                        onReject: { suggestion in
                            Task { try? await app.nodusMemoryStore.rejectSuggestion(id: suggestion.id); await refresh() }
                        }
                    )
                    .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                } header: {
                    Text("Suggested Memories")
                } footer: {
                    Text("Swipe right to add, left to reject. Nothing is saved until you confirm.")
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
/// Tinder-style stack for pending memory suggestions: swipe right to add,
/// left to reject. Buttons and VoiceOver actions do the same thing, and
/// Reduce Motion removes the fling/tilt.
private struct NodusSuggestionCardStack: View {
    let suggestions: [NodusMemorySuggestion]
    var onAdd: (NodusMemorySuggestion) -> Void
    var onEdit: (NodusMemorySuggestion) -> Void
    var onReject: (NodusMemorySuggestion) -> Void
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drag: CGSize = .zero
    @State private var leaving: UUID?

    private let commitDistance: CGFloat = 110

    var body: some View {
        let visible = Array(suggestions.filter { $0.id != leaving }.prefix(3))
        ZStack {
            ForEach(Array(visible.enumerated().reversed()), id: \.element.id) { index, suggestion in
                card(suggestion, isTop: index == 0)
                    .scaleEffect(index == 0 ? 1 : 1 - CGFloat(index) * 0.04, anchor: .bottom)
                    .offset(y: CGFloat(index) * 8)
                    .offset(index == 0 ? drag : .zero)
                    .rotationEffect(.degrees(index == 0 && !reduceMotion ? Double(drag.width / 22) : 0))
                    .allowsHitTesting(index == 0)
                    .accessibilityHidden(index != 0)
                    .zIndex(Double(visible.count - index))
            }
        }
        .padding(.bottom, CGFloat(max(0, visible.count - 1)) * 8)
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.82), value: suggestions.map(\.id))
    }

    private func card(_ suggestion: NodusMemorySuggestion, isTop: Bool) -> some View {
        let progress = min(1, abs(drag.width) / commitDistance)
        return VStack(alignment: .leading, spacing: ModulaSpacing.sm) {
            HStack {
                Text("Suggested")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if isTop, drag.width != 0 {
                    Label(drag.width > 0 ? "Add" : "Reject", systemImage: drag.width > 0 ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(drag.width > 0 ? app.appearance.accent.color : .red)
                        .opacity(progress)
                }
            }
            Text(suggestion.text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: ModulaSpacing.xs) {
                Button("Reject", role: .destructive) { fling(suggestion, add: false) }
                Spacer()
                Button("Edit & Add") { onEdit(suggestion) }
                Button("Add") { fling(suggestion, add: true) }
                    .buttonStyle(.borderedProminent)
                    .tint(app.appearance.accent.color)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(ModulaSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: ModulaRadius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: ModulaRadius.medium, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        )
        .shadow(color: .black.opacity(isTop ? 0.08 : 0.03), radius: 8, y: 3)
        .gesture(swipe(suggestion), including: isTop ? .all : .subviews)
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Add") { fling(suggestion, add: true) }
        .accessibilityAction(named: "Reject") { fling(suggestion, add: false) }
    }

    private func swipe(_ suggestion: NodusMemorySuggestion) -> some Gesture {
        DragGesture(minimumDistance: 14)
            .onChanged { value in
                drag = CGSize(width: value.translation.width, height: value.translation.height * 0.15)
            }
            .onEnded { value in
                let distance = value.translation.width
                let predicted = value.predictedEndTranslation.width
                if abs(distance) > commitDistance || abs(predicted) > commitDistance * 2.2 {
                    fling(suggestion, add: distance > 0)
                } else {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.75)) { drag = .zero }
                }
            }
    }

    private func fling(_ suggestion: NodusMemorySuggestion, add: Bool) {
        HapticEngine.shared.play(add ? .confirmation : .selection)
        let finish = {
            leaving = suggestion.id
            drag = .zero
            add ? onAdd(suggestion) : onReject(suggestion)
        }
        if reduceMotion {
            finish()
        } else {
            withAnimation(.easeIn(duration: 0.18)) {
                drag = CGSize(width: add ? 480 : -480, height: drag.height)
            }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(180))
                finish()
            }
        }
    }
}
// End of Release-shipped Nodus Chat surface.
