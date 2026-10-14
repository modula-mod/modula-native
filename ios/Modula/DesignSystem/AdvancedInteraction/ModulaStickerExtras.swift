import SwiftUI

// MARK: - Local stickers (client-rendered, carried in comment text)
//
// Greenfield only accepts its own first-party sticker IDs as comment media, so animated,
// mascot and custom-pack stickers travel as a short token in the comment text:
//   {{sticker:anim:party}}  {{sticker:mascot:pip}}  {{sticker:emoji:🦄}}
// Current clients render them as stickers; older clients show the token as text.

struct ModulaLocalSticker: Hashable, Identifiable {
    enum Kind: String { case anim, mascot, emoji }
    let kind: Kind
    let value: String
    var id: String { token }
    var token: String { "{{sticker:\(kind.rawValue):\(value)}}" }

    var label: String {
        switch kind {
        case .anim: ModulaAnimatedSticker.Style(rawValue: value)?.label ?? "Sticker"
        case .mascot: ModulaMascotKind(rawValue: value)?.name ?? "Moliboo"
        case .emoji: value
        }
    }

    /// As a pending composer item (same pipeline as first-party stickers).
    var asSticker: ModulaSticker {
        ModulaSticker(id: token, packID: "local.\(kind.rawValue)", emoji: kind == .emoji ? value : (kind == .anim ? (ModulaAnimatedSticker.Style(rawValue: value)?.emoji ?? "✨") : "🐾"), label: label)
    }

    private static let regex = try! NSRegularExpression(pattern: #"\{\{sticker:(anim|mascot|emoji):([^}\s]{1,24})\}\}"#)

    /// Pulls sticker tokens out of comment text; returns them plus the remaining text.
    static func extract(_ text: String) -> (stickers: [ModulaLocalSticker], text: String) {
        guard text.contains("{{sticker:") else { return ([], text) }
        let ns = text as NSString
        var stickers: [ModulaLocalSticker] = []
        for m in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            guard let kind = Kind(rawValue: ns.substring(with: m.range(at: 1))) else { continue }
            let value = ns.substring(with: m.range(at: 2))
            if kind == .mascot && ModulaMascotKind(rawValue: value) == nil { continue }
            if kind == .anim && ModulaAnimatedSticker.Style(rawValue: value) == nil { continue }
            stickers.append(ModulaLocalSticker(kind: kind, value: value))
        }
        let stripped = regex.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: ns.length), withTemplate: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (stickers, stripped)
    }

    static func from(_ sticker: ModulaSticker) -> ModulaLocalSticker? {
        guard sticker.packID.hasPrefix("local.") else { return nil }
        return extract(sticker.id).stickers.first
    }
}

struct ModulaLocalStickerView: View {
    let sticker: ModulaLocalSticker
    var size: CGFloat = 96
    var body: some View {
        switch sticker.kind {
        case .anim:
            if let style = ModulaAnimatedSticker.Style(rawValue: sticker.value) { ModulaAnimatedSticker(style: style, size: size) }
        case .mascot:
            if let kind = ModulaMascotKind(rawValue: sticker.value) { ModulaMascotSticker(kind: kind, size: size) }
        case .emoji:
            ModulaStickerView(emoji: sticker.value, size: size)
        }
    }
}

/// Row of local stickers on a posted comment.
struct ModulaLocalStickerRow: View {
    let stickers: [ModulaLocalSticker]
    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(stickers.prefix(4).enumerated()), id: \.offset) { _, sticker in
                ModulaLocalStickerView(sticker: sticker, size: 96)
                    .accessibilityLabel("\(sticker.label) sticker")
            }
        }
    }
}

// MARK: - Animated emoji stickers (pure SwiftUI, no Lottie)

struct ModulaAnimatedSticker: View {
    enum Style: String, CaseIterable, Identifiable {
        case party, love, fire, laugh, wave, star, rocket, clap, mind, cool, cry, sparkle, thinking, hundred, ghost, rainbow
        var id: String { rawValue }
        var emoji: String {
            switch self {
            case .party: "🎉"; case .love: "❤️"; case .fire: "🔥"; case .laugh: "😂"; case .wave: "👋"; case .star: "⭐️"
            case .rocket: "🚀"; case .clap: "👏"; case .mind: "🤯"; case .cool: "😎"; case .cry: "😭"; case .sparkle: "✨"
            case .thinking: "🤔"; case .hundred: "💯"; case .ghost: "👻"; case .rainbow: "🌈"
            }
        }
        var label: String { rawValue.capitalized }
        enum Motion { case bounce, beat, flicker, shake, wave, spin, launch, pop, float }
        var motion: Motion {
            switch self {
            case .party, .clap, .hundred: .pop
            case .love: .beat
            case .fire, .sparkle: .flicker
            case .laugh, .cry, .mind: .shake
            case .wave: .wave
            case .star, .cool: .spin
            case .rocket: .launch
            case .ghost, .thinking, .rainbow: .float
            }
        }
    }

    let style: Style
    var size: CGFloat = 96
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            let f = transform(t)
            ZStack {
                if style.motion == .pop || style == .sparkle {
                    ForEach(0..<6, id: \.self) { i in
                        let phase = (t * 0.9 + Double(i) / 6).truncatingRemainder(dividingBy: 1)
                        let angle = Double(i) / 6 * .pi * 2
                        Circle()
                            .fill([Color.pink, .yellow, .mint, .purple, .orange, .blue][i])
                            .frame(width: size * 0.06, height: size * 0.06)
                            .offset(x: cos(angle) * size * 0.42 * phase, y: sin(angle) * size * 0.42 * phase)
                            .opacity(1 - phase)
                    }
                }
                Text(style.emoji)
                    .font(.system(size: size * 0.6))
                    .shadow(color: .white, radius: 0, x: 1.5, y: 1.5)
                    .shadow(color: .white, radius: 0, x: -1.5, y: -1.5)
                    .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
                    .scaleEffect(x: f.sx, y: f.sy, anchor: .bottom)
                    .rotationEffect(.degrees(f.rot), anchor: style.motion == .wave ? .bottomTrailing : .center)
                    .offset(x: f.dx, y: f.dy)
                    .opacity(f.alpha)
            }
            .frame(width: size, height: size)
        }
        .accessibilityLabel("\(style.label) animated sticker")
    }

    private func transform(_ t: Double) -> (sx: CGFloat, sy: CGFloat, rot: Double, dx: CGFloat, dy: CGFloat, alpha: Double) {
        switch style.motion {
        case .bounce, .pop:
            let p = abs(sin(t * 3.2))
            return (1 + 0.06 * (1 - p), 1 - 0.06 * (1 - p) + 0.04 * p, 0, 0, -CGFloat(p) * size * 0.08, 1)
        case .beat:
            let p = pow(max(0, sin(t * 6)), 8) + 0.6 * pow(max(0, sin(t * 6 - 0.9)), 8)
            return (1 + 0.14 * p, 1 + 0.14 * p, 0, 0, 0, 1)
        case .flicker:
            return (1 + 0.04 * sin(t * 11), 1 + 0.07 * sin(t * 7.3), 3 * sin(t * 5), 0, 0, 0.9 + 0.1 * sin(t * 13))
        case .shake:
            return (1, 1, 7 * sin(t * 18) * max(0, sin(t * 2)), CGFloat(2 * sin(t * 22)), 0, 1)
        case .wave:
            return (1, 1, 18 * sin(t * 7), 0, 0, 1)
        case .spin:
            return (CGFloat(cos(t * 2.4)), 1, 0, 0, CGFloat(-3 * sin(t * 4.8)), 1)
        case .launch:
            let p = (t * 0.7).truncatingRemainder(dividingBy: 1)
            let y = p < 0.7 ? -sin(p / 0.7 * .pi) * 0.12 : 0
            return (1, 1, -8 + 4 * sin(t * 20), CGFloat(1.5 * sin(t * 25)), CGFloat(y) * size, 1)
        case .float:
            return (1, 1, 4 * sin(t * 1.6), CGFloat(sin(t * 1.1)) * size * 0.04, CGFloat(sin(t * 2.2)) * size * 0.06, 1)
        }
    }
}

// MARK: - Mascot stickers

struct ModulaMascotSticker: View {
    let kind: ModulaMascotKind
    var size: CGFloat = 96
    var mood: MascotMood = .happy
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            ModulaMascotFigure(kind: kind, pose: pose(t), size: size * 0.42)
                .frame(width: size, height: size)
                .background(Circle().fill(kind.palette.light.opacity(0.35)))
        }
        .accessibilityLabel("\(kind.name) Moliboo sticker")
    }

    private func pose(_ t: Double) -> MascotPose {
        var pose = MascotPose(t: t, mood: mood, amp: reduceMotion ? 0 : 1)
        pose.hop = CGFloat(max(0, sin(t * 2.6))) * size * 0.05
        pose.breathe = CGFloat(sin(t * 1.4)) * 0.5 + 0.5
        return pose
    }
}

// MARK: - Kaomoji / text faces

enum ModulaKaomoji {
    static let sections: [(String, [String])] = [
        ("Happy", ["(◕‿◕)", "(＾▽＾)", "ヽ(•‿•)ノ", "(✿◠‿◠)", "(*^▽^*)", "٩(◕‿◕)۶", "(ﾉ◕ヮ◕)ﾉ*:･ﾟ✧", "( ˘ ³˘)♥", "(ᵔᴥᵔ)", "(¬‿¬)"]),
        ("Love", ["(♥ω♥*)", "(´∀｀)♡", "(｡♥‿♥｡)", "♡( ◡‿◡ )", "(っ˘з(˘⌣˘ )", "(づ｡◕‿‿◕｡)づ", "( ˘⌣˘)♡(˘⌣˘ )"]),
        ("Shrug & meh", ["¯\\_(ツ)_/¯", "┐(´ー｀)┌", "(¬_¬)", "(￣ヘ￣)", "(-_-;)", "ಠ_ಠ", "(・_・;)"]),
        ("Sad", ["(╥﹏╥)", "(ಥ﹏ಥ)", "(T_T)", "(｡•́︿•̀｡)", "(っ˘̩╭╮˘̩)っ", "(´；ω；`)"]),
        ("Angry", ["(╯°□°)╯︵ ┻━┻", "┬─┬ノ( º _ ºノ)", "(ง •̀_•́)ง", "(ノಠ益ಠ)ノ彡┻━┻", "(¬､¬)", "ᕦ(ò_óˇ)ᕤ"]),
        ("Animals", ["ʕ•ᴥ•ʔ", "(=^･ω･^=)", "U・ᴥ・U", "(・⊝・)", "<コ:彡", "~>°)～～～", "🐾(ฅ'ω'ฅ)"]),
        ("Actions", ["(っ•́｡•́)♪♬", "( •_•)>⌐■-■", "(⌐■_■)", "ᕕ( ᐛ )ᕗ", "(￣▽￣)ノ", "o(≧▽≦)o", "(ﾉ´ヮ`)ﾉ*: ･ﾟ"]),
    ]
}

struct ModulaKaomojiGrid: View {
    var onPick: (String) -> Void
    @AppStorage("composer.recentKaomoji") private var recentRaw = ""
    private var recents: [String] { recentRaw.isEmpty ? [] : recentRaw.components(separatedBy: "\u{1F}") }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10, pinnedViews: [.sectionHeaders]) {
                if !recents.isEmpty { section("Recent", recents) }
                ForEach(ModulaKaomoji.sections, id: \.0) { title, faces in section(title, faces) }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .accessibilityIdentifier("composer.panel.kaomoji")
    }

    private func section(_ title: String, _ faces: [String]) -> some View {
        Section {
            ModulaFlowLayout(spacing: 6) {
                ForEach(faces, id: \.self) { face in
                    Button {
                        onPick(face)
                        var list = recents.filter { $0 != face }
                        list.insert(face, at: 0)
                        recentRaw = list.prefix(12).joined(separator: "\u{1F}")
                        HapticEngine.shared.play(.selection)
                    } label: {
                        Text(face).font(.callout).lineLimit(1).padding(.horizontal, 12).frame(height: 36)
                    }
                    .buttonStyle(.plain)
                    .modulaGlass(in: Capsule())
                }
            }
        } header: {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.vertical, 2)
        }
    }
}

/// Simple wrapping flow layout.
struct ModulaFlowLayout: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0
        for view in subviews {
            let s = view.sizeThatFits(.unspecified)
            if x + s.width > width, x > 0 { x = 0; y += row + spacing; row = 0 }
            x += s.width + spacing
            row = max(row, s.height)
        }
        return CGSize(width: width, height: y + row)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for view in subviews {
            let s = view.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += row + spacing; row = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            row = max(row, s.height)
        }
    }
}

// MARK: - Custom sticker packs (local)

struct ModulaCustomStickerPack: Codable, Identifiable, Hashable {
    var id = UUID().uuidString
    var title: String
    var emoji: [String]
}

@MainActor @Observable
final class ModulaCustomStickerStore {
    static let shared = ModulaCustomStickerStore()
    private let key = "composer.customStickerPacks"
    var packs: [ModulaCustomStickerPack] = []

    init() {
        if let data = UserDefaults.standard.data(forKey: key), let decoded = try? JSONDecoder().decode([ModulaCustomStickerPack].self, from: data) {
            packs = decoded
        }
    }

    func save(_ pack: ModulaCustomStickerPack) {
        if let index = packs.firstIndex(where: { $0.id == pack.id }) { packs[index] = pack } else { packs.append(pack) }
        persist()
    }

    func delete(_ pack: ModulaCustomStickerPack) {
        packs.removeAll { $0.id == pack.id }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(packs) { UserDefaults.standard.set(data, forKey: key) }
    }
}

struct ModulaCustomPackEditor: View {
    var pack: ModulaCustomStickerPack?
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var emojiText = ""

    private var emoji: [String] {
        var seen = Set<String>()
        return emojiText.filter { $0.unicodeScalars.contains { $0.properties.isEmojiPresentation || $0.properties.isEmoji && $0.value > 0xFF } }
            .map(String.init).filter { seen.insert($0).inserted }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                TextField("Pack name", text: $title)
                    .padding(.horizontal, 14).frame(height: 44)
                    .modulaGlass(in: Capsule(), interactive: false, specular: true)
                TextField("Type or paste emoji for this pack", text: $emojiText, axis: .vertical)
                    .lineLimit(2...4)
                    .padding(12)
                    .modulaGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous), interactive: false, specular: true)
                if !emoji.isEmpty {
                    ScrollView {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 8) {
                            ForEach(emoji, id: \.self) { ModulaStickerView(emoji: $0, size: 56) }
                        }
                    }
                } else {
                    Text("Each emoji becomes a die-cut sticker you can send in comments.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(20)
            .navigationTitle(pack == nil ? "New sticker pack" : "Edit pack")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var updated = pack ?? ModulaCustomStickerPack(title: "", emoji: [])
                        updated.title = title.isEmpty ? "My stickers" : title
                        updated.emoji = Array(emoji.prefix(48))
                        ModulaCustomStickerStore.shared.save(updated)
                        HapticEngine.shared.play(.success)
                        dismiss()
                    }
                    .disabled(emoji.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            title = pack?.title ?? ""
            emojiText = pack?.emoji.joined() ?? ""
        }
    }
}

// MARK: - GIF favourites (local)

@MainActor @Observable
final class ModulaGifFavourites {
    static let shared = ModulaGifFavourites()
    private struct Stored: Codable { var id: String; var title: String?; var url: URL; var preview: URL; var width: Int?; var height: Int? }
    private let key = "composer.gifFavourites"
    private(set) var items: [ModulaGif] = []

    init() {
        if let data = UserDefaults.standard.data(forKey: key), let stored = try? JSONDecoder().decode([Stored].self, from: data) {
            items = stored.map { ModulaGif(id: $0.id, title: $0.title, url: $0.url, previewURL: $0.preview, width: $0.width, height: $0.height) }
        }
    }

    func contains(_ gif: ModulaGif) -> Bool { items.contains { $0.id == gif.id } }

    func toggle(_ gif: ModulaGif) {
        if contains(gif) { items.removeAll { $0.id == gif.id } } else { items.insert(gif, at: 0) }
        let stored = items.prefix(60).map { Stored(id: $0.id, title: $0.title, url: $0.url, preview: $0.previewURL, width: $0.width, height: $0.height) }
        if let data = try? JSONEncoder().encode(Array(stored)) { UserDefaults.standard.set(data, forKey: key) }
        HapticEngine.shared.play(.selection)
    }
}

// MARK: - Edge fade for horizontal chip rows

extension View {
    func modulaHorizontalEdgeFade(_ width: CGFloat = 16) -> some View {
        mask {
            HStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing).frame(width: width)
                Rectangle()
                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing).frame(width: width)
            }
        }
    }
}
