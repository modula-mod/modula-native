import AVFoundation
import PhotosUI
import Speech
import SwiftUI
import UIKit
import UniformTypeIdentifiers

#if DEBUG

struct NodusComposerAttachment: Identifiable, Equatable {
    let id = UUID()
    var title: String
    var image: UIImage?
    var note: String?

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
}

enum NodusComposerPlugin: String, CaseIterable, Identifiable {
    case knowledge
    case memory
    case camera
    case photos
    case files
    case projects
    case folders

    var id: String { rawValue }

    var title: String {
        switch self {
        case .knowledge: "Knowledge"
        case .memory: "Memory"
        case .camera: "Camera"
        case .photos: "Photos"
        case .files: "Files"
        case .projects: "Projects"
        case .folders: "Folders"
        }
    }

    var subtitle: String {
        switch self {
        case .knowledge: "Collections stored on this iPhone"
        case .memory: "Confirmed memory, with swipe to archive"
        case .camera: "A picture for this chat, kept on this iPhone"
        case .photos: "Attach a photo. Nodus reads your words, not the picture"
        case .files: "A local file. Text notes can be included with the question"
        case .projects: "A local brief, folders, and the chats inside them"
        case .folders: "Group chats on this iPhone"
        }
    }

    var group: String {
        switch self {
        case .knowledge, .memory, .projects, .folders: "Library"
        default: "Capture"
        }
    }

    var symbol: String {
        switch self {
        case .knowledge: "books.vertical"
        case .memory: "memorychip"
        case .camera: "camera"
        case .photos: "photo"
        case .files: "doc"
        case .projects: "square.stack.3d.up"
        case .folders: "folder"
        }
    }
}

struct NodusPluginSheet: View {
    var query: Binding<String>
    var memoryOn: Bool
    var onSelect: (NodusComposerPlugin) -> Void

    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss

    private var matches: [NodusComposerPlugin] {
        let clean = query.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return NodusComposerPlugin.allCases.filter {
            clean.isEmpty || $0.title.lowercased().contains(clean) || $0.subtitle.lowercased().contains(clean)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if query.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ForEach(["Library", "Capture"], id: \.self) { name in
                        Section(name) {
                            ForEach(NodusComposerPlugin.allCases.filter { $0.group == name }) { plugin in
                                pluginRow(plugin)
                            }
                        }
                    }
                } else if matches.isEmpty {
                    ContentUnavailableView.search(text: query.wrappedValue)
                } else {
                    Section("Results") {
                        ForEach(matches) { plugin in
                            pluginRow(plugin)
                        }
                    }
                }
            }
            .searchable(text: query, prompt: "Search what you can attach")
            .navigationTitle("Plugins")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { NodusStudioClose() }
            }
            .presentationDragIndicator(.visible)
        }
        .accessibilityIdentifier("nodus.chat.plugins")
    }

    private func pluginRow(_ plugin: NodusComposerPlugin) -> some View {
        Button {
            onSelect(plugin)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                NodusStudioGlyph(symbol: plugin.symbol)
                VStack(alignment: .leading, spacing: 2) {
                    Text(plugin.title)
                    Text(plugin.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isOn(plugin) {
                    Text("On")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(app.appearance.accent.color)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(app.appearance.accent.color.opacity(0.12), in: Capsule())
                }
            }
        }
        .accessibilityIdentifier("nodus.chat.plugin.\(plugin.rawValue)")
    }

    private func isOn(_ plugin: NodusComposerPlugin) -> Bool {
        plugin == .memory && memoryOn
    }
}

struct NodusThinkingRow: View {
    var text: String
    var stage: NodusReasoningStage?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 10) {
            NodusThinkingOrb(stage: stage, reduceMotion: reduceMotion)
            NodusThinkingCaption(text: text, reduceMotion: reduceMotion)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
        .accessibilityIdentifier("nodus.chat.generating")
    }
}

struct NodusThinkingOrb: View {
    var stage: NodusReasoningStage?
    var reduceMotion: Bool
    var size: CGFloat = 42

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 60 : 1.0 / 30.0, paused: reduceMotion)) { timeline in
            let time = reduceMotion ? 0.6 : timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, canvasSize in
                let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
                let radius = min(canvasSize.width, canvasSize.height) * 0.40 * breath(time)
                let count = 40
                for index in 0..<count {
                    let point = dot(index: index, count: count, time: time)
                    let depth = (point.z + 1) / 2
                    let dotSize = 1.15 + (depth * 1.7)
                    let origin = CGPoint(
                        x: center.x + CGFloat(point.x) * radius - dotSize / 2,
                        y: center.y + CGFloat(point.y) * radius - dotSize / 2
                    )
                    let rect = CGRect(x: origin.x, y: origin.y, width: dotSize, height: dotSize)
                    context.fill(
                        Path(ellipseIn: rect),
                        with: .color(Color.primary.opacity(0.18 + depth * 0.78 * highlight(point, time: time)))
                    )
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func breath(_ time: Double) -> CGFloat {
        switch motion {
        case .breathe: CGFloat(0.86 + (reduceMotion ? 0 : 0.14 * (sin(time * 1.6) + 1) / 2))
        default: 1
        }
    }

    private func highlight(_ point: SIMD3<Double>, time: Double) -> Double {
        switch motion {
        case .scan:
            let band = abs(point.x - sin(time * 1.7))
            return band < 0.18 ? 1 : 0.55
        case .weave:
            return 0.72 + 0.28 * sin(time * 2.2 + point.y * 4)
        default:
            return 1
        }
    }

    private var motion: Motion {
        switch stage {
        case .searchingKnowledge, .searchingWeb: .scan
        case .checkingMemory, .drafting: .weave
        case .finalizing: .breathe
        default: .orbit
        }
    }

    private enum Motion { case orbit, scan, weave, breathe }

    private func dot(index: Int, count: Int, time: Double) -> SIMD3<Double> {
        let seed = Double(index)
        let y = 1 - (seed / Double(count - 1)) * 2
        let ring = sqrt(max(0, 1 - y * y))
        let theta = seed * 2.399963
        let spun: Double
        switch motion {
        case .weave: spun = time * (index.isMultiple(of: 2) ? 0.85 : -0.55)
        case .breathe: spun = time * 0.35
        case .scan: spun = time * 0.45
        case .orbit: spun = time * 0.9
        }
        let point = SIMD3(ring * cos(theta), y, ring * sin(theta))
        let yaw = spun + (reduceMotion ? 0.4 : 0)
        let pitch = motion == .orbit ? 0.55 : 0.25
        let cy = cos(yaw), sy = sin(yaw)
        let x1 = point.x * cy - point.z * sy
        let z1 = point.x * sy + point.z * cy
        let cp = cos(pitch), sp = sin(pitch)
        return SIMD3(x1, point.y * cp - z1 * sp, point.y * sp + z1 * cp)
    }
}

private struct NodusThinkingCaption: View {
    var text: String
    var reduceMotion: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 60 : 1.0 / 24.0, paused: reduceMotion)) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
            Text(text)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .overlay {
                    if !reduceMotion {
                        GeometryReader { proxy in
                            LinearGradient(
                                colors: [.clear, .white.opacity(0.85), .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(width: proxy.size.width * 0.45)
                            .offset(x: -proxy.size.width * 0.3 + (proxy.size.width * 1.3 * phase))
                            .blendMode(.sourceAtop)
                        }
                    }
                }
                .mask { Text(text).font(.footnote.weight(.medium)) }
        }
    }
}

struct NodusMessageReactions: View {
    var symbols: [String]
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        HStack(spacing: 6) {
            ForEach(symbols, id: \.self) { symbol in
                Image(systemName: symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(app.appearance.accent.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(app.appearance.accent.color.opacity(0.12), in: Capsule())
                    .transition(.scale(scale: 0.7).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.32, bounce: 0.35), value: symbols)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Reactions")
    }
}

enum NodusReaction: String, CaseIterable {
    case heart = "heart.fill"
    case up = "hand.thumbsup.fill"
    case down = "hand.thumbsdown.fill"
    case star = "star.fill"
    case idea = "lightbulb.fill"

    var title: String {
        switch self {
        case .heart: "Love"
        case .up: "Useful"
        case .down: "Not useful"
        case .star: "Star"
        case .idea: "Insight"
        }
    }
}

struct NodusInlineCamera: View {
    var onCapture: (UIImage) -> Void
    var onClose: () -> Void
    @StateObject private var camera = NodusCameraSession()
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        ZStack {
            preview
            VStack {
                HStack {
                    cameraButton("xmark", label: "Close camera", id: "nodus.chat.camera.close", action: onClose)
                    Spacer()
                    cameraButton("arrow.triangle.2.circlepath.camera", label: "Flip camera", id: "nodus.chat.camera.flip") {
                        camera.flip()
                    }
                }
                Spacer()
                Button {
                    camera.capture(onCapture)
                } label: {
                    Circle()
                        .fill(.white)
                        .frame(width: 62, height: 62)
                        .overlay { Circle().stroke(app.appearance.accent.color, lineWidth: 3).padding(4) }
                }
                .buttonStyle(.plain)
                .disabled(!camera.isReady)
                .accessibilityLabel("Take photo")
                .accessibilityIdentifier("nodus.chat.camera.shutter")
                .padding(.bottom, 12)
            }
            .padding(10)
        }
        .frame(height: 228)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityIdentifier("nodus.chat.camera")
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
    }

    @ViewBuilder
    private var preview: some View {
        if camera.denied {
            cameraNotice("Camera access is off", symbol: "camera.fill")
        } else if let message = camera.unavailable {
            cameraNotice(message, symbol: "camera")
        } else {
            NodusCameraPreview(session: camera.session)
                .overlay(Color.black.opacity(0.05))
        }
    }

    private func cameraNotice(_ title: String, symbol: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.title2)
            Text(title).font(.footnote).multilineTextAlignment(.center)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .secondarySystemBackground))
    }

    private func cameraButton(_ symbol: String, label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .frame(width: 36, height: 36)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }
}

private struct NodusCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> NodusPreviewView {
        let view = NodusPreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: NodusPreviewView, context: Context) {
        uiView.previewLayer.session = session
    }
}

private final class NodusPreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

private final class NodusCameraSession: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    @Published var denied = false
    @Published var unavailable: String?
    @Published var isReady = false
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "nodus.inline.camera")
    private var position: AVCaptureDevice.Position = .back
    private var onCapture: ((UIImage) -> Void)?
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
        queue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
        isReady = false
    }

    func flip() {
        position = position == .back ? .front : .back
        configureAndRun()
    }

    func capture(_ handler: @escaping (UIImage) -> Void) {
        guard isReady else { return }
        onCapture = handler
        let settings = AVCapturePhotoSettings()
        queue.async { [output] in
            output.capturePhoto(with: settings, delegate: self)
        }
    }

    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else { return }
        DispatchQueue.main.async {
            self.onCapture?(image)
            self.onCapture = nil
        }
    }

    private func configureAndRun() {
        queue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .photo
            self.session.inputs.forEach { self.session.removeInput($0) }
            let position = self.position
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
                  let input = try? AVCaptureDeviceInput(device: device),
                  self.session.canAddInput(input) else {
                self.session.commitConfiguration()
                DispatchQueue.main.async {
                    self.unavailable = "Camera isn't available here"
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
            DispatchQueue.main.async {
                self.unavailable = nil
                self.isReady = true
            }
        }
    }
}

@MainActor
final class NodusDictation: ObservableObject {
    @Published var isListening = false
    @Published var status: String?
    private let recognizer = SFSpeechRecognizer()
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func toggle(current: @escaping () -> String, apply: @escaping (String) -> Void) {
        if isListening {
            stop()
            return
        }
        SFSpeechRecognizer.requestAuthorization { auth in
            DispatchQueue.main.async {
                guard auth == .authorized else {
                    self.status = "Dictation stays off until Speech Recognition is allowed"
                    return
                }
                self.start(current: current, apply: apply)
            }
        }
    }

    func stop() {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        isListening = false
        if status == "Listening on this iPhone" { status = nil }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func start(current: @escaping () -> String, apply: @escaping (String) -> Void) {
        guard let recognizer, recognizer.isAvailable else {
            status = "Dictation isn't available right now"
            return
        }
        guard recognizer.supportsOnDeviceRecognition else {
            status = "On-device dictation isn't available on this iPhone"
            return
        }
        stop()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        self.request = request
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }
            engine.prepare()
            try engine.start()
        } catch {
            status = "The microphone couldn't start"
            return
        }
        let starting = current()
        isListening = true
        status = "Listening on this iPhone"
        task = recognizer.recognitionTask(with: request) { result, error in
            let spoken = result?.bestTranscription.formattedString
            let finished = error != nil || result?.isFinal == true
            DispatchQueue.main.async {
                if let spoken {
                    apply(starting.isEmpty ? spoken : starting + " " + spoken)
                }
                if finished { self.stop() }
            }
        }
    }
}

struct NodusPhotoThumb: View {
    var image: UIImage
    var title: String
    var open: Bool
    var namespace: Namespace.ID
    var geometryID: String
    var onOpen: () -> Void
    var onRemove: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drag: CGFloat = 0

    var body: some View {
        Button(action: onOpen) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 86, height: 108)
                .clipShape(RoundedRectangle(cornerRadius: open ? 22 : 16, style: .continuous))
                .overlay(alignment: .bottomLeading) {
                    Text(title)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(6)
                }
                .matchedGeometryEffect(id: geometryID, in: namespace, isSource: !open)
        }
        .buttonStyle(.plain)
        .opacity(open ? 0 : 1)
        .offset(x: drag)
        .gesture(
            DragGesture(minimumDistance: 12)
                .onChanged { value in
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    drag = value.translation.width
                }
                .onEnded { value in
                    if value.translation.width < -70 {
                        withAnimation(.spring(duration: 0.32, bounce: reduceMotion ? 0 : 0.2)) { onRemove() }
                    } else {
                        withAnimation(.spring(duration: 0.35, bounce: reduceMotion ? 0 : 0.25)) { drag = 0 }
                    }
                }
        )
        .accessibilityLabel("Photo preview, \(title)")
        .accessibilityHint("Opens a larger preview. Swipe left to remove.")
        .accessibilityIdentifier("nodus.chat.photo.thumb")
    }
}

struct NodusPhotoStage: View {
    var image: UIImage
    var title: String
    var namespace: Namespace.ID
    var geometryID: String
    var onClose: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var zoom: CGFloat = 1
    @State private var drag: CGSize = .zero

    var body: some View {
        VStack(spacing: 8) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 240)
                .scaleEffect(zoom)
                .offset(drag)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .matchedGeometryEffect(id: geometryID, in: namespace)
                .gesture(magnify)
                .simultaneousGesture(dismissDrag)
                .onTapGesture(count: 2) {
                    withAnimation(.spring(duration: 0.35, bounce: reduceMotion ? 0 : 0.2)) {
                        zoom = zoom > 1.05 ? 1 : 2
                    }
                }
                .accessibilityLabel("Expanded photo, \(title)")
                .accessibilityHint("Pinch or double-tap to zoom. Drag down to close.")
            HStack {
                Text("Kept on this iPhone")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .frame(width: 28, height: 28)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close preview")
            }
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .accessibilityIdentifier("nodus.chat.photo.stage")
    }

    private var magnify: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                zoom = min(max(value.magnification, 1), 3)
            }
            .onEnded { _ in
                withAnimation(.spring(duration: 0.35, bounce: reduceMotion ? 0 : 0.18)) { zoom = 1 }
            }
    }

    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: 16)
            .onChanged { value in
                guard value.translation.height > 0, abs(value.translation.height) > abs(value.translation.width) else { return }
                drag = value.translation
            }
            .onEnded { value in
                if value.translation.height > 90 {
                    onClose()
                } else {
                    withAnimation(.spring(duration: 0.35, bounce: reduceMotion ? 0 : 0.22)) { drag = .zero }
                }
            }
    }
}

struct NodusMessageSwipe<Content: View>: View {
    var onReply: () -> Void
    var onFork: () -> Void
    var onLove: () -> Void
    @ViewBuilder var content: () -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var offset: CGFloat = 0
    @State private var burst = false

    var body: some View {
        ZStack {
            HStack {
                Image(systemName: "arrowshape.turn.up.left.fill")
                    .foregroundStyle(.tint)
                    .opacity(min(max(offset / 70, 0), 1))
                Spacer()
                Image(systemName: "arrow.triangle.branch")
                    .foregroundStyle(.tint)
                    .opacity(min(max(-offset / 70, 0), 1))
            }
            .padding(.horizontal, 8)
            content()
                .offset(x: offset)
                .overlay {
                    if burst {
                        Image(systemName: "heart.fill")
                            .font(.title2)
                            .foregroundStyle(.pink)
                            .transition(.scale(scale: 0.4).combined(with: .opacity))
                    }
                }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(swipe)
        .onTapGesture(count: 2) {
            onLove()
            guard !reduceMotion else { return }
            withAnimation(.spring(duration: 0.28, bounce: 0.45)) { burst = true }
            Task {
                try? await Task.sleep(for: .milliseconds(450))
                withAnimation(.easeOut(duration: 0.2)) { burst = false }
            }
        }
        .accessibilityHint("Swipe right to reply, swipe left to fork, double-tap to love.")
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 28)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                offset = min(max(value.translation.width, -110), 110)
            }
            .onEnded { value in
                let width = value.translation.width
                if width > 72 { onReply() }
                else if width < -72 { onFork() }
                withAnimation(.spring(duration: 0.34, bounce: reduceMotion ? 0 : 0.28)) { offset = 0 }
            }
    }
}

struct NodusStudioGlyph: View {
    var symbol: String
    var size: CGFloat = 36
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        Image(systemName: symbol)
            .font(.body.weight(.semibold))
            .foregroundStyle(app.appearance.accent.color)
            .frame(width: size, height: size)
            .background(app.appearance.accent.color.opacity(0.14), in: Circle())
    }
}

struct NodusStudioClose: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark")
                .font(.body.weight(.semibold))
        }
        .accessibilityLabel("Close")
    }
}

struct NodusThinkBudgetPopover: View {
    var step: NodusThinkStep
    var onChange: (Int) -> Void
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                NodusStudioGlyph(symbol: "brain", size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(step.title).font(.headline)
                    Text("Reply budget").font(.caption).foregroundStyle(.secondary)
                }
            }
            Text(step.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Slider(
                value: Binding(
                    get: { Double(step.rawValue) },
                    set: { onChange(Int($0.rounded())) }
                ),
                in: 1...5,
                step: 1
            )
            .tint(app.appearance.accent.color)
            .accessibilityLabel("Reply budget")
            .accessibilityValue(step.detail)
            HStack {
                ForEach(NodusThinkStep.allCases, id: \.rawValue) { item in
                    Text(item.title)
                        .font(.caption2.weight(item == step ? .bold : .regular))
                        .foregroundStyle(item == step ? Color.primary : Color.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(16)
        .frame(width: 300)
        .accessibilityIdentifier("nodus.chat.think.slider")
    }
}

struct NodusModelSheet: View {
    var identity: NodusModelIdentity?
    var availability: IntelligenceAvailability
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        NavigationStack {
            List {
                if let identity {
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 12) {
                                NodusStudioGlyph(symbol: "brain", size: 52)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(identity.displayName).font(.title3.weight(.semibold))
                                    Text(identity.stage.displayName)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.orange)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(.orange.opacity(0.12), in: Capsule())
                                }
                            }
                            Text(availability.displayName)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                    }
                    Section("Bundle") {
                        LabeledContent("Base", value: identity.baseModel)
                        LabeledContent("Revision", value: identity.baseRevision)
                        LabeledContent("Quantization", value: identity.quantization)
                        LabeledContent("Runtime", value: identity.runtimeFormat)
                        LabeledContent("Provider", value: NodusIntelligenceProvider.providerID)
                    }
                    Section {
                        Label("Runs on this iPhone", systemImage: "iphone")
                            .foregroundStyle(app.appearance.accent.color)
                        Text("Nodus uses this bundle only. If it is missing, the chat does not switch to another model.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ContentUnavailableView(
                        "Nodus model not installed",
                        systemImage: "brain.head.profile",
                        description: Text("A verified experimental bundle was not found. Chats, Knowledge, and Memory remain on this iPhone.")
                    )
                }
            }
            .navigationTitle("Models")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { NodusStudioClose() } }
            .presentationDragIndicator(.visible)
            .accessibilityIdentifier("nodus.chat.models")
        }
    }
}

struct NodusSystemInfoSheet: View {
    var chats: Int
    var projects: Int
    var folders: Int
    var prompts: Int
    var personas: Int
    var skills: Int

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LazyVGrid(columns: columns, spacing: 10) {
                        stat("Chats", chats, "bubble.left.and.bubble.right")
                        stat("Projects", projects, "square.stack.3d.up")
                        stat("Folders", folders, "folder")
                        stat("Prompts", prompts, "text.quote")
                        stat("Personas", personas, "person")
                        stat("Skills", skills, "wand.and.stars")
                    }
                    .padding(.vertical, 4)
                }
                Section("This iPhone") {
                    LabeledContent("System", value: UIDevice.current.systemName + " " + UIDevice.current.systemVersion)
                    LabeledContent("Device", value: UIDevice.current.model)
                }
                Section {
                    Text("Counts of what is stored on this iPhone. The model itself is under Models.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("System Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { NodusStudioClose() } }
            .presentationDragIndicator(.visible)
            .accessibilityIdentifier("nodus.chat.system-info")
        }
    }

    private func stat(_ title: String, _ value: Int, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol).foregroundStyle(.tint)
            Text("\(value)").font(.title2.weight(.semibold))
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(TintShapeStyle().opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct NodusConnectorsSheet: View {
    @Environment(AppEnvironment.self) private var app
    @Bindable var model: NodusChatViewModel
    var draftCount: Int
    var onLibrary: () -> Void
    var onKnowledge: () -> Void
    var onMemory: () -> Void
    @State private var collectionNames: [String] = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    statusRow("Project", symbol: "square.stack.3d.up", value: projectName, action: onLibrary)
                    statusRow("Folder", symbol: "folder", value: folderName, action: onLibrary)
                    statusRow("Knowledge", symbol: "books.vertical", value: knowledgeValue, action: onKnowledge)
                    statusRow("Memory", symbol: "memorychip", value: model.activeConversation?.memoryEnabled == true ? "On for this chat" : "Off for this chat", action: onMemory)
                    LabeledContent("In the composer", value: draftCount == 0 ? "Nothing attached" : "\(draftCount)")
                } header: {
                    Text("Attached to this chat")
                } footer: {
                    Text("Project, folder, knowledge, and memory for this chat. Search is in Chat Settings. How it looks is in Customise. Persona and skills have their own pages.")
                }
            }
            .navigationTitle("Attached")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { NodusStudioClose() } }
            .presentationDragIndicator(.visible)
            .task { await loadCollections() }
            .accessibilityIdentifier("nodus.chat.connectors")
        }
    }

    private var projectName: String {
        model.activeConversation.flatMap { model.library.project(for: $0.id)?.name } ?? "None"
    }

    private var folderName: String {
        model.activeConversation.flatMap { model.library.folder(for: $0.id)?.name } ?? "None"
    }

    private var knowledgeValue: String {
        if collectionNames.isEmpty { return "None" }
        return collectionNames.joined(separator: ", ")
    }

    private func loadCollections() async {
        let ids = model.activeConversation?.attachedKnowledgeCollectionIDs ?? []
        let collections = await app.nodusKnowledgeStore.collections()
        collectionNames = collections.filter { ids.contains($0.id) }.map(\.name)
    }

    private func statusRow(_ title: String, symbol: String, value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                NodusStudioGlyph(symbol: symbol)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(.primary)
                    Text(value).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
        }
    }
}

enum NodusMarketCategory: String, CaseIterable, Identifiable, Hashable {
    case writing, thinking, research, planning

    var id: String { rawValue }

    var title: String {
        switch self {
        case .writing: "Writing"
        case .thinking: "Thinking"
        case .research: "Research"
        case .planning: "Planning"
        }
    }

    var symbol: String {
        switch self {
        case .writing: "pencil.line"
        case .thinking: "brain"
        case .research: "text.magnifyingglass"
        case .planning: "checklist"
        }
    }
}

struct NodusMarketPrompt: Identifiable, Hashable {
    let id: String
    let title: String
    let summary: String
    let body: String
    let symbol: String
    let category: NodusMarketCategory
    let featured: Bool
}

enum NodusMarketCatalog {
    static let prompts: [NodusMarketPrompt] = [
        NodusMarketPrompt(id: "rewrite", title: "Rewrite clearly", summary: "Shorter and clearer, without new facts.", body: "Rewrite the following so it is shorter and clearer, without adding facts:\n", symbol: "pencil.line", category: .writing, featured: true),
        NodusMarketPrompt(id: "shorter", title: "Make it shorter", summary: "Keep the meaning and cut the rest.", body: "Make the following shorter. Keep the meaning and do not add facts:\n", symbol: "arrow.down.right.and.arrow.up.left", category: .writing, featured: false),
        NodusMarketPrompt(id: "plain", title: "Plain words", summary: "Say it so it can be read once.", body: "Rewrite the following in plain words. Do not add facts:\n", symbol: "textformat", category: .writing, featured: false),
        NodusMarketPrompt(id: "questions", title: "Open questions", summary: "List what is still unanswered.", body: "List the open questions in the following. Do not answer them:\n", symbol: "questionmark.bubble", category: .thinking, featured: true),
        NodusMarketPrompt(id: "assumptions", title: "Name assumptions", summary: "Separate what is stated from what is assumed.", body: "List the assumptions in the following. Mark anything that is not actually stated:\n", symbol: "lightbulb", category: .thinking, featured: false),
        NodusMarketPrompt(id: "options", title: "Two options", summary: "Set out two ways forward and the tradeoff.", body: "Give two options for the following. For each, name the tradeoff. Do not invent facts:\n", symbol: "arrow.triangle.branch", category: .thinking, featured: false),
        NodusMarketPrompt(id: "summarise", title: "Summarise", summary: "A few sentences, staying with the text.", body: "Summarise the following in a few sentences. Stay with what is written:\n", symbol: "text.alignleft", category: .research, featured: true),
        NodusMarketPrompt(id: "sources", title: "What needs a source", summary: "Point at claims that are not supported here.", body: "Read the following and list claims that would need a source. Do not look anything up:\n", symbol: "quote.opening", category: .research, featured: false),
        NodusMarketPrompt(id: "terms", title: "Terms", summary: "Pull the words that need a definition.", body: "List the specialised terms in the following and define each one from the text only:\n", symbol: "character.book.closed", category: .research, featured: false),
        NodusMarketPrompt(id: "checklist", title: "Checklist", summary: "Turn the text into steps you can do.", body: "Turn the following into a checklist:\n", symbol: "checklist", category: .planning, featured: true),
        NodusMarketPrompt(id: "next", title: "Next three actions", summary: "The next concrete things, in order.", body: "From the following, list the next three actions in order. Skip anything already done:\n", symbol: "list.number", category: .planning, featured: false),
        NodusMarketPrompt(id: "notes", title: "Notes outline", summary: "Headings and bullets, nothing extra.", body: "Turn the following into notes with short headings and bullets. Do not add facts:\n", symbol: "note.text", category: .planning, featured: false)
    ]

    static var featured: [NodusMarketPrompt] { prompts.filter(\.featured) }
}

struct NodusMarketplaceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppEnvironment.self) private var app
    @Bindable var model: NodusChatViewModel
    @State private var query = ""
    @State private var category: NodusMarketCategory?
    @State private var selected: NodusMarketPrompt?

    var body: some View {
        NavigationStack {
            List {
                if queryTrimmed.isEmpty {
                    Section {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(NodusMarketCatalog.featured) { prompt in
                                    featuredCard(prompt)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    } header: {
                        Text("Featured")
                    } footer: {
                        Text("Included with Modula. Adding a prompt stores a copy on this iPhone. Nothing is downloaded.")
                    }
                }
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            categoryChip(nil, title: "All")
                            ForEach(NodusMarketCategory.allCases) { item in
                                categoryChip(item, title: item.title)
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
                Section {
                    if filtered.isEmpty {
                        ContentUnavailableView.search(text: query)
                    }
                    ForEach(filtered) { prompt in
                        marketRow(prompt)
                    }
                } header: {
                    HStack {
                        Text(category?.title ?? "All prompts")
                        Spacer()
                        if let category {
                            Button("Add \(category.title)") { add(NodusMarketCatalog.prompts.filter { $0.category == category }) }
                                .font(.caption.weight(.semibold))
                        }
                    }
                }
                Section("On this iPhone") {
                    let saved = savedPrompts
                    if saved.isEmpty {
                        Text("Nothing saved yet. Add a prompt above and it stays on this iPhone.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(saved) { prompt in
                        Button { insert(prompt.body) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(prompt.title)
                                Text(prompt.body).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                        .contextMenu {
                            Button("Use", systemImage: "text.insert") { insert(prompt.body) }
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                Task { await model.deletePrompt(id: prompt.id) }
                            }
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: "Search the marketplace")
            .navigationTitle("Marketplace")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { NodusStudioClose() } }
            .presentationDragIndicator(.visible)
            .navigationDestination(item: $selected) { prompt in
                marketDetail(prompt)
            }
            .accessibilityIdentifier("nodus.chat.marketplace")
        }
    }

    private var queryTrimmed: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filtered: [NodusMarketPrompt] {
        NodusMarketCatalog.prompts.filter { prompt in
            let matchesCategory = category == nil || prompt.category == category
            let needle = queryTrimmed.lowercased()
            let matchesQuery = needle.isEmpty || prompt.title.lowercased().contains(needle) || prompt.summary.lowercased().contains(needle)
            return matchesCategory && matchesQuery
        }
    }

    private var savedPrompts: [NodusPrompt] {
        let needle = queryTrimmed.lowercased()
        return model.library.prompts.filter { prompt in
            needle.isEmpty || prompt.title.lowercased().contains(needle) || prompt.body.lowercased().contains(needle)
        }
    }

    private var projectID: UUID? {
        model.activeConversation.flatMap { model.library.project(for: $0.id)?.id }
    }

    private func featuredCard(_ prompt: NodusMarketPrompt) -> some View {
        Button { selected = prompt } label: {
            VStack(alignment: .leading, spacing: 10) {
                NodusStudioGlyph(symbol: prompt.symbol)
                Text(prompt.title).font(.headline).foregroundStyle(.primary)
                Text(prompt.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Text(prompt.category.title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(app.appearance.accent.color)
            }
            .padding(14)
            .frame(width: 210, alignment: .leading)
            .modulaChrome(in: RoundedRectangle(cornerRadius: 20, style: .continuous), opaque: false)
        }
        .buttonStyle(.plain)
    }

    private func categoryChip(_ value: NodusMarketCategory?, title: String) -> some View {
        let on = category == value
        return Button { category = value } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .foregroundStyle(on ? Color.white : Color.primary)
                .background(on ? AnyShapeStyle(app.appearance.accent.color) : AnyShapeStyle(Color.secondary.opacity(0.12)), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func marketRow(_ prompt: NodusMarketPrompt) -> some View {
        HStack(spacing: 12) {
            Button { selected = prompt } label: {
                HStack(spacing: 12) {
                    NodusStudioGlyph(symbol: prompt.symbol)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(prompt.title).foregroundStyle(.primary)
                        Text(prompt.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
            }
            .buttonStyle(.plain)
            Spacer(minLength: 8)
            addButton(prompt)
        }
        .contextMenu {
            Button("Use", systemImage: "text.insert") { insert(prompt.body) }
            Button(isSaved(prompt) ? "Remove" : "Add", systemImage: isSaved(prompt) ? "minus.circle" : "plus.circle") {
                isSaved(prompt) ? remove(prompt) : add([prompt])
            }
            Menu("Category", systemImage: prompt.category.symbol) {
                Button(prompt.category.title) { category = prompt.category }
            }
        }
    }

    private func addButton(_ prompt: NodusMarketPrompt) -> some View {
        Button(isSaved(prompt) ? "Added" : "Add") {
            if isSaved(prompt) { remove(prompt) } else { add([prompt]) }
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .foregroundStyle(isSaved(prompt) ? Color.secondary : app.appearance.accent.color)
        .background(Color.secondary.opacity(isSaved(prompt) ? 0.12 : 0.14), in: Capsule())
        .buttonStyle(.plain)
        .accessibilityLabel(isSaved(prompt) ? "Remove \(prompt.title)" : "Add \(prompt.title)")
    }

    private func marketDetail(_ prompt: NodusMarketPrompt) -> some View {
        List {
            Section {
                HStack(spacing: 12) {
                    NodusStudioGlyph(symbol: prompt.symbol, size: 48)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(prompt.title).font(.title3.weight(.semibold))
                        Text(prompt.category.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(app.appearance.accent.color)
                    }
                }
                .padding(.vertical, 4)
                Text(prompt.summary).foregroundStyle(.secondary)
            }
            Section("Prompt") {
                Text(prompt.body).textSelection(.enabled)
            }
            Section {
                Button("Use in this chat", systemImage: "text.insert") { insert(prompt.body) }
                Button(isSaved(prompt) ? "Remove from this iPhone" : "Add to this iPhone", systemImage: isSaved(prompt) ? "minus.circle" : "plus.circle") {
                    isSaved(prompt) ? remove(prompt) : add([prompt])
                }
            } footer: {
                Text("Using a prompt puts it in the composer. Adding it keeps a copy with your saved prompts.")
            }
        }
        .navigationTitle(prompt.title)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("nodus.chat.marketplace.detail")
    }

    private func isSaved(_ prompt: NodusMarketPrompt) -> Bool {
        model.library.prompts.contains { $0.title == prompt.title }
    }

    private func add(_ prompts: [NodusMarketPrompt]) {
        Task {
            for prompt in prompts where !isSaved(prompt) {
                await model.savePrompt(title: prompt.title, body: prompt.body, projectID: projectID)
            }
        }
    }

    private func remove(_ prompt: NodusMarketPrompt) {
        guard let saved = model.library.prompts.first(where: { $0.title == prompt.title }) else { return }
        Task { await model.deletePrompt(id: saved.id) }
    }

    private func insert(_ body: String) {
        let current = model.input.trimmingCharacters(in: .whitespacesAndNewlines)
        model.input = current.isEmpty ? body : current + "\n" + body
        dismiss()
    }
}

struct NodusSkillsSheet: View {
    @Bindable var model: NodusChatViewModel

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("A skill adds one instruction line for this chat. Nodus reads it with your question. It does not gain a new tool.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section {
                    ForEach(NodusSkill.allCases) { skill in
                        let on = model.activeSkills.contains(skill)
                        Button {
                            Task { await model.toggleSkill(skill) }
                        } label: {
                            HStack(spacing: 12) {
                                NodusStudioGlyph(symbol: skill.symbol)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(skill.title).foregroundStyle(.primary)
                                    Text(skill.instruction).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(on ? AnyShapeStyle(TintShapeStyle()) : AnyShapeStyle(Color.secondary))
                                    .contentTransition(.symbolEffect(.replace))
                            }
                        }
                        .buttonStyle(.plain)
                        .sensoryFeedback(.selection, trigger: on)
                    }
                }
            }
            .animation(.spring(duration: 0.32, bounce: 0.28), value: model.activeSkills.map(\.rawValue))
            .navigationTitle("Skills")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { NodusStudioClose() } }
            .presentationDragIndicator(.visible)
            .accessibilityIdentifier("nodus.chat.skills")
        }
    }
}

struct NodusPersonaSheet: View {
    @Bindable var model: NodusChatViewModel
    @State private var custom = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(NodusPersonaPreset.allCases) { preset in
                        let selected = model.activePersona == preset.instruction
                        Button {
                            Task { await model.setPersona(preset.instruction) }
                        } label: {
                            HStack(spacing: 12) {
                                NodusStudioGlyph(symbol: preset.symbol)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(preset.title).foregroundStyle(.primary)
                                    Text(preset.instruction.isEmpty ? "No extra instruction." : preset.instruction)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if selected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.tint)
                                        .transition(.scale.combined(with: .opacity))
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Voice")
                } footer: {
                    Text("A persona is an instruction written on this iPhone. It does not switch Nodus to another model.")
                }
                Section("Your own") {
                    TextField("How should Nodus answer in this chat?", text: $custom, axis: .vertical)
                        .lineLimit(3 ... 6)
                    Button("Use this persona") {
                        Task { await model.setPersona(custom) }
                    }
                    .disabled(custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("Persona")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { NodusStudioClose() } }
            .presentationDragIndicator(.visible)
            .onAppear { custom = model.activePersona }
            .animation(.spring(duration: 0.32, bounce: 0.25), value: model.activePersona)
            .accessibilityIdentifier("nodus.chat.persona")
        }
    }
}

struct NodusCustomiseSheet: View {
    @Environment(AppEnvironment.self) private var app
    @Bindable var model: NodusChatViewModel

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("A reply in this chat.")
                        .font(model.messageFont)
                        .padding(model.messageDensity == "compact" ? 8 : 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(selectedTint.color(accent: app.appearance.accent.color).opacity(0.22), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .animation(.spring(duration: 0.35, bounce: 0.2), value: model.messageTextSize)
                        .animation(.spring(duration: 0.35, bounce: 0.2), value: model.messageDensity)
                        .animation(.spring(duration: 0.35, bounce: 0.25), value: selectedTint)
                    if model.showMessageTimes {
                        Text(Date.now, style: .time)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Preview")
                }
                Section("Colour") {
                    HStack(spacing: 10) {
                        ForEach(NodusChatTint.allCases) { tint in
                            let selected = selectedTint == tint
                            Button {
                                guard let conversation = model.activeConversation else { return }
                                Task { await model.setColor(conversation, color: tint == .accent ? "" : tint.rawValue) }
                            } label: {
                                Circle()
                                    .fill(tint.color(accent: app.appearance.accent.color))
                                    .frame(width: selected ? 36 : 28, height: selected ? 36 : 28)
                                    .overlay {
                                        if selected {
                                            Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(.white)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(tint.title)
                        }
                    }
                    .animation(.spring(duration: 0.35, bounce: 0.3), value: selectedTint)
                }
                Section("Messages") {
                    Picker("Text", selection: textSizeBinding) {
                        Text("Small").tag("small")
                        Text("Regular").tag("regular")
                        Text("Large").tag("large")
                    }
                    .pickerStyle(.segmented)
                    Picker("Spacing", selection: densityBinding) {
                        Text("Comfortable").tag("comfortable")
                        Text("Compact").tag("compact")
                    }
                    .pickerStyle(.segmented)
                    Toggle("Show the time on each message", isOn: timesBinding)
                }
                Section {
                    Text("Colour, text size, spacing, and timestamps change this chat’s look. Instructions, Search, and Memory stay in Chat Settings.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Customise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { NodusStudioClose() } }
            .presentationDragIndicator(.visible)
            .accessibilityIdentifier("nodus.chat.customise")
        }
    }

    private var selectedTint: NodusChatTint {
        let name = model.activeConversation.flatMap { model.library.placement(for: $0.id)?.color } ?? ""
        return NodusChatTint(rawValue: name) ?? .accent
    }

    private var densityBinding: Binding<String> {
        Binding(get: { model.messageDensity }, set: { value in Task { await model.setMessageDensity(value) } })
    }

    private var timesBinding: Binding<Bool> {
        Binding(get: { model.showMessageTimes }, set: { value in Task { await model.setShowTimes(value) } })
    }

    private var textSizeBinding: Binding<String> {
        Binding(get: { model.messageTextSize }, set: { value in Task { await model.setMessageTextSize(value) } })
    }
}

struct NodusRemoteSheet: View {
    var pathStatus: String
    var interfaceName: String
    var searchOn: Bool
    var webCitations: Int

    var body: some View {
        NavigationStack {
            List {
                Section("This iPhone") {
                    LabeledContent("Network", value: pathStatus)
                    LabeledContent("Interface", value: interfaceName)
                }
                Section("What can leave") {
                    LabeledContent("Nodus", value: "Stays here")
                    LabeledContent("Pictures", value: "Stay here")
                    LabeledContent("Memory", value: "Stays here")
                    LabeledContent("Search", value: searchOn ? "Query only, when you send" : "Off")
                    LabeledContent("Web sources in this chat", value: "\(webCitations)")
                }
                Section {
                    Text("Turn Search on from the composer or from Chat Settings. This page only shows the connection. It does not send anything.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Remote")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { NodusStudioClose() } }
            .presentationDragIndicator(.visible)
            .accessibilityIdentifier("nodus.chat.remote")
        }
    }
}

enum NodusChatFunction: String, CaseIterable, Identifiable {
    case speak, note, prompt, time

    var id: String { rawValue }

    var title: String {
        switch self {
        case .speak: "Speak last reply"
        case .note: "Save reply as a note"
        case .prompt: "Save reply as a prompt"
        case .time: "Insert the time"
        }
    }

    var detail: String {
        switch self {
        case .speak: "Read it aloud on this iPhone."
        case .note: "Keep it on the chat. Notes are not sent to Nodus."
        case .prompt: "Keep it with your saved prompts on this iPhone."
        case .time: "Put the current time into the composer."
        }
    }

    var symbol: String {
        switch self {
        case .speak: "speaker.wave.2"
        case .note: "note.text"
        case .prompt: "text.quote"
        case .time: "clock"
        }
    }
}

struct NodusFunctionsSheet: View {
    var lastReply: String?
    var onSelect: (NodusChatFunction) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let lastReply, !lastReply.isEmpty {
                        Text(lastReply).font(.subheadline).lineLimit(6)
                    } else {
                        Text("No reply yet. Speak, note, and prompt use the latest Nodus reply.")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Latest reply")
                }
                Section {
                    ForEach(NodusChatFunction.allCases) { function in
                        Button {
                            onSelect(function)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                NodusStudioGlyph(symbol: function.symbol)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(function.title).foregroundStyle(.primary)
                                    Text(function.detail).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .disabled(function != .time && (lastReply?.isEmpty != false))
                    }
                }
            }
            .navigationTitle("Reply tools")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { NodusStudioClose() } }
            .presentationDragIndicator(.visible)
            .accessibilityIdentifier("nodus.chat.functions")
        }
    }
}
#endif
