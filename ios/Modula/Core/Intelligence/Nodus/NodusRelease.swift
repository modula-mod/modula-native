import CryptoKit
import Foundation

// MARK: - Feature flag

/// Runtime switch for the shipped Nodus Chat surface.
///
/// On by default in every configuration. Two independent controls can turn it off:
/// - `ModulaNodusChatEnabled = NO` in Info.plist is the build/rollout kill switch.
/// - The user's "Use Nodus for AI Chat" preference (`modula.nodus.chat.enabled`).
/// Even when enabled, Release only routes to Nodus once a verified model is installed
/// and the device can run it; otherwise AI Chat falls back to Apple Foundation Models.
enum NodusChatFeature {
    static let infoPlistKey = "ModulaNodusChatEnabled"
    static let userPreferenceKey = "modula.nodus.chat.enabled"

    static func isShipped(bundle: Bundle = .main) -> Bool {
        (bundle.object(forInfoDictionaryKey: infoPlistKey) as? Bool) ?? true
    }

    static func userPrefersNodus(defaults: UserDefaults = .standard) -> Bool {
        (defaults.object(forKey: userPreferenceKey) as? Bool) ?? true
    }

    static func setUserPrefersNodus(_ enabled: Bool, defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: userPreferenceKey)
    }

    static func isEnabled(bundle: Bundle = .main, defaults: UserDefaults = .standard) -> Bool {
        isShipped(bundle: bundle) && userPrefersNodus(defaults: defaults)
    }

    /// Developer builds always show Nodus' own unavailable/not-installed states so the
    /// surface stays testable on Simulator. Release never shows a Nodus chat that cannot answer.
    static var showsUnavailableNodus: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }
}

enum NodusChatSurface: Sendable, Equatable {
    case nodus
    case appleFallback
}

enum NodusChatRouting {
    static func surface(
        featureEnabled: Bool,
        nodusAvailability: IntelligenceAvailability?,
        showsUnavailableNodus: Bool = NodusChatFeature.showsUnavailableNodus
    ) -> NodusChatSurface {
        guard featureEnabled else { return .appleFallback }
        if showsUnavailableNodus { return .nodus }
        return nodusAvailability == .available ? .nodus : .appleFallback
    }
}

// MARK: - Device capability

enum NodusDeviceCapability: Sendable, Equatable {
    case supported
    case insufficientMemory
    case unsupportedDevice

    /// Matches `MLXNodusRuntime`'s load floor for the 4-bit Nodus artifact.
    static let minimumMemoryBytes: UInt64 = 6 * 1_024 * 1_024 * 1_024

    static var runningOnSimulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

    static var mlxLinked: Bool {
        #if canImport(MLXLLM) && canImport(MLXLMCommon) && canImport(MLXHuggingFace) && canImport(Tokenizers)
        true
        #else
        false
        #endif
    }

    static func evaluate(
        physicalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory,
        isSimulator: Bool = runningOnSimulator,
        mlxAvailable: Bool = mlxLinked,
        minimumMemory: UInt64 = minimumMemoryBytes
    ) -> Self {
        // MLX aborts while building its Metal scheduler on Simulator.
        guard mlxAvailable, !isSimulator else { return .unsupportedDevice }
        guard physicalMemory >= minimumMemory else { return .insufficientMemory }
        return .supported
    }

    var displayName: String {
        switch self {
        case .supported: "Supported"
        case .insufficientMemory: "This iPhone doesn’t have enough memory for Nodus."
        case .unsupportedDevice: "Nodus can’t run on this device."
        }
    }
}

// MARK: - Model location

enum NodusModelStorage {
    static func defaultRoot() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appending(path: "Modula/Nodus/models")
    }

    static func acceptedDirectory(root: URL = defaultRoot()) -> URL { root.appending(path: "accepted") }
    static func downloadMarker(root: URL = defaultRoot()) -> URL { root.appending(path: "download.in-progress") }

    /// Synchronous presence check (no hashing) for labels; integrity is verified on install and load.
    static func hasInstalledModel(root: URL = defaultRoot(), bundle: Bundle = .main) -> Bool {
        if FileManager.default.fileExists(atPath: acceptedDirectory(root: root).appending(path: "nodus-manifest.json").path) {
            return true
        }
        guard let resources = bundle.resourceURL else { return false }
        return FileManager.default.fileExists(
            atPath: resources.appending(path: "Nodus/R7/\(NodusExperimentalManifest.fileName)").path
        )
    }
}

// MARK: - Release endpoint

/// Where the app learns about the current downloadable Nodus artifact.
///
/// Resolution order: user-defaults override (developer/testing), Info.plist
/// `ModulaNodusModelReleaseURL`, then the Greenfield API default
/// `<api>/v1/intelligence/nodus/releases/latest?platform=ios`.
enum NodusModelEndpoint {
    static let infoPlistKey = "ModulaNodusModelReleaseURL"
    static let overrideKey = "modula.nodus.modelReleaseURL"
    static let defaultPath = "v1/intelligence/nodus/releases/latest"

    static func resolve(
        apiBaseURL: URL?,
        bundle: Bundle = .main,
        defaults: UserDefaults = .standard
    ) -> URL? {
        if let raw = defaults.string(forKey: overrideKey), let url = secure(raw) { return url }
        if let raw = bundle.object(forInfoDictionaryKey: infoPlistKey) as? String, let url = secure(raw) { return url }
        guard let apiBaseURL, apiBaseURL.scheme == "https" else { return nil }
        var components = URLComponents(url: apiBaseURL.appending(path: defaultPath), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "platform", value: "ios"),
            URLQueryItem(name: "hostVersion", value: ModulaHost.version),
        ]
        return components?.url
    }

    private static func secure(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme == "https", url.host != nil else { return nil }
        return url
    }
}

// MARK: - Release descriptor

/// Signed-off release descriptor served by the registry. Every byte it points at is
/// verified twice: per-file SHA-256 here while downloading, then the full
/// `NodusArtifactInstaller.verify` (file set, per-file hashes, canonical artifact hash)
/// before atomic promotion into `accepted`.
struct NodusModelRelease: Sendable, Equatable, Codable {
    struct File: Sendable, Equatable, Codable {
        let path: String
        let url: URL
        let sha256: String
        let bytes: Int64
    }

    let schemaVersion: Int
    let nodusVersion: String
    let artifactHash: String
    let manifestURL: URL
    let manifestSHA256: String
    let files: [File]

    var totalBytes: Int64 { files.reduce(0) { $0 + $1.bytes } }

    func validate() throws {
        guard schemaVersion == 1 else { throw NodusModelDownloadError.unsupportedRelease }
        guard Self.isArtifactHash(artifactHash) else { throw NodusModelDownloadError.unsupportedRelease }
        guard Self.isHex64(manifestSHA256), manifestURL.scheme == "https" else {
            throw NodusModelDownloadError.unsupportedRelease
        }
        guard !files.isEmpty else { throw NodusModelDownloadError.unsupportedRelease }
        var seen = Set<String>()
        for file in files {
            guard Self.isSafeRelativePath(file.path), file.path != "nodus-manifest.json",
                  seen.insert(file.path).inserted,
                  file.url.scheme == "https",
                  Self.isHex64(file.sha256),
                  file.bytes > 0 else {
                throw NodusModelDownloadError.unsupportedRelease
            }
        }
    }

    static func isArtifactHash(_ value: String) -> Bool {
        value.hasPrefix("sha256:") && isHex64(String(value.dropFirst(7)))
    }

    static func isHex64(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy { $0.isHexDigit && !$0.isUppercase }
    }

    static func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\") else { return false }
        return !path.split(separator: "/", omittingEmptySubsequences: false).contains { $0.isEmpty || $0 == "." || $0 == ".." }
    }
}

enum NodusModelDownloadError: Error, Sendable, Equatable {
    case endpointNotConfigured
    case releaseUnavailable(Int)
    case unsupportedRelease
    case deviceUnsupported(NodusDeviceCapability)
    case insufficientStorage(required: Int64)
    case hashMismatch(String)
    case manifestMismatch
    case alreadyDownloading
    case transport(String)

    var userMessage: String {
        switch self {
        case .endpointNotConfigured, .releaseUnavailable:
            "Nodus isn’t available to download yet."
        case .unsupportedRelease, .manifestMismatch:
            "This Nodus release can’t be verified, so it wasn’t installed."
        case .deviceUnsupported(let capability):
            capability.displayName
        case .insufficientStorage:
            "Not enough free space to download Nodus."
        case .hashMismatch:
            "The download didn’t match its checksum, so it was discarded."
        case .alreadyDownloading:
            "Nodus is already downloading."
        case .transport:
            "The download didn’t finish. Check your connection and try again."
        }
    }
}

// MARK: - Transport

protocol NodusModelTransport: Sendable {
    func data(from url: URL) async throws -> (Data, Int)
    /// Downloads to a temporary file the caller then owns.
    func download(from url: URL) async throws -> URL
}

struct URLSessionNodusModelTransport: NodusModelTransport {
    let session: URLSession

    init(session: URLSession = .shared) { self.session = session }

    func data(from url: URL) async throws -> (Data, Int) {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    func download(from url: URL) async throws -> URL {
        let (temporary, response) = try await session.download(from: url)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            try? FileManager.default.removeItem(at: temporary)
            throw NodusModelDownloadError.releaseUnavailable(status)
        }
        // URLSession deletes its temp file when this call returns; move it somewhere we own.
        let owned = FileManager.default.temporaryDirectory.appending(path: "nodus-\(UUID().uuidString)")
        try FileManager.default.moveItem(at: temporary, to: owned)
        return owned
    }
}

// MARK: - Downloader

actor NodusModelDownloader {
    private let root: URL
    private let installer: NodusArtifactInstaller
    private let transport: any NodusModelTransport
    private let capability: @Sendable () -> NodusDeviceCapability
    private let availableCapacity: @Sendable (URL) -> Int64?
    private var running = false

    init(
        root: URL = NodusModelStorage.defaultRoot(),
        installer: NodusArtifactInstaller? = nil,
        transport: any NodusModelTransport = URLSessionNodusModelTransport(),
        capability: @escaping @Sendable () -> NodusDeviceCapability = { NodusDeviceCapability.evaluate() },
        availableCapacity: @escaping @Sendable (URL) -> Int64? = NodusModelDownloader.systemAvailableCapacity
    ) {
        self.root = root
        self.installer = installer ?? NodusArtifactInstaller(root: root)
        self.transport = transport
        self.capability = capability
        self.availableCapacity = availableCapacity
    }

    func fetchRelease(from endpoint: URL?) async throws -> NodusModelRelease {
        guard let endpoint else { throw NodusModelDownloadError.endpointNotConfigured }
        let (data, status) = try await mapTransport { try await self.transport.data(from: endpoint) }
        guard (200..<300).contains(status) else { throw NodusModelDownloadError.releaseUnavailable(status) }
        let release: NodusModelRelease
        do { release = try JSONDecoder().decode(NodusModelRelease.self, from: data) }
        catch { throw NodusModelDownloadError.unsupportedRelease }
        try release.validate()
        return release
    }

    /// Downloads, verifies, and atomically installs `release`. `progress` reports 0...1
    /// by verified bytes. Throws without touching the current `accepted` model on any failure.
    @discardableResult
    func install(
        _ release: NodusModelRelease,
        progress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws -> NodusModelManifest {
        let capability = capability()
        guard capability == .supported else { throw NodusModelDownloadError.deviceUnsupported(capability) }
        try release.validate()
        guard !running else { throw NodusModelDownloadError.alreadyDownloading }
        running = true
        defer { running = false }

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        Self.excludeFromBackup(root)
        // Staging + installer copy + previous model can coexist briefly.
        let required = release.totalBytes * 2
        if let capacity = availableCapacity(root), capacity < required {
            throw NodusModelDownloadError.insufficientStorage(required: required)
        }

        let marker = NodusModelStorage.downloadMarker(root: root)
        let staging = root.appending(path: "download-\(UUID().uuidString)")
        fileManager.createFile(atPath: marker.path, contents: Data(release.artifactHash.utf8))
        defer {
            try? fileManager.removeItem(at: staging)
            try? fileManager.removeItem(at: marker)
        }
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)

        let manifestFile = try await fetchVerified(release.manifestURL, sha256: release.manifestSHA256, label: "nodus-manifest.json")
        try fileManager.moveItem(at: manifestFile, to: staging.appending(path: "nodus-manifest.json"))
        let manifest: NodusModelManifest
        do {
            manifest = try JSONDecoder().decode(
                NodusModelManifest.self,
                from: Data(contentsOf: staging.appending(path: "nodus-manifest.json"))
            )
        } catch { throw NodusModelDownloadError.manifestMismatch }
        // The descriptor and the manifest must describe the same artifact, file for file.
        guard manifest.artifactHash == release.artifactHash,
              manifest.files == Dictionary(uniqueKeysWithValues: release.files.map { ($0.path, $0.sha256) }) else {
            throw NodusModelDownloadError.manifestMismatch
        }

        let total = max(release.totalBytes, 1)
        var completed: Int64 = 0
        progress(0)
        for file in release.files {
            try Task.checkCancellation()
            let downloaded = try await fetchVerified(file.url, sha256: file.sha256, label: file.path)
            let destination = staging.appending(path: file.path)
            try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.moveItem(at: downloaded, to: destination)
            completed += file.bytes
            progress(min(Double(completed) / Double(total), 1))
        }
        try Task.checkCancellation()
        do {
            return try await installer.installVerifiedArtifact(from: staging, expectedArtifactHash: release.artifactHash)
        } catch let error as NodusArtifactError {
            switch error {
            case .hashMismatch(let path): throw NodusModelDownloadError.hashMismatch(path)
            default: throw NodusModelDownloadError.manifestMismatch
            }
        }
    }

    private func fetchVerified(_ url: URL, sha256 expected: String, label: String) async throws -> URL {
        let file = try await mapTransport { try await self.transport.download(from: url) }
        do {
            guard try Self.sha256(file) == expected else { throw NodusModelDownloadError.hashMismatch(label) }
        } catch {
            try? FileManager.default.removeItem(at: file)
            throw error
        }
        return file
    }

    private func mapTransport<T: Sendable>(_ body: @Sendable () async throws -> T) async throws -> T {
        do { return try await body() }
        catch let error as NodusModelDownloadError { throw error }
        catch is CancellationError { throw CancellationError() }
        catch let error as URLError where error.code == .cancelled { throw CancellationError() }
        catch { throw NodusModelDownloadError.transport(String(describing: error)) }
    }

    static func sha256(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var digest = SHA256()
        while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty { digest.update(data: data) }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }

    @Sendable static func systemAvailableCapacity(_ url: URL) -> Int64? {
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    private static func excludeFromBackup(_ url: URL) {
        var target = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? target.setResourceValues(values)
    }
}
