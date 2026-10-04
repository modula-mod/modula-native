import SwiftUI

/// Telegram-style media panel shown in place of the keyboard: Emoji, Stickers and GIFs.
struct ModulaComposerMediaPanel: View {
    enum Tab: String, CaseIterable, Identifiable {
        case emoji = "Emoji", stickers = "Stickers", gifs = "GIFs"
        var id: String { rawValue }
        var systemImage: String {
            switch self {
            case .emoji: "face.smiling"
            case .stickers: "seal"
            case .gifs: "play.square.stack"
            }
        }
    }

    var client: GreenfieldClient
    var initialTab: Tab = .emoji
    var allowsGifs = true
    var onEmoji: (String) -> Void
    var onGif: (ModulaGif) -> Void
    var onSticker: ((ModulaSticker) -> Void)? = nil

    @State private var tab: Tab = .emoji
    @Namespace private var tabGlass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var tabs: [Tab] {
        Tab.allCases.filter { ($0 != .gifs || allowsGifs) && ($0 != .stickers || onSticker != nil) }
    }

    var body: some View {
        VStack(spacing: 8) {
            if tabs.count > 1 {
                ModulaGlassGroup(spacing: 6) {
                    HStack(spacing: 6) {
                        ForEach(tabs) { item in
                            Button {
                                tab = item
                                HapticEngine.shared.play(.selection)
                            } label: {
                                Label(item.rawValue, systemImage: item.systemImage)
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 14)
                                    .frame(minHeight: 36)
                                    .foregroundStyle(tab == item ? Color.primary : Color.secondary)
                                    .symbolEffect(.bounce, value: tab == item)
                            }
                            .buttonStyle(.plain)
                            .modulaGlass(in: Capsule(), tint: tab == item ? .accentColor : nil)
                            .modulaGlassID("panel.tab.\(item.rawValue)", in: tabGlass)
                            .accessibilityAddTraits(tab == item ? .isSelected : [])
                            .accessibilityIdentifier("composer.panel.\(item.rawValue.lowercased())")
                        }
                    }
                }
                .padding(.top, 8)
            }
            Group {
                switch tab {
                case .emoji: ModulaEmojiGrid(onPick: onEmoji)
                case .stickers: ModulaStickerPicker(client: client) { onSticker?($0) }
                case .gifs: ModulaGifPicker(repository: GreenfieldGifRepository(client: client), onPick: onGif)
                }
            }
            .transition(.opacity)
        }
        .frame(height: 320)
        .frame(maxWidth: .infinity)
        .modulaGlass(in: UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous), interactive: false)
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: tab)
        .onAppear { tab = tabs.contains(initialTab) ? initialTab : .emoji }
        .accessibilityIdentifier("composer.panel")
    }
}

// MARK: - Emoji (search, recents, skin tones)

struct ModulaEmojiGrid: View {
    var onPick: (String) -> Void
    @AppStorage("composer.recentEmoji") private var recentRaw = ""
    @AppStorage("composer.emojiSkinTone") private var skinTone = 0
    @State private var query = ""

    private static let tones: [String] = ["", "\u{1F3FB}", "\u{1F3FC}", "\u{1F3FD}", "\u{1F3FE}", "\u{1F3FF}"]

    private static let sections: [(String, [ClosedRange<UInt32>])] = [
        ("Smileys & people", [0x1F600...0x1F64F, 0x1F910...0x1F92F, 0x1F970...0x1F97F, 0x1F44A...0x1F450, 0x1F466...0x1F469, 0x1F590...0x1F596]),
        ("Animals & nature", [0x1F400...0x1F43F, 0x1F330...0x1F343]),
        ("Food & drink", [0x1F345...0x1F37F, 0x1F950...0x1F96F]),
        ("Activities & travel", [0x1F380...0x1F3FF, 0x1F680...0x1F6C5]),
        ("Objects & symbols", [0x1F4A0...0x1F4FF, 0x2600...0x26FF, 0x1F9E0...0x1F9FF])
    ]

    struct Item: Hashable { let base: Unicode.Scalar; let name: String }

    private static let emoji: [(String, [Item])] = sections.map { title, ranges in
        (title, ranges.flatMap { range in
            range.compactMap { value -> Item? in
                guard let scalar = Unicode.Scalar(value), scalar.properties.isEmojiPresentation else { return nil }
                return Item(base: scalar, name: (scalar.properties.name ?? "").lowercased())
            }
        })
    }

    private var recents: [String] { recentRaw.split(separator: " ").map(String.init) }

    private func render(_ item: Item, tone: Int? = nil) -> String {
        let tone = tone ?? skinTone
        guard tone > 0, item.base.properties.isEmojiModifierBase else { return String(Character(item.base)) }
        return String(Character(item.base)) + Self.tones[tone]
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                ModulaGlassSearchField(prompt: "Search emoji", text: $query)
                Menu {
                    Picker("Skin tone", selection: $skinTone) {
                        ForEach(0..<Self.tones.count, id: \.self) { index in
                            Text("👋" + Self.tones[index]).tag(index)
                        }
                    }
                } label: {
                    Text("👋" + Self.tones[skinTone]).font(.title3).frame(width: 40, height: 40)
                }
                .modulaGlass(in: Circle())
                .accessibilityLabel("Skin tone")
                .accessibilityIdentifier("composer.emoji.skintone")
            }
            .padding(.horizontal, 12)
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 8), alignment: .leading, spacing: 4, pinnedViews: [.sectionHeaders]) {
                    let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
                    if trimmed.isEmpty {
                        if !recents.isEmpty { section("Recent", recents.map { ($0, nil) }) }
                        ForEach(Self.emoji, id: \.0) { title, items in section(title, items.map { (render($0), $0) }) }
                    } else {
                        let matches = Self.emoji.flatMap(\.1).filter { $0.name.contains(trimmed) }
                        if matches.isEmpty {
                            Text("No emoji for “\(query)”").font(.footnote).foregroundStyle(.secondary).padding()
                        }
                        section("Results", matches.prefix(120).map { (render($0), $0) })
                    }
                }
                .padding(.horizontal, 10)
            }
        }
        .accessibilityIdentifier("composer.panel.emoji.grid")
    }

    private func pick(_ emoji: String) {
        onPick(emoji)
        var list = recents.filter { $0 != emoji }
        list.insert(emoji, at: 0)
        recentRaw = list.prefix(24).joined(separator: " ")
        HapticEngine.shared.play(.selection)
    }

    private func section(_ title: String, _ items: [(String, Item?)]) -> some View {
        Section {
            ForEach(items, id: \.0) { emoji, item in
                Button { pick(emoji) } label: {
                    Text(emoji).font(.system(size: 30)).frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item?.name ?? emoji)
                // Long-press a person emoji for every skin tone.
                .contextMenu {
                    if let item, item.base.properties.isEmojiModifierBase {
                        ForEach(0..<Self.tones.count, id: \.self) { tone in
                            Button(render(item, tone: tone)) { pick(render(item, tone: tone)) }
                        }
                    }
                }
            }
        } header: {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
                .background(.clear)
        }
    }
}

// MARK: - Stickers (first-party packs from Greenfield)

struct ModulaSticker: Identifiable, Hashable, Sendable {
    let id: String
    let packID: String
    let emoji: String
    let label: String
}

struct ModulaStickerPack: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let icon: String
    let stickers: [ModulaSticker]
}

@MainActor
enum ModulaStickerCatalog {
    private static var cached: [ModulaStickerPack]?

    static func packs(client: GreenfieldClient) async throws -> [ModulaStickerPack] {
        if let cached { return cached }
        let value = try await client.json("GET", path: "/v1/stickers/packs")
        let packs: [ModulaStickerPack] = (value["packs"]?.array ?? []).compactMap { pack in
            guard let id = pack["id"]?.string, let title = pack["title"]?.string else { return nil }
            let stickers: [ModulaSticker] = (pack["stickers"]?.array ?? []).compactMap { sticker in
                guard let sid = sticker["id"]?.string, let emoji = sticker["emoji"]?.string else { return nil }
                return ModulaSticker(id: sid, packID: id, emoji: emoji, label: sticker["label"]?.string ?? emoji)
            }
            return ModulaStickerPack(id: id, title: title, icon: pack["icon"]?.string ?? stickers.first?.emoji ?? "⭐️", stickers: stickers)
        }
        cached = packs
        return packs
    }
}

struct ModulaStickerPicker: View {
    var client: GreenfieldClient
    var onPick: (ModulaSticker) -> Void
    @State private var packs: [ModulaStickerPack] = []
    @State private var selected: String?
    @State private var failed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 6) {
            if failed {
                ContentUnavailableView {
                    Label("Couldn’t load stickers", systemImage: "seal")
                } actions: {
                    Button("Retry") { Task { await load() } }
                }
            } else if packs.isEmpty {
                ProgressView().frame(maxHeight: .infinity)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(packs) { pack in
                            Button {
                                selected = pack.id
                                HapticEngine.shared.play(.selection)
                            } label: {
                                Text(pack.icon).font(.title2).frame(width: 44, height: 40)
                            }
                            .buttonStyle(.plain)
                            .modulaGlass(in: Capsule(), tint: selected == pack.id ? .accentColor : nil)
                            .accessibilityLabel(pack.title)
                            .accessibilityAddTraits(selected == pack.id ? .isSelected : [])
                        }
                    }
                    .padding(.horizontal, 12)
                }
                if let pack = packs.first(where: { $0.id == selected }) ?? packs.first {
                    ScrollView {
                        Text(pack.title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 10) {
                            ForEach(pack.stickers) { sticker in
                                Button { onPick(sticker); HapticEngine.shared.play(.success) } label: {
                                    ModulaStickerView(emoji: sticker.emoji, size: 64)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(sticker.label) sticker")
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                }
            }
        }
        .task { await load() }
        .accessibilityIdentifier("composer.panel.stickers.grid")
    }

    private func load() async {
        failed = false
        do {
            packs = try await ModulaStickerCatalog.packs(client: client)
            if selected == nil { selected = packs.first?.id }
        } catch {
            failed = true
        }
    }
}

/// A first-party sticker: a large emoji on a soft glass disc with a die-cut white outline.
struct ModulaStickerView: View {
    let emoji: String
    var size: CGFloat = 96
    var body: some View {
        Text(emoji)
            .font(.system(size: size * 0.62))
            .shadow(color: .white, radius: 0, x: 1.5, y: 1.5)
            .shadow(color: .white, radius: 0, x: -1.5, y: -1.5)
            .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
            .frame(width: size, height: size)
            .background(Circle().fill(Color.primary.opacity(0.04)))
    }
}

// MARK: - GIFs

struct ModulaGifPicker: View {
    var repository: GreenfieldGifRepository
    var onPick: (ModulaGif) -> Void

    @State private var query = ""
    @State private var items: [ModulaGif] = []
    @State private var nextOffset: Int?
    @State private var state: LoadState = .idle

    enum LoadState: Equatable { case idle, loading, loaded, notConfigured, failed(String) }

    private static let categories = ["Trending", "Reactions", "LOL", "Love", "Happy", "Sad", "Celebrate", "Thumbs up", "Wow", "Yes", "No", "Thank you", "Hello"]

    var body: some View {
        VStack(spacing: 8) {
            ModulaGlassSearchField(prompt: "Search GIPHY", text: $query).padding(.horizontal, 12)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Self.categories, id: \.self) { category in
                        let active = category == "Trending" ? query.isEmpty : query.caseInsensitiveCompare(category) == .orderedSame
                        Button {
                            query = category == "Trending" ? "" : category
                            HapticEngine.shared.play(.selection)
                        } label: {
                            Text(category).font(.caption.weight(.semibold)).padding(.horizontal, 12).frame(minHeight: 30)
                                .foregroundStyle(active ? Color.primary : Color.secondary)
                        }
                        .buttonStyle(.plain)
                        .modulaGlass(in: Capsule(), tint: active ? .accentColor : nil)
                        .accessibilityAddTraits(active ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 12)
            }
            content
        }
        .task(id: query) {
            // Debounce typing; empty query shows trending.
            if !query.isEmpty { try? await Task.sleep(for: .milliseconds(350)) }
            guard !Task.isCancelled else { return }
            await load(reset: true)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .notConfigured:
            ContentUnavailableView {
                Label("GIFs aren’t set up yet", systemImage: "play.square.stack")
            } description: {
                Text("GIF search turns on once the Modula server has a GIF provider key.")
            }
            .accessibilityIdentifier("composer.gifs.unconfigured")
        case .failed(let message):
            ContentUnavailableView {
                Label("Couldn’t load GIFs", systemImage: "wifi.exclamationmark")
            } description: { Text(message) } actions: {
                Button("Retry") { Task { await load(reset: true) } }
            }
        default:
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 4), GridItem(.flexible(), spacing: 4), GridItem(.flexible(), spacing: 4)], spacing: 4) {
                    ForEach(items) { gif in
                        Button { onPick(gif) } label: {
                            ModulaAnimatedRemoteImage(url: gif.previewURL)
                                .frame(height: 96)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(gif.title ?? "GIF")
                        .onAppear {
                            if gif.id == items.last?.id, nextOffset != nil { Task { await load(reset: false) } }
                        }
                    }
                }
                .padding(.horizontal, 10)
                if state == .loading { ProgressView().padding() }
                Text("Powered by GIPHY").font(.caption2).foregroundStyle(.tertiary).padding(.bottom, 6)
            }
        }
    }

    private func load(reset: Bool) async {
        guard state != .loading || reset else { return }
        let offset = reset ? 0 : (nextOffset ?? 0)
        state = .loading
        do {
            let result = query.trimmingCharacters(in: .whitespaces).isEmpty
                ? try await repository.trending(offset: offset)
                : try await repository.search(query, offset: offset)
            items = reset ? result.items : items + result.items.filter { gif in !items.contains { $0.id == gif.id } }
            nextOffset = result.nextOffset
            state = .loaded
        } catch ModulaGifError.notConfigured {
            state = .notConfigured
        } catch ModulaGifError.failed(let message) {
            state = .failed(message)
        } catch {
            state = .failed("Try again in a moment.")
        }
    }
}
