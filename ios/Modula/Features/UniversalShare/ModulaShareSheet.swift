import SwiftUI

struct ModulaShareSheet: View {
    let payload: SharePayload
    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var showCollectionPicker = false
    @State private var showPeoplePicker = false
    @State private var peopleMode: PeoplePickerMode = .message
    @State private var copied = false
    @State private var showCode = false

    private var destinations: [ShareDestination] {
        ShareDestinationRegistry.destinations(
            for: payload,
            messagingSend: app.messaging.capabilities.send,
            inMailCompose: app.inMail.capabilities.send,
            collectionsAvailable: app.collections.capabilities.localCollections
        )
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    SharePreview(payload: payload)
                }
                Section("Share to") {
                    ForEach(destinations) { destination in
                        ShareDestinationRow(destination: destination) {
                            handle(destination)
                        }
                    }
                }
            }
            .modulaSoftScrollEdge()
            .navigationTitle("Share")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .keyboardShortcut(.escape, modifiers: [])
                }
            }
            .overlay(alignment: .bottom) {
                if copied {
                    Text("Link copied")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.bottom, 12)
                        .accessibilityLabel("Link copied")
                }
            }
        }
        .sheet(isPresented: $showCode) {
            ModulaCodeView(subject: ModulaCodeSubject(payload: payload)) { showCode = false }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showCollectionPicker) {
            if case .post(let id, _, _, _) = payload {
                CollectionPicker(postID: id)
            }
        }
        .sheet(isPresented: $showPeoplePicker) {
            PeoplePicker(mode: peopleMode, selectionLimit: 1) { people in
                guard let person = people.first else { return }
                switch peopleMode {
                case .message:
                    // Capability already gated; open new message with identity context via route.
                    app.navigation.open(.messages(.new))
                    app.navigation.flash("Message \(person.displayName)", symbol: "bubble.left")
                case .inMail:
                    var draft = ShareCoordinator.inMailPrefill(for: payload)
                    draft.toHandle = person.handle ?? person.id
                    app.inMail.draft = draft
                    app.navigation.open(.messages(.inMail(.compose)))
                case .share:
                    break
                }
            }
        }
        .accessibilityIdentifier("share.universal")
    }

    private func handle(_ destination: ShareDestination) {
        switch destination.kind {
        case .copyLink:
            UIPasteboard.general.string = ShareCoordinator.copyLink(payload)
            copied = true
            HapticEngine.shared.play(.confirmation)
            Task {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                copied = false
            }
        case .systemShare:
            HapticEngine.shared.play(.confirmation)
            // Keep System Share always available via the in-sheet ShareLink row below;
            // also surface the canonical URL through the existing share presentation.
            dismiss()
            if case .post(let id, _, _, _) = payload {
                app.navigation.presented = .share(.post(id, .root))
            } else if case .profile(let identity, _, _, _) = payload {
                if identity == "me" {
                    app.navigation.presented = .share(.me(.overview))
                } else {
                    app.navigation.presented = .share(.profile(identity, .overview))
                }
            } else if case .module(let id, _, _) = payload {
                app.navigation.presented = .share(.productHub(.module(id, .overview)))
            } else {
                app.navigation.flash(ShareCoordinator.copyLink(payload), symbol: "link")
            }
        case .messages:
            peopleMode = .message
            showPeoplePicker = true
        case .inMail:
            peopleMode = .inMail
            showPeoplePicker = true
        case .saveToCollection:
            showCollectionPicker = true
        case .qr:
            HapticEngine.shared.play(.selection)
            showCode = true
        }
    }
}

struct SharePreview: View {
    let payload: SharePayload

    var body: some View {
        HStack(spacing: 12) {
            previewGlyph
                .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text(payload.title)
                    .font(.body.weight(.semibold))
                    .lineLimit(2)
                Text(payload.canonicalURL.absoluteString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Share preview, \(payload.title)")
        .accessibilityIdentifier("share.preview")
    }

    @ViewBuilder
    private var previewGlyph: some View {
        switch payload {
        case .profile(_, _, _, _):
            ModulaAvatar(initials: String(payload.title.prefix(1)), size: 48)
        case .post(_, _, _, let hasMedia):
            Image(systemName: hasMedia ? "photo" : "text.alignleft")
                .font(.title3)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        case .module:
            Image(systemName: "shippingbox")
                .font(.title3)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        case .link:
            Image(systemName: "link")
                .font(.title3)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}

typealias ModulaSharePreview = SharePreview
typealias ModulaShareDestination = ShareDestination

struct ShareDestinationRow: View {
    let destination: ShareDestination
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(destination.title)
                    if let subtitle = destination.subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } icon: {
                Image(systemName: destination.icon.systemName)
            }
        }
        .accessibilityLabel(destination.title)
        .accessibilityHint(destination.subtitle ?? "")
        .accessibilityIdentifier("share.destination.\(destination.kind.rawValue)")
    }
}

typealias ModulaShareActionRow = ShareDestinationRow

enum PeoplePickerMode: Sendable {
    case message
    case inMail
    case share
}

struct PeoplePickerPerson: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let handle: String?
}

struct PeoplePicker: View {
    var mode: PeoplePickerMode
    var selectionLimit: Int = 1
    var onSelect: ([PeoplePickerPerson]) -> Void

    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selection: Set<String> = []

    /// Device-local recent recipients — IDs only, never message content.
    @State private var recentIDs: [String] = PeopleRecentsStore.load()

    private var results: [PeoplePickerPerson] {
        // Reuse Discover/profile search surfaces — no new people API.
        let fromList = app.discover.people.items
        let fromDashboard = app.discover.trending.dashboard?.people ?? []
        let merged = fromList.isEmpty ? fromDashboard : fromList
        let mapped = merged.map {
            PeoplePickerPerson(id: $0.id, displayName: $0.displayName, handle: $0.handle)
        }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return mapped }
        return mapped.filter {
            $0.displayName.lowercased().contains(trimmed)
                || ($0.handle?.lowercased().contains(trimmed) ?? false)
        }
    }

    private var recentPeople: [PeoplePickerPerson] {
        let all = Dictionary(uniqueKeysWithValues: results.map { ($0.id, $0) })
        return recentIDs.compactMap { all[$0] }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ModulaSearchField(text: $query, prompt: "Search people")
                }
                if query.isEmpty, !recentPeople.isEmpty {
                    Section("Recent") {
                        ForEach(recentPeople) { person in
                            PeoplePickerRow(person: person, selected: selection.contains(person.id)) {
                                toggle(person)
                            }
                        }
                    }
                }
                Section(query.isEmpty ? "People" : "Search results") {
                    ForEach(results) { person in
                        PeoplePickerRow(person: person, selected: selection.contains(person.id)) {
                            toggle(person)
                        }
                    }
                }
            }
            .modulaSoftScrollEdge()
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Select") {
                        let people = results.filter { selection.contains($0.id) }
                        PeopleRecentsStore.record(ids: people.map(\.id))
                        onSelect(people)
                        dismiss()
                    }
                    .disabled(selection.isEmpty)
                }
            }
        }
        .accessibilityIdentifier("people.picker")
    }

    private var title: String {
        switch mode {
        case .message: "New Message"
        case .inMail: "In-Mail"
        case .share: "Share with"
        }
    }

    private func toggle(_ person: PeoplePickerPerson) {
        if selection.contains(person.id) {
            selection.remove(person.id)
        } else if selectionLimit == 1 {
            selection = [person.id]
        } else if selection.count < selectionLimit {
            selection.insert(person.id)
        }
        HapticEngine.shared.play(.selection)
    }
}

struct PeoplePickerRow: View {
    let person: PeoplePickerPerson
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ModulaAvatar(initials: String(person.displayName.prefix(1)), size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(person.displayName)
                        .font(.body.weight(.medium))
                    if let handle = person.handle {
                        Text("@\(handle)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.tint)
                }
            }
        }
        .accessibilityLabel(person.displayName)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }
}

enum PeopleRecentsStore {
    private static let key = "n4d.people.recents"
    private static let limit = 12

    static func load() -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    static func record(ids: [String]) {
        var next = load().filter { !ids.contains($0) }
        next.insert(contentsOf: ids, at: 0)
        if next.count > limit { next = Array(next.prefix(limit)) }
        UserDefaults.standard.set(next, forKey: key)
    }
}
