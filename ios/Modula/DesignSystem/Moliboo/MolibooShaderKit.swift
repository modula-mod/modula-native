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
    enum Kind { case holo(Double), caustics(Color), nebula(Double), shimmer(Double) }
    let kind: Kind
    var fps: Double
    var animated: Bool
    func body(content: Content) -> some View {
        MolibooShaderClock(fps: fps, animated: animated) { t in
            content.visualEffect { v, proxy in
                let size = proxy.size
                switch kind {
                case .holo(let s):
                    return v.colorEffect(ShaderLibrary.molibooHoloFoil(.float2(size), .float(t), .float2(0, 0), .float(s)))
                case .caustics(let c):
                    return v.colorEffect(ShaderLibrary.molibooCaustics(.float2(size), .float(t), .color(c)))
                case .nebula(let i):
                    return v.colorEffect(ShaderLibrary.molibooNebula(.float2(size), .float(t), .float(i)))
                case .shimmer(let s):
                    return v.colorEffect(ShaderLibrary.molibooShimmer(.float2(size), .float(t), .float(s)))
                }
            }
        }
    }
}

extension View {
    /// Holographic foil (collection / sticker cards). Static rainbow under Reduce Motion.
    func molibooHoloFoil(_ strength: Double = 0.6, animated: Bool = true) -> some View {
        modifier(MolibooTimedEffect(kind: .holo(strength), fps: 24, animated: animated))
    }
    /// Caustic glow for the pedestal.
    func molibooCaustics(_ tint: Color = Color(red: 0.7, green: 1, blue: 0.9), animated: Bool = true) -> some View {
        modifier(MolibooTimedEffect(kind: .caustics(tint), fps: 20, animated: animated))
    }
    /// Aurora / nebula over a night sky.
    func molibooNebula(_ intensity: Double = 1, animated: Bool = true) -> some View {
        modifier(MolibooTimedEffect(kind: .nebula(intensity), fps: 15, animated: animated))
    }
    /// Legendary shimmer sweep.
    func molibooShimmer(_ strength: Double = 0.7, animated: Bool = true) -> some View {
        modifier(MolibooTimedEffect(kind: .shimmer(strength), fps: 30, animated: animated))
    }
    /// Ripple from `origin` each time `trigger` changes (distortion effect; nothing under Reduce Motion).
    func molibooRipple(trigger: Int, origin: CGPoint) -> some View { modifier(MolibooRippleEffect(trigger: trigger, origin: origin)) }
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
