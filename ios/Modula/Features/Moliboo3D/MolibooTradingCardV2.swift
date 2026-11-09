import SwiftUI
import UIKit

// MARK: - Card face (v2)

struct MolibooTradingCardV2: View {
    let card: MolibooGalleryCard
    var width: CGFloat = 260
    var outfit: MascotOutfit = MascotWardrobeStore.shared.outfit
    var tilt: CGSize = .zero
    var faceDown = false
    var interactive = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var scheme

    static let base = CGSize(width: 260, height: 384)
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 22, style: .continuous) }
    private var scale: CGFloat { width / Self.base.width }

    var body: some View {
        ZStack {
            if faceDown { back } else { front }
        }
        .frame(width: Self.base.width, height: Self.base.height)
        .scaleEffect(scale)
        .frame(width: width, height: width * Self.base.height / Self.base.width)
        .rotation3DEffect(.degrees(Double(reduceMotion ? 0 : tilt.width) * 10), axis: (0, 1, 0), perspective: 0.65)
        .rotation3DEffect(.degrees(Double(reduceMotion ? 0 : -tilt.height) * 8), axis: (1, 0, 0), perspective: 0.65)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(faceDown
            ? "Face-down Moliboo card"
            : "\(card.name), number \(card.catalogueNumber), \(card.familyName), \(card.rarity.title). \(card.flavour)")
    }

    private var front: some View {
        ZStack {
            shape.fill(card.theme.paper)
            familyWash
            VStack(spacing: 0) {
                header
                artWindow
                footer
            }
            if interactive, !reduceMotion, !reduceTransparency {
                foil
                    .clipShape(shape)
                    .allowsHitTesting(false)
            }
            shape.strokeBorder(
                LinearGradient(colors: card.theme.foil, startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: card.rarity >= .rare ? 2.2 : 1.2
            )
        }
        .clipShape(shape)
        .shadow(color: card.theme.accent.opacity(interactive ? 0.28 : 0.12), radius: interactive ? 16 : 6, y: interactive ? 8 : 3)
        .shadow(color: .black.opacity(0.12), radius: interactive ? 12 : 4, y: 3)
    }

    private var familyWash: some View {
        LinearGradient(
            colors: [
                card.theme.accent.opacity(scheme == .dark ? 0.38 : 0.22),
                card.theme.secondary.opacity(0.10),
                card.theme.paper.opacity(0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .clipShape(shape)
        .allowsHitTesting(false)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("#\(card.catalogueNumber)")
                .font(.system(size: 13, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(card.theme.ink)
            VStack(alignment: .leading, spacing: 1) {
                Text(card.name)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(card.familyName)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(card.theme.accent)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            rarityBadge
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var rarityBadge: some View {
        Text(card.rarity.title)
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .foregroundStyle(card.rarity >= .legendary ? Color(red: 0.28, green: 0.16, blue: 0.04) : card.theme.ink)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(card.rarity.color.opacity(0.92), in: Capsule())
    }

    private var artWindow: some View {
        let artShape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return ZStack {
            LinearGradient(
                colors: [card.theme.accent.opacity(0.35), card.theme.secondary.opacity(0.18), card.theme.paper],
                startPoint: .top,
                endPoint: .bottom
            )
            MolibooCardArtWindow(card: card, outfit: card.isLegend ? .empty : outfit, tilt: reduceMotion ? .zero : tilt)
        }
        .frame(height: 210)
        .padding(.horizontal, 12)
        .clipShape(artShape)
        .overlay(artShape.strokeBorder(Color.white.opacity(0.55), lineWidth: 1))
        .padding(.horizontal, 2)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(card.title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(card.theme.ink)
            Text(card.flavour)
                .font(.system(size: 11, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 14)
    }

    private var foil: some View {
        let shift = (tilt.width + tilt.height) * 0.45
        return ZStack {
            LinearGradient(
                colors: [.clear, .white, card.theme.secondary, card.theme.accent, .white.opacity(0.4), .clear],
                startPoint: UnitPoint(x: -0.4 + shift, y: -0.2),
                endPoint: UnitPoint(x: 1.1 + shift, y: 1.2)
            )
            .blendMode(.overlay)
            .opacity(card.rarity.foil)
            RadialGradient(
                colors: [.white.opacity(0.35), .clear],
                center: UnitPoint(x: 0.5 + tilt.width * 0.4, y: 0.32 + tilt.height * 0.4),
                startRadius: 0,
                endRadius: 180
            )
            .blendMode(.softLight)
        }
    }

    private var back: some View {
        ZStack {
            shape.fill(
                LinearGradient(
                    colors: [card.theme.ink, card.theme.accent.mix(with: .black, by: 0.45)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .strokeBorder(card.theme.secondary.opacity(0.55), lineWidth: 2)
                        .frame(width: 92, height: 92)
                    Circle()
                        .fill(card.theme.accent.opacity(0.22))
                        .frame(width: 72, height: 72)
                    // Original back glyph — never the ribbon M logo.
                    MolibooCardBackGlyph(color: card.theme.secondary)
                        .frame(width: 54, height: 48)
                }
                Text("MOLIBOO")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .tracking(3)
                    .foregroundStyle(.white.opacity(0.86))
                Text("Trading Card")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
            }
            shape.strokeBorder(Color.white.opacity(0.16), lineWidth: 1.2)
        }
        .clipShape(shape)
    }
}

/// Two bead eyes and a small glossy body — original card-back mark, not the ribbon logo.
struct MolibooCardBackGlyph: View {
    var color: Color
    var body: some View {
        ZStack {
            Capsule()
                .fill(color)
                .frame(width: 44, height: 38)
            HStack(spacing: 8) {
                Circle().fill(Color.white).frame(width: 8, height: 8)
                    .overlay(Circle().fill(Color.black).frame(width: 4, height: 4).offset(x: 0.5, y: 0.5))
                Circle().fill(Color.white).frame(width: 8, height: 8)
                    .overlay(Circle().fill(Color.black).frame(width: 4, height: 4).offset(x: 0.5, y: 0.5))
            }
            .offset(y: -2)
        }
        .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
    }
}

// MARK: - Art window

struct MolibooCardArtWindow: View {
    let card: MolibooGalleryCard
    var outfit: MascotOutfit
    var tilt: CGSize = .zero

    var body: some View {
        ZStack {
            if card.isSeries2 {
                series2Art
            } else if let kind = card.kind {
                liveFigure(kind)
            } else {
                silhouette(label: card.name)
            }
        }
        .offset(x: tilt.width * -6, y: tilt.height * -4)
    }

    @ViewBuilder
    private var series2Art: some View {
        if let image = MolibooPackagePortrait.image(for: card.character) {
            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .padding(8)
                if !card.isLegend, !outfit.isEmpty {
                    portraitOverlay
                }
            }
        } else {
            silhouette(label: "Not downloaded")
        }
    }

    @ViewBuilder
    private func liveFigure(_ kind: ModulaMascotKind) -> some View {
        ModulaMascotFigure(kind: kind, pose: .still(.happy), size: 108, outfit: card.isLegend ? .empty : outfit)
            .allowsHitTesting(false)
    }

    /// Body-anchored wardrobe overlay on a Series 2 portrait, using the character's rig when we have one.
    private var portraitOverlay: some View {
        let kind = card.kind ?? .pip
        let rig = MascotRig.stock(kind)
        let pose = MascotPose.still(.happy)
        let size: CGFloat = 108
        return ZStack {
            MascotWardrobeOverlay(outfit: outfit, rig: rig, pose: pose, size: size, layer: .back, animate: false)
            MascotWardrobeOverlay(outfit: outfit, rig: rig, pose: pose, size: size, layer: .body, animate: false)
            MascotWardrobeOverlay(outfit: outfit, rig: rig, pose: pose, size: size, layer: .front, animate: false)
        }
        .allowsHitTesting(false)
    }

    private func silhouette(label: String) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Capsule()
                    .fill(card.theme.accent.opacity(0.28))
                    .frame(width: 86, height: 96)
                HStack(spacing: 10) {
                    Circle().fill(card.theme.ink.opacity(0.25)).frame(width: 10, height: 10)
                    Circle().fill(card.theme.ink.opacity(0.25)).frame(width: 10, height: 10)
                }
                .offset(y: -10)
            }
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .accessibilityLabel(label)
    }
}

// MARK: - Inspect + flip + share

struct MolibooGalleryInspectView: View {
    let card: MolibooGalleryCard
    var outfit: MascotOutfit = MascotWardrobeStore.shared.outfit
    var onClose: () -> Void

    @State private var faceDown = false
    @State private var tiltSource = MolibooTiltSource()
    @State private var exportImage: Image?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                MolibooTradingCardV2(
                    card: card,
                    width: 280,
                    outfit: outfit,
                    tilt: reduceMotion ? .zero : tiltSource.tilt,
                    faceDown: faceDown,
                    interactive: !faceDown
                )
                .onTapGesture { flip() }
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Flips the card")
                .accessibilityIdentifier("cards.v2.inspect.\(card.catalogueNumber)")

                HStack(spacing: 12) {
                    Button(faceDown ? "Show front" : "Show back") { flip() }
                        .buttonStyle(.bordered)
                    if let exportImage {
                        ShareLink(
                            item: exportImage,
                            preview: SwiftUI.SharePreview("\(card.name) · #\(card.catalogueNumber)", image: exportImage)
                        ) {
                            Label("Share card", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button("Share card") { exportImage = renderedShareImage() }
                            .buttonStyle(.borderedProminent)
                    }
                }
                .font(.subheadline.weight(.semibold))
            }
            .padding(20)
            .navigationTitle("#\(card.catalogueNumber)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onClose)
                }
            }
        }
        .onAppear { if !reduceMotion { tiltSource.start() } }
        .onDisappear { tiltSource.stop() }
    }

    private func flip() {
        if reduceMotion {
            faceDown.toggle()
        } else {
            withAnimation(.spring(duration: 0.55, bounce: 0.18)) { faceDown.toggle() }
        }
        exportImage = nil
    }

    private func renderedShareImage() -> Image {
        let view = MolibooTradingCardV2(card: card, width: 390, outfit: outfit, interactive: false)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        if let ui = renderer.uiImage {
            return Image(uiImage: ui)
        }
        return Image(systemName: "rectangle.on.rectangle")
    }
}
