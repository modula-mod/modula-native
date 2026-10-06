import SwiftUI

// MARK: - Custom mascot (create-your-own, device-local)

struct CustomMascot: Identifiable, Codable, Equatable, Hashable, Sendable {
    var id: String
    var name: String
    var personality: String
    var tic: String
    /// 0...1 RGB
    var bodyR: Double
    var bodyG: Double
    var bodyB: Double
    var accentR: Double
    var accentG: Double
    var accentB: Double
    var irisR: Double
    var irisG: Double
    var irisB: Double
    var eyeStyle: String   // round, happy, sleepy
    var mouthStyle: String // smile, open, cat, none
    var ears: String       // none, round, pointy, floppy
    var extras: String     // none, gills, tail, antenna, horns
    var createdAt: Date
    /// Body silhouette (MascotBodyShape raw value) and whether it has little feet (for shoes/bottoms).
    var shape: String = MascotBodyShape.round.rawValue
    var feet: Bool = true

    var body: Color { Color(red: bodyR, green: bodyG, blue: bodyB) }
    var accent: Color { Color(red: accentR, green: accentG, blue: accentB) }
    var iris: Color { Color(red: irisR, green: irisG, blue: irisB) }
    var dark: Color { body.mix(with: .black, by: 0.28) }
    var light: Color { body.mix(with: .white, by: 0.35) }
    var outline: Color { body.mix(with: .black, by: 0.45) }

    static func fresh() -> CustomMascot {
        CustomMascot(
            id: "custom:\(UUID().uuidString)",
            name: "New friend",
            personality: "A custom companion you made",
            tic: "✦",
            bodyR: 0.98, bodyG: 0.72, bodyB: 0.78,
            accentR: 0.95, accentG: 0.4, accentB: 0.55,
            irisR: 0.25, irisG: 0.2, irisB: 0.3,
            eyeStyle: "round",
            mouthStyle: "smile",
            ears: "none",
            extras: "none",
            createdAt: Date()
        )
    }

    /// Stock-mascot-compatible voice prompt.
    var voicePersonality: String { personality }
}

extension CustomMascot {
    enum CodingKeys: String, CodingKey {
        case id, name, personality, tic, bodyR, bodyG, bodyB, accentR, accentG, accentB, irisR, irisG, irisB
        case eyeStyle, mouthStyle, ears, extras, createdAt, shape, feet
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Friend"
        personality = try c.decodeIfPresent(String.self, forKey: .personality) ?? ""
        tic = try c.decodeIfPresent(String.self, forKey: .tic) ?? "✦"
        bodyR = try c.decodeIfPresent(Double.self, forKey: .bodyR) ?? 0.98
        bodyG = try c.decodeIfPresent(Double.self, forKey: .bodyG) ?? 0.72
        bodyB = try c.decodeIfPresent(Double.self, forKey: .bodyB) ?? 0.78
        accentR = try c.decodeIfPresent(Double.self, forKey: .accentR) ?? 0.95
        accentG = try c.decodeIfPresent(Double.self, forKey: .accentG) ?? 0.4
        accentB = try c.decodeIfPresent(Double.self, forKey: .accentB) ?? 0.55
        irisR = try c.decodeIfPresent(Double.self, forKey: .irisR) ?? 0.25
        irisG = try c.decodeIfPresent(Double.self, forKey: .irisG) ?? 0.2
        irisB = try c.decodeIfPresent(Double.self, forKey: .irisB) ?? 0.3
        eyeStyle = try c.decodeIfPresent(String.self, forKey: .eyeStyle) ?? "round"
        mouthStyle = try c.decodeIfPresent(String.self, forKey: .mouthStyle) ?? "smile"
        ears = try c.decodeIfPresent(String.self, forKey: .ears) ?? "none"
        extras = try c.decodeIfPresent(String.self, forKey: .extras) ?? "none"
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        shape = try c.decodeIfPresent(String.self, forKey: .shape) ?? MascotBodyShape.round.rawValue
        feet = try c.decodeIfPresent(Bool.self, forKey: .feet) ?? true
    }
}

@MainActor @Observable
final class CustomMascotStore {
    static let shared = CustomMascotStore()
    static let maxCount = 5

    private let key = "composer.mascot.customs"
    private(set) var items: [CustomMascot] = []

    private init() { reload() }

    func reload() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([CustomMascot].self, from: data) else {
            items = []
            return
        }
        items = decoded
    }

    func mascot(id: String) -> CustomMascot? { items.first { $0.id == id } }

    @discardableResult
    func save(_ mascot: CustomMascot) -> Bool {
        if let idx = items.firstIndex(where: { $0.id == mascot.id }) {
            items[idx] = mascot
        } else {
            guard items.count < Self.maxCount else { return false }
            items.append(mascot)
        }
        persist()
        return true
    }

    func delete(id: String) {
        items.removeAll { $0.id == id }
        if UserDefaults.standard.string(forKey: ModulaMascotSettings.kindKey) == id {
            UserDefaults.standard.set(ModulaMascotKind.pip.rawValue, forKey: ModulaMascotSettings.kindKey)
        }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

/// Resolves either a stock `ModulaMascotKind` or a custom id from AppStorage.
enum MascotSelection: Equatable {
    case off
    case stock(ModulaMascotKind)
    case custom(CustomMascot)

    @MainActor
    static func resolve(raw: String) -> MascotSelection {
        if raw == ModulaMascotSettings.off || raw.isEmpty { return .off }
        if let kind = ModulaMascotKind(rawValue: raw) {
            return MascotEntitlements.canUse(kind) ? .stock(kind) : .stock(.pip)
        }
        if raw.hasPrefix("custom:"), let custom = CustomMascotStore.shared.mascot(id: raw) {
            return .custom(custom)
        }
        return .stock(.pip)
    }

    var displayName: String {
        switch self {
        case .off: "Off"
        case .stock(let k): k.name
        case .custom(let c): c.name
        }
    }

    var personality: String {
        switch self {
        case .off: ""
        case .stock(let k): k.personality
        case .custom(let c): c.personality
        }
    }

    var tic: String {
        switch self {
        case .off: ""
        case .stock(let k): k.tic
        case .custom(let c): c.tic
        }
    }

    var stockKind: ModulaMascotKind? {
        if case .stock(let k) = self { return k }
        return nil
    }

    var rawValue: String {
        switch self {
        case .off: ModulaMascotSettings.off
        case .stock(let k): k.rawValue
        case .custom(let c): c.id
        }
    }

    /// Anatomy rig for fitting wardrobe items (Pip stands in when the mascot is off).
    var rig: MascotRig {
        switch self {
        case .off: MascotRig.stock(.pip)
        case .stock(let k): MascotRig.stock(k)
        case .custom(let c): MascotRig.custom(c)
        }
    }

    var accent: Color {
        switch self {
        case .off: .gray
        case .stock(let k): k.palette.light
        case .custom(let c): c.light
        }
    }
}

// MARK: - Custom figure

struct CustomMascotFigure: View {
    let mascot: CustomMascot
    var pose: MascotPose
    var size: CGFloat = 48
    var outfit: MascotOutfit = .empty

    var body: some View {
        let s = size
        let t = pose.t
        let a = pose.amp
        let rig = MascotRig.custom(mascot)
        let c = ModulaMascotFigure.canvas(s)
        let foot = UnitPoint(x: 0.5, y: 0.5 + rig.footY * s / c.height)
        ZStack {
            if !outfit.isEmpty { MascotWardrobeOverlay(outfit: outfit, rig: rig, pose: pose, size: s, layer: .back, animate: a > 0) }
            extrasBehind(rig: rig, s: s, t: t, a: a)
            if mascot.feet { feet(rig: rig, s: s, t: t, a: a) }
            bodyLayer(rig: rig, s: s)
            if !outfit.isEmpty { MascotWardrobeOverlay(outfit: outfit, rig: rig, pose: pose, size: s, layer: .body, animate: a > 0) }
            face(rig: rig, s: s, t: t)
            extrasFront(rig: rig, s: s, t: t, a: a)
            if !outfit.isEmpty { MascotWardrobeOverlay(outfit: outfit, rig: rig, pose: pose, size: s, layer: .front, animate: a > 0) }
        }
        .frame(width: c.width, height: c.height)
        .drawingGroup(opaque: false, colorMode: .extendedLinear)
        .scaleEffect(x: 1 / sqrt(pose.squash), y: pose.squash, anchor: foot)
        .rotationEffect(.degrees(pose.sway), anchor: foot)
        .offset(x: pose.shiverX, y: -pose.hop)
    }

    private func bodyLayer(rig: MascotRig, s: CGFloat) -> some View {
        let shape = rig.bodyShape(size: s)
        let w = s * rig.bodyW, h = s * rig.bodyH
        return ZStack {
            shape.fill(RadialGradient(colors: [mascot.light, mascot.body, mascot.dark], center: UnitPoint(x: 0.36, y: 0.26), startRadius: s * 0.02, endRadius: s * 0.74))
            shape.fill(LinearGradient(colors: [.clear, .clear, mascot.dark.opacity(0.45)], startPoint: .top, endPoint: .bottom))
            shape.stroke(LinearGradient(colors: [.white.opacity(0.65), .clear], startPoint: .top, endPoint: .center), lineWidth: s * 0.03)
                .blur(radius: s * 0.01)
                .mask(shape)
            shape.stroke(mascot.outline.opacity(0.6), lineWidth: max(s * 0.03, 1.1))
            Ellipse().fill(LinearGradient(colors: [.white.opacity(0.9), .white.opacity(0.2)], startPoint: .top, endPoint: .bottom))
                .frame(width: s * 0.24, height: s * 0.11)
                .rotationEffect(.degrees(-24))
                .offset(x: -w * 0.22, y: -h * 0.28)
        }
        .frame(width: w, height: h)
        .offset(y: s * rig.bodyY)
    }

    private func feet(rig: MascotRig, s: CGFloat, t: Double, a: CGFloat) -> some View {
        ForEach([-1.0, 1.0], id: \.self) { side in
            Ellipse()
                .fill(LinearGradient(colors: [mascot.body, mascot.dark], startPoint: .top, endPoint: .bottom))
                .overlay(Ellipse().stroke(mascot.outline.opacity(0.55), lineWidth: max(s * 0.026, 1)))
                .frame(width: s * 0.22, height: s * 0.14)
                .offset(x: side * s * max(0.15, min(0.24, rig.bodyW * 0.22)), y: s * (rig.footY - 0.02))
        }
    }

    @ViewBuilder private func face(rig: MascotRig, s: CGFloat, t: Double) -> some View {
        ZStack {
            ForEach([-1.0, 1.0], id: \.self) { side in
                eye(s: s, size: s * rig.eyeSize)
                    .offset(x: side * s * rig.eyeSpread, y: s * rig.eyeY)
            }
            ForEach([-1.0, 1.0], id: \.self) { side in
                Ellipse().fill(RadialGradient(colors: [mascot.accent.opacity(0.5), .clear], center: .center, startRadius: 0, endRadius: s * 0.09))
                    .frame(width: s * 0.2, height: s * 0.12)
                    .offset(x: side * s * (rig.eyeSpread + 0.1), y: s * (rig.eyeY + 0.15))
            }
            mouth(s: s).offset(y: s * rig.mouthY)
        }
    }

    @ViewBuilder private func eye(s: CGFloat, size: CGFloat) -> some View {
        let blink = pose.blink
        switch mascot.eyeStyle {
        case "happy":
            MascotHappyEye().stroke(mascot.outline, style: StrokeStyle(lineWidth: max(s * 0.035, 1.2), lineCap: .round))
                .frame(width: size * 0.8, height: size * 0.45)
                .scaleEffect(y: 1 - blink * 0.85)
        case "sleepy":
            Capsule().fill(mascot.outline)
                .frame(width: size * 0.8, height: max(1.5, size * 0.12 * (1 - blink)))
        default:
            ZStack {
                Circle().fill(Color.white)
                Circle().fill(mascot.iris).frame(width: size * 0.58)
                    .offset(x: pose.look.width * size * 0.15, y: pose.look.height * size * 0.15)
                Circle().fill(Color.black.opacity(0.75)).frame(width: size * 0.28)
                    .offset(x: pose.look.width * size * 0.15, y: pose.look.height * size * 0.15)
                Circle().fill(Color.white.opacity(0.95)).frame(width: size * 0.18).offset(x: -size * 0.12, y: -size * 0.12)
            }
            .frame(width: size, height: size)
            .overlay(Circle().stroke(mascot.outline.opacity(0.6), lineWidth: max(s * 0.02, 0.8)))
            .scaleEffect(y: 1 - blink * 0.92)
        }
    }

    @ViewBuilder private func mouth(s: CGFloat) -> some View {
        switch mascot.mouthStyle {
        case "open":
            MascotOpenSmile().fill(mascot.outline.opacity(0.85))
                .frame(width: s * 0.16, height: s * (0.08 + 0.06 * pose.mouthOpen))
        case "cat":
            MascotCatMouth().stroke(mascot.outline, style: StrokeStyle(lineWidth: max(s * 0.03, 1), lineCap: .round))
                .frame(width: s * 0.16, height: s * 0.07)
        case "none":
            EmptyView()
        default:
            MascotSmile().stroke(mascot.outline, style: StrokeStyle(lineWidth: max(s * 0.03, 1), lineCap: .round))
                .frame(width: s * 0.14, height: s * 0.06)
        }
    }

    @ViewBuilder private func extrasBehind(rig: MascotRig, s: CGFloat, t: Double, a: CGFloat) -> some View {
        let top = s * (rig.bodyTop + 0.06)
        let da = Double(a)
        let ear = MascotSwatch(mascot.body)
        switch mascot.ears {
        case "round":
            ForEach([-1.0, 1.0], id: \.self) { side in
                Circle().fill(LinearGradient(colors: [ear.light, ear.dark], startPoint: .top, endPoint: .bottom))
                    .overlay(Circle().fill(mascot.accent.opacity(0.7)).scaleEffect(0.5))
                    .overlay(Circle().stroke(mascot.outline.opacity(0.55), lineWidth: max(s * 0.026, 1)))
                    .frame(width: s * 0.24)
                    .offset(x: side * s * rig.bodyW * 0.32, y: top - s * 0.04)
            }
        case "pointy":
            ForEach([-1.0, 1.0], id: \.self) { side in
                MascotTriangle().fill(LinearGradient(colors: [ear.light, ear.dark], startPoint: .top, endPoint: .bottom))
                    .overlay(MascotTriangle().fill(mascot.accent.opacity(0.8)).scaleEffect(0.5).offset(y: s * 0.03))
                    .overlay(MascotTriangle().stroke(mascot.outline.opacity(0.55), lineWidth: max(s * 0.026, 1)))
                    .frame(width: s * 0.22, height: s * 0.28)
                    .rotationEffect(.degrees(side * 16), anchor: .bottom)
                    .offset(x: side * s * rig.bodyW * 0.28, y: top - s * 0.1)
            }
        case "floppy":
            ForEach([-1.0, 1.0], id: \.self) { side in
                Capsule().fill(LinearGradient(colors: [ear.base, ear.dark], startPoint: .top, endPoint: .bottom))
                    .overlay(Capsule().stroke(mascot.outline.opacity(0.55), lineWidth: max(s * 0.026, 1)))
                    .frame(width: s * 0.15, height: s * 0.34)
                    .rotationEffect(.degrees(side * (32 + 6 * sin(t) * da)), anchor: .top)
                    .offset(x: side * s * rig.bodyW * 0.42, y: top + s * 0.08)
            }
        default: EmptyView()
        }
        if mascot.extras == "tail" {
            MascotTail()
                .stroke(LinearGradient(colors: [mascot.body, mascot.accent], startPoint: .leading, endPoint: .trailing), style: StrokeStyle(lineWidth: s * 0.1, lineCap: .round))
                .frame(width: s * 0.34, height: s * 0.38)
                .rotationEffect(.degrees(10 * sin(t * 1.5) * da), anchor: .bottomLeading)
                .offset(x: s * (rig.bodyW / 2 + 0.06), y: s * (rig.bodyY + 0.02))
        }
        if mascot.extras == "gills" {
            ForEach([-1.0, 1.0], id: \.self) { side in
                MascotFrond().fill(LinearGradient(colors: [mascot.accent, mascot.dark], startPoint: .top, endPoint: .bottom))
                    .overlay(MascotFrond().stroke(mascot.outline.opacity(0.5), lineWidth: max(s * 0.02, 0.8)))
                    .frame(width: s * 0.14, height: s * 0.32)
                    .offset(y: -s * 0.16)
                    .rotationEffect(.degrees(side * (60 + 8 * sin(t * 3) * da)), anchor: .bottom)
                    .offset(x: side * s * rig.bodyW * 0.42, y: s * rig.bodyY)
            }
        }
    }

    @ViewBuilder private func extrasFront(rig: MascotRig, s: CGFloat, t: Double, a: CGFloat) -> some View {
        switch mascot.extras {
        case "antenna":
            let da = Double(a)
            ZStack {
                Capsule().fill(mascot.outline.opacity(0.7)).frame(width: max(2, s * 0.03), height: s * 0.2).offset(y: -s * 0.1)
                Circle().fill(RadialGradient(colors: [mascot.accent.lighter(0.4), mascot.accent], center: .topLeading, startRadius: 0, endRadius: s * 0.08))
                    .overlay(Circle().stroke(mascot.outline.opacity(0.5), lineWidth: 0.8))
                    .frame(width: s * 0.11).offset(y: -s * 0.21)
            }
            .rotationEffect(.degrees(8 * sin(t * 1.8) * da), anchor: .bottom)
            .offset(y: s * (rig.bodyTop + 0.02))
        case "horns":
            ForEach([-1.0, 1.0], id: \.self) { side in
                MascotTriangle().fill(LinearGradient(colors: [mascot.accent.lighter(0.3), mascot.accent], startPoint: .top, endPoint: .bottom))
                    .overlay(MascotTriangle().stroke(mascot.outline.opacity(0.5), lineWidth: 0.8))
                    .frame(width: s * 0.12, height: s * 0.18)
                    .rotationEffect(.degrees(side * 14))
                    .offset(x: side * s * rig.bodyW * 0.22, y: s * (rig.bodyTop - 0.02))
            }
        default: EmptyView()
        }
    }
}

/// Live wrapper that drives a brain for a custom mascot (same timeline as stock).
struct CustomLiveMascot: View {
    let mascot: CustomMascot
    var size: CGFloat = 48
    var busy = false
    var touch: CGPoint? = nil
    var brain: MascotBrain
    var showsShadow = true
    var animated = true
    var outfit: MascotOutfit = .empty

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @State private var visible = false
    private let context = MascotContext.shared

    private var paused: Bool { !animated || reduceMotion || !visible || scenePhase != .active }

    var body: some View {
        let conditions = context.conditions(dark: colorScheme == .dark)
        let fps: Double = conditions.lowPower ? 30 : 60
        let c = ModulaLiveMascot.container(size)
        let rig = MascotRig.custom(mascot)
        TimelineView(.animation(minimumInterval: 1.0 / fps, paused: paused)) { timeline in
            let now = timeline.date.timeIntervalSinceReferenceDate
            let pose = brain.pose(at: now, touchLook: nil, tilt: ModulaMascotMotion.shared.tilt, busy: busy, reduceMotion: reduceMotion || !animated, conditions: conditions)
            ZStack {
                if showsShadow {
                    Ellipse()
                        .fill(RadialGradient(colors: [.black.opacity(colorScheme == .dark ? 0.5 : 0.3), .clear], center: .center, startRadius: 0, endRadius: size * 0.45))
                        .frame(width: size * rig.bodyW * 0.95, height: size * 0.18)
                        .offset(y: size * (rig.footY + (mascot.feet ? 0.04 : 0)))
                }
                CustomMascotFigure(mascot: mascot, pose: pose, size: size, outfit: outfit)
            }
            .frame(width: c.width, height: c.height)
        }
        .onAppear { visible = true; context.start() }
        .onDisappear { visible = false }
    }
}
