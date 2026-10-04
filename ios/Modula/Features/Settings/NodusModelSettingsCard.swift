import Observation
import SwiftUI

/// Owns the user-facing lifecycle of the downloadable Nodus model:
/// capability check → release lookup → verified download → install / delete,
/// plus the "Use Nodus for AI Chat" preference.
@MainActor @Observable
final class NodusModelManager {
    enum Phase: Equatable {
        case checking
        case unsupported(NodusDeviceCapability)
        case notInstalled(downloadBytes: Int64?)
        case unavailable(String)
        case downloading(Double)
        case installed(version: String, bytes: Int64)
        /// Developer builds ship Nodus R7 inside the app; it is never downloaded or removed.
        case bundled(name: String)
        case failed(String)
    }

    private(set) var phase: Phase = .checking
    var usesNodusForChat: Bool {
        didSet { NodusChatFeature.setUserPrefersNodus(usesNodusForChat, defaults: defaults) }
    }

    private let installer: NodusArtifactInstaller
    private let downloader: NodusModelDownloader
    private let endpoint: URL?
    private let capability: () -> NodusDeviceCapability
    private let defaults: UserDefaults
    private let onModelChanged: () async -> Void
    private var release: NodusModelRelease?
    private var downloadTask: Task<Void, Never>?

    init(
        installer: NodusArtifactInstaller,
        downloader: NodusModelDownloader,
        endpoint: URL?,
        capability: @escaping () -> NodusDeviceCapability = { NodusDeviceCapability.evaluate() },
        defaults: UserDefaults = .standard,
        onModelChanged: @escaping () async -> Void = {}
    ) {
        self.installer = installer
        self.downloader = downloader
        self.endpoint = endpoint
        self.capability = capability
        self.defaults = defaults
        self.onModelChanged = onModelChanged
        self.usesNodusForChat = NodusChatFeature.userPrefersNodus(defaults: defaults)
    }

    var isShipped: Bool { NodusChatFeature.isShipped() }

    func refresh() async {
        if case .downloading = phase { return }
        let capability = capability()
        if let bundled = Self.bundledModelName() { phase = .bundled(name: bundled); return }
        guard capability == .supported else { phase = .unsupported(capability); return }
        if let manifest = try? await installer.installedManifest() {
            let bytes = (try? await installer.installedSizeBytes()) ?? 0
            phase = .installed(version: manifest.nodusVersion, bytes: bytes)
            return
        }
        do {
            let release = try await downloader.fetchRelease(from: endpoint)
            self.release = release
            phase = .notInstalled(downloadBytes: release.totalBytes)
        } catch let error as NodusModelDownloadError {
            phase = .unavailable(error.userMessage)
        } catch {
            phase = .unavailable(NodusModelDownloadError.transport("").userMessage)
        }
    }

    func download() {
        guard downloadTask == nil else { return }
        if case .bundled = phase { return }
        phase = .downloading(0)
        downloadTask = Task { [weak self] in
            await self?.runDownload()
        }
    }

    func cancelDownload() {
        downloadTask?.cancel()
    }

    func deleteModel() async {
        try? await installer.deleteAcceptedArtifact()
        await onModelChanged()
        await refresh()
    }

    private func runDownload() async {
        defer { downloadTask = nil }
        do {
            let release: NodusModelRelease
            if let cached = self.release { release = cached }
            else { release = try await downloader.fetchRelease(from: endpoint) }
            self.release = release
            let manifest = try await downloader.install(release) { [weak self] value in
                Task { @MainActor in
                    guard let self, case .downloading = self.phase else { return }
                    self.phase = .downloading(value)
                }
            }
            await onModelChanged()
            let bytes = (try? await installer.installedSizeBytes()) ?? release.totalBytes
            phase = .installed(version: manifest.nodusVersion, bytes: bytes)
        } catch is CancellationError {
            phase = .notInstalled(downloadBytes: release?.totalBytes)
        } catch let error as NodusModelDownloadError {
            phase = .failed(error.userMessage)
        } catch {
            phase = .failed(NodusModelDownloadError.transport("").userMessage)
        }
    }

    /// The bundled experimental R7 artifact (Debug only; Release strips it at build time).
    static func bundledModelName(bundle: Bundle = .main) -> String? {
        guard let resources = bundle.resourceURL,
              let manifest = try? NodusExperimentalManifest.load(from: resources.appending(path: "Nodus/R7")) else {
            return nil
        }
        return manifest.displayName
    }

    static func formatted(bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

struct NodusModelSettingsCard: View {
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        @Bindable var models = app.nodusModels
        SettingsGroup(
            title: "Nodus",
            subtitle: "Modula’s on-device model. Runs entirely on this iPhone. AI Chat uses Apple Intelligence when Nodus isn’t installed."
        ) {
            VStack(alignment: .leading, spacing: 0) {
                status(models.phase)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("settings.intelligence.nodus.status")
                SettingsDivider()
                Toggle("Use Nodus for AI Chat", isOn: $models.usesNodusForChat)
                    .disabled(!models.isShipped)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("settings.intelligence.nodus.useForChat")
                actions(models)
            }
        }
        .task { await app.nodusModels.refresh() }
    }

    @ViewBuilder
    private func status(_ phase: NodusModelManager.Phase) -> some View {
        switch phase {
        case .checking:
            Label("Checking…", systemImage: "hourglass").foregroundStyle(.secondary)
        case .unsupported(let capability):
            Label(capability.displayName, systemImage: "iphone.slash").foregroundStyle(.secondary)
        case .notInstalled(let bytes):
            Label(
                bytes.map { "Not installed · \(NodusModelManager.formatted(bytes: $0)) download" } ?? "Not installed",
                systemImage: "arrow.down.circle"
            )
        case .unavailable(let message), .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
        case .downloading(let progress):
            VStack(alignment: .leading, spacing: 6) {
                Text("Downloading and verifying…")
                ProgressView(value: progress)
                    .accessibilityValue("\(Int(progress * 100)) percent")
            }
        case .bundled(let name):
            Label("\(name) · bundled with this developer build", systemImage: "shippingbox.fill")
        case .installed(let version, let bytes):
            Label("Installed · Nodus \(version) · \(NodusModelManager.formatted(bytes: bytes))", systemImage: "checkmark.seal.fill")
        }
    }

    @ViewBuilder
    private func actions(_ models: NodusModelManager) -> some View {
        switch models.phase {
        case .notInstalled, .failed:
            SettingsDivider()
            SettingsNavigationRow(title: "Download Nodus", subtitle: "Verified with SHA-256 before install", symbol: "arrow.down.circle") {
                models.download()
            }
            .accessibilityIdentifier("settings.intelligence.nodus.download")
        case .downloading:
            SettingsDivider()
            SettingsNavigationRow(title: "Cancel download", subtitle: nil, symbol: "xmark.circle") {
                models.cancelDownload()
            }
        case .installed:
            SettingsDivider()
            SettingsNavigationRow(title: "Open Nodus", subtitle: "Chat on this iPhone", symbol: "bubble.left.and.bubble.right") {
                PresentationCoordinator.present(.intelligenceChat, in: app.navigation)
            }
            SettingsDivider()
            SettingsNavigationRow(title: "Remove Nodus", subtitle: "Frees space. AI Chat switches to Apple Intelligence.", symbol: "trash") {
                Task { await models.deleteModel() }
            }
            .accessibilityIdentifier("settings.intelligence.nodus.remove")
        case .unavailable:
            SettingsDivider()
            SettingsNavigationRow(title: "Check again", subtitle: nil, symbol: "arrow.clockwise") {
                Task { await models.refresh() }
            }
        case .bundled:
            SettingsDivider()
            SettingsNavigationRow(title: "Open Nodus", subtitle: "Chat on this iPhone", symbol: "bubble.left.and.bubble.right") {
                PresentationCoordinator.present(.intelligenceChat, in: app.navigation)
            }
        case .checking, .unsupported:
            EmptyView()
        }
    }
}
