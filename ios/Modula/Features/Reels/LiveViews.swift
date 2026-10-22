import AVFoundation
import SwiftUI

// MARK: - Live v1 (client only)
//
// There is no streaming backend yet (no ingest, no LL-HLS/WebRTC playback, no live
// routes). Everything here sits behind the `dev.live` flag and runs on clearly
// labelled LOCAL PREVIEW data. Nothing is broadcast and no real viewers or comments
// are shown in production paths.

enum LiveFeatureFlags {
    static let key = "dev.live"
    /// On by default in DEBUG builds (dev preview), off by default in release.
    static var isEnabled: Bool {
        #if DEBUG
        (UserDefaults.standard.object(forKey: key) as? Bool) ?? true
        #else
        UserDefaults.standard.bool(forKey: key)
        #endif
    }
}

struct LivePreviewComment: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let text: String
}

/// Local preview data only — labelled as such in the UI.
enum LivePreviewData {
    static let names = ["preview_ana", "preview_ben", "preview_cai", "preview_dee", "preview_eli"]
    static let lines = ["(preview comment)", "Sample chat line", "Hello from local preview", "👋", "This is not a real viewer"]
    static func comment(_ i: Int) -> LivePreviewComment {
        LivePreviewComment(name: names[i % names.count], text: lines[(i * 3) % lines.count])
    }
}

// MARK: Entry flow

struct LiveHostFlow: View {
    @Environment(\.dismiss) private var dismiss
    @State private var phase: Phase = .setup
    @State private var title = ""
    @State private var stats = LiveSessionStats()

    enum Phase { case setup, live, summary }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch phase {
            case .setup:
                LiveSetupView(title: $title, onCancel: { dismiss() }, onStart: { withAnimation { phase = .live } })
            case .live:
                LiveRoomView(title: title.isEmpty ? "Untitled live" : title, isHost: true) { result in
                    stats = result
                    withAnimation { phase = .summary }
                }
            case .summary:
                LiveSummaryView(title: title, stats: stats) { dismiss() }
            }
        }
        .environment(\.colorScheme, .dark)
        .statusBarHidden(phase == .live)
    }
}

struct LiveSessionStats: Equatable {
    var duration: TimeInterval = 0
    var hearts = 0
    var comments = 0
}

// MARK: Setup

struct LiveSetupView: View {
    @Binding var title: String
    var onCancel: () -> Void
    var onStart: () -> Void
    @State private var camera = LiveCameraModel()
    @State private var countdown: Int?
    @State private var look: LiveLook = .natural
    @State private var beauty = false
    @State private var audience: LiveAudience = .everyone
    @State private var commentsOn = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            LiveCameraPreview(session: camera.session)
                .ignoresSafeArea()
                // Local-only looks layered over the preview (nothing is processed or sent).
                .overlay {
                    ZStack {
                        if let tint = look.tint { tint.blendMode(.softLight) }
                        if beauty { Color.white.opacity(0.18).blendMode(.softLight) }
                    }
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .animation(.easeInOut(duration: 0.25), value: look)
                    .animation(.easeInOut(duration: 0.25), value: beauty)
                }
                .overlay { if !camera.authorized { cameraDenied } }
            // Lighter scrims so the camera preview reads bright, not dim.
            LinearGradient(colors: [.black.opacity(0.35), .clear, .clear, .black.opacity(0.5)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea().allowsHitTesting(false)

            VStack(spacing: 16) {
                HStack {
                    ModulaGlassIconButton(title: "Close", systemImage: "xmark", foreground: .white, action: onCancel)
                    Spacer()
                    PreviewBadge()
                    Spacer()
                    ModulaGlassIconButton(title: "Flip camera", systemImage: "arrow.triangle.2.circlepath.camera", foreground: .white) {
                        camera.flip()
                        HapticEngine.shared.play(.selection)
                    }
                    .accessibilityIdentifier("live.setup.flip")
                }
                .padding(.horizontal, 14)

                Spacer()

                setupControls

                TextField("Add a title…", text: $title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    .modulaGlass(in: Capsule(), interactive: false)
                    .padding(.horizontal, 24)
                    .accessibilityIdentifier("live.setup.title")

                Button {
                    startCountdown()
                } label: {
                    Label("Go Live", systemImage: "dot.radiowaves.left.and.right")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 28)
                        .frame(height: 54)
                        .modulaGlass(in: Capsule(), tint: .red, prominent: true, specular: true)
                }
                .buttonStyle(.plain)
                .disabled(countdown != nil)
                .accessibilityIdentifier("live.setup.go")
                Text("Local preview only — nothing is broadcast yet.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.bottom, 12)
            }

            if let countdown {
                Text("\(countdown)")
                    .font(.system(size: 120, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText(countsDown: true))
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityLabel("Going live in \(countdown)")
            }
        }
        .task { await camera.start() }
        .onDisappear { camera.stop() }
    }

    private var setupControls: some View {
        ModulaGlassGroup(spacing: 8) {
            HStack(spacing: 8) {
                Menu {
                    Picker("Look", selection: $look) {
                        ForEach(LiveLook.allCases) { Text($0.title).tag($0) }
                    }
                } label: {
                    controlChip(look == .natural ? "Filter" : look.title, symbol: "camera.filters", on: look != .natural)
                }
                Button {
                    beauty.toggle(); HapticEngine.shared.play(.selection)
                } label: {
                    controlChip("Beauty", symbol: "sparkles", on: beauty)
                }
                .buttonStyle(.plain)
                Menu {
                    Picker("Who can watch", selection: $audience) {
                        ForEach(LiveAudience.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                    }
                } label: {
                    controlChip(audience.title, symbol: audience.symbol, on: false)
                }
                Button {
                    commentsOn.toggle(); HapticEngine.shared.play(.selection)
                } label: {
                    controlChip(commentsOn ? "Comments" : "No comments", symbol: commentsOn ? "bubble.left" : "bubble.left.slash", on: commentsOn)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
    }

    private func controlChip(_ title: String, symbol: String, on: Bool) -> some View {
        Label(title, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .frame(height: 34)
            .modulaGlass(in: Capsule(), interactive: true, tint: on ? .white.opacity(0.25) : nil)
            .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var cameraDenied: some View {
        ContentUnavailableView("Camera unavailable", systemImage: "video.slash", description: Text("Allow camera access in Settings to preview your live."))
    }

    private func startCountdown() {
        HapticEngine.shared.play(.confirmation)
        Task { @MainActor in
            for n in stride(from: 3, through: 1, by: -1) {
                withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7)) { countdown = n }
                HapticEngine.shared.play(.lightImpact)
                try? await Task.sleep(for: .seconds(1))
            }
            countdown = nil
            HapticEngine.shared.play(.success)
            onStart()
        }
    }
}

private struct PreviewBadge: View {
    var body: some View {
        Text("PREVIEW")
            .font(.system(size: 9, weight: .heavy))
            .tracking(0.8)
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Color.orange.opacity(0.7), in: Capsule())
            .accessibilityLabel("Developer preview, local data only")
    }
}

// MARK: Live room (host or viewer UI)

struct LiveRoomView: View {
    let title: String
    var isHost: Bool
    var onEnd: (LiveSessionStats) -> Void
    @State private var camera = LiveCameraModel()
    @State private var comments: [LivePreviewComment] = []
    @State private var hearts: [FloatingHeart] = []
    @State private var draft = ""
    @State private var started = Date()
    @State private var stats = LiveSessionStats()
    @State private var confirmEnd = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if isHost {
                LiveCameraPreview(session: camera.session).ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
            }
            LinearGradient(colors: [.black.opacity(0.55), .clear, .clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea().allowsHitTesting(false)

            VStack(spacing: 0) {
                topBar
                Spacer()
                HStack(alignment: .bottom) {
                    commentsList
                    Spacer(minLength: 12)
                    sideActions
                }
                .padding(.horizontal, 12)
                inputBar
            }

            ForEach(hearts) { heart in
                FloatingHeartView(heart: heart, reduceMotion: reduceMotion)
            }
            .allowsHitTesting(false)
        }
        .task {
            if isHost { await camera.start() }
            // Local preview chatter so the overlay can be evaluated. Labelled as preview.
            var i = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2.2))
                i += 1
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
                    comments.append(LivePreviewData.comment(i))
                    if comments.count > 30 { comments.removeFirst() }
                }
            }
        }
        .onDisappear { camera.stop() }
        .confirmationDialog("End your live?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("End Live", role: .destructive) {
                stats.duration = Date().timeIntervalSince(started)
                onEnd(stats)
            }
        }
        .accessibilityIdentifier("live.room")
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            Text("LIVE")
                .font(.caption.weight(.heavy))
                .foregroundStyle(.white)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.red, in: RoundedRectangle(cornerRadius: 5))
            Label("— preview", systemImage: "eye.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .modulaGlass(in: Capsule(), interactive: false, tint: .black.opacity(0.2))
                .accessibilityLabel("Viewer count unavailable in preview")
            PreviewBadge()
            Spacer()
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.white).lineLimit(1)
            ModulaGlassIconButton(title: isHost ? "End live" : "Close", systemImage: "xmark", foreground: .white) {
                if isHost { confirmEnd = true } else { onEnd(stats) }
            }
            .accessibilityIdentifier("live.end")
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    private var commentsList: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(comments) { comment in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(comment.name).font(.caption.weight(.bold)).foregroundStyle(.white.opacity(0.8))
                            Text(comment.text).font(.subheadline).foregroundStyle(.white)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .id(comment.id)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
            .frame(maxWidth: 280, maxHeight: 260)
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.3)], startPoint: .top, endPoint: .bottom))
            .onChange(of: comments.count) { _, _ in
                if let last = comments.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
        }
        .accessibilityLabel("Preview comments")
    }

    private var sideActions: some View {
        VStack(spacing: 14) {
            ModulaGlassIconButton(title: "Gifts (coming soon)", systemImage: "gift", foreground: .white) {
                HapticEngine.shared.play(.selection)
            }
            ModulaGlassIconButton(title: "Reactions (coming soon)", systemImage: "face.smiling", foreground: .white) {
                HapticEngine.shared.play(.selection)
            }
            ModulaGlassIconButton(title: "Send heart", systemImage: "heart.fill", foreground: .pink) {
                sendHeart()
            }
            .accessibilityIdentifier("live.heart")
        }
        .padding(.bottom, 8)
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Add a comment…", text: $draft)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(height: 42)
                .modulaGlass(in: Capsule(), interactive: false)
                .submitLabel(.send)
                .onSubmit(sendComment)
                .accessibilityIdentifier("live.comment.input")
            if isHost {
                ModulaGlassIconButton(title: "Flip camera", systemImage: "arrow.triangle.2.circlepath.camera", foreground: .white) { camera.flip() }
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
        .padding(.top, 8)
    }

    private func sendComment() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        comments.append(LivePreviewComment(name: "you (preview)", text: text))
        stats.comments += 1
        draft = ""
        HapticEngine.shared.play(.selection)
    }

    private func sendHeart() {
        stats.hearts += 1
        HapticEngine.shared.play(.lightImpact)
        let heart = FloatingHeart(xJitter: CGFloat.random(in: -24...24))
        hearts.append(heart)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            hearts.removeAll { $0.id == heart.id }
        }
    }
}

struct FloatingHeart: Identifiable, Equatable {
    let id = UUID()
    var xJitter: CGFloat
}

private struct FloatingHeartView: View {
    let heart: FloatingHeart
    var reduceMotion: Bool
    @State private var rise = false

    var body: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: 28))
            .foregroundStyle(.pink)
            .shadow(color: .pink.opacity(0.5), radius: 6)
            .offset(x: heart.xJitter + (rise && !reduceMotion ? CGFloat.random(in: -20...20) : 0), y: rise ? (reduceMotion ? -40 : -260) : 0)
            .opacity(rise ? 0 : 1)
            .scaleEffect(rise ? 1.2 : 0.6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(.trailing, 34)
            .padding(.bottom, 120)
            .onAppear { withAnimation(.easeOut(duration: reduceMotion ? 0.6 : 1.8)) { rise = true } }
    }
}

// MARK: Summary

struct LiveSummaryView: View {
    let title: String
    let stats: LiveSessionStats
    var onDone: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "checkmark.circle.fill").font(.system(size: 56)).foregroundStyle(.green)
            Text("Live ended").font(.title.bold()).foregroundStyle(.white)
            if !title.isEmpty { Text(title).foregroundStyle(.white.opacity(0.7)) }
            HStack(spacing: 12) {
                stat("Duration", Duration.seconds(stats.duration).formatted(.time(pattern: .minuteSecond)))
                stat("Hearts", "\(stats.hearts)")
                stat("Comments", "\(stats.comments)")
            }
            Text("Local preview — these numbers are from this device only.")
                .font(.caption).foregroundStyle(.white.opacity(0.6))
            Spacer()
            Button(action: onDone) {
                Text("Done").font(.headline).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 52)
                    .modulaGlass(in: Capsule(), tint: .white.opacity(0.2), specular: true)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .accessibilityIdentifier("live.summary.done")
        }
        .padding(.bottom, 20)
        .accessibilityIdentifier("live.summary")
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.title2.bold()).monospacedDigit().foregroundStyle(.white)
            Text(label).font(.caption).foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity).padding(.vertical, 14)
        .modulaGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous), interactive: false)
    }
}

// MARK: Camera

/// AVCaptureSession start/stop are thread-safe and blocking; run them off the main actor.
private struct LiveSessionBox: @unchecked Sendable {
    let session: AVCaptureSession
    func start() { if !session.isRunning { session.startRunning() } }
    func stop() { if session.isRunning { session.stopRunning() } }
}

@MainActor @Observable
final class LiveCameraModel {
    let session = AVCaptureSession()
    private(set) var authorized = true
    private var position: AVCaptureDevice.Position = .front

    func start() async {
        var granted = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            granted = await AVCaptureDevice.requestAccess(for: .video)
        }
        authorized = granted
        guard granted else { return }
        configure()
        let box = LiveSessionBox(session: session)
        Task.detached { box.start() }
    }

    func stop() {
        let box = LiveSessionBox(session: session)
        Task.detached { box.stop() }
    }

    func flip() {
        position = position == .front ? .back : .front
        configure()
    }

    private func configure() {
        session.beginConfiguration()
        session.inputs.forEach { session.removeInput($0) }
        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
           let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) {
            session.addInput(input)
        }
        session.commitConfiguration()
    }
}

struct LiveCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}


enum LiveLook: String, CaseIterable, Identifiable {
    case natural, warm, cool, vivid
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var tint: Color? {
        switch self {
        case .natural: nil
        case .warm: Color.orange.opacity(0.35)
        case .cool: Color.blue.opacity(0.3)
        case .vivid: Color.pink.opacity(0.25)
        }
    }
}

enum LiveAudience: String, CaseIterable, Identifiable {
    case everyone, followers, closeFriends
    var id: String { rawValue }
    var title: String {
        switch self {
        case .everyone: "Everyone"
        case .followers: "Followers"
        case .closeFriends: "Close friends"
        }
    }
    var symbol: String {
        switch self {
        case .everyone: "globe"
        case .followers: "person.2"
        case .closeFriends: "star.circle"
        }
    }
}
