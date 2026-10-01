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
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
            }
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
