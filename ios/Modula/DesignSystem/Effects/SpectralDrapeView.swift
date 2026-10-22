import MetalKit
import SwiftUI
import simd

/// Native recreation of React Bits "Spectral Drape": billowing strands of dots in perspective.
/// Decorative only. Paused off-screen / backgrounded; static frame for Reduce Motion or Low Power.
struct SpectralDrapeView: View {
    var accent: Color = .accentColor
    var interactive: Bool = true
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var phase
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var visible = false

    var body: some View {
        SpectralDrapeRepresentable(
            dark: scheme == .dark,
            accent: UIColor(accent),
            animated: !reduceMotion && !lowPower && phase == .active && visible,
            interactive: interactive
        )
        .background(scheme == .dark ? Color(hex: "#0A0A0A") : Color(white: 0.985))
        .onAppear { visible = true }
        .onDisappear { visible = false }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        .accessibilityHidden(true)
    }
}

private struct SpectralDrapeRepresentable: UIViewRepresentable {
    var dark: Bool
    var accent: UIColor
    var animated: Bool
    var interactive: Bool

    func makeCoordinator() -> DrapeRenderer { DrapeRenderer() }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.isOpaque = false
        view.backgroundColor = .clear
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        view.colorPixelFormat = .bgra8Unorm
        view.preferredFramesPerSecond = 30
        view.framebufferOnly = true
        context.coordinator.setup(view)
        view.delegate = context.coordinator
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(DrapeRenderer.tapped(_:)))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        let r = context.coordinator
        r.dark = dark
        r.accent = accent
        r.interactive = interactive
        r.rebuildPipelineIfNeeded(view)
        view.isPaused = !animated
        view.enableSetNeedsDisplay = !animated
        if !animated { view.setNeedsDisplay() }
    }
}

private struct DrapeUniforms {
    var viewProj: simd_float4x4
    var time: Float
    var aspect: Float
    var pointScale: Float
    var dark: Float
    var nearColor: SIMD4<Float>
    var farColor: SIMD4<Float>
    var ripple: SIMD2<Float>
    var rippleAge: Float
    var strands: UInt32
    var dotsPerStrand: UInt32
}

fileprivate final class DrapeRenderer: NSObject, MTKViewDelegate {
    var dark = true
    var accent: UIColor = .systemPurple
    var interactive = true
    private var queue: MTLCommandQueue?
    private var pipeline: MTLRenderPipelineState?
    private var pipelineDark: Bool?
    private let start = CACurrentMediaTime()
    private var staticTime: Float = 18
    private var ripple = SIMD2<Float>(-9, -9)
    private var rippleStart: CFTimeInterval = 0
    private let strands: UInt32 = 120
    private let dots: UInt32 = 200

    func setup(_ view: MTKView) {
        queue = view.device?.makeCommandQueue()
        rebuildPipelineIfNeeded(view)
    }

    func rebuildPipelineIfNeeded(_ view: MTKView) {
        guard pipelineDark != dark, let device = view.device,
              let lib = device.makeDefaultLibrary(),
              let v = lib.makeFunction(name: "spectralDrapeVertex"),
              let f = lib.makeFunction(name: "spectralDrapeFragment") else { return }
        let d = MTLRenderPipelineDescriptor()
        d.vertexFunction = v
        d.fragmentFunction = f
        let a = d.colorAttachments[0]!
        a.pixelFormat = view.colorPixelFormat
        a.isBlendingEnabled = true
        a.rgbBlendOperation = .add
        a.alphaBlendOperation = .add
        a.sourceRGBBlendFactor = .one
        a.sourceAlphaBlendFactor = .one
        // Dark: pure additive glow. Light: premultiplied "over" so dots read as ink on white.
        a.destinationRGBBlendFactor = dark ? .one : .oneMinusSourceAlpha
        a.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        pipeline = try? device.makeRenderPipelineState(descriptor: d)
        pipelineDark = dark
    }

    @objc func tapped(_ g: UITapGestureRecognizer) {
        guard interactive, let v = g.view, v.bounds.width > 0 else { return }
        let p = g.location(in: v)
        ripple = SIMD2(Float(p.x / v.bounds.width), Float(1 - p.y / v.bounds.height))
        rippleStart = CACurrentMediaTime()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let pipeline, let queue, let pass = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable, let cb = queue.makeCommandBuffer(),
              let enc = cb.makeRenderCommandEncoder(descriptor: pass) else { return }
        let size = view.drawableSize
        let aspect = Float(size.width / max(size.height, 1))
        let time = view.isPaused ? staticTime : Float(CACurrentMediaTime() - start)
        let proj = Self.perspective(fovy: 0.9, aspect: aspect, near: 0.1, far: 40)
        // Camera tilted ~-40°, turned ~-45°, looking at the sheet.
        let view4 = Self.translate(0, -0.2, -6.5) * Self.rotX(0.70) * Self.rotY(-.pi / 4)
        let near: SIMD4<Float>, far: SIMD4<Float>
        if dark {
            near = SIMD4(0.894, 0.859, 1.0, 1)   // #E4DBFF
            far = SIMD4(0.416, 0.294, 1.0, 1)    // #6A4BFF
        } else {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, al: CGFloat = 0
            accent.getRed(&r, green: &g, blue: &b, alpha: &al)
            near = SIMD4(Float(r), Float(g), Float(b), 1)
            far = SIMD4(Float(r) * 0.5 + 0.45, Float(g) * 0.5 + 0.45, Float(b) * 0.5 + 0.45, 1)
        }
        let age = rippleStart > 0 ? Float(CACurrentMediaTime() - rippleStart) : 99
        var u = DrapeUniforms(viewProj: proj * view4, time: time, aspect: aspect,
                              pointScale: Float(view.contentScaleFactor) * 1.4,
                              dark: dark ? 1 : 0, nearColor: near, farColor: far,
                              ripple: age < 3 ? ripple : SIMD2(-9, -9), rippleAge: age,
                              strands: strands, dotsPerStrand: dots)
        enc.setRenderPipelineState(pipeline)
        enc.setVertexBytes(&u, length: MemoryLayout<DrapeUniforms>.stride, index: 0)
        enc.setFragmentBytes(&u, length: MemoryLayout<DrapeUniforms>.stride, index: 0)
        enc.drawPrimitives(type: .point, vertexStart: 0, vertexCount: Int(strands * dots))
        enc.endEncoding()
        cb.present(drawable)
        cb.commit()
    }

    private static func perspective(fovy: Float, aspect: Float, near: Float, far: Float) -> simd_float4x4 {
        let y = 1 / tan(fovy * 0.5), x = y / aspect, z = far / (near - far)
        return simd_float4x4(columns: (SIMD4(x, 0, 0, 0), SIMD4(0, y, 0, 0), SIMD4(0, 0, z, -1), SIMD4(0, 0, z * near, 0)))
    }
    private static func translate(_ x: Float, _ y: Float, _ z: Float) -> simd_float4x4 {
        var m = matrix_identity_float4x4; m.columns.3 = SIMD4(x, y, z, 1); return m
    }
    private static func rotX(_ a: Float) -> simd_float4x4 {
        simd_float4x4(columns: (SIMD4(1, 0, 0, 0), SIMD4(0, cos(a), sin(a), 0), SIMD4(0, -sin(a), cos(a), 0), SIMD4(0, 0, 0, 1)))
    }
    private static func rotY(_ a: Float) -> simd_float4x4 {
        simd_float4x4(columns: (SIMD4(cos(a), 0, -sin(a), 0), SIMD4(0, 1, 0, 0), SIMD4(sin(a), 0, cos(a), 0), SIMD4(0, 0, 0, 1)))
    }
}
