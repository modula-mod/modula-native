import SwiftUI

struct CommandCenterView: View {
    var context: CommandContext = .global
    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var queryFocused: Bool
    @State private var query = ""
    @State private var selectedIndex = 0
    /// Shown inline (the sheet would cover a shell banner) when a command can't run.
    @State private var notice: String?

    private var capabilities: CommandCapabilitySnapshot {
        app.commandCapabilities()
    }

    private var commands: [ModulaCommand] {
        CommandRegistry.visible(capabilities: capabilities)
    }

    private var matches: [CommandMatch] {
        CommandMatcher.match(query: query, in: commands, recentIDs: app.commandRecents.recentIDs)
    }

    private var sections: [CommandSectionModel] {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return CommandRegistry.emptyQuerySections(
                context: context,
                capabilities: capabilities,
                recentIDs: app.commandRecents.recentIDs
            )
        }
        var result: [CommandSectionModel] = []
        if !matches.isEmpty {
            result.append(.init(id: "results", title: "Commands", commands: matches.map(\.command)))
        }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            result.append(.init(
                id: "search-fallback",
                title: "Search",
                commands: [
                    ModulaCommand(
                        id: CommandID(rawValue: "search.fallback"),
                        title: "Search Modula for “\(trimmed)”",
                        icon: .init("magnifyingglass"),
                        category: .search,
                        action: .searchStart(query: trimmed),
                        accessibilityHint: "Opens Search with this query"
                    )
                ]
            ))
        }
        return result
    }

    private var flatCommands: [ModulaCommand] {
        sections.flatMap(\.commands)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                CommandSearchField(text: $query, focused: $queryFocused)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                if let notice {
                    Label(notice, systemImage: "info.circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, ModulaSpacing.md)
                        .padding(.bottom, ModulaSpacing.xs)
                        .transition(.opacity)
                        .accessibilityIdentifier("command.notice")
                }

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: sectionSpacing, pinnedViews: []) {
                            ForEach(sections) { section in
                                CommandSectionView(title: section.title) {
                                    ForEach(Array(section.commands.enumerated()), id: \.element.id) { _, command in
                                        let globalIndex = flatCommands.firstIndex(where: { $0.id == command.id }) ?? 0
                                        CommandRow(
                                            command: command,
                                            selected: globalIndex == selectedIndex && !query.isEmpty
                                        ) {
                                            run(command)
                                        }
                                        .id(command.id.rawValue)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                    }
                    .modulaSoftScrollEdge()
                    .onChange(of: selectedIndex) { _, index in
                        guard index >= 0, index < flatCommands.count else { return }
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.12)) {
                            proxy.scrollTo(flatCommands[index].id.rawValue, anchor: .center)
                        }
                    }
                }
            }
            .modulaSoftScrollEdge()
            .navigationTitle("Command Center")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .keyboardShortcut(.escape, modifiers: [])
                }
            }
            .modulaCanvas()
            .tint(app.appearance.accent.color)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Command Center")
            .accessibilityIdentifier("command.center")
            .onAppear {
                queryFocused = true
                HapticEngine.shared.play(.contextOpen)
            }
            .onChange(of: query) { _, _ in
                // No haptic per keystroke: typing already has keyboard feedback.
                selectedIndex = 0
                notice = nil
            }
            .onKeyPress(.upArrow) {
                moveSelection(-1)
                return .handled
            }
            .onKeyPress(.downArrow) {
                moveSelection(1)
                return .handled
            }
            .onKeyPress(.return) {
                executeSelected()
                return .handled
            }
            .onKeyPress(.escape) {
                dismiss()
                return .handled
            }
        }
    }

    private var sectionSpacing: CGFloat {
        app.appearance.density == .compact ? 10 : 16
    }

    private func moveSelection(_ delta: Int) {
        guard !flatCommands.isEmpty else { return }
        selectedIndex = max(0, min(flatCommands.count - 1, selectedIndex + delta))
        HapticEngine.shared.play(.selection)
    }

    private func executeSelected() {
        guard selectedIndex >= 0, selectedIndex < flatCommands.count else { return }
        run(flatCommands[selectedIndex])
    }

    private func run(_ command: ModulaCommand) {
        let outcome = CommandExecutor.execute(
            command,
            navigation: app.navigation,
            signedIn: app.auth.isSignedIn
        ) { presentation in
            app.navigation.presented = presentation
        }
        switch outcome {
        case .executed:
            app.commandRecents.record(command)
            HapticEngine.shared.play(.confirmation)
            dismiss()
        case .requiresSignIn(let route):
            dismiss()
            app.navigation.requestAuthentication(returningTo: route)
        case .unavailable, .unsupported:
            HapticEngine.shared.play(.failure)
            let message = "“\(command.title)” isn’t available right now."
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { notice = message }
            AccessibilityNotification.Announcement(message).post()
        }
    }
}

struct CommandSearchField: View {
    @Binding var text: String
    var focused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("What do you want to do?", text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused(focused)
                .submitLabel(.go)
                .accessibilityLabel("Search commands")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        // Shared Liquid Glass input surface (design system).
        .modulaGlass(in: Capsule(), interactive: false)
        .accessibilityIdentifier("command.search")
    }
}

struct CommandSectionView<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
                .accessibilityAddTraits(.isHeader)
            content
        }
    }
}

struct CommandRow: View {
    @Environment(AppEnvironment.self) private var app
    let command: ModulaCommand
    var selected = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: command.icon.systemName)
                    .font(.body.weight(.semibold))
                    .frame(width: 28, height: 28)
                    .foregroundStyle(.primary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(command.title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    if let subtitle = command.subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                if command.category == .create {
                    Text("Create")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .background(selected ? app.appearance.accent.color.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(command.title)
        .accessibilityValue("command")
        .accessibilityHint(command.accessibilityHint ?? "")
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
        .accessibilityIdentifier("command.row.\(command.id.rawValue)")
    }
}

struct CreateActionPicker: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var showsLive = false

    private var capabilities: CommandCapabilitySnapshot {
        CommandCapabilitySnapshot(
            signedIn: app.auth.isSignedIn,
            storyCreate: app.stories.capabilities.create,
            messagingSend: app.messaging.capabilities.send,
            inMailCompose: app.inMail.capabilities.send,
            installedModuleIDs: app.catalogue.installedIDs
        )
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(CreateActionRegistry.actions(capabilities: capabilities).filter { $0.availability == .available || $0.availability == .requiresSignIn }) { item in
                    Button {
                        run(item)
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                if let subtitle = item.subtitle {
                                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        } icon: {
                            Image(systemName: item.icon.systemName)
                        }
                    }
                    .disabled(item.availability == .requiresSignIn && !app.auth.isSignedIn)
                    .accessibilityLabel(item.title)
                }
                if LiveFeatureFlags.isEnabled {
                    Button {
                        showsLive = true
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Go Live")
                                Text("Developer preview · not broadcast").font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "dot.radiowaves.left.and.right").foregroundStyle(.red)
                        }
                    }
                    .accessibilityIdentifier("create.live")
                }
            }
            .fullScreenCover(isPresented: $showsLive) { LiveHostFlow() }
            .modulaSoftScrollEdge()
            .navigationTitle("Create")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .keyboardShortcut(.escape, modifiers: [])
                }
            }
        }
        .presentationDetents([.medium])
        .accessibilityIdentifier("create.picker")
        .onAppear { HapticEngine.shared.play(.contextOpen) }
    }

    private func run(_ item: CreateAction) {
        let command = ModulaCommand(
            id: CommandID(rawValue: "create.\(item.id)"),
            title: item.title,
            icon: item.icon,
            category: .create,
            availability: item.availability,
            action: item.action
        )
        let outcome = CommandExecutor.execute(
            command,
            navigation: app.navigation,
            signedIn: app.auth.isSignedIn
        ) { presentation in
            app.navigation.presented = presentation
        }
        if outcome == .executed {
            HapticEngine.shared.play(.confirmation)
            dismiss()
        } else if case .requiresSignIn(let route) = outcome {
            dismiss()
            app.navigation.requestAuthentication(returningTo: route)
        }
    }
}


// MARK: - Command palette (glass, global)

/// Shared switch for the glass command palette. Opened by pulling down and sliding left
/// on any feed (the existing pull chooser's "Command" slot), long-pressing the Tools
/// accessory, or ⌘K. Doesn't fight system pull-down or pull-to-refresh.
@MainActor @Observable
final class CommandPaletteCenter {
    static let shared = CommandPaletteCenter()
    private(set) var isPresented = false

    func present() {
        guard !isPresented else { return }
        isPresented = true
        HapticEngine.shared.play(.contextOpen)
    }

    func dismiss() { isPresented = false }
}

/// Mount once at the root, above tabs and chrome.
struct CommandPaletteHost: View {
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var center: CommandPaletteCenter { CommandPaletteCenter.shared }

    var body: some View {
        let calm = ModulaEffectGate.reduceMotion(systemReduceMotion)
        ZStack(alignment: .top) {
            if center.isPresented {
                CommandPaletteView()
                    .transition(calm ? .opacity : .asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.96, anchor: .top)),
                        removal: .opacity.combined(with: .scale(scale: 0.98, anchor: .top))
                    ))
            }
        }
        .animation(calm ? .easeOut(duration: 0.15) : .spring(response: 0.4, dampingFraction: 0.84), value: center.isPresented)
    }
}

struct CommandPaletteView: View {
    @Environment(AppEnvironment.self) private var app
    @FocusState private var focused: Bool
    @State private var query = ""
    @State private var searchTask: Task<Void, Never>?
    @State private var dragY: CGFloat = 0

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var commands: [ModulaCommand] {
        let all = CommandRegistry.visible(capabilities: app.commandCapabilities())
        if trimmed.isEmpty {
            return Array(CommandRegistry.emptyQuerySections(context: .global, capabilities: app.commandCapabilities(), recentIDs: app.commandRecents.recentIDs)
                .flatMap(\.commands).prefix(6))
        }
        return Array(CommandMatcher.match(query: query, in: all, recentIDs: app.commandRecents.recentIDs).map(\.command).prefix(6))
    }

    private var hits: [SearchHit] {
        guard !trimmed.isEmpty, app.discover.search.query == trimmed else { return [] }
        return app.discover.search.results
    }

    private var people: [SearchHit] { Array(hits.filter { $0.entityType == "profile" }.prefix(4)) }
    private var posts: [SearchHit] { Array(hits.filter { $0.entityType == "post" }.prefix(4)) }
    private var modules: [CatalogueProduct] {
        guard !trimmed.isEmpty else { return [] }
        let local = app.catalogue.products.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
        let remoteIDs = hits.compactMap(\.moduleID)
        let remote = remoteIDs.compactMap { app.catalogue.product($0) }.filter { r in !local.contains(where: { $0.id == r.id }) }
        return Array((local + remote).prefix(4))
    }

    var body: some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.black.opacity(0.25))
                .ignoresSafeArea()
                .onTapGesture { close() }
                .accessibilityLabel("Close command palette")
                .accessibilityAddTraits(.isButton)

            VStack(spacing: 0) {
                field
                    .padding(12)
                Divider().opacity(0.4)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if !people.isEmpty { section("People") { ForEach(people) { personRow($0) } } }
                        if !posts.isEmpty { section("Posts") { ForEach(posts) { postRow($0) } } }
                        if !modules.isEmpty { section("Modules") { ForEach(modules) { moduleRow($0) } } }
                        if !commands.isEmpty {
                            section(trimmed.isEmpty ? "Suggested" : "Commands & Settings") {
                                ForEach(commands) { command in
                                    CommandRow(command: command) { run(command) }
                                }
                            }
                        }
                        if !trimmed.isEmpty {
                            Button {
                                app.navigation.open(.search(.root(trimmed)))
                                close()
                            } label: {
                                Label("Search everything for “\(trimmed)”", systemImage: "magnifyingglass")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(12)
                                    .modulaGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous), interactive: true)
                            }
                            .buttonStyle(ModulaPressStyle(scale: 0.98, haptic: .navigation))
                        }
                        if app.discover.search.loadState == .loading, !trimmed.isEmpty {
                            ProgressView().frame(maxWidth: .infinity)
                        }
                    }
                    .padding(12)
                }
                .scrollDismissesKeyboard(.interactively)
                .frame(maxHeight: 460)
            }
            .modulaGlass(in: RoundedRectangle(cornerRadius: 28, style: .continuous), interactive: false, specular: true)
            .shadow(color: .black.opacity(0.25), radius: 30, y: 14)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .offset(y: min(dragY, 0))
            .gesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { dragY = $0.translation.height }
                    .onEnded { value in
                        if value.translation.height < -60 { close() }
                        withAnimation(.spring(duration: 0.3)) { dragY = 0 }
                    }
            )
        }
        .onAppear { focused = true }
        .onChange(of: query) { _, _ in schedule() }
        .onDisappear { searchTask?.cancel() }
        .onKeyPress(.escape) { close(); return .handled }
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { close() }
        .accessibilityIdentifier("command.palette")
    }

    private var field: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search posts, people, modules, settings", text: $query)
                .textFieldStyle(.plain)
                .focused($focused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .onSubmit {
                    if let first = commands.first, trimmed.isEmpty || hits.isEmpty { run(first) }
                    else if !trimmed.isEmpty { app.navigation.open(.search(.root(trimmed))); close() }
                }
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .modulaGlass(in: Capsule(), interactive: true)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .padding(.leading, 10)
            content()
        }
    }

    private func row(icon: AnyView, title: String, subtitle: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                icon.frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.medium)).lineLimit(1)
                    if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(ModulaPressStyle(scale: 0.98, haptic: .navigation))
    }

    private func personRow(_ hit: SearchHit) -> some View {
        let person = hit.person
        return row(
            icon: AnyView(ModulaAvatar(initials: String((person?.displayName ?? hit.title).prefix(1)), url: person?.avatarURL, size: 32, name: person?.displayName ?? hit.title)),
            title: person?.displayName ?? hit.title,
            subtitle: person.map { "@\($0.handle)" } ?? hit.handle.map { "@\($0)" }
        ) { open(hit) }
    }

    private func postRow(_ hit: SearchHit) -> some View {
        row(
            icon: AnyView(Image(systemName: "text.bubble").font(.body.weight(.semibold))),
            title: hit.post?.text ?? hit.title,
            subtitle: hit.post?.author.map { "@\($0.handle)" } ?? hit.excerpt
        ) { open(hit) }
    }

    private func moduleRow(_ product: CatalogueProduct) -> some View {
        row(
            icon: AnyView(ProductArtwork(product: product, size: 32)),
            title: product.name,
            subtitle: app.catalogue.installedIDs.contains(product.id) ? "Installed" : "Module"
        ) {
            app.navigation.open(.productHub(.module(product.id, .overview)))
            close()
        }
    }

    private func open(_ hit: SearchHit) {
        guard let destination = hit.destination else { return }
        app.navigation.open(destination)
        close()
    }

    private func schedule() {
        searchTask?.cancel()
        let text = trimmed
        guard !text.isEmpty else { return }
        searchTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(260))
            guard !Task.isCancelled else { return }
            await app.discover.performSearch(query: text, section: nil)
        }
    }

    private func run(_ command: ModulaCommand) {
        let outcome = CommandExecutor.execute(command, navigation: app.navigation, signedIn: app.auth.isSignedIn) { presentation in
            app.navigation.presented = presentation
        }
        switch outcome {
        case .executed:
            app.commandRecents.record(command)
            HapticEngine.shared.play(.confirmation)
            close()
        case .requiresSignIn(let route):
            close()
            app.navigation.requestAuthentication(returningTo: route)
        case .unavailable, .unsupported:
            ModulaHapticTexture.play(.error)
            app.navigation.flash("“\(command.title)” isn’t available right now.", symbol: "exclamationmark.circle")
        }
    }

    private func close() {
        focused = false
        CommandPaletteCenter.shared.dismiss()
    }
}
