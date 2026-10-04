import SwiftUI
import CoreMotion

// MARK: - Model & preferences

/// Six original composer mascots, drawn entirely with SwiftUI shapes.
enum ModulaMascotKind: String, CaseIterable, Identifiable, Sendable {
    case pip, moss, nimbus, ember, tuck, mochi
    var id: String { rawValue }

    var name: String {
        switch self {
        case .pip: "Pip"
        case .moss: "Moss"
        case .nimbus: "Nimbus"
        case .ember: "Ember"
        case .tuck: "Tuck"
        case .mochi: "Mochi"
        }
    }

    var blurb: String {
        switch self {
        case .pip: "Frilly little axolotl"
        case .moss: "Calm pond frog"
        case .nimbus: "Soft drifting cloud"
        case .ember: "Warm friendly spark"
        case .tuck: "Night-owl reader"
        case .mochi: "Sleepy round cat"
        }
    }

    var palette: (top: Color, bottom: Color, accent: Color) {
        switch self {
        case .pip: (Color(red: 1.0, green: 0.74, blue: 0.82), Color(red: 0.96, green: 0.55, blue: 0.70), Color(red: 0.93, green: 0.36, blue: 0.56))
        case .moss: (Color(red: 0.62, green: 0.88, blue: 0.56), Color(red: 0.36, green: 0.72, blue: 0.42), Color(red: 0.24, green: 0.55, blue: 0.32))
        case .nimbus: (Color(red: 0.97, green: 0.98, blue: 1.0), Color(red: 0.78, green: 0.86, blue: 0.98), Color(red: 0.55, green: 0.68, blue: 0.95))
        case .ember: (Color(red: 1.0, green: 0.82, blue: 0.40), Color(red: 1.0, green: 0.52, blue: 0.27), Color(red: 0.92, green: 0.32, blue: 0.20))
        case .tuck: (Color(red: 0.78, green: 0.64, blue: 0.50), Color(red: 0.56, green: 0.42, blue: 0.31), Color(red: 0.98, green: 0.88, blue: 0.70))
        case .mochi: (Color(red: 0.86, green: 0.86, blue: 0.90), Color(red: 0.66, green: 0.66, blue: 0.74), Color(red: 1.0, green: 0.70, blue: 0.76))
        }
    }
}

enum ModulaMascotPlacement: String, Sendable { case nodus, comments, other }

/// AppStorage keys for the composer mascot (Settings → Chats → Composer).
enum ModulaMascotSettings {
    static let kindKey = "composer.mascot.kind"           // ModulaMascotKind rawValue, or "off"
    static let nodusKey = "composer.mascot.show.nodus"
    static let commentsKey = "composer.mascot.show.comments"
    static let otherKey = "composer.mascot.show.other"
    static let off = "off"

    static func key(for placement: ModulaMascotPlacement) -> String {
        switch placement {
        case .nodus: nodusKey
        case .comments: commentsKey
        case .other: otherKey
        }
    }
    static func defaultShown(_ placement: ModulaMascotPlacement) -> Bool { placement == .nodus }
}

// MARK: - Tilt (CoreMotion, shared, ref-counted)

@MainActor @Observable
final class ModulaMascotMotion {
    static let shared = ModulaMascotMotion()
    /// -1…1 look offset from device tilt.
    private(set) var tilt: CGSize = .zero
    @ObservationIgnored private let manager = CMMotionManager()
    @ObservationIgnored private var users = 0

    func start() {
        users += 1
        guard users == 1, manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 30.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let g = motion?.gravity else { return }
            // Neutral ≈ phone held at a reading angle; look follows the low side.
            let x = max(-1, min(1, g.x * 1.8))
            let y = max(-1, min(1, (-g.z - 0.55) * -1.6))
            let next = CGSize(width: x, height: y)
            // Light low-pass so eyes drift rather than jitter.
            self.tilt = CGSize(width: self.tilt.width * 0.8 + next.width * 0.2, height: self.tilt.height * 0.8 + next.height * 0.2)
        }
    }

    func stop() {
        users = max(users - 1, 0)
        guard users == 0 else { return }
        manager.stopDeviceMotionUpdates()
        tilt = .zero
    }
}

// MARK: - Drawing

/// A mascot face/body. `look` is a -1…1 vector for the pupils.
struct ModulaMascotView: View {
    let kind: ModulaMascotKind
    var look: CGSize = .zero
    var blinking = false
    var busy = false
    var size: CGFloat = 36

    var body: some View {
        let p = kind.palette
        let s = size
        ZStack {
            decorationsBehind(p: p, s: s)
            bodyShape(s: s)
                .fill(LinearGradient(colors: [p.top, p.bottom], startPoint: .top, endPoint: .bottom))
                .overlay(
                    bodyShape(s: s).stroke(.white.opacity(0.35), lineWidth: max(s * 0.02, 0.6)).blendMode(.plusLighter)
                )
                .shadow(color: p.bottom.opacity(0.35), radius: s * 0.08, y: s * 0.04)
            // Specular highlight.
            Ellipse()
                .fill(.white.opacity(0.45))
                .frame(width: s * 0.28, height: s * 0.13)
                .rotationEffect(.degrees(-20))
                .offset(x: -s * 0.18, y: -s * 0.24)
                .blur(radius: s * 0.02)
            decorationsFront(p: p, s: s)
            face(p: p, s: s)
        }
        .frame(width: s * 1.25, height: s * 1.1)
        .accessibilityHidden(true)
    }

    private func bodyShape(s: CGFloat) -> AnyShape {
        switch kind {
        case .pip, .mochi, .tuck:
            AnyShape(Ellipse().size(width: s, height: s * 0.86).offset(x: s * 0.125, y: s * 0.17))
        case .moss:
            AnyShape(Ellipse().size(width: s * 1.04, height: s * 0.78).offset(x: s * 0.105, y: s * 0.25))
        case .nimbus:
            AnyShape(MascotCloudShape().size(width: s * 1.1, height: s * 0.8).offset(x: s * 0.075, y: s * 0.22))
        case .ember:
            AnyShape(MascotDropShape().size(width: s * 0.9, height: s * 0.98).offset(x: s * 0.175, y: s * 0.08))
        }
    }

    @ViewBuilder
    private func decorationsBehind(p: (top: Color, bottom: Color, accent: Color), s: CGFloat) -> some View {
        switch kind {
        case .pip:
            // Three feathery gill fronds per side.
            ForEach(0..<3, id: \.self) { i in
                let angle = Double(i - 1) * 28
                Capsule().fill(p.accent)
                    .frame(width: s * 0.11, height: s * 0.34)
                    .offset(y: -s * 0.17)
                    .rotationEffect(.degrees(-62 + angle), anchor: .bottom)
                    .offset(x: -s * 0.40, y: -s * 0.02)
                Capsule().fill(p.accent)
                    .frame(width: s * 0.11, height: s * 0.34)
                    .offset(y: -s * 0.17)
                    .rotationEffect(.degrees(62 - angle), anchor: .bottom)
                    .offset(x: s * 0.40, y: -s * 0.02)
            }
        case .mochi:
            ForEach([-1.0, 1.0], id: \.self) { side in
                MascotTriangle().fill(p.bottom)
                    .frame(width: s * 0.30, height: s * 0.30)
                    .rotationEffect(.degrees(side * 16))
                    .offset(x: side * s * 0.28, y: -s * 0.30)
                MascotTriangle().fill(p.accent.opacity(0.8))
                    .frame(width: s * 0.15, height: s * 0.15)
                    .rotationEffect(.degrees(side * 16))
                    .offset(x: side * s * 0.28, y: -s * 0.26)
            }
        case .tuck:
            ForEach([-1.0, 1.0], id: \.self) { side in
                MascotTriangle().fill(p.bottom)
                    .frame(width: s * 0.22, height: s * 0.26)
                    .rotationEffect(.degrees(side * 28))
                    .offset(x: side * s * 0.34, y: -s * 0.30)
            }
        case .moss:
            // Eye bumps.
            ForEach([-1.0, 1.0], id: \.self) { side in
                Circle().fill(LinearGradient(colors: [p.top, p.bottom], startPoint: .top, endPoint: .bottom))
                    .frame(width: s * 0.38, height: s * 0.38)
                    .offset(x: side * s * 0.24, y: -s * 0.16)
            }
        case .ember:
            Circle().fill(p.top.opacity(busy ? 0.7 : 0.35)).frame(width: s * 0.2).blur(radius: s * 0.05)
                .offset(x: s * 0.06, y: -s * 0.46)
        case .nimbus:
            EmptyView()
        }
    }

    @ViewBuilder
    private func decorationsFront(p: (top: Color, bottom: Color, accent: Color), s: CGFloat) -> some View {
        switch kind {
        case .tuck:
            Ellipse().fill(p.accent.opacity(0.9))
                .frame(width: s * 0.46, height: s * 0.36)
                .offset(y: s * 0.30)
        case .pip, .mochi:
            ForEach([-1.0, 1.0], id: \.self) { side in
                Ellipse().fill(p.accent.opacity(0.45))
                    .frame(width: s * 0.16, height: s * 0.09)
                    .offset(x: side * s * 0.30, y: s * 0.16)
            }
        default:
            EmptyView()
        }
    }

    private func face(p: (top: Color, bottom: Color, accent: Color), s: CGFloat) -> some View {
        let eyeSize: CGFloat = kind == .tuck ? s * 0.26 : (kind == .moss ? s * 0.22 : s * 0.19)
        let eyeY: CGFloat = kind == .moss ? -s * 0.15 : (kind == .ember ? s * 0.06 : -s * 0.01)
        let spread: CGFloat = kind == .moss ? s * 0.24 : (kind == .tuck ? s * 0.17 : s * 0.19)
        return ZStack {
            ForEach([-1.0, 1.0], id: \.self) { side in
                ModulaMascotEye(look: look, blinking: blinking, squint: busy, size: eyeSize, ringed: kind == .tuck)
                    .offset(x: side * spread, y: eyeY)
            }
            mouth(p: p, s: s)
        }
    }

    @ViewBuilder
    private func mouth(p: (top: Color, bottom: Color, accent: Color), s: CGFloat) -> some View {
        let y: CGFloat = kind == .moss ? s * 0.12 : (kind == .ember ? s * 0.26 : s * 0.15)
        switch kind {
        case .tuck:
            MascotTriangle().rotation(.degrees(180)).fill(Color(red: 0.98, green: 0.72, blue: 0.30))
                .frame(width: s * 0.11, height: s * 0.09).offset(y: s * 0.12)
        case .mochi:
            MascotCatMouth().stroke(Color.black.opacity(0.55), style: StrokeStyle(lineWidth: max(s * 0.03, 0.8), lineCap: .round))
                .frame(width: s * 0.16, height: s * 0.06).offset(y: y)
        default:
            MascotSmile().stroke(Color.black.opacity(0.55), style: StrokeStyle(lineWidth: max(s * 0.03, 0.8), lineCap: .round))
                .frame(width: busy ? s * 0.08 : s * 0.14, height: s * 0.05).offset(y: y)
        }
    }
}

struct ModulaMascotEye: View {
    var look: CGSize
    var blinking: Bool
    var squint: Bool
    var size: CGFloat
    var ringed = false

    var body: some View {
        let travel = size * 0.2
        ZStack {
            if ringed {
                Circle().fill(Color(red: 0.98, green: 0.90, blue: 0.74)).frame(width: size * 1.3, height: size * 1.3)
            }
            Circle().fill(.white).frame(width: size, height: size)
            Circle().fill(Color(red: 0.12, green: 0.12, blue: 0.16))
                .frame(width: size * 0.56, height: size * 0.56)
                .overlay(Circle().fill(.white).frame(width: size * 0.18).offset(x: -size * 0.09, y: -size * 0.09))
                .offset(x: look.width * travel, y: look.height * travel)
        }
        .scaleEffect(x: 1, y: blinking ? 0.12 : (squint ? 0.7 : 1))
    }
}

// MARK: - Shapes

struct MascotTriangle: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

struct MascotSmile: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: r.midX, y: r.maxY * 1.6))
        return p
    }
}

struct MascotCatMouth: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.midX, y: r.minY), control: CGPoint(x: r.minX + r.width * 0.25, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: r.minX + r.width * 0.75, y: r.maxY))
        return p
    }
}

struct MascotCloudShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height
        p.addEllipse(in: CGRect(x: r.minX, y: r.minY + h * 0.30, width: w * 0.5, height: h * 0.62))
        p.addEllipse(in: CGRect(x: r.minX + w * 0.22, y: r.minY, width: w * 0.56, height: h * 0.80))
        p.addEllipse(in: CGRect(x: r.minX + w * 0.50, y: r.minY + h * 0.24, width: w * 0.5, height: h * 0.66))
        p.addRoundedRect(in: CGRect(x: r.minX + w * 0.1, y: r.minY + h * 0.5, width: w * 0.8, height: h * 0.5), cornerSize: CGSize(width: h * 0.25, height: h * 0.25))
        return p
    }
}

struct MascotDropShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height
        p.move(to: CGPoint(x: r.minX + w * 0.58, y: r.minY))
        p.addCurve(to: CGPoint(x: r.maxX, y: r.minY + h * 0.66),
                   control1: CGPoint(x: r.minX + w * 0.70, y: r.minY + h * 0.22),
                   control2: CGPoint(x: r.maxX, y: r.minY + h * 0.36))
        p.addCurve(to: CGPoint(x: r.minX, y: r.minY + h * 0.66),
                   control1: CGPoint(x: r.maxX, y: r.maxY + h * 0.06),
                   control2: CGPoint(x: r.minX, y: r.maxY + h * 0.06))
        p.addCurve(to: CGPoint(x: r.minX + w * 0.58, y: r.minY),
                   control1: CGPoint(x: r.minX, y: r.minY + h * 0.38),
                   control2: CGPoint(x: r.minX + w * 0.42, y: r.minY + h * 0.22))
        p.closeSubpath()
        return p
    }
}

// MARK: - Composer host

/// Sits the chosen mascot on the composer's top-trailing edge when enabled for `placement`.
/// Eyes follow touches on the composer and device tilt; hold to swap via a Liquid Glass picker;
/// a soft glow breathes while `busy` (generating / sending / loading).
struct ModulaComposerMascotModifier: ViewModifier {
    let placement: ModulaMascotPlacement
    var busy: Bool
    @AppStorage(ModulaMascotSettings.kindKey) private var kindRaw = ModulaMascotKind.pip.rawValue
    @AppStorage private var shown: Bool
    @State private var touch: CGPoint?

    init(placement: ModulaMascotPlacement, busy: Bool) {
        self.placement = placement
        self.busy = busy
        _shown = AppStorage(wrappedValue: ModulaMascotSettings.defaultShown(placement), ModulaMascotSettings.key(for: placement))
    }

    func body(content: Content) -> some View {
        if shown, let kind = ModulaMascotKind(rawValue: kindRaw) {
            content
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .global)
                        .onChanged { touch = $0.location }
                        .onEnded { _ in touch = nil }
                )
                .overlay(alignment: .topTrailing) {
                    ModulaComposerMascot(kind: kind, busy: busy, touch: touch) { kindRaw = $0.rawValue }
                        .offset(x: -16, y: -27)
                }
        } else {
            content
        }
    }
}

extension View {
    func modulaComposerMascot(_ placement: ModulaMascotPlacement, busy: Bool = false) -> some View {
        modifier(ModulaComposerMascotModifier(placement: placement, busy: busy))
    }
}

struct ModulaComposerMascot: View {
    let kind: ModulaMascotKind
    var busy: Bool
    var touch: CGPoint?
    var onSelect: (ModulaMascotKind) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppEnvironment.self) private var app
    @State private var frame: CGRect = .zero
    @State private var blinking = false
    @State private var picking = false
    @State private var hop = false
    @State private var glow = false
    private let motion = ModulaMascotMotion.shared
    private let size: CGFloat = 32

    private var look: CGSize {
        if busy { return CGSize(width: 0.5, height: -0.7) }
        if let touch, frame != .zero {
            let dx = touch.x - frame.midX, dy = touch.y - frame.midY
            let d = max(hypot(dx, dy), 1)
            let m = min(d / 90, 1)
            return CGSize(width: dx / d * m, height: dy / d * m)
        }
        return reduceMotion ? .zero : motion.tilt
    }

    var body: some View {
        ModulaMascotView(kind: kind, look: look, blinking: blinking, busy: busy, size: size)
            .background {
                // Loading glow.
                Circle()
                    .fill(RadialGradient(colors: [app.appearance.accent.color.opacity(0.75), kind.palette.bottom.opacity(0.3), .clear], center: .center, startRadius: 2, endRadius: size * 0.95))
                    .frame(width: size * 1.9, height: size * 1.9)
                    .blur(radius: 6)
                    .opacity(busy ? (glow ? 1 : 0.45) : 0)
                    .scaleEffect(busy && !reduceMotion ? (glow ? 1.12 : 0.9) : 1)
            }
            .offset(y: hop ? -5 : 0)
            .scaleEffect(picking ? 1.12 : 1)
            .animation(.smooth(duration: 0.18), value: look)
            .animation(.spring(response: 0.28, dampingFraction: 0.55), value: hop)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: picking)
            .animation(busy && !reduceMotion ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true) : .easeOut(duration: 0.3), value: glow)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
            .contentShape(Rectangle().inset(by: -6))
            .onTapGesture {
                if picking { picking = false; return }
                hop = true
                HapticEngine.shared.play(.selection)
                Task { try? await Task.sleep(for: .milliseconds(180)); hop = false }
            }
            .onLongPressGesture(minimumDuration: 0.35) {
                HapticEngine.shared.play(.selection)
                picking.toggle()
            }
            .overlay(alignment: .bottomTrailing) {
                if picking {
                    ModulaMascotPicker(selected: kind) { choice in
                        onSelect(choice)
                        HapticEngine.shared.play(.selection)
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) { picking = false }
                    }
                    .offset(x: 8, y: -size * 1.35)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.4, anchor: .bottomTrailing).combined(with: .opacity))
                }
            }
            .onChange(of: busy, initial: true) { _, value in glow = value }
            .task(id: reduceMotion) {
                if !reduceMotion { motion.start() }
                defer { if !reduceMotion { motion.stop() } }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(Double.random(in: 2.6...5.2)))
                    guard !Task.isCancelled else { break }
                    withAnimation(.easeInOut(duration: 0.08)) { blinking = true }
                    try? await Task.sleep(for: .milliseconds(120))
                    withAnimation(.easeInOut(duration: 0.1)) { blinking = false }
                }
            }
            .accessibilityElement()
            .accessibilityLabel("\(kind.name), composer mascot")
            .accessibilityHint("Hold to choose a different mascot")
            .accessibilityAction(named: "Choose mascot") { picking = true }
            .accessibilityIdentifier("composer.mascot")
    }
}

/// Liquid Glass row of the six mascots.
struct ModulaMascotPicker: View {
    let selected: ModulaMascotKind
    var onSelect: (ModulaMascotKind) -> Void
    @Namespace private var ns

    var body: some View {
        ModulaGlassGroup(spacing: 6) {
            HStack(spacing: 4) {
                ForEach(ModulaMascotKind.allCases) { kind in
                    Button { onSelect(kind) } label: {
                        ModulaMascotView(kind: kind, size: 26)
                            .frame(width: 42, height: 42)
                            .background {
                                if kind == selected {
                                    Circle().fill(Color.primary.opacity(0.08))
                                        .overlay(Circle().strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 1.5))
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(kind.name)
                    .accessibilityAddTraits(kind == selected ? .isSelected : [])
                }
            }
            .padding(5)
            .modulaGlass(in: Capsule())
        }
        .fixedSize()
        .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
    }
}

// MARK: - Settings section

/// Mascot choice + where it shows (Settings → Chats → Composer).
struct ComposerMascotSettingsSection: View {
    @AppStorage(ModulaMascotSettings.kindKey) private var kindRaw = ModulaMascotKind.pip.rawValue
    @AppStorage(ModulaMascotSettings.nodusKey) private var nodus = true
    @AppStorage(ModulaMascotSettings.commentsKey) private var comments = false
    @AppStorage(ModulaMascotSettings.otherKey) private var other = false

    private let columns = [GridItem(.adaptive(minimum: 84), spacing: 10)]

    var body: some View {
        Section {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(ModulaMascotKind.allCases) { kind in
                    tile(selected: kindRaw == kind.rawValue, title: kind.name) {
                        ModulaMascotView(kind: kind, size: 38)
                    } action: { kindRaw = kind.rawValue }
                }
                tile(selected: kindRaw == ModulaMascotSettings.off, title: "Off") {
                    Image(systemName: "eye.slash").font(.title2).foregroundStyle(.secondary).frame(height: 42)
                } action: { kindRaw = ModulaMascotSettings.off }
            }
            .padding(.vertical, 6)
        } header: {
            Text("Mascot")
        } footer: {
            Text("A little companion that sits on the composer. Its eyes follow your touch and the tilt of your iPhone, and it glows while something is generating or sending. Hold it in any composer to swap.")
        }
        if kindRaw != ModulaMascotSettings.off {
            Section("Show mascot on") {
                Toggle("Nodus", isOn: $nodus)
                Toggle("Comment inputs", isOn: $comments)
                Toggle("Other composers", isOn: $other)
            }
        }
    }

    private func tile<Icon: View>(selected: Bool, title: String, @ViewBuilder icon: () -> Icon, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy) { action() }
            HapticEngine.shared.play(.selection)
        } label: {
            VStack(spacing: 6) {
                icon()
                Text(title).font(.caption.weight(.medium)).foregroundStyle(selected ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 84)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.primary.opacity(selected ? 0.08 : 0.03)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
