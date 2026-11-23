import AVFoundation
import Photos
import SwiftUI
import UIKit

/// Full-screen photo capture for the composer, driven by Settings → Camera:
/// - "Show grid" draws a rule-of-thirds grid over the preview.
/// - "Mirror front camera" stores selfies the way the preview shows them.
/// - "Format" captures HEIC (when the device supports it) or JPEG.
/// - "Save to Photos" also adds each capture to your library (add-only access,
///   requested the first time; Modula never reads your library this way).
struct ModulaCameraCaptureView: View {
    var onCapture: (Data, String) -> Void
    var onClose: () -> Void
    @StateObject private var camera = ModulaCameraSession()
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var flash = false
    @State private var saveNotice: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            preview
            if ModulaPreferences.cameraGrid, camera.isReady {
                CameraThirdsGrid().allowsHitTesting(false).accessibilityHidden(true)
            }
            Color.white.opacity(flash ? 0.7 : 0).ignoresSafeArea().allowsHitTesting(false)
            VStack {
                HStack {
                    control("xmark", label: "Close camera", action: onClose)
                    Spacer()
                    Text(ModulaPreferences.cameraPrefersHEIC && camera.supportsHEIC ? "HEIC" : "JPEG")
                        .font(.caption2.weight(.bold).monospaced())
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.ultraThinMaterial, in: Capsule())
                        .accessibilityLabel("Format \(ModulaPreferences.cameraPrefersHEIC && camera.supportsHEIC ? "HEIC" : "JPEG")")
                    Spacer()
                    control("arrow.triangle.2.circlepath.camera", label: "Flip camera") { camera.flip() }
                }
                .padding(.horizontal, 16)
                Spacer()
                if let saveNotice {
                    Text(saveNotice)
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 8)
                }
                Button(action: shoot) {
                    Circle()
                        .fill(.white)
                        .frame(width: 74, height: 74)
                        .overlay { Circle().stroke(app.appearance.liveAccent, lineWidth: 4).padding(5) }
                }
                .buttonStyle(.plain)
                .disabled(!camera.isReady)
                .accessibilityLabel("Take photo")
                .accessibilityIdentifier("compose.camera.shutter")
                .padding(.bottom, 28)
            }
            .foregroundStyle(.white)
        }
        .statusBarHidden()
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
        .accessibilityIdentifier("compose.camera")
    }

    @ViewBuilder
    private var preview: some View {
        if camera.denied {
            notice("Camera access is off. Turn it on in iOS Settings → Modula.", symbol: "camera.fill", openSettings: true)
        } else if let message = camera.unavailable {
            notice(message, symbol: "camera", openSettings: false)
        } else {
            ModulaCameraPreview(session: camera.session).ignoresSafeArea()
        }
    }

    private func shoot() {
        HapticEngine.shared.play(.lightImpact)
        if !reduceMotion && !ModulaPreferences.extraMotionReduction {
            withAnimation(.easeOut(duration: 0.08)) { flash = true }
            withAnimation(.easeIn(duration: 0.25).delay(0.08)) { flash = false }
        }
        camera.capture(
            heic: ModulaPreferences.cameraPrefersHEIC,
            mirrorFront: ModulaPreferences.cameraMirrorFront
        ) { data, mimeType in
            if ModulaPreferences.cameraSavesToPhotos {
                Task {
                    let saved = await ModulaPhotoLibrarySaver.save(data)
                    saveNotice = saved ? "Saved to Photos" : "Couldn’t save to Photos — check access in iOS Settings."
                }
            }
            onCapture(data, mimeType)
        }
    }

    private func notice(_ text: String, symbol: String, openSettings: Bool) -> some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.largeTitle)
            Text(text).font(.callout).multilineTextAlignment(.center)
            if openSettings, let url = URL(string: UIApplication.openSettingsURLString) {
                Button("Open iOS Settings") { UIApplication.shared.open(url) }
                    .buttonStyle(.borderedProminent)
            }
        }
        .foregroundStyle(.white)
        .padding(32)
    }

    private func control(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

struct CameraThirdsGrid: View {
    var body: some View {
        GeometryReader { proxy in
            Path { path in
                let w = proxy.size.width, h = proxy.size.height
                for i in 1...2 {
                    let x = w * CGFloat(i) / 3, y = h * CGFloat(i) / 3
                    path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: h))
                    path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: w, y: y))
                }
            }
            .stroke(.white.opacity(0.45), lineWidth: 0.75)
        }
        .ignoresSafeArea()
    }
}

enum ModulaPhotoLibrarySaver {
    /// Add-only save; never requests read access to the library.
    static func save(_ data: Data) async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { return false }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
            }
            return true
        } catch {
            return false
        }
    }
}

private struct ModulaCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }
    func updateUIView(_ uiView: PreviewView, context: Context) { uiView.previewLayer.session = session }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

private final class ModulaCameraSession: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    @Published var denied = false
    @Published var unavailable: String?
    @Published var isReady = false
    @Published var supportsHEIC = false
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "digital.modula.composer.camera")
    private var position: AVCaptureDevice.Position = .back
    private var onCapture: ((Data, String) -> Void)?
    private var pendingMimeType = "image/jpeg"
    private var configured = false

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndRun()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted { self.configureAndRun() } else { self.denied = true }
                }
            }
        default:
            denied = true
        }
    }

    func stop() {
        queue.async { [session] in if session.isRunning { session.stopRunning() } }
        isReady = false
    }

    func flip() {
        position = position == .back ? .front : .back
        configureAndRun()
    }

    func capture(heic: Bool, mirrorFront: Bool, _ handler: @escaping (Data, String) -> Void) {
        guard isReady else { return }
        onCapture = handler
        let position = self.position
        queue.async { [output] in
            let useHEIC = heic && output.availablePhotoCodecTypes.contains(.hevc)
            let settings = useHEIC
                ? AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
                : AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            self.pendingMimeType = useHEIC ? "image/heic" : "image/jpeg"
            if let connection = output.connection(with: .video), connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = position == .front && mirrorFront
            }
            output.capturePhoto(with: settings, delegate: self)
        }
    }

    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation() else { return }
        let mimeType = pendingMimeType
        DispatchQueue.main.async {
            self.onCapture?(data, mimeType)
            self.onCapture = nil
        }
    }

    private func configureAndRun() {
        queue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .photo
            self.session.inputs.forEach { self.session.removeInput($0) }
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: self.position),
                  let input = try? AVCaptureDeviceInput(device: device),
                  self.session.canAddInput(input) else {
                self.session.commitConfiguration()
                DispatchQueue.main.async {
                    self.unavailable = "The camera isn’t available on this device."
                    self.isReady = false
                }
                return
            }
            self.session.addInput(input)
            if !self.configured, self.session.canAddOutput(self.output) {
                self.session.addOutput(self.output)
                self.configured = true
            }
            self.session.commitConfiguration()
            if !self.session.isRunning { self.session.startRunning() }
            let heic = self.output.availablePhotoCodecTypes.contains(.hevc)
            DispatchQueue.main.async {
                self.unavailable = nil
                self.supportsHEIC = heic
                self.isReady = true
            }
        }
    }
}
