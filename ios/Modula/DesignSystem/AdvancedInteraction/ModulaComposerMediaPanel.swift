import SwiftUI

/// Telegram-style media panel shown in place of the keyboard: Emoji, Faces (kaomoji), Stickers and GIFs.
struct ModulaComposerMediaPanel: View {
    enum Tab: String, CaseIterable, Identifiable {
        case emoji = "Emoji", kaomoji = "Faces", stickers = "Stickers", gifs = "GIFs"
        var id: String { rawValue }
        var systemImage: String {
            switch self {
            case .emoji: "face.smiling"
            case .kaomoji: "textformat.abc.dottedunderline"
            case .stickers: "seal"
            case .gifs: "play.square.stack"
            }
        }
    }

    var client: GreenfieldClient
    var initialTab: Tab = .emoji
    var initialStickerSection: String? = nil
    var allowsGifs = true
    var contentHeight: CGFloat = 292
    var onEmoji: (String) -> Void
    var onGif: (ModulaGif) -> Void
    var onSticker: ((ModulaSticker) -> Void)? = nil

    @State private var tab: Tab = .emoji
    /// Extra bottom padding when a parent ignores the safe area and the panel would run under the home indicator.
    @State private var homeIndicatorPadding: CGFloat = 0
    @Namespace private var tabGlass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppEnvironment.self) private var app
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var tabs: [Tab] {
        Tab.allCases.filter { ($0 != .gifs || allowsGifs) && ($0 != .stickers || onSticker != nil) }
    }

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous)
    }

    var body: some View {
        let canvas = ModulaPalette.resolve(app.appearance, scheme: colorScheme).canvas
        VStack(spacing: 0) {
            // Handle + tabs sit above the content with comfortable breathing room.
            Capsule()
                .fill(Color.primary.opacity(0.22))
                .frame(width: 36, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 10)
                .accessibilityHidden(true)
            if tabs.count > 1 {
                ModulaGlassGroup(spacing: 6) {
                    HStack(spacing: 6) {
                        ForEach(tabs) { item in
                            Button {
                                tab = item
                                HapticEngine.shared.play(.selection)
                            } label: {
                                Label(item.rawValue, systemImage: item.systemImage)
                                    .labelStyle(.titleAndIcon)
                                    .font(.footnote.weight(.semibold))
                                    .lineLimit(1)
                                    .padding(.horizontal, 11)
                                    .frame(minHeight: 34)
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
                    .padding(.horizontal, 12)
                }
                .padding(.bottom, 10)
            }
            Group {
                switch tab {
                case .emoji: ModulaEmojiGrid(onPick: onEmoji)
                case .kaomoji: ModulaKaomojiGrid(onPick: onEmoji)
                case .stickers: ModulaStickerPicker(client: client, initialSection: initialStickerSection) { onSticker?($0) }
                case .gifs:
                    ModulaGifPicker(repository: GreenfieldGifRepository(client: client), onPick: onGif) { alt in
                        withAnimation(.snappy) { tab = alt }
                    }
                }
            }
            .frame(height: contentHeight)
            .transition(.opacity)
            // Keep content clear of the home indicator; the opaque fill still covers it.
            Color.clear.frame(height: 6)
                .padding(.bottom, 4)
        }
        .padding(.bottom, homeIndicatorPadding)
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: { maxY in
            // Stable when bottom-pinned (maxY doesn't move with padding); clamped to the inset otherwise.
            guard let window = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first else { return }
            let inset = window.safeAreaInsets.bottom
            let limit = window.bounds.height - inset
            let needed = min(inset, max(0, maxY - limit))
            if abs(needed - homeIndicatorPadding) > 1 { homeIndicatorPadding = needed }
        }
        // Keyboard-replacement surface: opaque enough that the comment list never bleeds
        // through. Liquid Glass is reserved for the small tab chips above — a full-bleed
        // glassEffect here was compositing above the composer and chopping the mascot.
        .background {
            ZStack {
                // Opaque canvas first so comment-list content can never bleed through.
                shape.fill(canvas)
                if !reduceTransparency {
                    shape.fill(Color.clear)
                        .background(.ultraThickMaterial, in: shape)
                }
            }
            .overlay {
                shape.stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.55), Color.primary.opacity(0.06), .white.opacity(0.18)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.8
                )
                .allowsHitTesting(false)
            }
            // Extend the fill under the home indicator without clipping it away.
            .ignoresSafeArea(edges: .bottom)
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: tab)
        .onAppear { tab = tabs.contains(initialTab) ? initialTab : .emoji }
        .accessibilityIdentifier("composer.panel")
    }
}

// MARK: - Emoji (search, frequently used, categories bar, skin tones)

struct ModulaEmojiGrid: View {
    var onPick: (String) -> Void
    @AppStorage("composer.recentEmoji") private var recentRaw = ""
    @AppStorage("composer.emojiCounts") private var countsRaw = ""
    @AppStorage("composer.emojiSkinTone") private var skinTone = 0
    @State private var query = ""
    @State private var visibleSection = "Frequently used"
    @State private var sectionOffsets: [String: CGFloat] = [:]
    @State private var jumping = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppEnvironment.self) private var app

    private static let tones: [String] = ["", "\u{1F3FB}", "\u{1F3FC}", "\u{1F3FD}", "\u{1F3FE}", "\u{1F3FF}"]
    private static let columns = Array(repeating: GridItem(.flexible(minimum: 34), spacing: 0), count: 8)

    private static let sections: [(String, String, [ClosedRange<UInt32>])] = [
        ("Smileys & people", "face.smiling", [0x1F600...0x1F64F, 0x1F910...0x1F92F, 0x1F970...0x1F97F, 0x1F44A...0x1F450, 0x1F466...0x1F469, 0x1F590...0x1F596]),
        ("Animals & nature", "pawprint", [0x1F400...0x1F43F, 0x1F330...0x1F343]),
        ("Food & drink", "fork.knife", [0x1F345...0x1F37F, 0x1F950...0x1F96F]),
        ("Activities", "soccerball", [0x1F380...0x1F3FF]),
        ("Travel & places", "car", [0x1F680...0x1F6C5]),
        ("Objects", "lightbulb", [0x1F4A0...0x1F4FF, 0x1F9E0...0x1F9FF]),
        ("Symbols", "heart", [0x2600...0x26FF, 0x2700...0x27BF])
    ]

    struct Item: Hashable { let base: Unicode.Scalar; let name: String }

    private static let emoji: [(String, String, [Item])] = sections.map { title, icon, ranges in
        (title, icon, ranges.flatMap { range in
            range.compactMap { value -> Item? in
                guard let scalar = Unicode.Scalar(value), scalar.properties.isEmojiPresentation else { return nil }
                return Item(base: scalar, name: (scalar.properties.name ?? "").lowercased())
            }
        })
    }

    private var recents: [String] { recentRaw.split(separator: " ").map(String.init) }

    /// Most-used first (counts persisted), topped up with recents.
    private var frequent: [String] {
        let counts = countsRaw.split(separator: " ").reduce(into: [String: Int]()) { dict, pair in
            let parts = pair.split(separator: "=")
            if parts.count == 2, let n = Int(parts[1]) { dict[String(parts[0])] = n }
        }
        var list = counts.sorted { $0.value > $1.value }.map(\.key)
        for r in recents where !list.contains(r) { list.append(r) }
        // Whole rows only, so a lone emoji never wraps onto a second line.
        let columns = 8
        let count = list.count >= columns ? min(list.count / columns * columns, columns * 2) : list.count
        return Array(list.prefix(count))
    }

    /// Everyday keywords that Unicode names don't contain.
    private static let aliases: [String: [String]] = [
        "love": ["❤️", "😍", "🥰", "😘", "💕", "💖"], "lol": ["😂", "🤣", "😆"], "haha": ["😂", "🤣", "😆"],
        "cry": ["😭", "😢", "🥲"], "sad": ["😢", "😭", "😞", "🥺"], "happy": ["😀", "😊", "😁", "🥳"],
        "fire": ["🔥"], "lit": ["🔥"], "ok": ["👌", "👍"], "yes": ["👍", "✅"], "no": ["👎", "❌"],
        "thanks": ["🙏", "🫶"], "party": ["🥳", "🎉", "🎊"], "angry": ["😡", "😠", "🤬"], "cool": ["😎", "🆒"],
        "wow": ["😮", "🤯", "😲"], "think": ["🤔"], "eyes": ["👀"], "clap": ["👏"], "heart": ["❤️", "💜", "💙", "💚", "🧡", "💛"],
        "dead": ["💀"], "skull": ["💀"], "100": ["💯"], "star": ["⭐️", "🌟", "✨"], "sparkle": ["✨"], "pray": ["🙏"],
    ]

    private func render(_ item: Item, tone: Int? = nil) -> String {
        let tone = tone ?? skinTone
        guard tone > 0, item.base.properties.isEmojiModifierBase else { return String(Character(item.base)) }
        return String(Character(item.base)) + Self.tones[tone]
    }

    var body: some View {
        let canvas = ModulaPalette.resolve(app.appearance, scheme: colorScheme).canvas
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                ModulaGlassSearchField(prompt: "Search emoji or words like “love”", text: $query)
                Menu {
                    Picker("Skin tone", selection: $skinTone) {
                        ForEach(0..<Self.tones.count, id: \.self) { index in
                            Text("👋" + Self.tones[index]).tag(index)
                        }
                    }
                } label: {
                    Text("👋" + Self.tones[skinTone])
                        .font(.title3)
                        .frame(width: 44, height: 44)
                        .overlay(Circle().strokeBorder(Color.accentColor.opacity(0.45), lineWidth: 1.2).padding(2))
                        .contentShape(Circle())
                }
                .modulaGlass(in: Circle(), interactive: true)
                .onChange(of: skinTone) { _, _ in HapticEngine.shared.play(.selection) }
                .accessibilityLabel("Skin tone")
                .accessibilityIdentifier("composer.emoji.skintone")
            }
            .padding(.horizontal, 12)

            // Explicit VStack so the category strip sits under the scroll view (never overlays labels).
            // Per-section LazyVGrid (not Section-in-LazyVGrid) keeps a dense, even keyboard layout.
            ScrollViewReader { proxy in
                VStack(spacing: 0) {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
                            if trimmed.isEmpty {
                                if !frequent.isEmpty {
                                    emojiBlock(title: "Frequently used", cells: frequent.map { EmojiCell(id: "freq.\($0)", glyph: $0, item: nil) })
                                }
                                ForEach(Self.emoji, id: \.0) { title, _, items in
                                    emojiBlock(
                                        title: title,
                                        cells: items.enumerated().map { index, item in
                                            EmojiCell(id: "\(title).\(index)", glyph: render(item), item: item)
                                        }
                                    )
                                }
                            } else {
                                let aliasGlyphs = Self.aliases.filter { $0.key.hasPrefix(trimmed) }.flatMap(\.value)
                                let matches = Self.emoji.flatMap(\.2).filter { $0.name.contains(trimmed) }
                                if !aliasGlyphs.isEmpty {
                                    emojiBlock(title: "Suggested", cells: Array(NSOrderedSet(array: aliasGlyphs)).compactMap { $0 as? String }.map { EmojiCell(id: "alias.\($0)", glyph: $0, item: nil) })
                                }
                                if matches.isEmpty && aliasGlyphs.isEmpty {
                                    Text("No emoji for “\(query)”")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 24)
                                } else if !matches.isEmpty {
                                    emojiBlock(
                                        title: "Results",
                                        cells: matches.prefix(120).enumerated().map { index, item in
                                            EmojiCell(id: "result.\(index)", glyph: render(item), item: item)
                                        }
                                    )
                                }
                            }
                        }
                        .padding(.horizontal, 8)
                        // Last row scrolls fully clear of the category bar.
                        .padding(.bottom, 18)
                    }
                    .coordinateSpace(name: "emoji.scroll")
                    .scrollIndicators(.hidden)
                    .onChange(of: sectionOffsets) { _, offsets in
                        guard !jumping else { return }
                        // The section whose header has most recently crossed the top wins.
                        let current = offsets.filter { $0.value <= 40 }.max { $0.value < $1.value }?.key
                            ?? offsets.min { $0.value < $1.value }?.key
                        if let current, current != visibleSection { visibleSection = current }
                    }

                    if query.isEmpty {
                        categoryBar(proxy)
                            .padding(.top, 6)
                            .padding(.bottom, 2)
                            .background(canvas)
                    }
                }
            }
        }
        .accessibilityIdentifier("composer.panel.emoji.grid")
    }

    private struct EmojiCell: Identifiable {
        let id: String
        let glyph: String
        let item: Item?
    }

    @ViewBuilder
    private func emojiBlock(title: String, cells: [EmojiCell]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
            LazyVGrid(columns: Self.columns, spacing: 2) {
                ForEach(cells) { cell in
                    Button { pick(cell.glyph) } label: {
                        Text(cell.glyph)
                            .font(.system(size: 30))
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(EmojiKeyStyle())
                    .accessibilityLabel(cell.item?.name ?? cell.glyph)
                    // Touch and hold: big preview + skin tones (when the emoji supports them).
                    .contextMenu {
                        if let item = cell.item, item.base.properties.isEmojiModifierBase {
                            ForEach(0..<Self.tones.count, id: \.self) { tone in
                                Button(render(item, tone: tone)) { pick(render(item, tone: tone)) }
                            }
                        } else {
                            Button("Insert \(cell.glyph)") { pick(cell.glyph) }
                        }
                    } preview: {
                        VStack(spacing: 6) {
                            Text(cell.glyph).font(.system(size: 88))
                            if let name = cell.item?.name, !name.isEmpty {
                                Text(name.capitalized).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            }
                        }
                        .padding(20)
                    }
                }
            }
        }
        .id("section.\(title)")
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named("emoji.scroll")).minY } action: { y in
            sectionOffsets[title] = y
        }
    }

    private func categoryBar(_ proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 0) {
            let items: [(String, String)] = (frequent.isEmpty ? [] : [("Frequently used", "clock")]) + Self.emoji.map { ($0.0, $0.1) }
            ForEach(items, id: \.0) { title, icon in
                Button {
                    visibleSection = title
                    jumping = true
                    withAnimation(.snappy) { proxy.scrollTo("section.\(title)", anchor: .top) }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { jumping = false }
                    HapticEngine.shared.play(.selection)
                } label: {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(visibleSection == title ? Color.accentColor : Color.secondary)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background {
                            if visibleSection == title {
                                Capsule().fill(Color.accentColor.opacity(0.18)).padding(.horizontal, 3)
                            }
                        }
                        .animation(.snappy(duration: 0.18), value: visibleSection)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(title)
                .accessibilityAddTraits(visibleSection == title ? .isSelected : [])
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .modulaGlass(in: Capsule(), interactive: false)
        .padding(.horizontal, 12)
    }

    private func pick(_ emoji: String) {
        onPick(emoji)
        var list = recents.filter { $0 != emoji }
        list.insert(emoji, at: 0)
        recentRaw = list.prefix(24).joined(separator: " ")
        var counts = countsRaw.split(separator: " ").reduce(into: [String: Int]()) { dict, pair in
            let parts = pair.split(separator: "=")
            if parts.count == 2, let n = Int(parts[1]) { dict[String(parts[0])] = n }
        }
        counts[emoji, default: 0] += 1
        countsRaw = counts.sorted { $0.value > $1.value }.prefix(40).map { "\($0.key)=\($0.value)" }.joined(separator: " ")
        HapticEngine.shared.play(.selection)
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
    var initialSection: String? = nil
    var onPick: (ModulaSticker) -> Void
    @State private var packs: [ModulaStickerPack] = []
    @State private var selected: String = "animated"
    @State private var failed = false
    @State private var loading = true
    @State private var editingPack: ModulaCustomStickerPack?
    @State private var creatingPack = false
    @State private var premiumKind: ModulaMascotKind?
    @State private var custom = ModulaCustomStickerStore.shared
    @AppStorage("composer.recentStickers") private var recentStickersRaw = ""

    /// Recent stickers persist between sessions as "id|pack|emoji|label" records.
    private var recentStickers: [ModulaSticker] {
        recentStickersRaw.split(separator: "\u{1E}").compactMap { record in
            let p = record.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            return p.count == 4 ? ModulaSticker(id: p[0], packID: p[1], emoji: p[2], label: p[3]) : nil
        }
    }

    private func pickSticker(_ sticker: ModulaSticker) {
        onPick(sticker)
        var list = recentStickers.filter { $0.id != sticker.id }
        list.insert(sticker, at: 0)
        recentStickersRaw = list.prefix(16).map { "\($0.id)|\($0.packID)|\($0.emoji)|\($0.label)" }.joined(separator: "\u{1E}")
        HapticEngine.shared.play(.success)
    }

    private struct Section: Identifiable { let id: String; let title: String; let icon: String; let isSymbol: Bool }

    private var sections: [Section] {
        (recentStickers.isEmpty ? [] : [Section(id: "recent", title: "Recent", icon: "clock", isSymbol: true)])
        + [Section(id: "animated", title: "Animated", icon: "sparkles", isSymbol: true),
         Section(id: "mascots", title: "Moliboos", icon: "pawprint.fill", isSymbol: true)]
        + packs.map { Section(id: $0.id, title: $0.title, icon: $0.icon, isSymbol: false) }
        + custom.packs.map { Section(id: "custom.\($0.id)", title: $0.title, icon: $0.emoji.first ?? "⭐️", isSymbol: false) }
        + [Section(id: "mine", title: "My packs", icon: "plus.square.on.square", isSymbol: true)]
    }

    var body: some View {
        VStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(sections) { section in
                        Button {
                            selected = section.id
                            HapticEngine.shared.play(.selection)
                        } label: {
                            Group {
                                if section.isSymbol { Image(systemName: section.icon).font(.system(size: 17, weight: .semibold)).foregroundStyle(selected == section.id ? Color.white : Color.primary) }
                                else { Text(section.icon).font(.title2) }
                            }
                            .frame(width: 44, height: 38)
                        }
                        .buttonStyle(.plain)
                        .modulaGlass(in: Capsule(), tint: selected == section.id ? .accentColor : nil)
                        .accessibilityLabel(section.title)
                        .accessibilityAddTraits(selected == section.id ? .isSelected : [])
                    }
                    if loading { ProgressView().padding(.horizontal, 8) }
                }
                .padding(.vertical, 4)
            }
            .contentMargins(.horizontal, 12, for: .scrollContent)
            .modulaHorizontalEdgeFade()
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text(sections.first { $0.id == selected }?.title ?? "")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    content
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            }
        }
        .task { await load() }
        .onAppear { if let initialSection { selected = initialSection } }
        .sheet(isPresented: $creatingPack) { ModulaCustomPackEditor(pack: nil) }
        .sheet(item: $editingPack) { ModulaCustomPackEditor(pack: $0) }
        .sheet(item: $premiumKind) { MascotPremiumSheet(kind: $0) }
        .accessibilityIdentifier("composer.panel.stickers.grid")
    }

    private var columns: [GridItem] { Array(repeating: GridItem(.flexible(), spacing: 8), count: 4) }

    @ViewBuilder
    private var content: some View {
        switch selected {
        case "recent":
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(recentStickers) { sticker in
                    Button { pickSticker(sticker) } label: { ModulaStickerView(emoji: sticker.emoji, size: 64) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(sticker.label) sticker")
                        .contextMenu { Button("Send") { pickSticker(sticker) } } preview: { ModulaStickerView(emoji: sticker.emoji, size: 180).padding(12) }
                }
            }
        case "animated":
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(ModulaAnimatedSticker.Style.allCases) { style in
                    stickerButton(ModulaLocalSticker(kind: .anim, value: style.rawValue)) { ModulaAnimatedSticker(style: style, size: 70) }
                }
            }
        case "mascots":
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(ModulaMascotKind.allCases) { kind in
                    let locked = !MascotEntitlements.canUse(kind)
                    Button {
                        if locked { premiumKind = kind; HapticEngine.shared.play(.lightImpact) }
                        else { pickSticker(ModulaLocalSticker(kind: .mascot, value: kind.rawValue).asSticker) }
                    } label: {
                        ModulaMascotSticker(kind: kind, size: 70)
                            .opacity(locked ? 0.55 : 1)
                            .overlay(alignment: .topTrailing) {
                                if kind.isPremium { MascotPremiumBadge(locked: locked) }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(kind.name) sticker\(locked ? ", Premium" : "")")
                    .contextMenu { if !locked { Button("Send") { pickSticker(ModulaLocalSticker(kind: .mascot, value: kind.rawValue).asSticker) } } } preview: {
                        ModulaMascotSticker(kind: kind, size: 180).padding(12)
                    }
                }
            }
        case "mine":
            VStack(alignment: .leading, spacing: 10) {
                Button { creatingPack = true } label: {
                    Label("New sticker pack", systemImage: "plus").font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16).frame(height: 44).frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .modulaGlass(in: Capsule(), tint: .accentColor)
                ForEach(custom.packs) { pack in
                    HStack {
                        Text(pack.emoji.prefix(5).joined()).font(.title3)
                        VStack(alignment: .leading) {
                            Text(pack.title).font(.subheadline.weight(.semibold))
                            Text("\(pack.emoji.count) stickers").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { editingPack = pack } label: { Image(systemName: "pencil").frame(width: 36, height: 36) }
                            .buttonStyle(.plain).modulaGlass(in: Circle())
                            .accessibilityLabel("Edit \(pack.title)")
                        Button(role: .destructive) { custom.delete(pack) } label: { Image(systemName: "trash").frame(width: 36, height: 36) }
                            .buttonStyle(.plain).foregroundStyle(.red).modulaGlass(in: Circle())
                            .accessibilityLabel("Delete \(pack.title)")
                    }
                    .padding(10)
                    .modulaGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous), interactive: false)
                }
                if custom.packs.isEmpty {
                    Text("Make your own packs from any emoji. They’re saved on this device and send as stickers in comments.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        default:
            if selected.hasPrefix("custom."), let pack = custom.packs.first(where: { "custom.\($0.id)" == selected }) {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(pack.emoji, id: \.self) { emoji in
                        stickerButton(ModulaLocalSticker(kind: .emoji, value: emoji)) { ModulaStickerView(emoji: emoji, size: 64) }
                    }
                }
            } else if let pack = packs.first(where: { $0.id == selected }) {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(pack.stickers) { sticker in
                        Button { pickSticker(sticker) } label: {
                            ModulaStickerView(emoji: sticker.emoji, size: 64)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(sticker.label) sticker")
                        .contextMenu { Button("Send") { pickSticker(sticker) } } preview: { ModulaStickerView(emoji: sticker.emoji, size: 180).padding(12) }
                    }
                }
            } else if failed {
                HStack {
                    Text("Couldn’t load the Modula packs.").font(.footnote).foregroundStyle(.secondary)
                    Button("Retry") { Task { await load() } }.font(.footnote.weight(.semibold))
                }
            }
        }
    }

    private func stickerButton<V: View>(_ sticker: ModulaLocalSticker, @ViewBuilder label: () -> V) -> some View {
        Button { pickSticker(sticker.asSticker) } label: { label() }
            .buttonStyle(.plain)
            .accessibilityLabel("\(sticker.label) sticker")
    }

    private func load() async {
        failed = false
        loading = true
        do { packs = try await ModulaStickerCatalog.packs(client: client) } catch { failed = true }
        loading = false
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
    var onAlternative: ((ModulaComposerMediaPanel.Tab) -> Void)? = nil

    @State private var query = ""
    @State private var items: [ModulaGif] = []
    @State private var nextOffset: Int?
    @State private var state: LoadState = .idle
    @State private var showingFavourites = false
    @State private var favourites = ModulaGifFavourites.shared

    enum LoadState: Equatable { case idle, loading, loaded, notConfigured, failed(String) }

    private static let categories = ["Trending", "Reactions", "LOL", "Love", "Happy", "Sad", "Celebrate", "Thumbs up", "Wow", "Yes", "No", "Thank you", "Hello"]

    var body: some View {
        VStack(spacing: 10) {
            ModulaGlassSearchField(prompt: "Search GIPHY", text: $query).padding(.horizontal, 12)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    chip("★ Favourites", active: showingFavourites) { showingFavourites = true }
                    ForEach(Self.categories, id: \.self) { category in
                        let active = !showingFavourites && (category == "Trending" ? query.isEmpty : query.caseInsensitiveCompare(category) == .orderedSame)
                        chip(category, active: active) {
                            showingFavourites = false
                            query = category == "Trending" ? "" : category
                        }
                    }
                }
                // Room for the glass rim and selected tint so nothing is clipped.
                .padding(.vertical, 5)
            }
            .contentMargins(.horizontal, 12, for: .scrollContent)
            .scrollClipDisabled()
            .modulaHorizontalEdgeFade()
            .frame(height: 44)
            content
        }
        .task(id: query) {
            if !query.isEmpty { showingFavourites = false; try? await Task.sleep(for: .milliseconds(350)) }
            guard !Task.isCancelled else { return }
            await load(reset: true)
        }
    }

    private func chip(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
            HapticEngine.shared.play(.selection)
        } label: {
            Text(title).font(.caption.weight(.semibold)).lineLimit(1)
                .padding(.horizontal, 14).frame(height: 32)
                .foregroundStyle(active ? Color.primary : Color.secondary)
        }
        .buttonStyle(.plain)
        .modulaGlass(in: Capsule(), tint: active ? .accentColor : nil)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    @ViewBuilder
    private var content: some View {
        if showingFavourites {
            if favourites.items.isEmpty {
                emptyState(symbol: "star", title: "No favourite GIFs yet", message: "Touch and hold any GIF and choose Favourite to keep it here.")
            } else {
                grid(favourites.items, paging: false)
            }
        } else {
            switch state {
            case .notConfigured:
                emptyState(symbol: "play.square.stack", title: "GIFs are taking a nap", message: "GIF search isn’t switched on for this server yet. Stickers and emoji work right now.", alternatives: true)
                    .accessibilityIdentifier("composer.gifs.unconfigured")
            case .failed(let message):
                emptyState(symbol: "wifi.exclamationmark", title: "Couldn’t load GIFs", message: message, alternatives: true, retry: true)
            default:
                if state == .loaded && items.isEmpty {
                    emptyState(symbol: "magnifyingglass", title: "No GIFs for “\(query)”", message: "Try another word, or send a sticker instead.", alternatives: true)
                } else {
                    grid(items, paging: true)
                }
            }
        }
    }

    /// Two-column masonry: each GIF keeps its aspect ratio; columns are balanced by height.
    private func masonry(_ gifs: [ModulaGif]) -> [[ModulaGif]] {
        var columns: [[ModulaGif]] = [[], []]
        var heights: [CGFloat] = [0, 0]
        for gif in gifs {
            let ratio = CGFloat(gif.height ?? 1) / CGFloat(max(gif.width ?? 1, 1))
            let i = heights[0] <= heights[1] ? 0 : 1
            columns[i].append(gif)
            heights[i] += min(max(ratio, 0.5), 1.8)
        }
        return columns
    }

    private func grid(_ gifs: [ModulaGif], paging: Bool) -> some View {
        ScrollView {
            HStack(alignment: .top, spacing: 4) {
                ForEach(Array(masonry(gifs).enumerated()), id: \.offset) { _, column in
                    LazyVStack(spacing: 4) {
                        ForEach(column) { gif in
                            gifCell(gif, paging: paging)
                        }
                    }
                }
            }
            .padding(.horizontal, 10)
            if paging && state == .loading { ProgressView().padding() }
            Text("Powered by GIPHY").font(.caption2).foregroundStyle(.tertiary).padding(.vertical, 6)
        }
        .scrollIndicators(.hidden)
    }

    private func gifCell(_ gif: ModulaGif, paging: Bool) -> some View {
        let ratio = min(max(CGFloat(gif.height ?? 1) / CGFloat(max(gif.width ?? 1, 1)), 0.5), 1.8)
        return Button { onPick(gif) } label: {
                        ModulaAnimatedRemoteImage(url: gif.previewURL)
                            .frame(maxWidth: .infinity)
                            .aspectRatio(1 / ratio, contentMode: .fill)
                            .background(Color.primary.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(alignment: .topTrailing) {
                                if favourites.contains(gif) {
                                    Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow).padding(5)
                                        .shadow(radius: 2)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(gif.title ?? "GIF")
                    .contextMenu {
                        Button(favourites.contains(gif) ? "Remove from favourites" : "Favourite",
                               systemImage: favourites.contains(gif) ? "star.slash" : "star") { favourites.toggle(gif) }
                    }
                    .onAppear {
                        if paging, gif.id == items.last?.id, nextOffset != nil { Task { await load(reset: false) } }
                    }
    }

    private func emptyState(symbol: String, title: String, message: String, alternatives: Bool = false, retry: Bool = false) -> some View {
        ScrollView {
            VStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 60, height: 60)
                    .modulaGlass(in: Circle(), interactive: false, specular: true)
                    .symbolEffect(.pulse, options: .repeating)
                Text(title).font(.headline)
                Text(message).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                if retry {
                    Button("Try again") { Task { await load(reset: true) } }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16).frame(height: 36)
                        .modulaGlass(in: Capsule())
                }
                if alternatives, let onAlternative {
                    HStack(spacing: 8) {
                        ForEach(ModulaAnimatedSticker.Style.allCases.prefix(4)) { style in
                            ModulaAnimatedSticker(style: style, size: 52)
                        }
                    }
                    .padding(.top, 2)
                    HStack(spacing: 8) {
                        Button { onAlternative(.stickers) } label: {
                            Label("Stickers", systemImage: "seal").font(.subheadline.weight(.semibold)).padding(.horizontal, 14).frame(height: 36)
                        }
                        .buttonStyle(.plain).modulaGlass(in: Capsule(), tint: .accentColor)
                        Button { onAlternative(.emoji) } label: {
                            Label("Emoji", systemImage: "face.smiling").font(.subheadline.weight(.semibold)).padding(.horizontal, 14).frame(height: 36)
                        }
                        .buttonStyle(.plain).modulaGlass(in: Capsule())
                        Button { onAlternative(.kaomoji) } label: {
                            Text("(◕‿◕)").font(.subheadline.weight(.semibold)).padding(.horizontal, 14).frame(height: 36)
                        }
                        .buttonStyle(.plain).modulaGlass(in: Capsule())
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
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

/// iOS-keyboard-like key press: a soft lift + highlight, with no lingering selection state.
private struct EmojiKeyStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.10 : 0))
            )
            .scaleEffect(configuration.isPressed ? 1.18 : 1)
            .animation(.spring(response: 0.18, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
