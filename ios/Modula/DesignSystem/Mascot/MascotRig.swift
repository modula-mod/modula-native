import SwiftUI

// MARK: - Body shapes

enum MascotBodyShape: String, Codable, Sendable, CaseIterable, Identifiable {
    case round, tall, wide, drop, square, cloud, dome, pebble, roundedRect, star
    var id: String { rawValue }
    var title: String {
        switch self {
        case .round: "Round"
        case .tall: "Tall"
        case .wide: "Wide"
        case .drop: "Drop"
        case .square: "Square"
        case .cloud: "Cloud"
        case .dome: "Dome"
        case .pebble: "Pebble"
        case .roundedRect: "Boxy"
        case .star: "Star"
        }
    }
    /// Shapes offered in the custom mascot editor.
    static let customChoices: [MascotBodyShape] = [.round, .tall, .wide, .drop, .square]
}

// MARK: - Anatomy rig

/// Anatomy rig for one mascot. All values are fractions of the figure size `s`, measured from the
/// centre of the figure canvas (y grows downward). Wardrobe items attach to these anchors so they
/// scale and wrap to every body, and the face area (eyes + mouth) is always kept clear.
struct MascotRig: Equatable, Sendable {
    var shape: MascotBodyShape
    var bodyW: CGFloat
    var bodyH: CGFloat
    var bodyY: CGFloat
    var cornerRadius: CGFloat = 0.24
    var eyeY: CGFloat
    var eyeSize: CGFloat
    var eyeSpread: CGFloat
    var mouthY: CGFloat
    var footY: CGFloat
    var hasFeet = true
    var hasLegs = true
    var floats = false
    var allowsTop = true
    var allowsHair = true
    var headTopOverride: CGFloat? = nil
    var hatScale: CGFloat = 1
    var hatMaxWidth: CGFloat? = nil
    var bodyTint: Color = .pink

    // Derived anchors
    var bodyTop: CGFloat { bodyY - bodyH / 2 }
    var bodyBottom: CGFloat { bodyY + bodyH / 2 }
    var eyeTop: CGFloat { eyeY - eyeSize * 0.62 }
    var eyeBottom: CGFloat { eyeY + eyeSize * 0.62 }
    var faceBottom: CGFloat { mouthY + 0.07 }
    var faceHalfWidth: CGFloat { eyeSpread + eyeSize * 0.62 }
    /// Where a hat brim rests: the top of the head, or just above protruding eyes.
    var headTop: CGFloat { headTopOverride ?? min(bodyTop + 0.03, eyeTop - 0.01) }
    /// How far a hat may sink onto the head without touching the eyes.
    var hatSink: CGFloat { max(0, min(0.06, eyeTop - 0.02 - headTop)) }
    var neckY: CGFloat { faceBottom + 0.012 }
    var torsoTop: CGFloat { neckY }
    var hipY: CGFloat { bodyBottom - bodyH * 0.22 }
    var torsoBand: CGFloat { max(0, bodyBottom - torsoTop) }
    var canWearTop: Bool { allowsTop && torsoBand >= 0.12 }
    var canWearNeck: Bool { torsoBand >= 0.05 }
    /// Room between the top of the body and the eyes, for fringes.
    var foreheadRoom: CGFloat { eyeTop - bodyTop }
    var canWearHair: Bool { allowsHair && foreheadRoom >= 0.07 }
    var hatWidth: CGFloat {
        let fit = max(0.34, chord(at: headTop + 0.1) * 0.98)
        return min(hatMaxWidth ?? 9, fit, 0.74) * hatScale
    }
    var handY: CGFloat { bodyY + bodyH * 0.14 }
    var hand: CGPoint { CGPoint(x: max(0.2, chord(at: handY) / 2) * 0.96, y: handY) }
    var backAnchorY: CGFloat { bodyY - bodyH * 0.08 }
    var petAnchor: CGPoint {
        CGPoint(x: bodyW / 2 + 0.3, y: floats ? bodyY + 0.12 : footY - 0.09)
    }

    /// Full body width at height `y` (fraction of s), approximated per silhouette.
    func chord(at y: CGFloat) -> CGFloat {
        let u = (y - bodyTop) / max(bodyH, 0.01)        // 0 top … 1 bottom
        guard u > 0, u < 1 else { return 0 }
        let dy = abs(u - 0.5) * 2                         // 0 centre … 1 edge
        switch shape {
        case .square, .roundedRect:
            let edge = max(0.2, 1 - cornerRadius * 2 / max(bodyH, 0.01))
            if dy <= edge { return bodyW }
            let k = (dy - edge) / max(1 - edge, 0.01)
            return bodyW * (0.55 + 0.45 * sqrt(max(0, 1 - k * k)))
        case .drop:
            if u < 0.66 { return bodyW * sin(u / 0.66 * .pi / 2) }
            let k = (u - 0.66) / 0.34
            return bodyW * sqrt(max(0, 1 - k * k))
        case .dome:
            if u < 0.78 {
                let k = (0.78 - u) / 0.78
                return bodyW * sqrt(max(0, 1 - k * k))
            }
            return bodyW * 0.96
        case .cloud:
            return bodyW * (u > 0.55 ? 0.92 : 0.98 * sqrt(max(0, 1 - pow((0.55 - u) / 0.6, 2))))
        case .star:
            return bodyW * 0.62 * sqrt(max(0, 1 - dy * dy))
        default:
            return bodyW * sqrt(max(0, 1 - dy * dy))
        }
    }

    func bodyShape(size s: CGFloat) -> AnyShape {
        switch shape {
        case .cloud: AnyShape(MascotCloudShape())
        case .drop: AnyShape(MascotDropShape())
        case .dome: AnyShape(MascotDomeShape())
        case .pebble: AnyShape(MascotPebbleShape())
        case .square, .roundedRect: AnyShape(RoundedRectangle(cornerRadius: s * cornerRadius, style: .continuous))
        case .star: AnyShape(MascotStarShape())
        default: AnyShape(Ellipse())
        }
    }

    /// Body frame inside a figure canvas of size `canvas`.
    func bodyRect(size s: CGFloat, canvas: CGSize) -> CGRect {
        CGRect(x: canvas.width / 2 - bodyW * s / 2, y: canvas.height / 2 + bodyTop * s, width: bodyW * s, height: bodyH * s)
    }

    func bodyPath(size s: CGFloat, canvas: CGSize) -> Path {
        bodyShape(size: s).path(in: bodyRect(size: s, canvas: canvas))
    }
}

// MARK: - Stock + custom rigs

extension MascotRig {
    static func stock(_ k: ModulaMascotKind) -> MascotRig {
        var r = MascotRig(
            shape: .round,
            bodyW: k.bodySize.width, bodyH: k.bodySize.height, bodyY: k.bodyOffsetY,
            eyeY: k.eyeY, eyeSize: k.eyeSize, eyeSpread: k.eyeSpread,
            mouthY: k.mouthY, footY: k.footFraction,
            bodyTint: k.palette.mid
        )
        switch k {
        case .pip:
            r.hatMaxWidth = 0.62                       // frills either side
        case .moss:
            r.hatScale = 0.9                           // eyes sit on top of the head
            r.allowsHair = false
        case .nimbus:
            r.shape = .cloud; r.hasFeet = false; r.hasLegs = false; r.floats = true
        case .mochi:
            r.hatMaxWidth = 0.46                       // between the ears
        case .sprout:
            r.hatScale = 0.92
        case .ember:
            r.shape = .drop; r.hasFeet = false; r.hasLegs = false; r.floats = true
            r.headTopOverride = r.bodyTop + 0.17; r.hatScale = 0.78
        case .tuck:
            r.hatMaxWidth = 0.5                        // ear tufts
        case .bloop:
            r.shape = .dome; r.hasFeet = false; r.hasLegs = false; r.floats = true
        case .bun:
            r.hatMaxWidth = 0.5
        case .pebble:
            r.shape = .pebble; r.hasFeet = false; r.hasLegs = false
        case .tofu:
            r.shape = .square; r.cornerRadius = 0.24; r.hasFeet = false; r.hasLegs = false
        case .comet:
            r.shape = .star; r.hasFeet = false; r.hasLegs = false; r.floats = true
            r.allowsTop = false; r.headTopOverride = r.bodyTop + 0.12; r.hatScale = 0.62
        case .puff:
            r.hasFeet = false; r.hasLegs = false; r.floats = true
        case .bolt:
            r.shape = .roundedRect; r.cornerRadius = 0.28; r.hasLegs = false
        case .glim:
            r.hasFeet = false; r.hasLegs = false; r.floats = true
        }
        return r
    }

    static func custom(_ m: CustomMascot) -> MascotRig {
        let shape = MascotBodyShape(rawValue: m.shape) ?? .round
        var w: CGFloat = 0.95, h: CGFloat = 0.82
        switch shape {
        case .tall: w = 0.82; h = 0.98
        case .wide: w = 1.08; h = 0.76
        case .drop: w = 0.92; h = 1.0
        case .square: w = 0.92; h = 0.84
        default: break
        }
        let bodyY: CGFloat = shape == .drop ? 0.04 : 0.10
        let eyeY: CGFloat = shape == .drop ? 0.10 : bodyY - h * 0.08
        var r = MascotRig(
            shape: shape == .square ? .square : shape,
            bodyW: w, bodyH: h, bodyY: bodyY,
            eyeY: eyeY, eyeSize: 0.2, eyeSpread: 0.19,
            mouthY: eyeY + 0.18, footY: bodyY + h / 2,
            bodyTint: m.body
        )
        r.cornerRadius = 0.24
        r.hasFeet = m.feet
        r.hasLegs = m.feet
        r.floats = !m.feet
        if m.ears != "none" { r.hatMaxWidth = 0.5 }
        if shape == .drop { r.headTopOverride = r.bodyTop + 0.17; r.hatScale = 0.8 }
        return r
    }
}

// MARK: - Fit

enum MascotNeed: Sendable, Hashable {
    case head, hair, face, torso, legs, legsOrFrill, frill, feet, neck, hand, back, aura, ground, scene
}

enum MascotFit: Equatable, Sendable {
    case fits
    case adapted(String)
    case none(String)

    var isWearable: Bool { if case .none = self { return false }; return true }
    var label: String? {
        switch self {
        case .fits: nil
        case .adapted(let s): s
        case .none(let s): s
        }
    }
}

extension MascotRig {
    func fit(_ need: MascotNeed) -> MascotFit {
        switch need {
        case .head, .face, .hand, .back, .aura, .ground, .scene, .frill:
            return .fits
        case .hair:
            return canWearHair ? .fits : .none("Doesn’t fit this mascot")
        case .torso:
            return canWearTop ? .fits : .none("Doesn’t fit this mascot")
        case .neck:
            return canWearNeck ? .fits : .none("Doesn’t fit this mascot")
        case .legs:
            return hasLegs ? .fits : .none("Doesn’t fit this mascot")
        case .legsOrFrill:
            return hasLegs ? .fits : .adapted("Wears as a frilly skirt")
        case .feet:
            return hasFeet ? .fits : .none("No feet for shoes")
        }
    }
}
