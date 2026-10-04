import AVFoundation
import CoreLocation
import MapKit
import QuickLook
import SwiftUI

/// Everything a posted comment can carry beyond text.
struct CommentMediaContent: View {
    let media: [SocialCommentMedia]
    var onVote: ((Int?) -> Void)? = nil

    var body: some View {
        let visual = media.filter(\.isVisualMedia)
        VStack(alignment: .leading, spacing: 8) {
            if !visual.isEmpty { CommentMediaGrid(media: visual) }
            ForEach(media.filter { !$0.isVisualMedia }) { item in
                switch item.kind {
                case .sticker:
                    ModulaStickerView(emoji: item.emoji ?? "⭐️", size: 110)
                        .accessibilityLabel("\(item.label ?? "Sticker") sticker")
                case .poll:
                    if let poll = item.poll { CommentPollView(poll: poll, onVote: onVote) }
                case .voice:
                    CommentVoicePlayer(url: item.url, durationMs: item.durationMs ?? 0, waveform: item.waveform)
                case .file:
                    CommentFileRow(url: item.url, name: item.fileName ?? "File", byteSize: item.byteSize, mimeType: item.mimeType)
                case .location:
                    if let lat = item.latitude, let lng = item.longitude {
                        CommentLocationCard(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng), name: item.label)
                    }
                default:
                    EmptyView()
                }
            }
        }
    }
}

// MARK: - Poll

struct CommentPollView: View {
    let poll: CommentPoll
    var onVote: ((Int?) -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var showsResults: Bool { poll.viewerVote != nil || poll.closed }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(poll.question, systemImage: "chart.bar.xaxis").font(.subheadline.weight(.semibold))
            ForEach(Array(poll.options.enumerated()), id: \.offset) { index, option in
                let count = poll.counts.indices.contains(index) ? poll.counts[index] : 0
                let fraction = poll.totalVotes > 0 ? Double(count) / Double(poll.totalVotes) : 0
                Button {
                    guard !poll.closed else { return }
                    onVote?(poll.viewerVote == index ? nil : index)
                    HapticEngine.shared.play(.selection)
                } label: {
                    HStack {
                        if poll.viewerVote == index { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor) }
                        Text(option).font(.subheadline).lineLimit(2)
                        Spacer()
                        if showsResults { Text("\(Int((fraction * 100).rounded()))%").font(.caption.monospacedDigit().weight(.semibold)) }
                    }
                    .padding(.horizontal, 12)
                    .frame(minHeight: 40)
                    .background(alignment: .leading) {
                        GeometryReader { proxy in
                            Capsule().fill(Color.accentColor.opacity(poll.viewerVote == index ? 0.28 : 0.14))
                                .frame(width: showsResults ? max(proxy.size.width * fraction, 0) : 0)
                                .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.8), value: fraction)
                        }
                    }
                    .overlay(Capsule().stroke(Color.primary.opacity(0.12)))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(onVote == nil || poll.closed)
                .accessibilityLabel(showsResults ? "\(option), \(Int((fraction * 100).rounded())) percent" : option)
                .accessibilityAddTraits(poll.viewerVote == index ? .isSelected : [])
            }
            Text(footer).font(.caption).foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("comment.poll")
    }

    private var footer: String {
        let votes = poll.totalVotes == 1 ? "1 vote" : "\(poll.totalVotes) votes"
        if poll.closed { return "\(votes) · Final results" }
        if let closesAt = poll.closesAt { return "\(votes) · Ends \(closesAt.formatted(.relative(presentation: .named)))" }
        return votes
    }
}

/// Sheet for creating a poll (2–4 options, optional duration).
struct CommentPollCreator: View {
    var onCreate: (_ question: String, _ options: [String], _ hours: Int?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var question = ""
    @State private var options = ["", ""]
    @State private var hours: Int? = 24
    @FocusState private var focusedField: Int?

    private var valid: Bool {
        let filled = options.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return !question.trimmingCharacters(in: .whitespaces).isEmpty && filled.count >= 2 && Set(filled.map { $0.lowercased() }).count == filled.count
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Question") {
                    TextField("Ask something…", text: $question, axis: .vertical)
                        .focused($focusedField, equals: -1)
                }
                Section("Options") {
                    ForEach(options.indices, id: \.self) { index in
                        HStack {
                            TextField("Option \(index + 1)", text: $options[index])
                                .focused($focusedField, equals: index)
                            if options.count > 2 {
                                Button(role: .destructive) { options.remove(at: index) } label: { Image(systemName: "minus.circle.fill") }
                                    .buttonStyle(.plain).foregroundStyle(.red)
                                    .accessibilityLabel("Remove option \(index + 1)")
                            }
                        }
                    }
                    if options.count < 4 {
                        Button { options.append(""); focusedField = options.count - 1 } label: { Label("Add option", systemImage: "plus.circle.fill") }
                    }
                }
                Section("Length") {
                    Picker("Poll length", selection: $hours) {
                        Text("1 hour").tag(Int?.some(1))
                        Text("1 day").tag(Int?.some(24))
                        Text("3 days").tag(Int?.some(72))
                        Text("1 week").tag(Int?.some(168))
                        Text("No end").tag(Int?.none)
                    }
                }
            }
            .navigationTitle("New poll")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onCreate(question.trimmingCharacters(in: .whitespaces), options.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }, hours)
                        HapticEngine.shared.play(.success)
                        dismiss()
                    }
                    .disabled(!valid)
                }
            }
            .onAppear { focusedField = -1 }
        }
        .accessibilityIdentifier("comment.poll.creator")
    }
}

// MARK: - Voice

@MainActor
fileprivate final class CommentAudioPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var isPlaying = false
    @Published var progress: CGFloat = 0
    @Published var loading = false
    private var player: AVAudioPlayer?
    private var timer: Timer?

    func toggle(url: URL, client: GreenfieldClient) async {
        if let player {
            if player.isPlaying { player.pause(); isPlaying = false } else { player.play(); isPlaying = true; startTimer() }
            return
        }
        loading = true
        defer { loading = false }
        guard let data = try? await client.mediaData(from: url, maximumBytes: 20_000_000),
              let player = try? AVAudioPlayer(data: data) else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        player.delegate = self
        self.player = player
        player.play()
        isPlaying = true
        startTimer()
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let player = self.player, player.duration > 0 else { return }
                self.progress = CGFloat(player.currentTime / player.duration)
            }
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
            self.progress = 0
            self.timer?.invalidate()
        }
    }
}

struct CommentVoicePlayer: View {
    let url: URL
    let durationMs: Int
    let waveform: [Int]
    @StateObject private var player = CommentAudioPlayer()
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        HStack(spacing: 10) {
            Button {
                Task { await player.toggle(url: url, client: app.client) }
            } label: {
                Group {
                    if player.loading { ProgressView().controlSize(.small) }
                    else { Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").contentTransition(.symbolEffect(.replace)) }
                }
                .frame(width: 38, height: 38)
                .foregroundStyle(.white)
                .background(Color.accentColor, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(player.isPlaying ? "Pause voice note" : "Play voice note")
            ModulaWaveformView(levels: waveform.isEmpty ? Array(repeating: 0.3, count: 32) : waveform.map { CGFloat($0) / 100 }, tint: .accentColor, progress: player.progress)
                .frame(height: 28)
            Text(Duration.milliseconds(durationMs).formatted(.time(pattern: .minuteSecond)))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .frame(maxWidth: 280)
        .background(Color.primary.opacity(0.05), in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("comment.voice")
    }
}

// MARK: - File

struct CommentFileRow: View {
    let url: URL
    let name: String
    let byteSize: Int?
    let mimeType: String?
    @State private var localURL: URL?
    @State private var loading = false
    @Environment(AppEnvironment.self) private var app

    private var symbol: String {
        if mimeType == "application/pdf" { return "doc.richtext.fill" }
        if mimeType?.hasPrefix("audio/") == true { return "waveform" }
        if mimeType?.contains("zip") == true { return "doc.zipper" }
        if mimeType?.contains("sheet") == true || mimeType?.contains("excel") == true { return "tablecells.fill" }
        return "doc.fill"
    }

    var body: some View {
        Button {
            Task { await open() }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.title2).foregroundStyle(Color.accentColor).frame(width: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.subheadline.weight(.semibold)).lineLimit(1)
                    if let byteSize { Text(ByteCountFormatter.string(fromByteCount: Int64(byteSize), countStyle: .file)).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                if loading { ProgressView().controlSize(.small) } else { Image(systemName: "arrow.down.circle").foregroundStyle(.secondary) }
            }
            .padding(10)
            .frame(maxWidth: 300)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .quickLookPreview($localURL)
        .accessibilityLabel("File \(name)")
        .accessibilityHint("Opens a preview")
    }

    private func open() async {
        loading = true
        defer { loading = false }
        guard let data = try? await app.client.mediaData(from: url, maximumBytes: 50_000_000) else { return }
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(name.replacingOccurrences(of: "/", with: "-"))
        try? data.write(to: destination, options: .atomic)
        localURL = destination
    }
}

// MARK: - Location

struct CommentLocationCard: View {
    let coordinate: CLLocationCoordinate2D
    let name: String?

    var body: some View {
        Button {
            let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
            item.name = name
            item.openInMaps()
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                Map(initialPosition: .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 900, longitudinalMeters: 900)), interactionModes: []) {
                    Marker(name ?? "Location", coordinate: coordinate)
                }
                .frame(height: 120)
                .allowsHitTesting(false)
                Label(name ?? "Shared location", systemImage: "mappin.and.ellipse")
                    .font(.caption.weight(.semibold))
                    .padding(10)
            }
            .frame(maxWidth: 280)
            .background(Color.primary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Location: \(name ?? "shared location"). Opens in Maps.")
    }
}

/// One-shot "share my location" with reverse-geocoded place name.
@MainActor
enum CommentLocation {
    static func current() async -> (CLLocationCoordinate2D, String?)? {
        let fetcher = CommentLocationFetcher()
        return await fetcher.current()
    }
}

@MainActor
fileprivate final class CommentLocationFetcher: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation?, Never>?

    func current() async -> (CLLocationCoordinate2D, String?)? {
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        let location: CLLocation? = await withCheckedContinuation { continuation in
            self.continuation = continuation
            manager.requestLocation()
        }
        guard let location else { return nil }
        let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first
        let name = placemark?.name ?? placemark?.locality
        return (location.coordinate, name)
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in self.continuation?.resume(returning: locations.last); self.continuation = nil }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.continuation?.resume(returning: nil); self.continuation = nil }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            if status == .denied || status == .restricted { self.continuation?.resume(returning: nil); self.continuation = nil }
        }
    }
}

// MARK: - Reactions

struct CommentReactionChips: View {
    let reactions: [CommentReactionCount]
    let viewerReaction: String?
    var onToggle: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(reactions, id: \.type) { reaction in
                    let mine = reaction.type == viewerReaction
                    Button {
                        onToggle(reaction.type)
                        HapticEngine.shared.play(.selection)
                    } label: {
                        HStack(spacing: 4) {
                            Text(reaction.emoji)
                            Text("\(reaction.count)").font(.caption.monospacedDigit().weight(.semibold))
                                .contentTransition(.numericText())
                        }
                        .padding(.horizontal, 9)
                        .frame(minHeight: 30)
                        .background(mine ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06), in: Capsule())
                        .overlay(Capsule().stroke(mine ? Color.accentColor : .clear, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(reaction.type), \(reaction.count)")
                    .accessibilityAddTraits(mine ? .isSelected : [])
                }
            }
        }
        .accessibilityIdentifier("comment.reactions")
    }
}

// MARK: - Long-press menu (Telegram-style glass overlay)

/// Dims the conversation, lifts the comment, shows a reaction bar above and a glass action list below.
struct CommentActionOverlay<Actions: View>: View {
    let comment: SocialComment
    let viewerReaction: String?
    var onReact: (String) -> Void
    var onDismiss: () -> Void
    @ViewBuilder var actions: () -> Actions
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Rectangle().fill(.black.opacity(0.35)).ignoresSafeArea()
                .onTapGesture(perform: onDismiss)
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("Close menu")
            VStack(spacing: 10) {
                ModulaGlassGroup(spacing: 4) {
                    HStack(spacing: 2) {
                        ForEach(Array(CommentReactionCount.allTypes.enumerated()), id: \.element) { index, type in
                            Button {
                                onReact(type)
                                HapticEngine.shared.play(.selection)
                                onDismiss()
                            } label: {
                                Text(CommentReactionCount(type: type, count: 0).emoji)
                                    .font(.system(size: 28))
                                    .frame(width: 40, height: 44)
                                    .background(viewerReaction == type ? Color.accentColor.opacity(0.25) : .clear, in: Circle())
                                    .scaleEffect(appeared || reduceMotion ? 1 : 0.3)
                                    .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.6).delay(Double(index) * 0.025), value: appeared)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(type.capitalized)
                        }
                    }
                    .padding(.horizontal, 6)
                    .modulaGlass(in: Capsule())
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        ModulaAvatar(initials: comment.author?.initials ?? "?", url: comment.author?.avatarURL, size: 26)
                        Text(comment.author?.displayName ?? "Comment").font(.subheadline.weight(.semibold))
                    }
                    if !comment.text.isEmpty {
                        Text(ModulaRichText.attributed(comment.text, revealSpoilers: false)).font(.body).lineLimit(6)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .scaleEffect(appeared || reduceMotion ? 1 : 0.96)
                VStack(alignment: .leading, spacing: 0) {
                    actions()
                        .labelStyle(CommentMenuLabelStyle())
                        .buttonStyle(.plain)
                }
                .padding(.vertical, 6)
                .frame(width: 250, alignment: .leading)
                .modulaGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous), interactive: false)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 20)
            .offset(y: appeared || reduceMotion ? 0 : 16)
        }
        .onAppear { withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) { appeared = true } }
        .accessibilityElement(children: .contain)
        .accessibilityAction(.escape, onDismiss)
        .accessibilityIdentifier("comment.menu")
    }
}

private struct CommentMenuLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            configuration.title.font(.body)
            Spacer()
            configuration.icon.font(.body).frame(width: 22)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}
