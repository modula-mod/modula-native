import SwiftUI

struct GubicGameDetailView: View {
    let gameId: String
    let initial: GubicGame?
    let store: GubicStore

    @Environment(AppEnvironment.self) private var app
    @State private var game: GubicGame?
    @State private var state: GubicLoadState = .idle
    @State private var achievements: [GubicAchievement] = []
    @State private var message: String?

    private var inLibrary: Bool { store.library.contains { $0.gameId == gameId } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ModulaSpacing.lg) {
                if let game = game ?? initial {
                    hero(game)
                    actions(game)
                    if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }
                    facts(game)
                    achievementSection
                    NavigationLink { GubicLobbiesView(gameId: game.id, gameTitle: game.title, store: store) } label: {
                        HStack {
                            Label("Lobbies", systemImage: "person.3").font(.headline)
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .foregroundStyle(app.appearance.liveAccent)
                        .padding(ModulaSpacing.md)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .modulaGlass(in: RoundedRectangle(cornerRadius: ModulaRadius.large, style: .continuous), interactive: true)
                    .accessibilityIdentifier("gubic.detail.lobbies")
                } else if state == .loading || state == .idle {
                    ModulaLoadingState(title: "Loading game…")
                } else {
                    GubicStateView(state: state, emptyTitle: "Game not available", emptyMessage: "This game isn't published right now.",
                                   retry: { Task { await load() } })
                }
            }
            .padding(.horizontal, ModulaLayout.contentInset)
            .padding(.bottom, 140)
        }
        .navigationTitle(game?.title ?? initial?.title ?? "Game")
        .navigationBarTitleDisplayMode(.inline)
        .modulaCanvas()
        .task { await load() }
    }

    private func load() async {
        state = .loading
        do {
            game = try await store.game(gameId)
            state = game == nil ? .failed("Unexpected response") : .loaded
            achievements = (try? await store.achievements(for: gameId)) ?? []
        } catch {
            state = .from(error)
        }
    }

    private func hero(_ game: GubicGame) -> some View {
        HStack(alignment: .top, spacing: ModulaSpacing.md) {
            GubicGameArt(url: game.iconURL, size: 96)
            VStack(alignment: .leading, spacing: 4) {
                Text(game.title).font(.title2.bold())
                if !game.publisher.isEmpty {
                    Label(game.publisher, systemImage: game.publisherVerified ? "checkmark.seal" : "person")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Text(game.summary).font(.subheadline).foregroundStyle(.secondary).lineLimit(4)
            }
        }
        .padding(.top, ModulaSpacing.sm)
    }

    private func actions(_ game: GubicGame) -> some View {
        VStack(spacing: ModulaSpacing.sm) {
            // Install and launch go through the verified Product Hub package flow (WebGameHost).
            ModulaButton(title: "Get or open", symbol: "arrow.down.circle") {
                app.navigation.open(.productHub(.module(game.id, .overview)))
            }
            .disabled(game.availability != "available")
            .accessibilityIdentifier("gubic.detail.get")
            GubicAccentButton(title: inLibrary ? "Remove from Library" : "Add to Library", symbol: inLibrary ? "minus.circle" : "plus.circle") {
                Task {
                    do {
                        if inLibrary { try await store.removeFromLibrary(game.id) } else { try await store.addToLibrary(game.id) }
                        message = nil
                    } catch {
                        message = (error as? APIError)?.userFacingMessage ?? error.localizedDescription
                    }
                }
            }
            .accessibilityIdentifier("gubic.detail.library")
        }
    }

    private func facts(_ game: GubicGame) -> some View {
        VStack(alignment: .leading, spacing: ModulaSpacing.xs) {
            fact("Genre", game.genre)
            fact("Runtime", game.runtime)
            fact("Version", game.version)
            if let age = game.ageRating { fact("Age rating", age) }
            if let bytes = game.downloadBytes { fact("Download", ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)) }
            if game.availability != "available" { fact("Availability", game.availability.replacingOccurrences(of: "-", with: " ").capitalized) }
        }
        .padding(ModulaSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modulaGlass(in: RoundedRectangle(cornerRadius: ModulaRadius.large, style: .continuous), interactive: false)
    }

    private func fact(_ label: String, _ value: String) -> some View {
        HStack { Text(label).foregroundStyle(.secondary); Spacer(); Text(value.isEmpty ? "—" : value) }.font(.subheadline)
    }

    @ViewBuilder private var achievementSection: some View {
        VStack(alignment: .leading, spacing: ModulaSpacing.sm) {
            Text("Achievements").font(.title3.bold())
            if achievements.isEmpty {
                Text("This game hasn't declared any achievements.").font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(achievements) { item in
                HStack(spacing: ModulaSpacing.sm) {
                    Image(systemName: item.unlockedAt == nil ? "trophy" : "trophy.fill")
                        .foregroundStyle(item.unlockedAt == nil ? Color.secondary : app.appearance.liveAccent)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.title).font(.subheadline.weight(.semibold))
                        if !item.description.isEmpty { Text(item.description).font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    Text("\(item.points) pts").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}
