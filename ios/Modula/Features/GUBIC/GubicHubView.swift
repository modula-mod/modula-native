import SwiftUI

// MARK: Shared pieces

/// GUBIC mark from the provided app icon. Never the Modula M ribbon.
struct GubicMark: View {
    var size: CGFloat = 56
    var body: some View {
        Image("GubicAppIcon")
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
            .accessibilityLabel("GUBIC")
    }
}

/// Secondary action: glass capsule tinted with the user's live accent.
struct GubicAccentButton: View {
    let title: String
    var symbol: String?
    var compact = false
    let action: () -> Void
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        Button {
            HapticEngine.shared.play(.selection)
            action()
        } label: {
            Group {
                if let symbol { Label(title, systemImage: symbol) } else { Text(title) }
            }
            .font(compact ? .subheadline.weight(.semibold) : .headline)
            .foregroundStyle(app.appearance.liveAccent)
            .padding(.horizontal, compact ? ModulaSpacing.md : ModulaSpacing.lg)
            .frame(minHeight: ModulaLayout.minimumTouch)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .modulaGlass(in: Capsule(), interactive: true, tint: app.appearance.liveAccent.opacity(0.18))
    }
}

struct GubicStateView: View {
    let state: GubicLoadState
    let emptyTitle: String
    let emptyMessage: String
    var symbol = "gamecontroller"
    var retry: (() -> Void)?
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        VStack(spacing: ModulaSpacing.md) {
            switch state {
            case .notDeployed:
                ModulaEmptyState(title: "GUBIC isn't live on this server yet",
                                 message: "This Modula server doesn't have the GUBIC routes yet. Nothing is shown until they're deployed.",
                                 symbol: "server.rack")
            case .signedOut:
                ModulaEmptyState(title: "Sign in to use GUBIC", message: "Your library, lobbies and achievements live in your Modula account.", symbol: "person.crop.circle")
                ModulaButton(title: "Sign in to Modula", symbol: "person.crop.circle") { app.navigation.open(.auth(.login)) }
            case .failed(let message):
                ModulaEmptyState(title: "Couldn't load GUBIC", message: message, symbol: "exclamationmark.triangle")
            default:
                ModulaEmptyState(title: emptyTitle, message: emptyMessage, symbol: symbol)
            }
            if let retry, state != .signedOut {
                GubicAccentButton(title: "Try again", symbol: "arrow.clockwise", compact: true, action: retry)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, ModulaSpacing.lg)
    }
}

// MARK: Product Hub entry

/// One GUBIC card at the top of Product Hub, shown only when the feature flag is on.
struct GubicProductHubEntry: View {
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        if GubicFeature.enabled() {
            NavigationLink {
                GubicHubView(client: app.client)
            } label: {
                HStack(spacing: ModulaSpacing.md) {
                    GubicMark(size: 60)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("GUBIC").font(.headline)
                        Text("Discover, play and create games without leaving Modula.")
                            .font(.subheadline).foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.subheadline.weight(.semibold))
                        .foregroundStyle(app.appearance.liveAccent)
                }
                .padding(ModulaSpacing.md)
                .contentShape(RoundedRectangle(cornerRadius: ModulaRadius.large, style: .continuous))
            }
            .buttonStyle(.plain)
            .modulaGlass(in: RoundedRectangle(cornerRadius: ModulaRadius.large, style: .continuous), interactive: true)
            .accessibilityIdentifier("product-hub.gubic")
        }
    }
}

// MARK: Hub

enum GubicTab: String, CaseIterable, Identifiable {
    case discover, library, create
    var id: String { rawValue }
    var title: String {
        switch self {
        case .discover: "Discover"
        case .library: "Library"
        case .create: "Create"
        }
    }
}

struct GubicHubView: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var store: GubicStore
    @State private var tab = GubicTab.discover
    @State private var query = ""
    @State private var category: String?
    @State private var playing: GubicGameSource?

    init(client: GreenfieldClient) { _store = State(initialValue: GubicStore(client: client)) }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: ModulaSpacing.lg) {
                header
                Picker("Section", selection: $tab) {
                    ForEach(GubicTab.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("gubic.tabs")
                switch tab {
                case .discover: discover
                case .library: GubicLibrarySection(store: store, onPlaySample: { playing = .sample })
                case .create: GubicCreatorView(store: store)
                }
            }
            .padding(.horizontal, ModulaLayout.contentInset)
            .padding(.top, ModulaSpacing.sm)
            .padding(.bottom, 140)
        }
        .navigationTitle("GUBIC")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search games")
        .refreshable { await reload() }
        .modulaCanvas()
        .tint(app.appearance.liveAccent)
        .animation(reduceMotion ? nil : .snappy, value: tab)
        .task { await reload() }
        .fullScreenCover(item: $playing) { source in
            GubicPlayerView(source: source, store: store) { playing = nil }
        }
        .accessibilityIdentifier("gubic.hub")
    }

    private func reload() async {
        async let discover: Void = store.loadDiscover()
        async let capabilities: Void = store.loadCapabilities()
        async let library: Void = store.loadLibrary()
        _ = await (discover, capabilities, library)
    }

    private var header: some View {
        HStack(spacing: ModulaSpacing.md) {
            GubicMark(size: 64)
            VStack(alignment: .leading, spacing: 2) {
                Text("GUBIC").font(.title2.bold())
                Text("Play, create and share games. Your games and achievements become part of your Modula identity.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.top, ModulaSpacing.xs)
    }

    private var filtered: [GubicGame] {
        store.allGames.filter { game in
            (category == nil || game.categories.contains(category!))
                && (query.isEmpty || game.title.localizedCaseInsensitiveContains(query) || game.genre.localizedCaseInsensitiveContains(query))
        }
    }

    @ViewBuilder private var discover: some View {
        sampleCard
        if store.discoverState == .loading && store.allGames.isEmpty {
            ModulaLoadingState(title: "Loading games…")
        } else if store.discoverState != .loaded {
            GubicStateView(state: store.discoverState, emptyTitle: "No games yet", emptyMessage: "", retry: { Task { await store.loadDiscover() } })
        } else if store.allGames.isEmpty {
            GubicStateView(state: .loaded, emptyTitle: "No published games yet",
                           emptyMessage: "Games appear here once developers publish them and they pass review.",
                           retry: { Task { await store.loadDiscover() } })
        } else {
            if !store.categories.isEmpty { categoryChips }
            if query.isEmpty && category == nil {
                if !store.featured.isEmpty { GubicShelf(title: "Featured", games: store.featured, store: store) }
                if !store.newReleases.isEmpty { GubicShelf(title: "New releases", games: store.newReleases, store: store) }
            }
            GubicShelf(title: category.map { $0.capitalized } ?? (query.isEmpty ? "All games" : "Results"), games: filtered, store: store, vertical: true)
        }
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: ModulaSpacing.xs) {
                ForEach(store.categories, id: \.name) { item in
                    let selected = category == item.name
                    Button {
                        HapticEngine.shared.play(.selection)
                        category = selected ? nil : item.name
                    } label: {
                        Text("\(item.name.capitalized) · \(item.count)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(selected ? Color.white : app.appearance.liveAccent)
                            .padding(.horizontal, ModulaSpacing.md).frame(minHeight: 36)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .modulaGlass(in: Capsule(), interactive: true, tint: app.appearance.liveAccent.opacity(selected ? 0.9 : 0.15))
                }
            }
        }
    }

    private var sampleCard: some View {
        VStack(alignment: .leading, spacing: ModulaSpacing.sm) {
            HStack {
                Label("Bundled sample", systemImage: "shippingbox").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Text("Not in the catalogue").font(.caption).foregroundStyle(.secondary)
            }
            Text(GubicSampleGame.title).font(.title3.bold())
            Text(GubicSampleGame.summary).font(.subheadline).foregroundStyle(.secondary)
            ModulaButton(title: "Play sample", symbol: "play.fill") { playing = .sample }
                .accessibilityIdentifier("gubic.sample.play")
        }
        .padding(ModulaSpacing.md)
        .modulaGlass(in: RoundedRectangle(cornerRadius: ModulaRadius.large, style: .continuous), interactive: false)
    }
}

struct GubicShelf: View {
    let title: String
    let games: [GubicGame]
    let store: GubicStore
    var vertical = false

    var body: some View {
        VStack(alignment: .leading, spacing: ModulaSpacing.sm) {
            Text(title).font(.title3.bold())
            if vertical {
                if games.isEmpty {
                    Text("No games match.").font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(games) { game in
                    NavigationLink { GubicGameDetailView(gameId: game.id, initial: game, store: store) } label: { GubicGameRow(game: game) }
                        .buttonStyle(.plain)
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: ModulaSpacing.md) {
                        ForEach(games) { game in
                            NavigationLink { GubicGameDetailView(gameId: game.id, initial: game, store: store) } label: { GubicGameTile(game: game) }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}

struct GubicGameArt: View {
    let url: URL?
    var size: CGFloat = 64
    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase { image.resizable().aspectRatio(contentMode: .fill) } else { placeholder }
                }
            } else { placeholder }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
    }
    private var placeholder: some View {
        ZStack { Color.secondary.opacity(0.15); Image(systemName: "gamecontroller.fill").foregroundStyle(.secondary) }
    }
}

struct GubicGameTile: View {
    let game: GubicGame
    var body: some View {
        VStack(alignment: .leading, spacing: ModulaSpacing.xs) {
            GubicGameArt(url: game.coverURL ?? game.iconURL, size: 140)
            Text(game.title).font(.subheadline.weight(.semibold)).lineLimit(1)
            Text(game.genre).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(width: 140, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct GubicGameRow: View {
    let game: GubicGame
    @Environment(AppEnvironment.self) private var app
    var body: some View {
        HStack(spacing: ModulaSpacing.md) {
            GubicGameArt(url: game.iconURL, size: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(game.title).font(.headline).lineLimit(1)
                Text([game.genre, game.publisher].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(app.appearance.liveAccent)
        }
        .padding(.vertical, ModulaSpacing.xs)
        .contentShape(Rectangle())
    }
}

// MARK: Library

struct GubicLibrarySection: View {
    let store: GubicStore
    let onPlaySample: () -> Void

    var body: some View {
        if store.libraryState == .loading && store.library.isEmpty {
            ModulaLoadingState(title: "Loading your library…")
        } else if store.libraryState != .loaded {
            GubicStateView(state: store.libraryState, emptyTitle: "", emptyMessage: "", retry: { Task { await store.loadLibrary() } })
        } else if store.library.isEmpty {
            GubicStateView(state: .loaded, emptyTitle: "Your library is empty",
                           emptyMessage: "Games you add or play from Discover show up here with your play time and achievements.",
                           symbol: "square.stack", retry: { Task { await store.loadLibrary() } })
        } else {
            VStack(alignment: .leading, spacing: ModulaSpacing.sm) {
                ForEach(store.library) { item in
                    NavigationLink {
                        GubicGameDetailView(gameId: item.gameId, initial: item.game, store: store)
                    } label: {
                        HStack(spacing: ModulaSpacing.md) {
                            GubicGameArt(url: item.game?.iconURL, size: 56)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.game?.title ?? item.gameId).font(.headline).lineLimit(1)
                                Text(stats(item)).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            if item.favourite { Image(systemName: "heart.fill").foregroundStyle(.secondary).accessibilityLabel("Favourite") }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func stats(_ item: GubicLibraryItem) -> String {
        let minutes = item.totalPlaySeconds / 60
        var parts = ["\(item.playCount) \(item.playCount == 1 ? "play" : "plays")", "\(minutes) min"]
        if item.achievementsUnlocked > 0 { parts.append("\(item.achievementsUnlocked) achievements") }
        if item.game == nil { parts.append("no longer listed") }
        return parts.joined(separator: " · ")
    }
}
