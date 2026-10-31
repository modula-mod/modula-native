import SwiftUI

/// Shared clock for Moliboo shaders: one TimelineView capped at `fps`, paused off-screen, when the scene is
/// inactive, or under Reduce Motion (then `t` is a fixed still frame, so every effect has a static fallback).
struct MolibooShaderClock<Content: View>: View {
    var fps: Double = 30
    var animated = true
    @ViewBuilder var content: (Double) -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var onScreen = false
    private var running: Bool { animated && onScreen && scenePhase == .active && !reduceMotion }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / max(fps, 1), paused: !running)) { ctx in
            content(running ? ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600) : 1.5)
        }
        .onAppear { onScreen = true }
        .onDisappear { onScreen = false }
    }
}

private struct MolibooTimedEffect: ViewModifier {
    enum Kind {
        case holo(Double, CGSize)
        case caustics(Color)
        case nebula(Double)
        case shimmer(Double)
        case sunbeams(Color, Double)
        case stageAura(Color, Double)
        case specularRim(Double)
    }
    let kind: Kind
    var fps: Double
    var animated: Bool
    func body(content: Content) -> some View {
        MolibooShaderClock(fps: fps, animated: animated) { t in
            content.visualEffect { v, proxy in
                let size = proxy.size
                switch kind {
                case .holo(let s, let tilt):
                    return v.colorEffect(ShaderLibrary.molibooHoloFoil(.float2(size), .float(t), .float2(Float(tilt.width), Float(tilt.height)), .float(s)))
                case .caustics(let c):
                    return v.colorEffect(ShaderLibrary.molibooCaustics(.float2(size), .float(t), .color(c)))
                case .nebula(let i):
                    return v.colorEffect(ShaderLibrary.molibooNebula(.float2(size), .float(t), .float(i)))
                case .shimmer(let s):
                    return v.colorEffect(ShaderLibrary.molibooShimmer(.float2(size), .float(t), .float(s)))
                case .sunbeams(let c, let i):
                    return v.colorEffect(ShaderLibrary.molibooSunbeams(.float2(size), .float(t), .color(c), .float(i)))
                case .stageAura(let c, let s):
                    return v.colorEffect(ShaderLibrary.molibooStageAura(.float2(size), .float(t), .color(c), .float(s)))
                case .specularRim(let s):
                    return v.colorEffect(ShaderLibrary.molibooSpecularRim(.float2(size), .float(t), .float(s)))
                }
            }
        }
    }
}

extension View {
    /// Holographic foil (collection / trading / sticker cards) with optional live tilt response. Static rainbow under Reduce Motion.
    func molibooHoloFoil(_ strength: Double = 0.6, tilt: CGSize = .zero, animated: Bool = true) -> some View {
        modifier(MolibooTimedEffect(kind: .holo(strength, tilt), fps: 24, animated: animated))
    }
    /// Caustic glow for the pedestal.
    func molibooCaustics(_ tint: Color = Color(red: 0.7, green: 1, blue: 0.9), animated: Bool = true) -> some View {
        modifier(MolibooTimedEffect(kind: .caustics(tint), fps: 20, animated: animated))
    }
    /// Aurora / nebula over a night sky.
    func molibooNebula(_ intensity: Double = 1, animated: Bool = true) -> some View {
        modifier(MolibooTimedEffect(kind: .nebula(intensity), fps: 15, animated: animated))
    }
    /// Daylight volumetric sunbeams for Meadow / Cozy Room / Morning / Afternoon stages.
    func molibooSunbeams(_ tint: Color = Color(red: 1.0, green: 0.96, blue: 0.82), intensity: Double = 0.85, animated: Bool = true) -> some View {
        modifier(MolibooTimedEffect(kind: .sunbeams(tint, intensity), fps: 18, animated: animated))
    }
    /// Soft volumetric stage aura behind the active Moliboo.
    func molibooStageAura(_ tint: Color = Color(red: 0.21, green: 0.61, blue: 0.67), strength: Double = 0.65, animated: Bool = true) -> some View {
        modifier(MolibooTimedEffect(kind: .stageAura(tint, strength), fps: 20, animated: animated))
    }
    /// Travelling liquid-glass specular rim highlight on active pills, cards, and badges.
    func molibooSpecularRim(_ strength: Double = 0.55, animated: Bool = true) -> some View {
        modifier(MolibooTimedEffect(kind: .specularRim(strength), fps: 20, animated: animated))
    }
    /// Legendary shimmer sweep.
    func molibooShimmer(_ strength: Double = 0.7, animated: Bool = true) -> some View {
        modifier(MolibooTimedEffect(kind: .shimmer(strength), fps: 30, animated: animated))
    }
    /// Ripple from `origin` each time `trigger` changes (distortion effect; nothing under Reduce Motion).
    func molibooRipple(trigger: Int, origin: CGPoint) -> some View { modifier(MolibooRippleEffect(trigger: trigger, origin: origin)) }
    /// Expanding joy/care pulse wave triggered on care actions (`Say hi`, `Play`, `Give treat`, `Pet`).
    func molibooJoyPulse(trigger: Int, tint: Color = Color(red: 0.21, green: 0.78, blue: 0.82)) -> some View {
        modifier(MolibooJoyPulseEffect(trigger: trigger, tint: tint))
    }
    /// Full-opacity portrait with a soft feathered edge (never faded / grey).
    func molibooPortraitEdge(_ feather: CGFloat = 0.14) -> some View {
        mask {
            GeometryReader { g in
                RadialGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 1 - feather), .init(color: .clear, location: 1)],
                               center: .center, startRadius: 0, endRadius: max(g.size.width, g.size.height) * 0.62)
            }
        }
    }
    /// Liquid Glass *behind* content (no vibrancy on images/text placed on it).
    func molibooGlassBackground<S: Shape>(_ shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        background { shape.fill(Color.clear).modulaGlass(in: shape, interactive: interactive, tint: tint, specular: true) }
    }
}

private struct MolibooRippleEffect: ViewModifier {
    let trigger: Int
    let origin: CGPoint
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start: Date = .distantPast
    func body(content: Content) -> some View {
        let active = !reduceMotion && Date().timeIntervalSince(start) < 1.6
        TimelineView(.animation(minimumInterval: 1 / 60, paused: !active)) { ctx in
            let age = ctx.date.timeIntervalSince(start)
            content.distortionEffect(ShaderLibrary.molibooRipple(.float2(origin), .float(age), .float(age < 1.6 ? 9 : 0)),
                                     maxSampleOffset: CGSize(width: 12, height: 12), isEnabled: !reduceMotion && age < 1.6)
        }
        .onChange(of: trigger) { _, _ in start = Date() }
    }
}

/// Expanding joy ring drawn as its own overlay (not a colour effect on the content), so it is a clean circle
/// over every layer, is never squared off by layer bounds, and ends at 0.86 × the host's half-size.
private struct MolibooJoyPulseEffect: ViewModifier {
    let trigger: Int
    let tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start: Date = .distantPast
    @State private var running = false
    private static let duration = 1.4
    func body(content: Content) -> some View {
        content.overlay {
            if running && !reduceMotion {
                GeometryReader { g in
                    TimelineView(.animation(minimumInterval: 1 / 60)) { ctx in
                        let p = min(1, max(0, ctx.date.timeIntervalSince(start) / Self.duration))
                        let eased = 1 - pow(1 - p, 2.2)
                        let r = min(g.size.width, g.size.height) / 2 * 0.86 * max(0.12, eased)
                        Circle()
                            .stroke(AngularGradient(colors: [tint, tint.opacity(0.75), .pink.opacity(0.7), tint], center: .center),
                                    lineWidth: 4 + 10 * (1 - p))
                            .blur(radius: 3 + 5 * p)
                            .frame(width: r * 2, height: r * 2)
                            .position(x: g.size.width / 2, y: g.size.height / 2)
                            .opacity(0.8 * (1 - p))
                    }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .onChange(of: trigger) { _, _ in
            let begun = Date()
            start = begun; running = true
            // Stop the 60 fps timeline once the ring has faded.
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(Self.duration + 0.05))
                if start == begun { running = false }
            }
        }
    }
}

/// Pack opening: the foil wrapper burns away from the centre revealing `content`.
struct MolibooPackReveal<Wrapper: View, Content: View>: View {
    @Binding var opened: Bool
    @ViewBuilder var wrapper: Wrapper
    @ViewBuilder var content: Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: Double = 0
    var body: some View {
        ZStack {
            content.scaleEffect(opened ? 1 : 0.85).opacity(opened ? 1 : 0)
            if progress < 1 {
                wrapper.visualEffect { v, proxy in
                    v.layerEffect(ShaderLibrary.molibooPackReveal(.float2(proxy.size), .float(progress)), maxSampleOffset: .zero)
                }
            }
        }
        .onChange(of: opened) { _, o in
            withAnimation(reduceMotion ? nil : .easeIn(duration: 0.9)) { progress = o ? 1 : 0 }
        }
    }
}

/// Animatable pack-tear dissolve (Metal layer effect); drive `progress` 0→1 inside withAnimation.
struct MolibooDissolve: ViewModifier, @MainActor Animatable {
    var progress: Double
    var animatableData: Double { get { progress } set { progress = newValue } }
    func body(content: Content) -> some View {
        let p = progress
        return content.visualEffect { v, proxy in
            v.layerEffect(ShaderLibrary.molibooPackReveal(.float2(proxy.size), .float(p)), maxSampleOffset: .zero, isEnabled: p > 0.001)
        }
    }
}
