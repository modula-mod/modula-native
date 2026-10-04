import AVFoundation
import SwiftUI
import UIKit

/// Shared inline camera card (Nodus chat + comment composer): live preview, shutter, flip,
/// flash, close, and optional short-video mode. Results go back as a UIImage or a movie file URL.
struct ModulaInlineCamera: View {
    enum Mode: String, CaseIterable { case photo = "Photo", video = "Video" }

    var modes: [Mode] = [.photo]
    var idPrefix = "camera"
    var height: CGFloat = 228
    var maxVideoSeconds: Double = 15
    var onPhoto: (UIImage) -> Void
    var onVideo: ((URL) -> Void)? = nil
    var onClose: () -> Void

    @StateObject private var camera = ModulaInlineCameraSession()
    @State private var mode: Mode = .photo
    @State private var flash: AVCaptureDevice.FlashMode = .off
    @State private var flashPulse = false
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        ZStack {
            preview
            if flashPulse { Color.white.opacity(0.85).transition(.opacity) }
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    control("xmark", label: "Close camera", id: "\(idPrefix).close", action: onClose)
                    Spacer()
                    if camera.isRecording {
                        Label(Duration.seconds(camera.recordedSeconds).formatted(.time(pattern: .minuteSecond)), systemImage: "record.circle")
                            .font(.caption.monospacedDigit().weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10).frame(height: 30)
                            .background(.red, in: Capsule())
                            .transition(.scale.combined(with: .opacity))
                    }
                    Spacer()
                    control(flashSymbol, label: "Flash \(flashLabel)", id: "\(idPrefix).flash") {
                        flash = switch flash { case .off: .auto; case .auto: .on; default: .off }
                        HapticEngine.shared.play(.selection)
                    }
                    control("arrow.triangle.2.circlepath.camera", label: "Flip camera", id: "\(idPrefix).flip") {
                        camera.flip()
                        HapticEngine.shared.play(.selection)
                    }
                    .disabled(camera.isRecording)
                }
                Spacer()
                HStack {
                    if modes.count > 1 {
                        HStack(spacing: 2) {
                            ForEach(modes, id: \.self) { item in
                                Button {
                                    guard !camera.isRecording else { return }
                                    withAnimation(.snappy) { mode = item }
                                    HapticEngine.shared.play(.selection)
                                } label: {
                                    Text(item.rawValue).font(.caption.weight(.bold))
                                        .foregroundStyle(mode == item ? .black : .white)
                                        .padding(.horizontal, 10).frame(height: 28)
                                        .background { if mode == item { Capsule().fill(.white) } }
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(mode == item ? .isSelected : [])
                            }
                        }
                        .padding(3)
                        .background(.ultraThinMaterial, in: Capsule())
                        .frame(width: 120, alignment: .leading)
                    } else {
                        Color.clear.frame(width: 120, height: 1)
                    }
                    Spacer()
                    shutter
                    Spacer()
                    Color.clear.frame(width: 120, height: 1)
                }
                .padding(.bottom, 4)
            }
            .padding(10)
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.18), lineWidth: 0.8) }
        .animation(.snappy, value: camera.isRecording)
        .accessibilityIdentifier(idPrefix)
        .onAppear {
            mode = modes.first ?? .photo
            camera.start(withAudio: modes.contains(.video))
        }
        .onDisappear { camera.stop() }
        .onChange(of: camera.finishedVideo) { _, url in
            if let url { onVideo?(url); camera.finishedVideo = nil }
        }
    }

    private var shutter: some View {
        Button {
            switch mode {
            case .photo:
                camera.capture(flash: flash) { image in onPhoto(image) }
                withAnimation(.easeOut(duration: 0.08)) { flashPulse = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { withAnimation(.easeIn(duration: 0.2)) { flashPulse = false } }
                HapticEngine.shared.play(.actionConfirmed)
            case .video:
                if camera.isRecording { camera.stopRecording() } else { camera.startRecording(torch: flash == .on, maxSeconds: maxVideoSeconds) }
                HapticEngine.shared.play(.lightImpact)
            }
        } label: {
            ZStack {
                Circle().strokeBorder(.white, lineWidth: 4).frame(width: 64, height: 64)
                if mode == .video {
                    RoundedRectangle(cornerRadius: camera.isRecording ? 6 : 26, style: .continuous)
                        .fill(.red)
                        .frame(width: camera.isRecording ? 26 : 52, height: camera.isRecording ? 26 : 52)
                } else {
                    Circle().fill(.white).frame(width: 52, height: 52)
                        .overlay { Circle().stroke(app.appearance.accent.color, lineWidth: 2).padding(3) }
                }
                if camera.isRecording {
                    Circle().trim(from: 0, to: min(camera.recordedSeconds / maxVideoSeconds, 1))
                        .stroke(.red, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 64, height: 64)
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: camera.isRecording)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: mode)
        }
        .buttonStyle(.plain)
        .disabled(!camera.isReady)
        .accessibilityLabel(mode == .photo ? "Take photo" : (camera.isRecording ? "Stop recording" : "Record video"))
        .accessibilityIdentifier("\(idPrefix).shutter")
    }

    private var flashSymbol: String {
        switch flash { case .on: "bolt.fill"; case .auto: "bolt.badge.automatic.fill"; default: "bolt.slash.fill" }
    }
    private var flashLabel: String {
        switch flash { case .on: "on"; case .auto: "auto"; default: "off" }
    }

    @ViewBuilder
    private var preview: some View {
        if camera.denied {
            notice("Camera access is off", symbol: "camera.fill", settings: true)
        } else if let message = camera.unavailable {
            notice(message, symbol: "camera", settings: false)
        } else {
            ModulaCameraLivePreview(session: camera.session).overlay(Color.black.opacity(0.05))
        }
    }

    private func notice(_ title: String, symbol: String, settings: Bool) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.title2)
            Text(title).font(.footnote).multilineTextAlignment(.center)
            if settings {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .font(.footnote.weight(.semibold))
            }
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .secondarySystemBackground))
    }

    private func control(_ symbol: String, label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 36, height: 36)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }
}

private struct ModulaCameraLivePreview: UIViewRepresentable {
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

private final class ModulaInlineCameraSession: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate, AVCaptureFileOutputRecordingDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    @Published var denied = false
    @Published var unavailable: String?
    @Published var isReady = false
    @Published var isRecording = false
    @Published var recordedSeconds: Double = 0
    @Published var finishedVideo: URL?
    private let photoOutput = AVCapturePhotoOutput()
    private let movieOutput = AVCaptureMovieFileOutput()
    private let queue = DispatchQueue(label: "modula.inline.camera")
    private var position: AVCaptureDevice.Position = .back
    private var onCapture: ((UIImage) -> Void)?
    private var configuredOutputs = false
    private var withAudio = false
    private var timer: Timer?
    private var device: AVCaptureDevice?

    func start(withAudio: Bool) {
        self.withAudio = withAudio
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: configureAndRun()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async { if granted { self.configureAndRun() } else { self.denied = true } }
            }
        default: denied = true
        }
    }

    func stop() {
        if isRecording { stopRecording() }
        queue.async { [session] in if session.isRunning { session.stopRunning() } }
        isReady = false
    }

    func flip() {
        position = position == .back ? .front : .back
        configureAndRun()
    }

    func capture(flash: AVCaptureDevice.FlashMode, _ handler: @escaping (UIImage) -> Void) {
        guard isReady else { return }
        onCapture = handler
        queue.async { [photoOutput] in
            let settings = AVCapturePhotoSettings()
            if photoOutput.supportedFlashModes.contains(flash) { settings.flashMode = flash }
            photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    func startRecording(torch: Bool, maxSeconds: Double) {
        guard isReady, !movieOutput.isRecording else { return }
        let url = FileManager.default.temporaryDirectory.appending(path: "comment-\(UUID().uuidString).mov")
        queue.async { [movieOutput, device] in
            if torch, let device, device.hasTorch, (try? device.lockForConfiguration()) != nil {
                device.torchMode = .on
                device.unlockForConfiguration()
            }
            movieOutput.maxRecordedDuration = CMTime(seconds: maxSeconds, preferredTimescale: 600)
            movieOutput.startRecording(to: url, recordingDelegate: self)
        }
        isRecording = true
        recordedSeconds = 0
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { self?.recordedSeconds += 0.1 }
        }
    }

    func stopRecording() {
        queue.async { [movieOutput] in if movieOutput.isRecording { movieOutput.stopRecording() } }
    }

    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else { return }
        DispatchQueue.main.async {
            self.onCapture?(image)
            self.onCapture = nil
        }
    }

    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        let ok = error == nil || ((error as NSError?)?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool) == true
        queue.async { [device] in
            if let device, device.hasTorch, device.torchMode == .on, (try? device.lockForConfiguration()) != nil {
                device.torchMode = .off
                device.unlockForConfiguration()
            }
        }
        DispatchQueue.main.async {
            self.timer?.invalidate()
            self.isRecording = false
            if ok { self.finishedVideo = outputFileURL }
        }
    }

    private func configureAndRun() {
        queue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = self.withAudio ? .high : .photo
            self.session.inputs.forEach { self.session.removeInput($0) }
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: self.position),
                  let input = try? AVCaptureDeviceInput(device: device),
                  self.session.canAddInput(input) else {
                self.session.commitConfiguration()
                DispatchQueue.main.async { self.unavailable = "Camera isn't available here"; self.isReady = false }
                return
            }
            self.session.addInput(input)
            self.device = device
            if self.withAudio, AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
               let mic = AVCaptureDevice.default(for: .audio), let audio = try? AVCaptureDeviceInput(device: mic), self.session.canAddInput(audio) {
                self.session.addInput(audio)
            }
            if !self.configuredOutputs {
                if self.session.canAddOutput(self.photoOutput) { self.session.addOutput(self.photoOutput) }
                if self.withAudio, self.session.canAddOutput(self.movieOutput) { self.session.addOutput(self.movieOutput) }
                self.configuredOutputs = true
            }
            if let connection = self.movieOutput.connection(with: .video), connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = self.position == .front
            }
            self.session.commitConfiguration()
            if !self.session.isRunning { self.session.startRunning() }
            DispatchQueue.main.async { self.unavailable = nil; self.isReady = true }
            // Ask for the microphone lazily so video has sound next time.
            if self.withAudio, AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
                AVCaptureDevice.requestAccess(for: .audio) { granted in if granted { self.configureAndRun() } }
            }
        }
    }
}
