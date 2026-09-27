import SwiftUI

private enum CatalogTab: String, CaseIterable, Hashable, Sendable { case following, forYou, modules, links }

struct TabsCatalogPage: View {
    @State private var selection: CatalogTab = .following
    @State private var layout: ModulaTabLayout = .scrollable
    @State private var compact = false
    @State private var showsBadges = true

    private var items: [ModulaTabItem<CatalogTab>] {
        [
            .init(id: .following, title: "Following", systemImage: "person.2", badgeCount: showsBadges ? 3 : nil),
            .init(id: .forYou, title: "For You", systemImage: "sparkles"),
            .init(id: .modules, title: "Modules", systemImage: "shippingbox", showsNotificationDot: showsBadges),
            .init(id: .links, title: "Links", systemImage: "link")
        ]
    }

    var body: some View {
        Form {
            Section("Lab") {
                Picker("Layout", selection: $layout) {
                    ForEach(ModulaTabLayout.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                Toggle("Compact", isOn: $compact)
                Toggle("Badges", isOn: $showsBadges)
            }
            Section("Text + icon + badge") {
                ModulaTabStrip(items: items, selection: $selection, layout: layout, compact: compact)
                    .padding(.vertical, 8)
                Text("Selected: \(selection.rawValue)").font(.caption).foregroundStyle(.secondary)
            }
            Section("Dynamic items") {
                ModulaTabStrip(items: Array(items.prefix(3)), selection: $selection, layout: .equalWidth, compact: true)
            }
        }
        .navigationTitle("Tabs")
    }
}

private enum CatalogSpace: String, CaseIterable, Hashable, Sendable { case following, forYou, modules, friends, work, saved }

struct SpacesCatalogPage: View {
    @State private var selection: CatalogSpace = .following
    @State private var enabled: Set<CatalogSpace> = Set(CatalogSpace.allCases)

    private var spaces: [ModulaSpace<CatalogSpace>] {
        CatalogSpace.allCases.map {
            ModulaSpace(
                id: $0,
                title: $0 == .forYou ? "For You" : $0.rawValue.capitalized,
                systemImage: symbol($0),
                badgeCount: $0 == .work ? 7 : nil,
                showsNotificationDot: $0 == .friends
            )
        }
    }

    var body: some View {
        List {
            Section("Switcher") {
                ModulaSpaceSwitcher(spaces: spaces.filter { enabled.contains($0.id) }, selection: $selection)
                    .padding(.vertical, 8)
            }
            Section("Editor rows") {
                ForEach(spaces) { space in
                    ModulaSpaceEditorRow(space: space, enabled: enabled.contains(space.id)) {
                        if enabled.contains(space.id) { enabled.remove(space.id) } else { enabled.insert(space.id) }
                    }
                }
            }
            Section {
                Text("Spaces remain domain-neutral: feeds, projects, messages, files, and notifications can share the same interaction primitive.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Spaces")
    }

    private func symbol(_ space: CatalogSpace) -> String {
        switch space {
        case .following: "person.2"; case .forYou: "sparkles"; case .modules: "shippingbox"
        case .friends: "person.3"; case .work: "briefcase"; case .saved: "bookmark"
        }
    }
}

struct SelectionCatalogPage: View {
    private let rows = ["Messages", "Notifications", "Vault Notes", "Media", "Saved items"]
    @State private var selection = ModulaSelectionState<String>()

    var body: some View {
        VStack(spacing: ModulaSpacing.sm) {
            HStack {
                Button("Select") { selection.enter() }
                Button("Select all") { selection.selectAll(rows) }
                Button("Deselect all") { selection.deselectAll() }
                Spacer()
            }
            .buttonStyle(.bordered)
            .padding(.horizontal)

            List(rows, id: \.self) { row in
                ModulaSelectableRow(id: row, selection: selection, onOpen: {}) {
                    Label(row, systemImage: "doc.text")
                }
            }

            if selection.isActive {
                ModulaSelectionToolbar(
                    count: selection.selectedIDs.count,
                    actions: [
                        .init(id: "share", title: "Share", systemImage: "square.and.arrow.up"),
                        .init(id: "delete", title: "Delete", systemImage: "trash", role: .destructive)
                    ],
                    onAction: { _ in },
                    onClose: { selection.clear() }
                )
                .padding()
            }
        }
        .navigationTitle("Selection")
    }
}

struct IndicatorsCatalogPage: View {
    @State private var count = 7.0

    var body: some View {
        Form {
            Section("Count lab") {
                Slider(value: $count, in: 0...120, step: 1)
                HStack(spacing: 16) {
                    ModulaUnreadIndicator(count: Int(count), tone: .accent)
                    ModulaUnreadIndicator(count: Int(count), tone: .neutral)
                    ModulaUnreadIndicator(count: Int(count), tone: .warning)
                    ModulaUnreadIndicator(count: Int(count), tone: .error)
                }
            }
            Section("Dots and presence") {
                HStack(spacing: 20) {
                    ModulaNotificationDot()
                    ModulaNotificationDot(tone: .muted)
                    ForEach(ModulaPresence.allCases, id: \.self) { ModulaPresenceIndicator(presence: $0) }
                }
            }
            Section("Badges") {
                ViewThatFits {
                    HStack {
                        ModulaBadge(title: "Selected", symbol: "checkmark", style: .filled, selected: true)
                        ModulaBadge(title: "Muted", symbol: "bell.slash", tone: .muted, style: .tinted)
                        ModulaBadge(title: "Warning", symbol: "exclamationmark.triangle", tone: .warning, style: .outlined)
                    }
                    VStack(alignment: .leading) {
                        ModulaBadge(title: "Selected", symbol: "checkmark", style: .filled, selected: true)
                        ModulaBadge(title: "Muted", symbol: "bell.slash", tone: .muted, style: .tinted)
                    }
                }
            }
        }
        .navigationTitle("Indicators")
    }
}
