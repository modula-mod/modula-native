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

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                HStack(spacing: 8) {
                    Image(systemName: "m.circle.fill")
                        .font(.title2)
                        .foregroundStyle(app.appearance.accent.color)
                    Text("Modula")
                        .font(.title3.weight(.bold))
                }

                ModulaAvatar(initials: profile.initials, url: profile.avatarURL, size: 72)
                VStack(spacing: 4) {
                    Text(profile.displayName)
                        .font(.title2.weight(.bold))
                    Text("@\(profile.handle)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let image = Self.qrImage(for: profile.shareURL.absoluteString) {
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 220, height: 220)
                        .padding(16)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .accessibilityLabel("Modula Code for @\(profile.handle)")
                        .accessibilityHint("QR code opens the public profile link")
                }

                Text(profile.shareURL.absoluteString)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)

                Spacer()
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ModulaPalette.resolve(app.appearance, scheme: scheme).canvas.ignoresSafeArea())
            .navigationTitle("My Modula Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", action: onDismiss)
                }
            }
        }
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
