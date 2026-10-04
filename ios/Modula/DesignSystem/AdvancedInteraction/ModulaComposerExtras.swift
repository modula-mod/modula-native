import AVFoundation
import SwiftUI

// MARK: - Voice notes

struct ModulaVoiceNote: Equatable, Sendable {
    var fileURL: URL
    var durationMs: Int
    /// 0…100 amplitude samples (≤ 64) for the waveform.
    var waveform: [Int]
}

/// Hold-to-record voice notes: AAC in a temporary file, live metering for the waveform.
@MainActor
final class ModulaVoiceRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var levels: [CGFloat] = []
    @Published private(set) var elapsed: TimeInterval = 0
    @Published var permissionDenied = false
    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var samples: [CGFloat] = []
    private var startedAt = Date()

    func start() async -> Bool {
        guard !isRecording else { return true }
        let granted = await AVAudioApplication.requestRecordPermission()
        guard granted else { permissionDenied = true; return false }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("voice-\(UUID().uuidString).m4a")
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.isMeteringEnabled = true
            guard recorder.record() else { return false }
            self.recorder = recorder
            samples = []
            levels = []
            startedAt = Date()
            elapsed = 0
            isRecording = true
            timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
            return true
        } catch {
            return false
        }
    }

    private func tick() {
        guard let recorder, isRecording else { return }
        recorder.updateMeters()
        let power = recorder.averagePower(forChannel: 0)
        let level = CGFloat(max(0, min(1, (power + 50) / 50)))
        samples.append(level)
        levels = Array((levels + [level]).suffix(36))
        elapsed = Date().timeIntervalSince(startedAt)
        if elapsed > 5 * 60 { _ = finish() }
    }

    /// Stops and returns the note (nil when too short to be intentional).
    func finish() -> ModulaVoiceNote? {
        guard let recorder else { return nil }
        let duration = recorder.currentTime
        recorder.stop()
        cleanup()
        guard duration >= 0.6 else {
            try? FileManager.default.removeItem(at: recorder.url)
            return nil
        }
        return ModulaVoiceNote(fileURL: recorder.url, durationMs: Int(duration * 1000), waveform: Self.downsample(samples, to: 48))
    }

    func cancel() {
        guard let recorder else { return }
        recorder.stop()
        recorder.deleteRecording()
        cleanup()
    }

    private func cleanup() {
        timer?.invalidate()
        timer = nil
        recorder = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    static func downsample(_ values: [CGFloat], to count: Int) -> [Int] {
        guard !values.isEmpty else { return [] }
        let bucket = max(1, values.count / count)
        return stride(from: 0, to: values.count, by: bucket).prefix(count).map { start in
            let slice = values[start..<min(start + bucket, values.count)]
            return Int((slice.max() ?? 0) * 100)
        }
    }
}

/// Live recording strip shown in place of the text field.
struct ModulaRecordingPill: View {
    @ObservedObject var recorder: ModulaVoiceRecorder
    var cancelProgress: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(.red).frame(width: 9, height: 9)
                .opacity(reduceMotion ? 1 : (Int(recorder.elapsed * 2) % 2 == 0 ? 1 : 0.35))
                .animation(.easeInOut(duration: 0.4), value: Int(recorder.elapsed * 2))
            Text(Duration.seconds(recorder.elapsed).formatted(.time(pattern: .minuteSecond)))
                .font(.subheadline.monospacedDigit().weight(.semibold))
            ModulaWaveformView(levels: recorder.levels, tint: .red)
                .frame(height: 26)
            Label("Slide to cancel", systemImage: "chevron.left")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
                .opacity(Double(1 - cancelProgress))
                .offset(x: -cancelProgress * 30)
                .fixedSize()
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Recording voice note")
        .accessibilityIdentifier("composer.recording")
    }
}

struct ModulaWaveformView: View {
    var levels: [CGFloat]
    var tint: Color = .accentColor
    var progress: CGFloat? = nil

    var body: some View {
        GeometryReader { proxy in
            let count = max(levels.count, 1)
            let barWidth = max(2, proxy.size.width / CGFloat(count) - 2)
            HStack(alignment: .center, spacing: 2) {
                ForEach(Array(levels.enumerated()), id: \.offset) { index, level in
                    Capsule()
                        .fill(tint.opacity(progress.map { CGFloat(index) / CGFloat(count) <= $0 ? 1 : 0.35 } ?? 0.9))
                        .frame(width: barWidth, height: max(3, proxy.size.height * level))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Formatting

enum ModulaTextFormat: String, CaseIterable, Identifiable {
    case bold, italic, code, spoiler, link
    var id: String { rawValue }
    var systemImage: String {
        switch self {
        case .bold: "bold"
        case .italic: "italic"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .spoiler: "eye.slash"
        case .link: "link"
        }
    }
    var title: String { rawValue.capitalized }
    var markers: (String, String) {
        switch self {
        case .bold: ("**", "**")
        case .italic: ("_", "_")
        case .code: ("`", "`")
        case .spoiler: ("||", "||")
        case .link: ("[", "](https://)")
        }
    }

    /// Wraps the last word (or inserts an empty pair) — the composer has no selection API.
    static func apply(_ format: ModulaTextFormat, to text: String) -> String {
        let (open, close) = format.markers
        guard let last = text.last, !last.isWhitespace else { return text + open + close }
        let words = text.split(separator: " ", omittingEmptySubsequences: false)
        guard let word = words.last, !word.isEmpty else { return text + open + close }
        let prefix = text.dropLast(word.count)
        return prefix + open + word + close
    }
}

struct ModulaFormattingBar: View {
    var onFormat: (ModulaTextFormat) -> Void
    var onTranslate: (() -> Void)?

    var body: some View {
        HStack(spacing: 4) {
            ForEach(ModulaTextFormat.allCases) { format in
                Button { onFormat(format); HapticEngine.shared.play(.selection) } label: {
                    Image(systemName: format.systemImage).font(.subheadline.weight(.semibold)).frame(width: 40, height: 34)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(format.title)
                .accessibilityIdentifier("composer.format.\(format.rawValue)")
            }
            Spacer(minLength: 0)
            if let onTranslate {
                Button(action: onTranslate) {
                    Label("Translate", systemImage: "translate").font(.caption.weight(.semibold)).padding(.horizontal, 10).frame(height: 34)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("composer.translate")
            }
        }
        .padding(.horizontal, 6)
        .modulaGlass(in: Capsule(), interactive: false)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("composer.formatting")
    }
}

// MARK: - Rich comment text (markdown + spoilers + Modula links)

enum ModulaRichText {
    /// **bold**, _italic_, `code`, [links](url), ||spoilers|| (hidden until revealed), plus @mentions/#tags/URLs.
    static func attributed(_ text: String, revealSpoilers: Bool) -> AttributedString {
        ModulaMarkup.render(text, revealSpoilers: revealSpoilers)
    }

    static func hasSpoiler(_ text: String) -> Bool { ModulaMarkup.hasHiddenContent(text) }
}
