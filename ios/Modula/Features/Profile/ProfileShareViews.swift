import AVFoundation
import CoreImage.CIFilterBuiltins
import Photos
import PhotosUI
import SwiftUI
import UIKit
import VisionKit

/// Profile share: the universal Modula share sheet with the profile's own code card.
struct ProfileShareSheet: View {
    let profile: ModulaProfile
    var onCopy: () -> Void
    var onShare: () -> Void
    var onShowCode: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        ModulaShareSheet(
            payload: .profile(identity: profile.routeID, displayName: profile.displayName, handle: profile.handle, avatarURL: profile.avatarURL),
            codeSubject: ModulaCodeSubject(profile: profile)
        )
        .accessibilityIdentifier("profile.share.sheet")
    }
}

// MARK: - Modula Code (branded QR)

/// What a Modula Code points at: a profile, post, module or link. Only the canonical public
/// URL is ever encoded — never session or auth material.
struct ModulaCodeSubject: Equatable {
    var title: String
    var subtitle: String?
    var url: URL
    var avatarURL: URL?
    var initials: String
    var isVerified = false
    var kind: String = "Profile"

    init(title: String, subtitle: String?, url: URL, avatarURL: URL? = nil, initials: String, isVerified: Bool = false, kind: String = "Profile") {
        self.title = title
        self.subtitle = subtitle
        self.url = url
        self.avatarURL = avatarURL
        self.initials = initials
        self.isVerified = isVerified
        self.kind = kind
    }

    init(profile: ModulaProfile) {
        self.init(
            title: profile.displayName,
            subtitle: "@\(profile.handle)",
            url: profile.shareURL,
            avatarURL: profile.avatarURL,
            initials: profile.initials,
            isVerified: profile.isVerified,
            kind: "Profile"
        )
    }

    init(payload: SharePayload) {
        let kind: String
        var avatar: URL?
        var subtitle: String?
        switch payload {
        case .profile(_, _, let handle, let avatarURL):
            kind = "Profile"; avatar = avatarURL; subtitle = handle.map { "@\($0)" }
        case .post(_, let author, _, _):
            kind = "Post"; subtitle = author.map { "Post by \($0)" }
        case .module(_, _, let publisher):
            kind = "Module"; subtitle = publisher
        case .link(let url, _):
            kind = "Link"; subtitle = url.host
        }
        let title = payload.title
        self.init(
            title: title.count > 60 ? String(title.prefix(57)) + "…" : title,
            subtitle: subtitle,
            url: payload.canonicalURL,
            avatarURL: avatar,
            initials: String(title.prefix(1)).uppercased(),
            kind: kind
        )
    }
}

/// The module grid of a QR symbol (row-major, top-left origin, quiet zone trimmed).
struct ModulaQRMatrix: Equatable {
    let size: Int
    let bits: [Bool]

    subscript(row: Int, column: Int) -> Bool { bits[row * size + column] }

    /// High error correction so the centre badge can cover part of the symbol safely.
    static func make(_ payload: String, correction: String = "H") -> ModulaQRMatrix? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        filter.correctionLevel = correction
        guard let output = filter.outputImage,
              let cgImage = CIContext().createCGImage(output, from: output.extent) else { return nil }
        let width = cgImage.width, height = cgImage.height
        guard width > 0, height > 0 else { return nil }
        var pixels = [UInt8](repeating: 255, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.interpolationQuality = .none
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where pixels[y * width + x] < 128 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        let size = max(maxX - minX, maxY - minY) + 1
        var bits = [Bool](repeating: false, count: size * size)
        for row in 0..<size {
            for column in 0..<size {
                let x = minX + column, y = minY + row
                if x < width, y < height { bits[row * size + column] = pixels[y * width + x] < 128 }
            }
        }
        return ModulaQRMatrix(size: size, bits: bits)
    }

    /// Finder-pattern ("eye") cells, drawn as rounded squares instead of dots.
    func isFinder(_ row: Int, _ column: Int) -> Bool {
        let far = size - 7
        return (row < 7 && column < 7) || (row < 7 && column >= far) || (row >= far && column < 7)
    }

    /// Modules hidden under the centre badge — about 23% of the side, kept odd so it stays centred.
    var centerHole: ClosedRange<Int> {
        var span = Int((Double(size) * 0.23).rounded())
        if span % 2 == 0 { span += 1 }
        span = max(span, 5)
        let start = (size - span) / 2
        return start...(start + span - 1)
    }

    var centerFraction: CGFloat { CGFloat(centerHole.count) / CGFloat(size) }
}

/// Colourways for the code. Every style keeps dark modules on the white plate so it scans.
enum ModulaCodeStyle: String, CaseIterable, Identifiable {
    case theme, ink, mono
    static let storageKey = "modula.code.style"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .theme: "Theme"
        case .ink: "Ink"
        case .mono: "Mono"
        }
    }

    func modules(_ accent: Color) -> (Color, Color) {
        switch self {
        case .theme: (accent.mix(with: .black, by: 0.18), accent.mix(with: .black, by: 0.55))
        case .ink: (Color(red: 0.07, green: 0.16, blue: 0.22), accent.mix(with: .black, by: 0.62))
        case .mono: (.black, .black)
        }
    }

    func eyes(_ accent: Color) -> Color {
        switch self {
        case .theme: accent.mix(with: .black, by: 0.4)
        case .ink: Color(red: 0.05, green: 0.12, blue: 0.17)
        case .mono: .black
        }
    }
}

/// A branded QR: rounded dots, rounded finder eyes, theme gradient, and a centre badge.
struct ModulaBrandedQRCode<Center: View>: View {
    let matrix: ModulaQRMatrix
    var style: ModulaCodeStyle = .theme
    var accent: Color
    @ViewBuilder var center: () -> Center

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {
                Canvas { context, _ in
                    let n = matrix.size
                    let cell = side / CGFloat(n)
                    let hole = matrix.centerHole
                    var dots = Path()
                    for row in 0..<n {
                        for column in 0..<n where matrix[row, column] {
                            if matrix.isFinder(row, column) || (hole.contains(row) && hole.contains(column)) { continue }
                            let rect = CGRect(x: CGFloat(column) * cell, y: CGFloat(row) * cell, width: cell, height: cell)
                                .insetBy(dx: cell * 0.06, dy: cell * 0.06)
                            dots.addRoundedRect(in: rect, cornerSize: CGSize(width: rect.width * 0.42, height: rect.height * 0.42))
                        }
                    }
                    let (start, end) = style.modules(accent)
                    context.fill(dots, with: .linearGradient(
                        Gradient(colors: [start, end]),
                        startPoint: .zero, endPoint: CGPoint(x: side, y: side)
                    ))
                    let eye = style.eyes(accent)
                    for (row, column) in [(0, 0), (0, n - 7), (n - 7, 0)] {
                        let outer = CGRect(x: CGFloat(column) * cell, y: CGFloat(row) * cell, width: 7 * cell, height: 7 * cell)
                        context.stroke(
                            Path(roundedRect: outer.insetBy(dx: cell / 2, dy: cell / 2), cornerRadius: cell * 1.8, style: .continuous),
                            with: .color(eye), lineWidth: cell
                        )
                        context.fill(
                            Path(roundedRect: outer.insetBy(dx: cell * 2, dy: cell * 2), cornerRadius: cell * 0.95, style: .continuous),
                            with: .color(eye)
                        )
                    }
                }
                .frame(width: side, height: side)

                center()
                    .frame(width: side * matrix.centerFraction * 0.92, height: side * matrix.centerFraction * 0.92)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// White rounded badge holding the avatar or app icon in the middle of the code.
private struct ModulaCodeCenterBadge: View {
    var image: UIImage?
    var avatarURL: URL?
    var initials: String

    var body: some View {
        GeometryReader { geo in
            let side = geo.size.width
            RoundedRectangle(cornerRadius: side * 0.3, style: .continuous)
                .fill(Color.white)
                .overlay {
                    Group {
                        if let image {
                            Image(uiImage: image).resizable().scaledToFill()
                                .clipShape(Circle())
                        } else if let avatarURL {
                            ModulaAvatar(initials: initials, url: avatarURL, size: side * 0.8)
                                .environment(\.modulaSuppressOwnFrame, true)
                        } else {
                            ModulaUnitTile(variant: .teal, cornerFraction: 0.22)
                        }
                    }
                    .frame(width: side * 0.8, height: side * 0.8)
                }
        }
        .accessibilityHidden(true)
    }
}

/// Decodes a QR from a still image (Photos import and tests).
enum ModulaCodeDecoder {
    static func decode(_ image: UIImage) -> String? {
        guard let ciImage = CIImage(image: image) else { return nil }
        let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        return detector?.features(in: ciImage).compactMap { ($0 as? CIQRCodeFeature)?.messageString }.first
    }
}

/// What a scanned code is, so Modula links open in-app and everything else asks first.
enum ModulaScannedCode: Equatable {
    case modula(URL)
    case web(URL)
    case text(String)

    static func classify(_ raw: String) -> ModulaScannedCode {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: text), let scheme = url.scheme?.lowercased() {
            let host = url.host?.lowercased()
            if (scheme == "modula" || (scheme == "https" && host == "modula.digital")), RouteParser.parse(text) != nil {
                return .modula(url)
            }
            if scheme == "http" || scheme == "https", host != nil { return .web(url) }
        }
        return .text(text)
    }
}

enum ModulaCodeMode: String, CaseIterable, Identifiable {
    case myCode, scan
    var id: String { rawValue }
    var symbol: String { self == .myCode ? "qrcode" : "qrcode.viewfinder" }
}

/// Profile entry point kept for existing call sites and tests.
struct ModulaProfileCodeView: View {
    let profile: ModulaProfile
    var initialMode: ModulaCodeMode = .myCode
    var onDismiss: () -> Void

    var body: some View {
        ModulaCodeView(subject: ModulaCodeSubject(profile: profile), initialMode: initialMode, onDismiss: onDismiss)
            .accessibilityIdentifier("profile.modulaCode")
    }

    /// Encodes only the canonical public profile URL — never session/auth material.
    static func qrPayload(for profile: ModulaProfile) -> String {
        profile.shareURL.absoluteString
    }

    static func qrImage(for payload: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

/// My Code / Scan in one Liquid Glass screen.
struct ModulaCodeView: View {
    /// nil when signed out: only the scanner is offered.
    let subject: ModulaCodeSubject?
    var initialMode: ModulaCodeMode = .myCode
    var onDismiss: () -> Void

    @Environment(AppEnvironment.self) private var app
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage(ModulaCodeStyle.storageKey) private var styleRaw = ModulaCodeStyle.theme.rawValue
    @State private var mode: ModulaCodeMode = .myCode
    @State private var copied = false
    @State private var appeared = false
    @State private var exportImage: UIImage?
    @State private var avatarImage: UIImage?
    @Namespace private var switchNamespace

    private var accent: Color { app.appearance.liveAccent }
    private var style: ModulaCodeStyle { ModulaCodeStyle(rawValue: styleRaw) ?? .theme }
    private var reduceMotion: Bool { ModulaEffectGate.reduceMotion(systemReduceMotion) }
    private var matrix: ModulaQRMatrix? { subject.flatMap { ModulaQRMatrix.make($0.url.absoluteString) } }

    var body: some View {
        NavigationStack {
            Group {
                switch mode {
                case .myCode: myCode
                case .scan: ModulaCodeScanner(accent: accent, onOpen: open)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .top, spacing: 0) {
                if subject != nil {
                    modeSwitch
                        .padding(.top, 4)
                        .padding(.bottom, 10)
                }
            }
            .background(background)
            .modulaSoftScrollEdge()
            .navigationTitle(mode == .scan ? "Scan" : "Modula Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", action: onDismiss)
                        .accessibilityIdentifier("modulaCode.done")
                }
            }
        }
        .onAppear {
            mode = subject == nil ? .scan : initialMode
            withAnimation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.8)) { appeared = true }
        }
        .task(id: subject?.avatarURL) { await loadAvatar() }
        .task(id: "\(styleRaw)-\(subject?.url.absoluteString ?? "")-\(avatarImage != nil)-\(scheme == .dark)") { renderExport() }
        .accessibilityIdentifier("modulaCode")
    }

    // MARK: Chrome

    private var background: some View {
        ZStack {
            ModulaPalette.resolve(app.appearance, scheme: scheme).canvas.opacity(0.55)
            ModulaAuroraBackground(tint: accent, secondary: nil, intensity: 0.6)
                .opacity(mode == .scan ? 0.25 : 0.5)
        }
        .ignoresSafeArea()
    }

    private var modeSwitch: some View {
        ModulaGlassGroup(spacing: 4) {
            HStack(spacing: 2) {
                ForEach(ModulaCodeMode.allCases) { item in
                    let selected = item == mode
                    Button {
                        guard item != mode else { return }
                        HapticEngine.shared.play(.selection)
                        withAnimation(reduceMotion ? nil : .snappy(duration: 0.32)) { mode = item }
                    } label: {
                        Label(item == .myCode ? "My Code" : "Scan", systemImage: item.symbol)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(selected ? Color.white : Color.primary)
                            .padding(.horizontal, 18)
                            .frame(height: 38)
                            .background {
                                if selected {
                                    Capsule().fill(accent.gradient)
                                        .matchedGeometryEffect(id: "code.mode", in: switchNamespace)
                                }
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
                    .accessibilityIdentifier("modulaCode.mode.\(item.rawValue)")
                }
            }
            .padding(4)
            .modulaGlass(in: Capsule(), interactive: false, specular: true)
        }
    }

    // MARK: My Code

    @ViewBuilder
    private var myCode: some View {
        if let subject, let matrix {
            ScrollView {
                VStack(spacing: 20) {
                    card(subject, matrix)
                        .scaleEffect(appeared || reduceMotion ? 1 : 0.94)
                        .opacity(appeared ? 1 : 0)
                    stylePicker
                    actions(subject)
                    Text(subject.kind == "Profile"
                         ? "Anyone who scans this opens your public Modula profile."
                         : "Anyone who scans this opens this \(subject.kind.lowercased()) on Modula.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
        } else {
            ContentUnavailableView("No code yet", systemImage: "qrcode", description: Text("Sign in to get your Modula Code."))
        }
    }

    private func card(_ subject: ModulaCodeSubject, _ matrix: ModulaQRMatrix) -> some View {
        VStack(spacing: 18) {
            HStack {
                ModulaWordmark(height: 18)
                Spacer()
                Text(subject.kind.uppercased())
                    .font(.caption2.weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(accent)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(accent.opacity(0.14), in: Capsule())
            }

            ModulaBrandedQRCode(matrix: matrix, style: style, accent: accent) {
                ModulaCodeCenterBadge(image: avatarImage, avatarURL: subject.avatarURL, initials: subject.initials)
            }
            .padding(18)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .shadow(color: accent.opacity(scheme == .dark ? 0.35 : 0.18), radius: 18, y: 8)
            .frame(maxWidth: 300)
            .accessibilityElement()
            .accessibilityLabel("Modula Code for \(subject.subtitle ?? subject.title)")
            .accessibilityHint("Scanning it opens \(subject.url.absoluteString)")
            .accessibilityIdentifier("modulaCode.qr")

            VStack(spacing: 4) {
                HStack(spacing: 5) {
                    Text(subject.title)
                        .font(.title3.weight(.bold))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    if subject.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(accent)
                            .accessibilityLabel("Verified account")
                    }
                }
                if let subtitle = subject.subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Text(subject.url.absoluteString.replacingOccurrences(of: "https://", with: ""))
                .font(.footnote.monospaced().weight(.semibold))
                .foregroundStyle(Color.primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Color(uiColor: .systemBackground).opacity(0.55), in: Capsule())
        }
        .padding(22)
        .modulaGlass(in: RoundedRectangle(cornerRadius: 34, style: .continuous), interactive: false, specular: true)
    }

    private var stylePicker: some View {
        HStack(spacing: 14) {
            ForEach(ModulaCodeStyle.allCases) { item in
                let (start, end) = item.modules(accent)
                Button {
                    HapticEngine.shared.play(.selection)
                    withAnimation(reduceMotion ? nil : .snappy) { styleRaw = item.rawValue }
                } label: {
                    VStack(spacing: 6) {
                        Circle()
                            .fill(LinearGradient(colors: [start, end], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 30, height: 30)
                            .overlay(Circle().stroke(Color.white.opacity(0.8), lineWidth: 2).padding(2))
                            .overlay(Circle().stroke(item == style ? accent : .clear, lineWidth: 2.5).padding(-4))
                        Text(item.title)
                            .font(.caption.weight(item == style ? .semibold : .regular))
                            .foregroundStyle(item == style ? .primary : .secondary)
                    }
                    .frame(minWidth: 52, minHeight: 56)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(item.title) colours")
                .accessibilityAddTraits(item == style ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 8)
        .modulaGlass(in: Capsule(), interactive: false)
    }

    private func actions(_ subject: ModulaCodeSubject) -> some View {
        ModulaGlassGroup(spacing: 10) {
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    if let exportImage {
                        ShareLink(
                            item: Image(uiImage: exportImage),
                            subject: Text(subject.title),
                            message: Text(subject.url.absoluteString),
                            preview: SwiftUI.SharePreview("Modula Code · \(subject.title)", image: Image(uiImage: exportImage))
                        ) {
                            actionLabel("Share Code", symbol: "square.and.arrow.up", prominent: true)
                        }
                        .buttonStyle(.plain)
                        .simultaneousGesture(TapGesture().onEnded { HapticEngine.shared.play(.lightImpact) })
                        .modulaAccentCTA()
                        .accessibilityIdentifier("modulaCode.shareImage")
                    }
                    Button { copyLink(subject) } label: {
                        actionLabel(copied ? "Copied" : "Copy Link", symbol: copied ? "checkmark" : "link", prominent: false)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.plain)
                    .modulaGlass(in: Capsule(), interactive: true, specular: true)
                    .accessibilityIdentifier("modulaCode.copy")
                }
                HStack(spacing: 10) {
                    Button { saveToPhotos() } label: {
                        actionLabel("Save Image", symbol: "arrow.down.to.line", prominent: false)
                    }
                    .buttonStyle(.plain)
                    .modulaGlass(in: Capsule(), interactive: true)
                    .disabled(exportImage == nil)
                    .accessibilityIdentifier("modulaCode.save")
                    ShareLink(item: subject.url) {
                        actionLabel("Share Link", symbol: "paperplane", prominent: false)
                    }
                    .buttonStyle(.plain)
                    .modulaGlass(in: Capsule(), interactive: true)
                    .accessibilityIdentifier("modulaCode.shareLink")
                }
            }
        }
    }

    private func actionLabel(_ title: String, symbol: String, prominent: Bool) -> some View {
        Label(title, systemImage: symbol)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .contentShape(Capsule())
    }

    // MARK: Actions

    private func copyLink(_ subject: ModulaCodeSubject) {
        UIPasteboard.general.string = subject.url.absoluteString
        HapticEngine.shared.play(.confirmation)
        ModulaToastCenter.shared.show("Link copied", symbol: "link", tone: .info)
        withAnimation(.snappy) { copied = true }
        Task {
            try? await Task.sleep(for: .seconds(1.4))
            withAnimation(.snappy) { copied = false }
        }
    }

    private func saveToPhotos() {
        guard let image = exportImage else { return }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                Task { @MainActor in
                    HapticEngine.shared.play(.warning)
                    ModulaToastCenter.shared.show("Allow Photos access in Settings to save", symbol: "photo.badge.exclamationmark", tone: .info)
                }
                return
            }
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }) { success, _ in
                Task { @MainActor in
                    HapticEngine.shared.play(success ? .saveComplete : .failure)
                    ModulaToastCenter.shared.show(success ? "Saved to Photos" : "Couldn't save image",
                                                  symbol: success ? "checkmark.circle" : "exclamationmark.triangle",
                                                  tone: .info)
                }
            }
        }
    }

    private func open(_ code: ModulaScannedCode) {
        switch code {
        case .modula(let url):
            onDismiss()
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                if !app.navigation.open(path: url.absoluteString) { ModulaLinkRouter.open(url, source: nil) }
            }
        case .web(let url):
            onDismiss()
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                ModulaLinkRouter.open(url, source: nil)
            }
        case .text(let text):
            UIPasteboard.general.string = text
            HapticEngine.shared.play(.confirmation)
            ModulaToastCenter.shared.show("Text copied", symbol: "doc.on.doc", tone: .info)
        }
    }

    private func loadAvatar() async {
        guard let url = subject?.avatarURL, url.scheme == "https" else { avatarImage = nil; return }
        guard let (data, _) = try? await URLSession.shared.data(from: url), let image = UIImage(data: data) else { return }
        avatarImage = image
    }

    @MainActor
    private func renderExport() {
        guard let subject, let matrix else { exportImage = nil; return }
        let card = ModulaCodeExportCard(subject: subject, matrix: matrix, style: style, accent: accent, centerImage: avatarImage)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        exportImage = renderer.uiImage
    }
}

/// Flat, render-safe card used for the shared/saved image (glass doesn't rasterise).
struct ModulaCodeExportCard: View {
    let subject: ModulaCodeSubject
    let matrix: ModulaQRMatrix
    var style: ModulaCodeStyle
    var accent: Color
    var centerImage: UIImage?

    var body: some View {
        VStack(spacing: 18) {
            ModulaWordmark(height: 24, onDark: true)
            ModulaBrandedQRCode(matrix: matrix, style: style, accent: accent) {
                ModulaCodeCenterBadge(image: centerImage, avatarURL: nil, initials: subject.initials)
            }
            .padding(20)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            .frame(width: 300, height: 300)
            VStack(spacing: 4) {
                Text(subject.title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                if let subtitle = subject.subtitle {
                    Text(subtitle)
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            Text("Scan with your camera to open on Modula")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 36)
        .frame(width: 400)
        .background(
            LinearGradient(colors: [accent.mix(with: .white, by: 0.08), accent.mix(with: .black, by: 0.5)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .environment(\.colorScheme, .dark)
    }
}

// MARK: - Scanner

/// Live camera scanner with viewfinder, torch, Photos import and a confirm card.
struct ModulaCodeScanner: View {
    var accent: Color
    var onOpen: (ModulaScannedCode) -> Void

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.openURL) private var openURL
    @State private var status = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var result: ModulaScannedCode?
    @State private var torchOn = false
    @State private var pulse = false
    @State private var photoItem: PhotosPickerItem?

    private var reduceMotion: Bool { ModulaEffectGate.reduceMotion(systemReduceMotion) }
    private var cameraReady: Bool {
        DataScannerViewController.isSupported && status == .authorized && DataScannerViewController.isAvailable
    }

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .fill(Color.black.opacity(0.85))
                if cameraReady {
                    ModulaDataScanner(paused: result != nil) { raw in
                        guard result == nil else { return }
                        HapticEngine.shared.play(.success)
                        withAnimation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.82)) {
                            result = ModulaScannedCode.classify(raw)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
                    viewfinder
                } else {
                    unavailable
                }
            }
            .aspectRatio(0.82, contentMode: .fit)
            .frame(maxWidth: 420)
            .overlay(alignment: .bottom) {
                if let result {
                    resultCard(result)
                        .padding(12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }

            controls
            Text(result == nil ? "Point your camera at a Modula Code or any QR." : "Code found")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .contentTransition(.opacity)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .task {
            if status == .notDetermined {
                let granted = await AVCaptureDevice.requestAccess(for: .video)
                status = granted ? .authorized : .denied
            }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await decodePhoto(item) }
        }
        .onDisappear { setTorch(false) }
        .accessibilityIdentifier("modulaCode.scanner")
    }

    private var viewfinder: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height) * 0.62
            ViewfinderCorners()
                .stroke(Color.white, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                .frame(width: side, height: side)
                .scaleEffect(pulse ? 1.04 : 1)
                .opacity(result == nil ? 1 : 0)
                .shadow(color: .black.opacity(0.3), radius: 6)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
                .onAppear {
                    guard !reduceMotion else { return }
                    withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { pulse = true }
                }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var unavailable: some View {
        VStack(spacing: 12) {
            Image(systemName: status == .denied || status == .restricted ? "camera.fill" : "qrcode.viewfinder")
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
            Text(status == .denied || status == .restricted ? "Camera access is off" : "Camera scanning isn't available here")
                .font(.headline)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text(status == .denied || status == .restricted
                 ? "Turn on camera access for Modula in Settings, or pick a photo of a code."
                 : "You can still scan a code from a photo.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
            if status == .denied || status == .restricted, let url = URL(string: UIApplication.openSettingsURLString) {
                Button("Open Settings") { openURL(url) }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18).frame(height: 40)
                    .modulaAccentCTA()
                    .buttonStyle(.plain)
            }
        }
        .padding(28)
    }

    private var controls: some View {
        ModulaGlassGroup(spacing: 14) {
            HStack(spacing: 14) {
                if cameraReady, Self.hasTorch {
                    ModulaGlassIconButton(
                        title: torchOn ? "Turn torch off" : "Turn torch on",
                        systemImage: torchOn ? "flashlight.on.fill" : "flashlight.off.fill",
                        size: 54,
                        tint: torchOn ? accent : nil,
                        foreground: torchOn ? .white : .primary
                    ) {
                        setTorch(!torchOn)
                        HapticEngine.shared.play(.lightImpact)
                    }
                    .accessibilityIdentifier("modulaCode.torch")
                }
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("From Photos", systemImage: "photo.on.rectangle")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 20)
                        .frame(height: 54)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .modulaGlass(in: Capsule(), interactive: true, specular: true)
                .accessibilityIdentifier("modulaCode.photos")
            }
        }
    }

    private func resultCard(_ code: ModulaScannedCode) -> some View {
        let (symbol, title, detail, action): (String, String, String, String) = {
            switch code {
            case .modula(let url): ("sparkles", "Modula link", url.path.isEmpty ? "modula.digital" : url.path, "Open")
            case .web(let url): ("safari", url.host ?? "Website", "Opens outside Modula", "Open")
            case .text(let text): ("text.quote", "Text", text, "Copy")
            }
        }()
        return VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(accent.gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline).lineLimit(1)
                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            ModulaGlassGroup(spacing: 8) {
                HStack(spacing: 8) {
                    Button {
                        HapticEngine.shared.play(.selection)
                        withAnimation(reduceMotion ? nil : .snappy) { result = nil }
                    } label: {
                        Text("Scan Again").font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                            .frame(maxWidth: .infinity).frame(height: 44).contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .modulaGlass(in: Capsule(), interactive: true)
                    Button {
                        HapticEngine.shared.play(.confirmation)
                        onOpen(code)
                        if case .text = code { withAnimation(.snappy) { result = nil } }
                    } label: {
                        Text(action).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).frame(height: 44).contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .modulaAccentCTA()
                    .accessibilityIdentifier("modulaCode.result.open")
                }
            }
        }
        .padding(14)
        .modulaGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous), interactive: false, specular: true)
        .accessibilityIdentifier("modulaCode.result")
    }

    private func decodePhoto(_ item: PhotosPickerItem) async {
        defer { photoItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
        if let raw = ModulaCodeDecoder.decode(image) {
            HapticEngine.shared.play(.success)
            withAnimation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.82)) {
                result = ModulaScannedCode.classify(raw)
            }
        } else {
            HapticEngine.shared.play(.warning)
            ModulaToastCenter.shared.show("No code found in that photo", symbol: "qrcode", tone: .info)
        }
    }

    private static var hasTorch: Bool { AVCaptureDevice.default(for: .video)?.hasTorch ?? false }

    private func setTorch(_ on: Bool) {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
            torchOn = on
        } catch {
            torchOn = false
        }
    }
}

private struct ViewfinderCorners: Shape {
    func path(in rect: CGRect) -> Path {
        let arm = rect.width * 0.2, radius = rect.width * 0.09
        var path = Path()
        func corner(_ origin: CGPoint, _ dx: CGFloat, _ dy: CGFloat) {
            path.move(to: CGPoint(x: origin.x, y: origin.y + dy * arm))
            path.addLine(to: CGPoint(x: origin.x, y: origin.y + dy * radius))
            path.addQuadCurve(to: CGPoint(x: origin.x + dx * radius, y: origin.y), control: origin)
            path.addLine(to: CGPoint(x: origin.x + dx * arm, y: origin.y))
        }
        corner(CGPoint(x: rect.minX, y: rect.minY), 1, 1)
        corner(CGPoint(x: rect.maxX, y: rect.minY), -1, 1)
        corner(CGPoint(x: rect.minX, y: rect.maxY), 1, -1)
        corner(CGPoint(x: rect.maxX, y: rect.maxY), -1, -1)
        return path
    }
}

/// VisionKit scanner without its own chrome; pauses while a result is on screen.
private struct ModulaDataScanner: UIViewControllerRepresentable {
    var paused: Bool
    var onCode: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        context.coordinator.onCode = onCode
        if paused {
            if scanner.isScanning { scanner.stopScanning() }
        } else if !scanner.isScanning {
            DispatchQueue.main.async { try? scanner.startScanning() }
        }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onCode: (String) -> Void
        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }
        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in addedItems {
                if case .barcode(let code) = item, let text = code.payloadStringValue, !text.isEmpty {
                    onCode(text)
                    return
                }
            }
        }
    }
}
