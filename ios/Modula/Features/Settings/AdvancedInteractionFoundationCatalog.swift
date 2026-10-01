import SwiftUI

struct ContextCatalogPage: View {
    @State private var latestAction = "None"
    @State private var previewPresented = false

    private var actions: [ModulaContextAction] {
        [
            .init(id: "save", title: "Save", systemImage: "bookmark"),
            .init(id: "disabled", title: "Unavailable", systemImage: "lock", role: .disabled),
            .init(
                id: "more",
                title: "More",
                systemImage: "ellipsis.circle",
                children: [
                    .init(id: "copy", title: "Copy", systemImage: "doc.on.doc"),
                    .init(id: "delete", title: "Delete", systemImage: "trash", role: .destructive)
                ]
            )
        ]
    }

    private var groups: [ModulaContextActionGroup] {
        [
            .init(id: "organize", title: "Organize", actions: [
                .init(id: "pin", title: "Pin", systemImage: "pin"),
                .init(id: "move", title: "Move", systemImage: "folder")
            ]),
            .init(id: "manage", title: "Manage", actions: [
                .init(id: "mute", title: "Mute", systemImage: "bell.slash"),
                .init(id: "remove", title: "Remove", systemImage: "trash", role: .destructive)
            ])
        ]
    }

    private var longActions: [ModulaContextAction] {
        (1...7).map {
            .init(id: "long-\($0)", title: "Long-content action \($0)", systemImage: "list.number")
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: ModulaSpacing.md) {
                CatalogLabSection(title: "Simple Context Menu", note: "Long press. VoiceOver exposes the same actions.") {
                    Text("Latest action: \(latestAction)").font(.caption).foregroundStyle(.secondary)
                    Text("Long-press this source")
                        .frame(maxWidth: .infinity, minHeight: 88)
                        .background(TintShapeStyle().opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                        .modulaContextMenu(actions: actions) { latestAction = $0.title }
                }
                CatalogLabSection(title: "Context Menu + Preview") {
                    Button("Open preview") { previewPresented = true }
                        .buttonStyle(.borderedProminent)
                    Text("The preview uses the shared overlay host and elevated Modula material.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                CatalogLabSection(title: "Context Menu + Groups") {
                    ModulaContextMenu(actions: [], groups: groups, onSelect: { latestAction = $0.title }) {
                        Label("Open grouped actions", systemImage: "square.grid.2x2")
                            .frame(maxWidth: .infinity, minHeight: ModulaLayout.minimumTouch)
                    }
                }
                CatalogLabSection(
                    title: "Long Content + Edge Placement",
                    note: "Long-press the bottom source, scrub the action list, or dismiss interactively. Reduce Motion substitutes opacity transitions."
                ) {
                    ModulaContextHost(
                        actions: longActions,
                        placement: .bottom,
                        dismissBehavior: .interactive,
                        onSelect: { latestAction = $0.title }
                    ) {
                        Label("Edge source", systemImage: "hand.tap")
                            .frame(maxWidth: .infinity, minHeight: ModulaLayout.minimumTouch)
                            .background(TintShapeStyle().opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                    } preview: {
                        Text("A deliberately longer preview verifies wrapping, Dynamic Type, bottom-edge placement, and bounded actions without clipping.")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(minHeight: 360)
                }
            }.padding()
        }
        .modulaOverlay(isPresented: $previewPresented, presentation: .modal) {
            VStack(alignment: .leading, spacing: 14) {
                Label("Elevated preview", systemImage: "sparkles")
                    .font(.headline)
                Text("Untrusted content never receives authority from presentation context.")
                    .font(.body)
                Button("Dismiss") { previewPresented = false }
            }
            .padding(20)
            .frame(maxWidth: 320)
            .modulaMaterial(.floating, in: RoundedRectangle(cornerRadius: ModulaRadius.large), depth: .overlay)
        }
        .navigationTitle("Context")
    }
}

struct ReactionsCatalogPage: View {
    enum Reaction: String, CaseIterable, Hashable, Sendable { case like, love, celebrate, insight, laugh, surprise }
    @State private var selection: Reaction? = .love
    @State private var compact = false
    @State private var counts = true

    private var items: [ModulaReactionItem<Reaction>] {
        Reaction.allCases.map { reaction in
            ModulaReactionItem(
                id: reaction,
                title: reactionName(reaction),
                systemImage: reactionSymbol(reaction),
                count: counts ? (reaction == .love ? 24 : 3) : nil
            )
        }
    }

    var body: some View {
        Form {
            Section("Lab") {
                Toggle("Compact", isOn: $compact)
                Toggle("Counts", isOn: $counts)
                Text("Selected: \(selection.map(reactionName) ?? "None")")
            }
            Section("Tap, press, and drag") {
                ModulaReactionBar(
                    items: items,
                    selectedID: selection,
                    compact: compact,
                    maximumVisibleItems: 5,
                    onSelect: { selection = $0 },
                    onOverflow: { selection = .surprise }
                )
                    .padding(.vertical, 12)
                Text("Drag horizontally across reactions, then release to commit. VoiceOver users can select each reaction as a button.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Reactions")
    }

    private func reactionName(_ reaction: Reaction) -> String {
        switch reaction {
        case .like: "Like"; case .love: "Love"; case .celebrate: "Celebrate"
        case .insight: "Insightful"; case .laugh: "Laugh"; case .surprise: "Surprise"
        }
    }

    private func reactionSymbol(_ reaction: Reaction) -> String {
        switch reaction {
        case .like: "hand.thumbsup"; case .love: "heart"; case .celebrate: "party.popper"
        case .insight: "lightbulb"; case .laugh: "face.smiling"; case .surprise: "exclamationmark.bubble"
        }
    }
}

struct OverlaysCatalogPage: View {
    @State private var modal = false
    @State private var bottom = false
    @State private var floating = false

    var body: some View {
        List {
            Section("Presentations") {
                Button("Modal overlay") { modal = true }
                Button("Bottom overlay") { bottom = true }
                Button("Floating overlay") { floating = true }
            }
            Section("Contract") {
                Text("The host owns z-order, background, focus, interactive dismissal, safe-area behavior, and reduced-motion transitions—not navigation.")
            }
        }
        .modulaOverlay(isPresented: $modal, presentation: .modal) { overlayCard("Modal", binding: $modal) }
        .modulaOverlay(isPresented: $bottom, presentation: .bottom) { overlayCard("Bottom", binding: $bottom).padding() }
        .modulaOverlay(isPresented: $floating, presentation: .floating) { overlayCard("Floating", binding: $floating) }
        .navigationTitle("Overlays")
    }

    private func overlayCard(_ title: String, binding: Binding<Bool>) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "square.stack.3d.up").font(.largeTitle)
            Text(title).font(.headline)
            Button("Close") { binding.wrappedValue = false }
        }
        .padding(24)
        .frame(maxWidth: 300)
        .modulaMaterial(.floating, in: RoundedRectangle(cornerRadius: ModulaRadius.large), depth: .overlay)
    }
}

struct SheetsCatalogPage: View {
    @State private var sheetPresented = false
    @State private var detent: ModulaSheetDetent = .medium
    @State private var scrollable = false
    @State private var dismissible = true
    @State private var backgroundInteraction = false
    @State private var morphPresented = false

    var body: some View {
        ModulaMorphSheetHost(isPresented: $morphPresented) {
            Form {
                Section("Lab") {
                    Picker("Initial detent", selection: $detent) {
                        ForEach(ModulaSheetDetent.allCases) { Text($0.rawValue.capitalized).tag($0) }
                    }
                    Toggle("Scrollable content", isOn: $scrollable)
                    Toggle("Dismissible", isOn: $dismissible)
                    Toggle("Background interaction", isOn: $backgroundInteraction)
                }
                Section("Examples") {
                    Button("Present detented sheet") { sheetPresented = true }
                        .buttonStyle(.borderedProminent)
                    Text("Use the floating source button to exercise the connected morph path.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        } source: {
            Label("Morph", systemImage: "sparkles")
                .font(.headline)
                .padding(.horizontal, 16)
                .frame(minHeight: ModulaLayout.minimumTouch)
                .background(.tint, in: Capsule())
                .foregroundStyle(.white)
        } sheet: {
            SheetCatalogContent(scrollable: scrollable)
        }
        .sheet(isPresented: $sheetPresented) {
            ModulaSheet(
                detents: [.content, .compact, .medium, .large, .full],
                selectedDetent: $detent,
                dismissible: dismissible,
                backgroundInteractionEnabled: backgroundInteraction,
                transition: .morph,
                morphSource: .init("catalog.sheet.button")
            ) {
                SheetCatalogContent(scrollable: scrollable)
            }
        }
        .navigationTitle("Sheets")
    }
}

private struct SheetCatalogContent: View {
    let scrollable: Bool
    @State private var text = ""

    var body: some View {
        VStack(spacing: 0) {
            ModulaSheetHandle()
            ModulaSheetHeader("Morphing Sheet", subtitle: "Drag between detents")
            if scrollable {
                ScrollView {
                    LazyVStack { ForEach(1...30, id: \.self) { Text("Scrollable row \($0)").frame(maxWidth: .infinity, alignment: .leading).padding() } }
                }
            } else {
                TextField("Keyboard avoidance test", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .padding()
                Spacer()
            }
        }
    }
}
