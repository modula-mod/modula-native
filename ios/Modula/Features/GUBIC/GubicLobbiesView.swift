import SwiftUI

/// Lobby list, create, join-by-code and a live lobby room over the GUBIC lobby WebSocket.
struct GubicLobbiesView: View {
    let gameId: String
    let gameTitle: String
    let store: GubicStore

    @Environment(AppEnvironment.self) private var app
    @State private var lobbies: [GubicLobby] = []
    @State private var state: GubicLoadState = .idle
    @State private var code = ""
    @State private var title = ""
    @State private var invite = false
    @State private var size = 4
    @State private var error: String?
    @State private var room: GubicLobby?

    private var maxSize: Int { store.capabilities.lobbySize ?? 8 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ModulaSpacing.lg) {
                if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                joinCard
                createCard
                Text("Open lobbies").font(.title3.bold())
                if state == .loading && lobbies.isEmpty {
                    ModulaLoadingState(title: "Loading lobbies…")
                } else if state != .loaded {
                    GubicStateView(state: state, emptyTitle: "", emptyMessage: "", retry: { Task { await load() } })
                } else if lobbies.isEmpty {
                    GubicStateView(state: .loaded, emptyTitle: "No open lobbies", emptyMessage: "Create one and share the code with friends.",
                                   symbol: "person.3", retry: { Task { await load() } })
                } else {
                    ForEach(lobbies) { lobby in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(lobby.title).font(.headline)
                                Text("\(lobby.playerCount)/\(lobby.maxPlayers) players").font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                            GubicAccentButton(title: "Join", compact: true) { Task { await run { room = try await store.joinLobby(id: lobby.id) } } }
                        }
                    }
                }
            }
            .padding(.horizontal, ModulaLayout.contentInset)
            .padding(.bottom, 140)
        }
        .navigationTitle("Lobbies")
        .navigationBarTitleDisplayMode(.inline)
        .modulaCanvas()
        .task { await load() }
        .sheet(item: $room) { lobby in
            NavigationStack { GubicLobbyRoomView(lobby: lobby, gameTitle: gameTitle, store: store) }
                .presentationDetents([.large])
        }
    }

    private var joinCard: some View {
        VStack(alignment: .leading, spacing: ModulaSpacing.sm) {
            Text("Join with a code").font(.headline)
            HStack {
                TextField("6-character code", text: $code)
                    .textInputAutocapitalization(.characters).autocorrectionDisabled()
                    .font(.body.monospaced())
                    .padding(.horizontal, ModulaSpacing.md).frame(minHeight: 44)
                    .modulaGlass(in: Capsule(), interactive: false)
                    .accessibilityIdentifier("gubic.lobby.code")
                GubicAccentButton(title: "Join", compact: true) {
                    Task { await run { room = try await store.joinLobby(code: code.trimmingCharacters(in: .whitespaces).uppercased()) } }
                }
                .disabled(code.trimmingCharacters(in: .whitespaces).count != 6)
            }
        }
    }

    private var createCard: some View {
        VStack(alignment: .leading, spacing: ModulaSpacing.sm) {
            Text("Create a lobby").font(.headline)
            TextField("Lobby name", text: $title)
                .padding(.horizontal, ModulaSpacing.md).frame(minHeight: 44)
                .modulaGlass(in: Capsule(), interactive: false)
            Toggle("Invite only", isOn: $invite)
            Stepper("Up to \(size) players", value: $size, in: 2...max(2, maxSize))
            if store.capabilities.loaded, maxSize < 16 {
                GubicPremiumNote(text: "Your plan hosts up to \(maxSize) players. Larger lobbies come with Modula Plus and Horizon.")
            }
            ModulaButton(title: "Create lobby", symbol: "plus") {
                Task { await run { room = try await store.createLobby(gameId: gameId, title: title.isEmpty ? "\(gameTitle) lobby" : title, invite: invite, maxPlayers: size) } }
            }
            .accessibilityIdentifier("gubic.lobby.create")
        }
        .padding(ModulaSpacing.md)
        .modulaGlass(in: RoundedRectangle(cornerRadius: ModulaRadius.large, style: .continuous), interactive: false)
    }

    private func load() async {
        state = .loading
        do { lobbies = try await store.lobbies(gameId: gameId); state = .loaded } catch { state = .from(error) }
    }

    private func run(_ work: () async throws -> Void) async {
        do { try await work(); error = nil; await load() } catch {
            self.error = (error as? APIError)?.userFacingMessage ?? error.localizedDescription
        }
    }
}

struct GubicLobbyRoomView: View {
    @State var lobby: GubicLobby
    let gameTitle: String
    let store: GubicStore

    @Environment(\.dismiss) private var dismiss
    @Environment(AppEnvironment.self) private var app
    @State private var socket: URLSessionWebSocketTask?
    @State private var live = false
    @State private var error: String?

    private var me: GubicLobby.Member? { lobby.members.first { $0.isYou } }

    var body: some View {
        List {
            Section {
                LabeledContent("Game", value: gameTitle)
                LabeledContent("Status", value: lobby.status.capitalized)
                if let code = lobby.joinCode {
                    LabeledContent("Code") { Text(code).font(.body.monospaced().weight(.semibold)).textSelection(.enabled) }
                }
                LabeledContent("Updates", value: live ? "Live" : "Refresh to update")
            }
            Section("Players \(lobby.playerCount)/\(lobby.maxPlayers)") {
                ForEach(lobby.members, id: \.handle) { member in
                    HStack {
                        Text("@\(member.handle)\(member.isYou ? " (you)" : "")")
                        Spacer()
                        if member.role == "host" { Text("Host").foregroundStyle(.secondary) }
                        else { Image(systemName: member.ready ? "checkmark.circle.fill" : "circle").foregroundStyle(member.ready ? app.appearance.liveAccent : .secondary) }
                    }
                }
            }
            if let error { Section { Text(error).foregroundStyle(.red) } }
            Section {
                if lobby.isHost {
                    ModulaButton(title: "Start game", symbol: "play.fill") { act { try await store.startLobby(lobby.id) } }
                        .disabled(lobby.status != "open")
                } else if let me {
                    ModulaButton(title: me.ready ? "Not ready" : "Ready", symbol: me.ready ? "xmark" : "checkmark") {
                        act { try await store.setReady(lobby.id, ready: !me.ready) }
                    }
                }
                GubicAccentButton(title: lobby.isHost ? "Close lobby" : "Leave lobby", symbol: "rectangle.portrait.and.arrow.right") {
                    Task { try? await store.leaveLobby(lobby.id); dismiss() }
                }
            }
            .listRowBackground(Color.clear)
        }
        .navigationTitle(lobby.title)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await refresh() }
        .task { await connect() }
        .onDisappear { socket?.cancel(with: .goingAway, reason: nil) }
    }

    private func act(_ work: @escaping () async throws -> GubicLobby?) {
        Task {
            do { if let updated = try await work() { lobby = updated }; error = nil } catch {
                self.error = (error as? APIError)?.userFacingMessage ?? error.localizedDescription
            }
        }
    }

    private func refresh() async {
        if let updated = try? await store.lobby(lobby.id) { lobby = updated }
    }

    /// Live updates: the server pushes revision notices; the room refetches the authoritative lobby.
    private func connect() async {
        guard let request = try? await store.lobbySocketRequest(lobby.id) else { return }
        let task = URLSession.shared.webSocketTask(with: request)
        socket = task
        task.resume()
        while !Task.isCancelled {
            guard let message = try? await task.receive() else { live = false; return }
            live = true
            guard case .string(let text) = message, let data = text.data(using: .utf8),
                  let event = try? JSONDecoder().decode(JSONValue.self, from: data), let type = event["type"]?.string else { continue }
            switch type {
            case "lobby.updated", "lobby.started": await refresh()
            case "lobby.closed": await refresh(); live = false
            default: break
            }
        }
    }
}

struct GubicPremiumNote: View {
    let text: String
    @Environment(AppEnvironment.self) private var app
    var body: some View {
        HStack(alignment: .top, spacing: ModulaSpacing.sm) {
            Image(systemName: "sparkles").foregroundStyle(app.appearance.liveAccent)
            VStack(alignment: .leading, spacing: 4) {
                Text(text).font(.footnote)
                Button("What's in Modula Premium") { app.navigation.open(.settings(.premium(.compare))) }
                    .font(.footnote.weight(.semibold)).foregroundStyle(app.appearance.liveAccent)
                    .frame(minHeight: 44)
            }
        }
        .padding(ModulaSpacing.sm)
        .modulaGlass(in: RoundedRectangle(cornerRadius: ModulaRadius.medium, style: .continuous), interactive: false)
    }
}
