import AVFoundation
import CoreImage
import PhotosUI
import SwiftUI
import UIKit
import Vision

// MARK: - Create Story v3 — full-bleed camera (Instagram/Snapchat/TikTok style)
//
// Everything here runs on device: AVFoundation capture, Core Image filters, Vision person
// segmentation (portrait blur / green screen) and Vision face tracking for face effects.

enum StoryCaptureMode: String, CaseIterable, Identifiable, Sendable {
    case text = "Create", photo = "Photo", video = "Video", boomerang = "Boomerang", handsFree = "Hands-free", ar = "AR", layout = "Layout"
    var id: String { rawValue }
}

enum StoryCameraEffect: String, CaseIterable, Identifiable, Sendable {
    case none, beauty, portrait, greenScreen, glasses, crown, bear, hearts, moliboo
    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: "None"
        case .beauty: "Smooth"
        case .portrait: "Portrait"
        case .greenScreen: "Backdrop"
        case .glasses: "Shades"
        case .crown: "Crown"
        case .bear: "Bear"
        case .hearts: "Hearts"
        case .moliboo: "Moliboo"
        }
    }
    var glyph: String {
        switch self {
        case .none: "⊘"
        case .beauty: "✨"
        case .portrait: "🌫️"
        case .greenScreen: "🏝️"
        case .glasses: "🕶️"
        case .crown: "👑"
        case .bear: "🐻"
        case .hearts: "😍"
        case .moliboo: "🫧"
        }
    }
    var needsSegmentation: Bool { self == .portrait || self == .greenScreen }
    var needsFaces: Bool {
        switch self {
        case .glasses, .crown, .bear, .hearts, .moliboo: true
        default: false
        }
    }
}

/// Processes camera frames through Vision + Core Image and publishes the result for display and capture.
private final class StoryCameraEngine: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureFileOutputRecordingDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    @Published var frame: CGImage?
    @Published var faces: [CGRect] = []
    @Published var denied = false
    @Published var unavailable: String?
    @Published var isReady = false
    @Published var isRecording = false
    @Published var recordedSeconds: Double = 0
    @Published var finishedVideo: URL?
    @Published var zoom: CGFloat = 1
    @Published var position: AVCaptureDevice.Position = .back

    private let videoOutput = AVCaptureVideoDataOutput()
    private let movieOutput = AVCaptureMovieFileOutput()
    private let sessionQueue = DispatchQueue(label: "modula.story.camera.session")
    private let frameQueue = DispatchQueue(label: "modula.story.camera.frames", qos: .userInteractive)
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    private let lock = NSLock()
    private var filterID = "none"
    private var effect: StoryCameraEffect = .none
    private var backdrop: CIImage?
    private var device: AVCaptureDevice?
    private var configured = false
    private var frameIndex = 0
    private var lastFaces: [CGRect] = []
    private var timer: Timer?

    // MARK: Settings (main → frame queue)

    func set(filter id: String) { lock.withLock { filterID = id } }
    func set(effect value: StoryCameraEffect) { lock.withLock { effect = value; if !value.needsFaces { lastFaces = [] } } ; if !value.needsFaces { faces = [] } }
    func set(backdrop image: UIImage?) {
        let ci = image.flatMap { $0.cgImage.map { CIImage(cgImage: $0) } }
        lock.withLock { backdrop = ci }
    }

    // MARK: Lifecycle

    func start() {
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
        sessionQueue.async { [session] in if session.isRunning { session.stopRunning() } }
        isReady = false
    }

    func flip() {
        position = position == .back ? .front : .back
        zoom = 1
        configureAndRun()
    }

    func setZoom(_ value: CGFloat) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.device else { return }
            let limit = min(device.activeFormat.videoMaxZoomFactor, 10)
            let clamped = min(max(value, 1), limit)
            if (try? device.lockForConfiguration()) != nil {
                device.videoZoomFactor = clamped
                device.unlockForConfiguration()
            }
            DispatchQueue.main.async { self.zoom = clamped }
        }
    }

    func setTorch(_ on: Bool) {
        sessionQueue.async { [weak self] in
            guard let device = self?.device, device.hasTorch, (try? device.lockForConfiguration()) != nil else { return }
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
        }
    }

    func startRecording(maxSeconds: Double, torch: Bool) {
        guard isReady, !isRecording else { return }
        let url = FileManager.default.temporaryDirectory.appending(path: "story-\(UUID().uuidString).mov")
        if torch, position == .back { setTorch(true) }
        sessionQueue.async { [movieOutput, position] in
            if let connection = movieOutput.connection(with: .video) {
                StoryCameraEngine.orient(connection, position: position)
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
        sessionQueue.async { [movieOutput] in if movieOutput.isRecording { movieOutput.stopRecording() } }
    }

    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        let ok = error == nil || ((error as NSError?)?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool) == true
        setTorch(false)
        DispatchQueue.main.async {
            self.timer?.invalidate()
            self.isRecording = false
            if ok { self.finishedVideo = outputFileURL }
        }
    }

    private func configureAndRun() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            let position = DispatchQueue.main.sync { self.position }
            self.session.beginConfiguration()
            if self.session.canSetSessionPreset(.hd1920x1080) { self.session.sessionPreset = .hd1920x1080 }
            self.session.inputs.forEach { self.session.removeInput($0) }
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
                  let input = try? AVCaptureDeviceInput(device: device),
                  self.session.canAddInput(input) else {
                self.session.commitConfiguration()
                DispatchQueue.main.async { self.unavailable = "Camera isn't available here"; self.isReady = false }
                return
            }
            self.session.addInput(input)
            self.device = device
            if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
               let mic = AVCaptureDevice.default(for: .audio), let audio = try? AVCaptureDeviceInput(device: mic), self.session.canAddInput(audio) {
                self.session.addInput(audio)
            }
            if !self.configured {
                self.videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                self.videoOutput.alwaysDiscardsLateVideoFrames = true
                self.videoOutput.setSampleBufferDelegate(self, queue: self.frameQueue)
                if self.session.canAddOutput(self.videoOutput) { self.session.addOutput(self.videoOutput) }
                if self.session.canAddOutput(self.movieOutput) { self.session.addOutput(self.movieOutput) }
                self.configured = true
            }
            for output in [self.videoOutput as AVCaptureOutput, self.movieOutput] {
                if let connection = output.connection(with: .video) {
                    StoryCameraEngine.orient(connection, position: position)
                }
            }
            self.session.commitConfiguration()
            if !self.session.isRunning { self.session.startRunning() }
            DispatchQueue.main.async { self.unavailable = nil; self.isReady = true }
            if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
                AVCaptureDevice.requestAccess(for: .audio) { granted in if granted { self.configureAndRun() } }
            }
        }
    }

    /// Portrait, upright, selfie-mirrored for the front camera. Mirroring is set
    /// *before* rotation: on the front camera, setting it after a 90° rotation
    /// flips the rotated frame and the image comes out upside down / sideways.
    nonisolated static func orient(_ connection: AVCaptureConnection, position: AVCaptureDevice.Position) {
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = position == .front
        }
        if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
    }

    // MARK: Frames

    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let (filterID, effect, backdrop) = lock.withLock { (self.filterID, self.effect, self.backdrop) }
        var image = CIImage(cvPixelBuffer: pixels)
        let extent = image.extent
        frameIndex &+= 1

        if effect.needsSegmentation {
            let request = VNGeneratePersonSegmentationRequest()
            request.qualityLevel = .balanced
            request.outputPixelFormat = kCVPixelFormatType_OneComponent8
            let handler = VNImageRequestHandler(cvPixelBuffer: pixels, orientation: .up)
            if (try? handler.perform([request])) != nil, let maskBuffer = request.results?.first?.pixelBuffer {
                var mask = CIImage(cvPixelBuffer: maskBuffer)
                mask = mask.transformed(by: CGAffineTransform(scaleX: extent.width / mask.extent.width, y: extent.height / mask.extent.height))
                let background: CIImage
                if effect == .greenScreen, let backdrop {
                    let s = max(extent.width / backdrop.extent.width, extent.height / backdrop.extent.height)
                    let scaled = backdrop.transformed(by: CGAffineTransform(scaleX: s, y: s))
                    background = scaled.transformed(by: CGAffineTransform(
                        translationX: (extent.width - scaled.extent.width) / 2 - scaled.extent.minX,
                        y: (extent.height - scaled.extent.height) / 2 - scaled.extent.minY
                    )).cropped(to: extent)
                } else if effect == .greenScreen {
                    background = CIImage(color: CIColor(red: 0.2, green: 0.85, blue: 0.45)).cropped(to: extent)
                } else {
                    background = image.clampedToExtent().applyingGaussianBlur(sigma: 22).cropped(to: extent)
                }
                image = image.applyingFilter("CIBlendWithMask", parameters: [
                    kCIInputBackgroundImageKey: background,
                    kCIInputMaskImageKey: mask,
                ])
            }
        } else if effect == .beauty {
            let smooth = image.clampedToExtent().applyingGaussianBlur(sigma: 5).cropped(to: extent)
                .applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0.45)])
            image = smooth.composited(over: image)
                .applyingFilter("CIColorControls", parameters: [kCIInputBrightnessKey: 0.02, kCIInputSaturationKey: 1.05])
        }

        if effect.needsFaces, frameIndex % 3 == 0 {
            let request = VNDetectFaceRectanglesRequest()
            let handler = VNImageRequestHandler(cvPixelBuffer: pixels, orientation: .up)
            if (try? handler.perform([request])) != nil {
                let rects = (request.results ?? []).prefix(3).map { face -> CGRect in
                    let b = face.boundingBox
                    return CGRect(x: b.minX, y: 1 - b.maxY, width: b.width, height: b.height)
                }
                lastFaces = Array(rects)
                let snapshot = lastFaces
                DispatchQueue.main.async { self.faces = snapshot }
            }
        }

        image = StoryFilterEngine.ciApply(filterID, to: image).cropped(to: extent)
        guard let cg = ciContext.createCGImage(image, from: extent) else { return }
        DispatchQueue.main.async { self.frame = cg }
    }
}

/// Face-tracked decorations, positioned for an aspect-fill frame inside any container.
struct StoryFaceDecorations: View {
    var faces: [CGRect]
    var effect: StoryCameraEffect
    var frameSize: CGSize

    var body: some View {
        GeometryReader { geo in
            let fw = max(frameSize.width, 1), fh = max(frameSize.height, 1)
            let s = max(geo.size.width / fw, geo.size.height / fh)
            let dx = (geo.size.width - fw * s) / 2, dy = (geo.size.height - fh * s) / 2
            ForEach(Array(faces.enumerated()), id: \.offset) { _, r in
                let rect = CGRect(x: dx + r.minX * fw * s, y: dy + r.minY * fh * s, width: r.width * fw * s, height: r.height * fh * s)
                decoration(in: rect)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func decoration(in rect: CGRect) -> some View {
        switch effect {
        case .glasses:
            Text("🕶️").font(.system(size: rect.width * 0.78)).position(x: rect.midX, y: rect.minY + rect.height * 0.40)
        case .crown:
            Text("👑").font(.system(size: rect.width * 0.7)).position(x: rect.midX, y: rect.minY - rect.width * 0.28)
        case .bear:
            Text("🐻").font(.system(size: rect.width * 1.25)).position(x: rect.midX, y: rect.midY)
        case .hearts:
            ZStack {
                Text("💕").font(.system(size: rect.width * 0.34)).position(x: rect.minX, y: rect.minY - rect.width * 0.1)
                Text("💖").font(.system(size: rect.width * 0.28)).position(x: rect.maxX, y: rect.minY)
                Text("💗").font(.system(size: rect.width * 0.22)).position(x: rect.midX, y: rect.minY - rect.width * 0.32)
            }
        case .moliboo:
            ModulaMascotSticker(kind: .pip, size: max(rect.width * 0.7, 40))
                .position(x: rect.maxX + rect.width * 0.32, y: rect.midY + rect.height * 0.2)
        default:
            EmptyView()
        }
    }
}

/// What a still capture flattens: the processed frame plus face decorations, at frame resolution.
struct StoryCameraStill: View {
    let frame: CGImage
    var faces: [CGRect]
    var effect: StoryCameraEffect

    var body: some View {
        let size = CGSize(width: frame.width, height: frame.height)
        ZStack {
            Image(decorative: frame, scale: 1).resizable()
            if effect.needsFaces { StoryFaceDecorations(faces: faces, effect: effect, frameSize: size) }
        }
        .frame(width: size.width, height: size.height)
    }
}

/// Full-bleed capture surface: modes, filter carousel around the shutter, effects, timer, flash, flip, zoom.
struct StoryCaptureStage: View {
    var canVideo: Bool
    @Binding var libraryItems: [PhotosPickerItem]
    var onPhoto: (UIImage) -> Void
    var onVideo: (URL) -> Void
    var onText: () -> Void
    var onLayout: () -> Void
    var onClose: () -> Void
    /// Restricts the mode list (e.g. the post composer only offers Photo / Video).
    var allowedModes: [StoryCaptureMode]? = nil

    @StateObject private var engine = StoryCameraEngine()
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var mode: StoryCaptureMode = .photo
    @State private var filterID: String? = "none"
    @State private var effect: StoryCameraEffect = .none
    @State private var showsEffects = false
    @State private var flashOn = false
    @State private var timerSeconds = 0
    @State private var countdown: Int?
    @State private var countdownTask: Task<Void, Never>?
    @State private var screenFlash = false
    @State private var holdTask: Task<Void, Never>?
    @State private var pressing = false
    @State private var holdRecording = false
    @State private var zoomBase: CGFloat = 1
    @State private var pinchBase: CGFloat?
    @State private var backdropItems: [PhotosPickerItem] = []
    // In-app PhotoKit library (replaces the system picker)
    @StateObject private var library = ModulaPhotoLibraryModel(includeVideos: true)
    @State private var showsLibrary = false
    @State private var librarySelection: [String] = []
    @State private var loadingLibrary = false
    // Multi-clip video
    @State private var clips: [StoryClip] = []
    @State private var speed: StoryClipSpeed = .normal
    @State private var merging = false
    // AR world stickers
    @StateObject private var ar = StoryARController()
    @State private var arSticker = "✨"
    private static let arStickers = ["✨", "💜", "🔥", "🎉", "🌟", "🦋", "🍕", "👑", "🫧", "😍"]
    private var clipsTotal: Double { clips.reduce(0) { $0 + $1.seconds / $1.speed } }

    private var modes: [StoryCaptureMode] {
        (allowedModes ?? StoryCaptureMode.allCases).filter { item in
            if item == .video, !canVideo { return false }
            if item == .ar, !StoryARController.isSupported { return false }
            return true
        }
    }
    private var accent: Color { app.appearance.accent.color }
    private var recordLimit: Double {
        switch mode {
        case .boomerang: 1.5
        case .video: max(60 - clips.reduce(0) { $0 + $1.seconds }, 1)
        default: 60
        }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if mode == .ar {
                StoryARView(controller: ar)
                    .ignoresSafeArea()
            } else {
                preview
                    .ignoresSafeArea()
                    .gesture(pinchGesture)
                    .gesture(swipeFilterGesture)
            }
            if merging {
                ProgressView("Joining clips…").tint(.white).foregroundStyle(.white)
                    .padding(18).modulaGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            if screenFlash { Color.white.ignoresSafeArea().transition(.opacity) }
            if let countdown {
                Text("\(countdown)")
                    .font(.system(size: 110, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.45), radius: 14)
                    .contentTransition(.numericText(countsDown: true))
                    .accessibilityLabel("Capturing in \(countdown)")
            }
            chrome
        }
        .onAppear {
            engine.start()
            engine.set(filter: filterID ?? "none")
        }
        .onDisappear { countdownTask?.cancel(); holdTask?.cancel(); engine.stop() }
        .onChange(of: filterID) { _, id in
            engine.set(filter: id ?? "none")
            HapticEngine.shared.play(.selection)
        }
        .onChange(of: effect) { _, value in engine.set(effect: value) }
        .onChange(of: engine.finishedVideo) { _, url in
            guard let url else { return }
            engine.finishedVideo = nil
            if mode == .video {
                withAnimation(.snappy) { clips.append(StoryClip(url: url, seconds: max(engine.recordedSeconds, 0.2), speed: speed.rawValue)) }
                HapticEngine.shared.play(.selection)
            } else if mode == .boomerang {
                Task {
                    let looped = (try? await StoryBoomerang.make(from: url)) ?? url
                    onVideo(looped)
                }
            } else {
                onVideo(url)
            }
        }
        .onChange(of: mode) { old, new in
            if new == .ar { engine.stop() } else if old == .ar { engine.start() }
        }
        .onChange(of: backdropItems) { _, items in
            guard let item = items.first else { return }
            backdropItems = []
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    let ratio = min(1, 1920 / max(image.size.width, image.size.height))
                    let up = await image.byPreparingThumbnail(ofSize: CGSize(width: image.size.width * ratio, height: image.size.height * ratio)) ?? image
                    engine.set(backdrop: up)
                }
            }
        }
        .sheet(isPresented: $showsLibrary) {
            NavigationStack {
                ModulaPhotoGrid(
                    model: library,
                    selection: $librarySelection,
                    maxSelection: 1,
                    accent: accent,
                    showsCameraTile: false,
                    allowsVideo: canVideo,
                    onVideoBlocked: { app.navigation.flash("Video stories are coming soon — pick a photo", symbol: "video.slash") },
                    onAdd: { pickLibrary() }
                )
                .padding(.horizontal, 2)
                .navigationTitle("Library")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { showsLibrary = false } } }
                .overlay { if loadingLibrary { ProgressView() } }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: showsEffects)
        .animation(.snappy(duration: 0.2), value: engine.isRecording)
        .accessibilityIdentifier("story.camera")
    }

    // MARK: Preview

    @ViewBuilder
    private var preview: some View {
        if engine.denied {
            notice("Camera access is off", symbol: "camera.fill", settings: true)
        } else if let message = engine.unavailable {
            notice(message, symbol: "camera", settings: false)
        } else if let frame = engine.frame {
            GeometryReader { geo in
                ZStack {
                    Image(decorative: frame, scale: 1)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                    if effect.needsFaces {
                        StoryFaceDecorations(faces: engine.faces, effect: effect, frameSize: CGSize(width: frame.width, height: frame.height))
                    }
                }
            }
        } else {
            ProgressView().tint(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func notice(_ title: String, symbol: String, settings: Bool) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.title)
            Text(title).font(.subheadline).multilineTextAlignment(.center)
            if settings {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .font(.subheadline.weight(.semibold))
            }
        }
        .foregroundStyle(.white.opacity(0.8))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Chrome

    private var chrome: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.horizontal, 14)
                .padding(.top, 6)
                .padding(.bottom, 24)
                .background(alignment: .top) { scrim(top: true) }
            if mode == .video, !clips.isEmpty || engine.isRecording {
                segmentBar.padding(.horizontal, 14).padding(.bottom, 8)
            }
            HStack(alignment: .top) {
                leftRail
                Spacer()
            }
            .padding(.leading, 12)
            .padding(.top, 4)
            Spacer(minLength: 0)
            if showsEffects, mode != .ar { effectsTray.transition(.move(edge: .bottom).combined(with: .opacity)) }
            if mode == .video { speedRow.padding(.bottom, 6) }
            if mode == .ar { arStickerRow.padding(.bottom, 6) }
            bottomControls
                .padding(.top, 28)
                .background(alignment: .bottom) { scrim(top: false) }
        }
    }

    private func scrim(top: Bool) -> some View {
        LinearGradient(
            colors: top ? [.black.opacity(0.5), .clear] : [.clear, .black.opacity(0.55)],
            startPoint: .top, endPoint: .bottom
        )
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            circle("xmark", label: "Close", id: "story.camera.close", action: onClose)
            Spacer()
            if engine.isRecording {
                Label(Duration.seconds(engine.recordedSeconds).formatted(.time(pattern: .minuteSecond)), systemImage: "record.circle")
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).frame(height: 30)
                    .background(.red, in: Capsule())
            } else if engine.zoom > 1.05 {
                Text(String(format: "%.1f×", engine.zoom))
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).frame(height: 30)
                    .modulaGlass(in: Capsule())
            }
            Spacer()
            ModulaGlassGroup(spacing: 8) {
                HStack(spacing: 8) {
                    circle(flashOn ? "bolt.fill" : "bolt.slash.fill", label: flashOn ? "Flash on" : "Flash off", id: "story.camera.flash") {
                        flashOn.toggle()
                        HapticEngine.shared.play(.selection)
                    }
                    circle(timerSeconds == 0 ? "timer" : "\(timerSeconds).circle", label: timerSeconds == 0 ? "Timer off" : "Timer \(timerSeconds) seconds", id: "story.camera.timer") {
                        timerSeconds = timerSeconds == 0 ? 3 : (timerSeconds == 3 ? 10 : 0)
                        HapticEngine.shared.play(.selection)
                    }
                    .disabled(engine.isRecording || countdown != nil)
                    circle("arrow.triangle.2.circlepath.camera", label: "Flip camera", id: "story.camera.flip") {
                        engine.flip()
                        HapticEngine.shared.play(.selection)
                    }
                    .disabled(engine.isRecording)
                }
            }
        }
    }

    /// Recorded segments as proportional capsules (60 s budget), plus the live one.
    private var segmentBar: some View {
        GeometryReader { geo in
            let w = geo.size.width
            HStack(spacing: 3) {
                ForEach(clips) { clip in
                    Capsule().fill(accent)
                        .frame(width: max(w * clip.seconds / 60 - 3, 4))
                        .overlay {
                            if clip.speed != 1 {
                                Text(StoryClipSpeed(rawValue: clip.speed)?.title ?? "")
                                    .font(.system(size: 7, weight: .heavy)).foregroundStyle(.white)
                            }
                        }
                }
                if engine.isRecording {
                    Capsule().fill(.red).frame(width: max(w * engine.recordedSeconds / 60, 4))
                }
                Spacer(minLength: 0)
            }
            .frame(height: 8)
            .background(Capsule().fill(.white.opacity(0.25)))
        }
        .frame(height: 8)
        .accessibilityElement()
        .accessibilityLabel("\(clips.count) clips recorded")
    }

    private func undoClip() {
        guard let last = clips.last else { return }
        withAnimation(.snappy) { _ = clips.removeLast() }
        try? FileManager.default.removeItem(at: last.url)
        HapticEngine.shared.play(.selection)
    }

    private func finishClips() {
        guard !clips.isEmpty, !merging else { return }
        merging = true
        let current = clips
        Task {
            defer { merging = false }
            do {
                let url = try await StoryClipMerger.merge(current)
                clips = []
                onVideo(url)
            } catch {
                app.navigation.flash("Couldn’t join those clips", symbol: "exclamationmark.triangle")
                HapticEngine.shared.play(.failure)
            }
        }
    }

    private var speedRow: some View {
        HStack(spacing: 4) {
            ForEach(StoryClipSpeed.allCases) { item in
                Button {
                    speed = item
                    HapticEngine.shared.play(.selection)
                } label: {
                    Text(item.title)
                        .font(.footnote.weight(.bold).monospacedDigit())
                        .foregroundStyle(speed == item ? Color.black : Color.white)
                        .padding(.horizontal, 10).frame(height: 30)
                        .background { if speed == item { Capsule().fill(.white) } }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Speed \(item.title)\(item.rawValue < 1 ? ", slow motion" : "")")
                .accessibilityAddTraits(speed == item ? .isSelected : [])
            }
        }
        .padding(3)
        .modulaGlass(in: Capsule())
        .disabled(engine.isRecording)
    }

    private var arStickerRow: some View {
        // One sticker tray: hint + emoji row + Clear in a single glass panel above the mode bar.
        VStack(alignment: .leading, spacing: 8) {
            Text(ar.placed == 0 ? "Tap a surface to place a sticker" : "Move around — stickers stay put")
                .font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 14)
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Self.arStickers, id: \.self) { emoji in
                        Button {
                            arSticker = emoji
                            ar.sticker = emoji
                            HapticEngine.shared.play(.selection)
                        } label: {
                            Text(emoji).font(.system(size: 26))
                                .frame(width: 46, height: 46)
                                .modulaGlass(in: Circle())
                                .overlay(Circle().strokeBorder(arSticker == emoji ? Color.white : .clear, lineWidth: 2.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
            }
            if ar.placed > 0 {
                Button("Clear") { ar.clear(); HapticEngine.shared.play(.selection) }
                    .font(.footnote.weight(.semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 12).frame(height: 34)
                    .modulaGlass(in: Capsule(), interactive: true)
                    .padding(.trailing, 14)
            }
        }
        }
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .modulaGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous), interactive: false)
        .padding(.horizontal, 10)
    }

    private var leftRail: some View {
        VStack(alignment: .leading, spacing: 12) {
            if allowedModes?.contains(.text) ?? true { railItem("textformat", "Create") { onText() } }
            railItem("face.smiling", "Effects", active: showsEffects || effect != .none) { showsEffects.toggle() }
            if allowedModes?.contains(.layout) ?? true { railItem("rectangle.split.2x2", "Layout") { onLayout() } }
            railItem("plus.magnifyingglass", "Zoom 2×", active: engine.zoom > 1.5) {
                engine.setZoom(engine.zoom > 1.5 ? 1 : 2)
            }
        }
    }

    private func railItem(_ symbol: String, _ title: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button {
            action()
            HapticEngine.shared.play(.selection)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(active ? Color.black : Color.white)
                    .frame(width: 40, height: 40)
                    .background { if active { Circle().fill(.white) } }
                    .modulaGlass(in: Circle())
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 3, y: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(ModulaPressStyle(scale: 0.94, haptic: nil))
        .accessibilityLabel(title)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private func circle(_ symbol: String, label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 42, height: 42)
                .modulaGlass(in: Circle(), interactive: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    private var effectsTray: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(StoryCameraEffect.allCases) { item in
                        Button {
                            effect = item
                            HapticEngine.shared.play(.selection)
                        } label: {
                            VStack(spacing: 4) {
                                Text(item.glyph)
                                    .font(.system(size: 26))
                                    .frame(width: 54, height: 54)
                                    .modulaGlass(in: Circle())
                                    .overlay(Circle().strokeBorder(effect == item ? Color.white : .clear, lineWidth: 2.5))
                                Text(item.title)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .shadow(color: .black.opacity(0.6), radius: 2)
                            }
                        }
                        .buttonStyle(ModulaPressStyle(scale: 0.92, haptic: nil))
                        .accessibilityLabel("\(item.title) effect")
                        .accessibilityAddTraits(effect == item ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 16)
            }
            if effect == .greenScreen {
                PhotosPicker(selection: $backdropItems, maxSelectionCount: 1, matching: .images) {
                    Label("Choose backdrop", systemImage: "photo")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14).frame(height: 34)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, 6)
    }

    private var bottomControls: some View {
        VStack(spacing: 14) {
            ZStack {
                if mode == .photo || mode == .handsFree || mode == .boomerang || (mode == .video && clips.isEmpty && !engine.isRecording) {
                    filterCarousel
                }
                shutter
            }
            .frame(height: 96)

            HStack(alignment: .center) {
                if mode == .video, !clips.isEmpty {
                    Button { undoClip() } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .modulaGlass(in: Circle(), interactive: true)
                    }
                    .buttonStyle(.plain)
                    .disabled(engine.isRecording || merging)
                    .accessibilityLabel("Undo last clip")
                } else {
                Button {
                    showsLibrary = true
                    HapticEngine.shared.play(.selection)
                } label: {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .modulaGlass(in: RoundedRectangle(cornerRadius: 12, style: .continuous), interactive: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Photo library")
                .accessibilityIdentifier("story.create.library")
                }
                modePicker
                if mode == .video, !clips.isEmpty {
                    Button { finishClips() } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .modulaGlass(in: Circle(), interactive: true, tint: accent, prominent: true)
                    }
                    .buttonStyle(.plain)
                    .disabled(engine.isRecording || merging)
                    .accessibilityLabel("Done, use \(clips.count) clips")
                } else {
                    Color.clear.frame(width: 44, height: 44)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
        }
    }

    private var modePicker: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(modes) { item in
                        Button {
                            select(item)
                            withAnimation(.snappy) { proxy.scrollTo(item.id, anchor: .center) }
                        } label: {
                            Text(item.rawValue)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(mode == item ? Color.black : Color.white)
                                .padding(.horizontal, 12).frame(height: 32)
                                .background { if mode == item { Capsule().fill(.white) } }
                                .shadow(color: mode == item ? .clear : .black.opacity(0.5), radius: 2)
                        }
                        .buttonStyle(.plain)
                        .id(item.id)
                        .accessibilityAddTraits(mode == item ? .isSelected : [])
                        .accessibilityIdentifier("story.camera.mode.\(item.rawValue)")
                    }
                }
                .padding(.horizontal, 8)
            }
            .onAppear { proxy.scrollTo(mode.id, anchor: .center) }
        }
        .frame(maxWidth: .infinity)
        .disabled(engine.isRecording || countdown != nil || !clips.isEmpty)
    }

    private func pickLibrary() {
        guard let id = librarySelection.first,
              let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else { return }
        loadingLibrary = true
        Task {
            defer { loadingLibrary = false; librarySelection = [] }
            if asset.mediaType == .video {
                if let url = await library.videoFile(asset) { showsLibrary = false; onVideo(url) }
            } else if let image = await library.fullImage(asset) {
                showsLibrary = false
                onPhoto(image)
            }
        }
    }

    private func select(_ item: StoryCaptureMode) {
        HapticEngine.shared.play(.selection)
        switch item {
        case .text: onText()
        case .layout: onLayout()
        default: withAnimation(.snappy(duration: 0.2)) { mode = item }
        }
    }

    /// Instagram-style: filters scroll *through* the shutter ring; the centred one is live.
    private var filterCarousel: some View {
        GeometryReader { geo in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(StoryFilter.catalog) { item in
                        Circle()
                            .fill(filterTint(item.id))
                            .overlay(Image(systemName: item.systemImage).font(.system(size: 18, weight: .semibold)).foregroundStyle(.white))
                            .frame(width: 58, height: 58)
                            .overlay(Circle().strokeBorder(.white.opacity(0.5), lineWidth: 1))
                            .id(Optional(item.id))
                            .onTapGesture { withAnimation(.snappy) { filterID = item.id } }
                            .accessibilityLabel("\(item.title) filter")
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, max((geo.size.width - 58) / 2, 0), for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $filterID, anchor: .center)
            .frame(height: 96)
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.2), .init(color: .black, location: 0.8), .init(color: .clear, location: 1)], startPoint: .leading, endPoint: .trailing))
        }
        .overlay(alignment: .top) {
            if let id = filterID, id != "none", let f = StoryFilter.catalog.first(where: { $0.id == id }) {
                Text(f.title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 2)
                    .offset(y: -20)
            }
        }
    }

    private func filterTint(_ id: String) -> some ShapeStyle {
        let hue = Double(abs(id.hashValue % 360)) / 360
        return id == "none" ? AnyShapeStyle(Color.white.opacity(0.18)) : AnyShapeStyle(Color(hue: hue, saturation: 0.55, brightness: 0.7).opacity(0.8))
    }

    private var shutter: some View {
        let recording = engine.isRecording
        return ZStack {
            Circle().strokeBorder(.white, lineWidth: 5).frame(width: 84, height: 84)
            if mode == .photo && !recording {
                Circle().fill(.white.opacity(pressing ? 0.6 : 0.25)).frame(width: 68, height: 68)
            } else {
                RoundedRectangle(cornerRadius: recording ? 8 : 34, style: .continuous)
                    .fill(.red)
                    .frame(width: recording ? 32 : 68, height: recording ? 32 : 68)
            }
            if recording {
                Circle().trim(from: 0, to: min(engine.recordedSeconds / recordLimit, 1))
                    .stroke(.red, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 84, height: 84)
            }
        }
        .scaleEffect(pressing && !reduceMotion ? 1.12 : 1)
        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: pressing)
        .contentShape(Circle())
        .gesture(shutterGesture)
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(mode == .photo ? "Take photo, hold to record" : (recording ? "Stop recording" : "Record \(mode.rawValue)"))
        .accessibilityAction { tapShutter() }
        .accessibilityIdentifier("story.camera.shutter")
        .disabled(mode != .ar && !engine.isReady)
    }

    private var shutterGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !pressing {
                    pressing = true
                    zoomBase = engine.zoom
                    if canVideo, mode == .photo || mode == .video, !engine.isRecording, countdown == nil {
                        holdTask = Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(280))
                            guard !Task.isCancelled, pressing, !engine.isRecording else { return }
                            holdRecording = true
                            engine.startRecording(maxSeconds: 60, torch: flashOn)
                            HapticEngine.shared.play(.lightImpact)
                        }
                    }
                }
                // Slide up on the shutter to zoom (TikTok / Instagram).
                if abs(value.translation.height) > 12 {
                    engine.setZoom(zoomBase * exp(-value.translation.height / 160))
                }
            }
            .onEnded { value in
                pressing = false
                holdTask?.cancel()
                if holdRecording {
                    holdRecording = false
                    engine.stopRecording()
                    return
                }
                if abs(value.translation.height) < 12 { tapShutter() }
            }
    }

    private func tapShutter() {
        if countdown != nil {
            countdownTask?.cancel()
            withAnimation(.snappy(duration: 0.2)) { countdown = nil }
            return
        }
        if engine.isRecording {
            engine.stopRecording()
            HapticEngine.shared.play(.lightImpact)
            return
        }
        let delay = mode == .handsFree ? max(timerSeconds, 3) : timerSeconds
        if delay > 0 { startCountdown(delay) } else { fire() }
    }

    private func fire() {
        switch mode {
        case .photo:
            capturePhoto()
        case .ar:
            if let image = ar.snapshot() {
                HapticEngine.shared.play(.actionConfirmed)
                onPhoto(image)
            }
        case .video, .handsFree, .boomerang:
            guard canVideo else {
                app.navigation.flash("Video stories are coming soon", symbol: "video.slash")
                return
            }
            engine.startRecording(maxSeconds: recordLimit, torch: flashOn)
            HapticEngine.shared.play(.lightImpact)
        default:
            break
        }
    }

    private func capturePhoto() {
        let front = engine.position == .front
        if flashOn {
            if front {
                withAnimation(.easeOut(duration: 0.06)) { screenFlash = true }
            } else {
                engine.setTorch(true)
            }
        }
        let wait = flashOn ? 0.28 : 0
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) {
            defer {
                if flashOn { engine.setTorch(false) }
                withAnimation(.easeIn(duration: 0.25)) { screenFlash = false }
            }
            guard let frame = engine.frame else { return }
            let renderer = ImageRenderer(content: StoryCameraStill(frame: frame, faces: engine.faces, effect: effect))
            renderer.scale = 1
            renderer.isOpaque = true
            let image = renderer.uiImage ?? UIImage(cgImage: frame)
            HapticEngine.shared.play(.actionConfirmed)
            if !flashOn, !reduceMotion {
                withAnimation(.easeOut(duration: 0.06)) { screenFlash = true }
            }
            onPhoto(image)
        }
    }

    private func startCountdown(_ seconds: Int) {
        countdownTask?.cancel()
        withAnimation(.snappy(duration: 0.2)) { countdown = seconds }
        countdownTask = Task { @MainActor in
            var left = seconds
            while left > 0 {
                HapticEngine.shared.play(.selection)
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                left -= 1
                withAnimation(.snappy(duration: 0.2)) { countdown = left > 0 ? left : nil }
            }
            fire()
        }
    }

    // MARK: Gestures

    private var pinchGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if pinchBase == nil { pinchBase = engine.zoom }
                engine.setZoom((pinchBase ?? 1) * value.magnification)
            }
            .onEnded { _ in pinchBase = nil }
    }

    /// Swipe across the preview to change filter, like Instagram.
    private var swipeFilterGesture: some Gesture {
        DragGesture(minimumDistance: 40)
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) * 1.5 else { return }
                let ids = StoryFilter.catalog.map(\.id)
                let i = ids.firstIndex(of: filterID ?? "none") ?? 0
                let next = value.translation.width < 0 ? min(i + 1, ids.count - 1) : max(i - 1, 0)
                withAnimation(.snappy) { filterID = ids[next] }
            }
    }
}

// MARK: - Subject lift ("sticker from photo") — Vision foreground instance mask

enum StorySubjectLifter {
    static func lift(_ image: UIImage) async -> UIImage? {
        let normalized: UIImage = {
            let maxSide: CGFloat = 1400
            let scale = min(1, maxSide / max(image.size.width, image.size.height))
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let format = UIGraphicsImageRendererFormat.default()
            format.scale = 1
            return UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        }()
        guard let cg = normalized.cgImage else { return nil }
        return await Task.detached(priority: .userInitiated) { () -> UIImage? in
            let request = VNGenerateForegroundInstanceMaskRequest()
            let handler = VNImageRequestHandler(cgImage: cg, orientation: .up)
            guard (try? handler.perform([request])) != nil, let result = request.results?.first,
                  let buffer = try? result.generateMaskedImage(ofInstances: result.allInstances, from: handler, croppedToInstancesExtent: true)
            else { return nil }
            let ci = CIImage(cvPixelBuffer: buffer)
            guard let out = CIContext().createCGImage(ci, from: ci.extent) else { return nil }
            return UIImage(cgImage: out)
        }.value
    }
}

/// Hex for a SwiftUI colour (used by the eyedropper colour picker).
func storyHexString(_ color: Color) -> String {
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
    func c(_ v: CGFloat) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
    return String(format: "#%02X%02X%02X", c(r), c(g), c(b))
}
