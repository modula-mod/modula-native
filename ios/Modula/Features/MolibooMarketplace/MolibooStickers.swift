import SwiftUI
import UIKit

// MARK: - Moliboo stickers
//
// Every Moliboo has a sticker set: its live code-drawn figure frozen in an expression, with a white die-cut edge
// and an optional caption. Rendered on device (no sticker catalogue is downloaded). Tap copies a PNG to paste
// anywhere; the composer's mascot stickers stay as they were.

struct MolibooStickerExpression: Identifiable, Hashable {
    let id: String
    let label: String
    let caption: String?
    let mood: MascotMood
    let t: Double

    var pose: MascotPose { MascotPose(t: t, mood: mood, amp: 1) }

    static func == (a: Self, b: Self) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }

    static let all: [MolibooStickerExpression] = [
        .init(id: "happy", label: "Happy", caption: nil, mood: .happy, t: 0.3),
        .init(id: "hi", label: "Hi!", caption: "Hi!", mood: .wave, t: 0.45),
        .init(id: "lol", label: "LOL", caption: "LOL", mood: .laughing, t: 0.2),
        .init(id: "yay", label: "Yay", caption: "Yay!", mood: .celebrate, t: 0.35),
        .init(id: "excited", label: "Excited", caption: nil, mood: .excited, t: 0.25),
        .init(id: "love", label: "Aww", caption: "Aww", mood: .pleased, t: 0.5),
        .init(id: "curious", label: "Hmm?", caption: "Hmm?", mood: .curious, t: 0.6),
        .init(id: "thinking", label: "Thinking", caption: nil, mood: .thinking, t: 0.4),
        .init(id: "wow", label: "Wow", caption: "Wow!", mood: .surprised, t: 0.3),
        .init(id: "shy", label: "Shy", caption: nil, mood: .shy, t: 0.5),
        .init(id: "dance", label: "Dance", caption: nil, mood: .dance, t: 0.7),
        .init(id: "dizzy", label: "Dizzy", caption: nil, mood: .dizzy, t: 0.55),
        .init(id: "sleepy", label: "Sleepy", caption: "zzz", mood: .sleepy, t: 0.4),
        .init(id: "sad", label: "Sad", caption: nil, mood: .sad, t: 0.4),
        .init(id: "bye", label: "Bye", caption: "Bye!", mood: .wave, t: 0.9),
        .init(id: "chill", label: "Chill", caption: nil, mood: .sit, t: 0.3),
    ]

    /// Renders a 512 px PNG sticker and copies it to the clipboard.
    @MainActor static func copy(kind: ModulaMascotKind, _ e: MolibooStickerExpression) -> Bool {
        let r = ImageRenderer(content: MolibooStickerArt(kind: kind, expression: e, size: 256))
        r.scale = 2
        guard let img = r.uiImage else { return false }
        UIPasteboard.general.image = img
        return true
    }
}

/// One sticker: die-cut white edge around the live figure, soft shadow, caption bubble.
struct MolibooStickerArt: View {
    let kind: ModulaMascotKind
    let expression: MolibooStickerExpression
    var size: CGFloat

    var body: some View {
        let s = size * 0.46
        let figure = ModulaMascotFigure(kind: kind, pose: expression.pose, size: s)
        ZStack(alignment: .bottom) {
            ZStack {
                // White sticker edge: the silhouette offset in eight directions, flattened to white.
                ForEach(0..<8, id: \.self) { i in
                    let a = Double(i) * .pi / 4
                    figure.colorMultiply(.black).colorInvert()
                        .offset(x: CGFloat(cos(a)) * size * 0.022, y: CGFloat(sin(a)) * size * 0.022)
                }
                figure
            }
            .compositingGroup()
            .shadow(color: .black.opacity(0.18), radius: size * 0.02, y: size * 0.012)
            if let caption = expression.caption {
                Text(caption)
                    .font(.system(size: size * 0.12, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, size * 0.06).padding(.vertical, size * 0.018)
                    .background(kind.palette.dark, in: Capsule())
                    .overlay(Capsule().stroke(.white, lineWidth: size * 0.018))
                    .rotationEffect(.degrees(-6))
                    .offset(y: -size * 0.02)
            }
        }
        .frame(width: size, height: size)
    }
}

/// Stickers tab: browse every Moliboo's set by family, pick a Moliboo, tap a sticker to copy it.
struct MolibooStickerBrowser: View {
    let notify: (String) -> Void
    @State private var family: MolibooFamily = .originals
    @State private var kind: ModulaMascotKind = .pip

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Sticker sets").font(.title2.weight(.bold))
                Text("\(ModulaMascotKind.allCases.count) Moliboos × \(MolibooStickerExpression.all.count) stickers. Tap one to copy it, then paste it in any chat.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(MolibooFamily.allCases) { f in
                        let c = f.kinds.first?.palette.mid ?? .pink
                        Button { family = f; if let first = f.kinds.first { kind = first } } label: {
                            HStack(spacing: 6) {
                                Circle().fill(c).frame(width: 10, height: 10)
                                Text(f.label).font(.subheadline.weight(.semibold))
                            }
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(c.opacity(family == f ? 0.32 : 0.1), in: Capsule())
                            .overlay(Capsule().stroke(c.opacity(family == f ? 0.9 : 0.3), lineWidth: family == f ? 1.5 : 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(family == f ? .isSelected : [])
                        .accessibilityIdentifier("moliboo.stickers.family.\(f.rawValue)")
                    }
                }
                .padding(.horizontal, 16)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    ForEach(family.kinds) { k in
                        Button { kind = k } label: {
                            VStack(spacing: 2) {
                                ModulaMascotFigure(kind: k, pose: .still(), size: 24).frame(width: 52, height: 46)
                                Text(k.name).font(.caption2).lineLimit(1).frame(width: 60)
                            }
                            .padding(4)
                            .background((kind == k ? k.palette.mid.opacity(0.3) : Color.primary.opacity(0.04)), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(k.name) stickers")
                        .accessibilityIdentifier("moliboo.stickers.kind.\(k.rawValue)")
                    }
                }
                .padding(.horizontal, 16)
            }
            .frame(height: 76)
            HStack {
                Text("\(kind.name) stickers").font(.headline)
                if kind.isDraft { Text("Series 2 draft").font(.caption.weight(.semibold)).foregroundStyle(.secondary) }
                Spacer()
                Text("#\(kind.catalogueNumber)").font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 98), spacing: 10)], spacing: 10) {
                ForEach(MolibooStickerExpression.all) { e in
                    Button {
                        notify(MolibooStickerExpression.copy(kind: kind, e) ? "\(kind.name) · \(e.label) copied" : "Couldn't make that sticker")
                    } label: {
                        MolibooStickerArt(kind: kind, expression: e, size: 98)
                            .padding(4)
                            .background(kind.palette.mid.opacity(0.1), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(kind.name) \(e.label) sticker")
                    .accessibilityIdentifier("moliboo.stickers.\(kind.rawValue).\(e.id)")
                }
            }
            .padding(.horizontal, 16)
        }
    }
}
