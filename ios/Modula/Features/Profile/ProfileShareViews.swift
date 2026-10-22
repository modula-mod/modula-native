import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

/// Pre-system share sheet with profile preview, copy, share, and Modula Code.
struct ProfileShareSheet: View {
    let profile: ModulaProfile
    var onCopy: () -> Void
    var onShare: () -> Void
    var onShowCode: () -> Void
    var onDismiss: () -> Void

    @Environment(AppEnvironment.self) private var app

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 14) {
                    ModulaAvatar(initials: profile.initials, url: profile.avatarURL, size: 56)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(profile.displayName)
                            .font(.headline.weight(.semibold))
                        Text("@\(profile.handle)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(profile.shareURL.absoluteString)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(14)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(spacing: 10) {
                    shareButton(title: "Copy Link", symbol: "doc.on.doc", action: {
                        onCopy()
                        HapticEngine.shared.play(.lightImpact)
                    })
                    shareButton(title: "Share", symbol: "square.and.arrow.up", action: {
                        onShare()
                        HapticEngine.shared.play(.lightImpact)
                    })
                    shareButton(title: "Modula Code", symbol: "qrcode", action: {
                        onShowCode()
                        HapticEngine.shared.play(.selection)
                    })
                }

                Spacer()
            }
            .padding(20)
            .modulaSoftScrollEdge()
            .navigationTitle("Share Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", action: onDismiss)
                }
            }
        }
        .presentationDetents([.medium])
        .accessibilityIdentifier("profile.share.sheet")
    }

    private func shareButton(title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 48)
                .padding(.horizontal, 14)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

struct ModulaProfileCodeView: View {
    let profile: ModulaProfile
    var onDismiss: () -> Void

    @Environment(AppEnvironment.self) private var app
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var copied = false
    @State private var appeared = false

    private var accent: Color { app.appearance.accent.color }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    card
                        .scaleEffect(appeared || ModulaEffectGate.reduceMotion(systemReduceMotion) ? 1 : 0.94)
                        .opacity(appeared ? 1 : 0)
                    actions
                    Text("Anyone who scans this opens your public Modula profile.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(20)
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
            }
            .background(
                ZStack {
                    ModulaPalette.resolve(app.appearance, scheme: scheme).canvas
                    ModulaAuroraBackground(tint: accent, secondary: nil, intensity: 0.6)
                        .opacity(0.5)
                }
                .ignoresSafeArea()
            )
            .modulaSoftScrollEdge()
            .navigationTitle("Profile card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", action: onDismiss)
                }
            }
            .onAppear {
                withAnimation(ModulaEffectGate.reduceMotion(systemReduceMotion) ? nil : .spring(response: 0.45, dampingFraction: 0.8)) {
                    appeared = true
                }
            }
        }
        .accessibilityIdentifier("profile.modulaCode")
    }

    /// QR profile card in Modula Liquid Glass.
    private var card: some View {
        VStack(spacing: 16) {
            HStack(spacing: 8) {
                ModulaWordmark(height: 20)
                Spacer()
            }

            HStack(spacing: 14) {
                ModulaAvatar(initials: profile.initials, url: profile.avatarURL, size: 64, name: profile.displayName)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(profile.displayName)
                            .font(.title3.weight(.bold))
                            .lineLimit(1)
                        if profile.isVerified {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(accent)
                                .accessibilityLabel("Verified account")
                        }
                    }
                    Text("@\(profile.handle)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }

            if let image = Self.qrImage(for: Self.qrPayload(for: profile)) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 220, height: 220)
                    .padding(16)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                    .accessibilityLabel("Modula Code for @\(profile.handle)")
                    .accessibilityHint("QR code opens the public profile link")
            }

            Text(profile.shareURL.absoluteString)
                .font(.caption.monospaced().weight(.medium))
                .foregroundStyle(Color.primary.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Color(uiColor: .systemBackground).opacity(0.55), in: Capsule())
        }
        .padding(20)
        .modulaGlass(in: RoundedRectangle(cornerRadius: 32, style: .continuous), interactive: false, specular: true)
    }

    private var actions: some View {
        ModulaGlassGroup(spacing: 10) {
            HStack(spacing: 10) {
                ShareLink(item: profile.shareURL) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .modulaGlass(in: Capsule(), interactive: true, tint: accent, prominent: true, specular: true)
                .accessibilityIdentifier("profile.card.share")

                Button {
                    UIPasteboard.general.string = profile.shareURL.absoluteString
                    HapticEngine.shared.play(.confirmation)
                    withAnimation(.snappy) { copied = true }
                    Task {
                        try? await Task.sleep(for: .seconds(1.4))
                        withAnimation(.snappy) { copied = false }
                    }
                } label: {
                    Label(copied ? "Copied" : "Copy link", systemImage: copied ? "checkmark" : "link")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .modulaGlass(in: Capsule(), interactive: true, specular: true)
                .accessibilityIdentifier("profile.card.copy")
            }
        }
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
