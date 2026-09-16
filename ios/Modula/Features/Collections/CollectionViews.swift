import SwiftUI

struct CollectionsView: View {
    @Environment(AppEnvironment.self) private var app
    @State private var showCreate = false
    @State private var newName = ""

    var body: some View {
        List {
            Section {
                ForEach(app.collections.collections.filter(\.isDefault)) { collection in
                    NavigationLink(value: AppRoute.collections(.collection(collection.id))) {
                        CollectionCard(collection: collection)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(collection.name), \(collection.itemCount) saved items")
                }
            }
            Section {
                ForEach(app.collections.userCollections) { collection in
                    NavigationLink(value: AppRoute.collections(.collection(collection.id))) {
                        CollectionCard(collection: collection)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(collection.name), \(collection.itemCount) saved items")
                }
                .onDelete(perform: delete)
            } footer: {
                Text(app.collections.capabilities.serverCollections
                     ? "Collections sync with your account."
                     : "Stored on this iPhone. Not synced to Greenfield.")
            }
        }
        .navigationTitle("Collections")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showCreate = true
                    HapticEngine.shared.play(.contextOpen)
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("New Collection")
            }
        }
        .sheet(isPresented: $showCreate) {
            NavigationStack {
                Form {
                    TextField("Name", text: $newName)
                    Text("Stored on this iPhone")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .navigationTitle("New Collection")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showCreate = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Create") {
                            _ = app.collections.create(name: newName)
                            newName = ""
                            showCreate = false
                            HapticEngine.shared.play(.confirmation)
                        }
                        .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .accessibilityIdentifier("collections.root")
    }

    private func delete(at offsets: IndexSet) {
        let deletable = app.collections.userCollections
        for index in offsets {
            guard index < deletable.count else { continue }
            app.collections.delete(id: deletable[index].id)
            HapticEngine.shared.play(.warning)
        }
    }
}

struct CollectionDetailView: View {
    let collectionID: String
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        Group {
            if let collection = app.collections.collections.first(where: { $0.id == collectionID }) {
                List {
                    Section {
                        Text(collection.storage == .local ? "Stored on this iPhone" : "Synced")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Section("Items") {
                        if collection.itemIDs.isEmpty {
                            Text("No items yet")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(collection.itemIDs, id: \.self) { id in
                                Text(id)
                                    .font(.body.monospaced())
                            }
                        }
                    }
                }
                .navigationTitle(collection.name)
                .accessibilityLabel("\(collection.name), \(collection.itemCount) saved items")
            } else {
                ModulaEmptyState(title: "Collection", message: "This collection is no longer available.", symbol: "rectangle.stack")
            }
        }
        .accessibilityIdentifier("collections.detail")
    }
}

struct CollectionCard: View {
    let collection: ModulaCollection

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: collection.isDefault ? "bookmark.fill" : "rectangle.stack")
                .font(.body.weight(.semibold))
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(collection.name)
                    .font(.body.weight(.semibold))
                Text("\(collection.itemCount) items · \(collection.storage == .local ? "On This Device" : "Synced")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(collection.name), \(collection.itemCount) saved items")
    }
}

struct CollectionPicker: View {
    let postID: String
    var onDone: (() -> Void)?
    @Environment(AppEnvironment.self) private var app
    @State private var newName = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Collections") {
                    ForEach(app.collections.collections.filter { !$0.isDefault }) { collection in
                        Button {
                            app.collections.add(postID: postID, to: collection.id)
                            HapticEngine.shared.play(.confirmation)
                            onDone?()
                            dismiss()
                        } label: {
                            CollectionCard(collection: collection)
                        }
                    }
                }
                Section("New Collection") {
                    HStack {
                        TextField("Name", text: $newName)
                        Button("Add") {
                            if let created = app.collections.create(name: newName) {
                                app.collections.add(postID: postID, to: created.id)
                                newName = ""
                                HapticEngine.shared.play(.confirmation)
                                onDone?()
                                dismiss()
                            }
                        }
                        .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    Text("Stored on this iPhone")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Save to Collection")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .accessibilityIdentifier("collections.picker")
    }
}
