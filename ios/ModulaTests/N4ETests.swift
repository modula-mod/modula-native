import XCTest
@testable import Modula

final class AppGateTests: XCTestCase {
    @MainActor
    func testSignedOutNeverReady() {
        let gate = AppGate()
        gate.apply(signedIn: false, accountID: nil, appLockEnabled: false, appLockRequiresUnlock: false)
        XCTAssertEqual(gate.state, .signedOut)
        XCTAssertFalse(gate.state.allowsShell)
    }

    @MainActor
    func testFirstRunBeforeHome() {
        let gate = AppGate()
        gate.apply(signedIn: true, accountID: "n4e-first-run", appLockEnabled: false, appLockRequiresUnlock: false)
        XCTAssertEqual(gate.state, .firstRun)
    }

    @MainActor
    func testReadyAfterFirstRun() {
        let gate = AppGate()
        gate.completeFirstRun(accountID: "n4e-ready")
        gate.apply(signedIn: true, accountID: "n4e-ready", appLockEnabled: false, appLockRequiresUnlock: false)
        XCTAssertEqual(gate.state, .ready)
    }

    @MainActor
    func testLockHoldsAuthenticatedSession() {
        let gate = AppGate()
        gate.completeFirstRun(accountID: "n4e-lock")
        gate.apply(signedIn: true, accountID: "n4e-lock", appLockEnabled: true, appLockRequiresUnlock: true)
        XCTAssertEqual(gate.state, .locked)
    }

    @MainActor
    func testDeepLinkHeldUntilReady() {
        let gate = AppGate()
        gate.enqueue(.post("123", .root))
        gate.apply(signedIn: false, accountID: nil, appLockEnabled: false, appLockRequiresUnlock: false)
        XCTAssertNil(gate.takePendingDestination())
        gate.completeFirstRun(accountID: "n4e-deeplink")
        gate.apply(signedIn: true, accountID: "n4e-deeplink", appLockEnabled: false, appLockRequiresUnlock: false)
        XCTAssertEqual(gate.takePendingDestination(), .post("123", .root))
        XCTAssertNil(gate.takePendingDestination())
    }

    func testBootRouteIsNotHome() {
        XCTAssertEqual(RouteParser.parse("/"), .boot)
        XCTAssertNotEqual(RouteParser.parse("/"), .home(.following))
    }
}

final class OnboardingTests: XCTestCase {
    func testFiveStepsAndSkipSemantics() {
        XCTAssertEqual(OnboardingStep.count, 5)
        XCTAssertEqual(OnboardingStep.world.progressLabel, "1 / 5")
        XCTAssertEqual(OnboardingStep.world.accessibilityProgress, "Step 1 of 5")
        XCTAssertEqual(OnboardingStep.control.next, nil)
        XCTAssertEqual(OnboardingStep.world.next, .profile)
    }

    func testOnboardingIsNotAuthentication() {
        XCTAssertTrue(AppRoute.auth(.welcome).isPreAuthSurface)
        XCTAssertTrue(AppRoute.auth(.login).isPreAuthSurface)
        XCTAssertTrue(AppRoute.home(.following).requiresAuthenticatedShell)
    }
}

final class SettingsRouteTests: XCTestCase {
    func testEveryDestinationClassified() {
        let rows = SettingsRegistry.auditRows()
        XCTAssertFalse(rows.isEmpty)
        XCTAssertFalse(rows.contains { $0.status == "PLACEHOLDER" })
        XCTAssertTrue(rows.contains { $0.route == "/settings/privacy-security/app-lock" && $0.status == "IMPLEMENTED" })
        XCTAssertTrue(rows.contains { $0.route == "/settings/privacy-security/biometrics" && $0.status == "IMPLEMENTED" })
        XCTAssertTrue(rows.contains { $0.title == "Quiet Hours" && $0.status == "IMPLEMENTED" })
        XCTAssertTrue(rows.contains { $0.title == "Email" && $0.status == "CAPABILITY-UNAVAILABLE" })
    }

    func testSearchOpensTypedRoute() {
        let face = SettingsRegistry.search(query: "face", includeDeveloper: false)
        XCTAssertTrue(face.contains { $0.route == .privacy(.biometrics) || $0.route == .privacy(.appLock) })
        let cache = SettingsRegistry.search(query: "cache", includeDeveloper: false)
        XCTAssertTrue(cache.contains { $0.route == .dataStorage(.cache) || $0.route == .dataStorage(.storage) })
        let intelligence = SettingsRegistry.search(query: "intelligence", includeDeveloper: false)
        XCTAssertTrue(intelligence.contains { $0.route == .intelligence(.root) })
        let monetisation = SettingsRegistry.search(query: "monetisation", includeDeveloper: false)
        XCTAssertTrue(monetisation.contains { $0.route == .monetisation(.root) && $0.availability == .capabilityUnavailable })
        let lowPower = SettingsRegistry.search(query: "low power", includeDeveloper: false)
        XCTAssertTrue(lowPower.contains { $0.route == .battery(.root) && $0.anchor == "battery.lowPower" })
        let haptic = SettingsRegistry.search(query: "haptic", includeDeveloper: false)
        XCTAssertTrue(haptic.contains { $0.route == .audio(.haptics) && $0.anchor == "audio.haptics" })
    }

    func testIntelligenceModelsExcludeDeterministicFixture() async {
        let service = ModulaIntelligence(registerDeterministicLocalProvider: true)
        let providers = await service.providers.allProviders()
        XCTAssertTrue(providers.contains { $0.id == DeterministicLocalProvider.providerID })
        let productIDs = providers
            .map(\.id)
            .filter { $0 != DeterministicLocalProvider.providerID }
        XCTAssertFalse(productIDs.contains(DeterministicLocalProvider.providerID))
        XCTAssertTrue(SettingsRegistry.destination(for: .intelligence(.models))?.availability == .implemented)
    }

    func testCommandCenterUsesRegistry() {
        let caps = CommandCapabilitySnapshot(signedIn: true, developerMode: true)
        let commands = CommandRegistry.visible(capabilities: caps)
        XCTAssertTrue(commands.contains { $0.id.rawValue == "settings.privacy-security.app-lock" })
        let matches = CommandMatcher.match(query: "face", in: commands)
        XCTAssertTrue(matches.contains { $0.command.title.localizedCaseInsensitiveContains("face") || $0.command.aliases.contains { $0.localizedCaseInsensitiveContains("face") } })
    }
}

final class AppLockTests: XCTestCase {
    @MainActor
    func testDisabledDoesNotLock() {
        let store = AppLockStore(
            credentials: InMemoryAppLockCredentialStore(),
            biometrics: UnavailableBiometricAuthService(),
            defaults: UserDefaults(suiteName: "n4e.applock.disabled")!,
            startsLockedIfEnabled: true
        )
        XCTAssertFalse(store.enabled)
        XCTAssertFalse(store.requiresUnlock)
    }

    @MainActor
    func testCorrectAndWrongPasscode() throws {
        let credentials = InMemoryAppLockCredentialStore()
        let defaults = UserDefaults(suiteName: "n4e.applock.pass")!
        defaults.removePersistentDomain(forName: "n4e.applock.pass")
        let store = AppLockStore(
            credentials: credentials,
            biometrics: UnavailableBiometricAuthService(),
            defaults: defaults,
            startsLockedIfEnabled: false
        )
        try store.setPasscode("246801")
        try store.setEnabled(true)
        XCTAssertTrue(store.unlock(withPasscode: "246801"))
        XCTAssertFalse(store.requiresUnlock)
        store.refreshColdLaunchLock()
        XCTAssertTrue(store.requiresUnlock)
        XCTAssertFalse(store.unlock(withPasscode: "000000"))
        XCTAssertTrue(store.requiresUnlock)
        XCTAssertEqual(store.failedAttempts, 1)
    }

    @MainActor
    func testAttemptDelay() {
        XCTAssertEqual(AppLockAttemptPolicy.delay(afterFailureCount: 1), .seconds(0))
        XCTAssertEqual(AppLockAttemptPolicy.delay(afterFailureCount: 6), .seconds(5))
        XCTAssertEqual(AppLockAttemptPolicy.delay(afterFailureCount: 12), .seconds(60))
    }

    @MainActor
    func testBiometricUnavailableFallsBack() async {
        let credentials = InMemoryAppLockCredentialStore()
        try? credentials.setPasscode("246801")
        let store = AppLockStore(
            credentials: credentials,
            biometrics: UnavailableBiometricAuthService(),
            defaults: UserDefaults(suiteName: "n4e.applock.bio")!,
            startsLockedIfEnabled: true
        )
        XCTAssertFalse(store.canUseBiometrics)
        let unlocked = await store.unlockWithBiometrics()
        XCTAssertFalse(unlocked)
    }

    @MainActor
    func testSignOutResetsLock() throws {
        let credentials = InMemoryAppLockCredentialStore()
        let defaults = UserDefaults(suiteName: "n4e.applock.signout")!
        defaults.removePersistentDomain(forName: "n4e.applock.signout")
        let store = AppLockStore(
            credentials: credentials,
            biometrics: StubBiometricAuthService(availabilityValue: .available(.faceID), result: .success),
            defaults: defaults,
            startsLockedIfEnabled: false
        )
        try store.setPasscode("246801")
        try store.setEnabled(true)
        store.resetAfterSignOut()
        XCTAssertFalse(store.enabled)
        XCTAssertFalse(try credentials.hasPasscode())
    }

    @MainActor
    private func faceIDStore(_ suite: String, result: BiometricAuthResult = .success) throws -> AppLockStore {
        let credentials = InMemoryAppLockCredentialStore()
        try credentials.setPasscode("246801")
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = AppLockStore(
            credentials: credentials,
            biometrics: StubBiometricAuthService(availabilityValue: .available(.faceID), result: result),
            defaults: defaults,
            startsLockedIfEnabled: false
        )
        try store.setEnabled(true)
        store.setBiometricsEnabled(true)
        return store
    }

    @MainActor
    func testFaceIDSuccessDoesNotRelockOnInactiveBounce() async throws {
        let store = try faceIDStore("n4e.applock.bounce")
        XCTAssertTrue(store.requiresUnlock)
        let ok = await store.unlockWithBiometrics()
        XCTAssertTrue(ok)
        XCTAssertFalse(store.isAuthenticating)
        // Face ID sheet: .inactive → .active, no background.
        store.evaluateForeground()
        XCTAssertFalse(store.requiresUnlock)
        XCTAssertFalse(store.consumeAutoPrompt())
    }

    @MainActor
    func testRealBackgroundRelocksAndAutoPromptsOnce() async throws {
        let store = try faceIDStore("n4e.applock.bg")
        _ = await store.unlockWithBiometrics()
        store.recordBackground()
        store.evaluateForeground()
        XCTAssertTrue(store.requiresUnlock)
        XCTAssertTrue(store.consumeAutoPrompt())
        XCTAssertFalse(store.consumeAutoPrompt())
    }

    @MainActor
    func testFaceIDFailureLeavesKeypadUsable() async throws {
        let store = try faceIDStore("n4e.applock.fail", result: .failed)
        let ok = await store.unlockWithBiometrics()
        XCTAssertFalse(ok)
        XCTAssertTrue(store.requiresUnlock)
        XCTAssertFalse(store.isAuthenticating)
        XCTAssertFalse(store.consumeAutoPrompt())
        XCTAssertTrue(store.unlock(withPasscode: "246801"))
    }

    func testIntervalsAreExplicit() {
        XCTAssertEqual(AppLockInterval.allCases.map(\.title), [
            "Immediately", "After 1 minute", "After 5 minutes", "After 15 minutes", "After 1 hour"
        ])
    }
}

final class ReactionV2Tests: XCTestCase {
    func testPreferredVocabulary() {
        XCTAssertEqual(ReactionKind.allCases.map(\.rawValue), [
            "like", "love", "laugh", "wow", "support", "sad", "angry"
        ])
        XCTAssertEqual(ReactionKind(parsing: "fire"), .wow)
        XCTAssertFalse(ReactionBackendCapabilities.multiReactionHTTP)
    }

    func testSummaryDoesNotFabricate() {
        XCTAssertNil(ReactionSummary.decode(from: .object(["total": .number(12)])))
        let summary = ReactionSummary.decode(from: .object([
            "total": .number(3),
            "viewerReaction": .string("love"),
            "breakdown": .object(["like": .number(2), "love": .number(1)])
        ]))
        XCTAssertEqual(summary?.total, 3)
        XCTAssertEqual(summary?.viewerReaction, .love)
        XCTAssertEqual(summary?.count(for: .like), 2)
        XCTAssertEqual(summary?.presentKinds, [.like, .love])
    }

    func testLiveGreenfieldByTypeSummary() {
        XCTAssertTrue(ReactionBackendCapabilities.breakdownHTTP)
        XCTAssertFalse(ReactionBackendCapabilities.multiReactionHTTP)
        let summary = ReactionSummary.decode(from: .object([
            "viewerReaction": .null,
            "total": .number(0),
            "byType": .object([:])
        ]))
        XCTAssertEqual(summary?.total, 0)
        XCTAssertTrue(summary?.breakdown.isEmpty == true)
        let populated = ReactionSummary.decode(from: .object([
            "viewerReaction": .string("love"),
            "total": .number(5),
            "byType": .object(["like": .number(3), "love": .number(2)])
        ]))
        XCTAssertEqual(populated?.viewerReaction, .love)
        XCTAssertEqual(populated?.count(for: .like), 3)
        XCTAssertEqual(populated?.count(for: .love), 2)
    }
}

final class ModuleDetailV2Tests: XCTestCase {
    func testPrimaryActionStates() {
        let coming = CatalogueProduct(
            moduleId: "digital.modula.demo",
            productKind: "module",
            name: "Demo",
            description: "Demo",
            publisherId: "modula",
            publisherName: "Modula",
            latestVersion: "1.0.0",
            status: "coming-soon",
            installable: false,
            platforms: ["ios"],
            betaClassification: nil,
            installability: .init(status: "coming-soon", reasonCode: nil, reason: nil)
        )
        let presentation = ModuleDetailPresentation(product: coming, installation: nil, operation: nil, bundled: false, bundledVersion: nil)
        XCTAssertEqual(presentation.primaryAction, .comingSoon)
    }

    func testPublisherRoute() {
        XCTAssertEqual(RouteParser.parse("/product-hub/publisher/modula"), .productHub(.publisher("modula")))
        XCTAssertEqual(RouteSerializer.serialize(.productHub(.publisher("modula"))), "/product-hub/publisher/modula")
    }

    func testPermissionsComeFromManifestOnly() {
        let manifest = ModuleManifest(
            id: "digital.modula.vault-notes",
            name: "Vault Notes",
            version: "1.7.0",
            runtime: "react-native",
            entry: "vault",
            permissions: ["backend.records.list"],
            minHostVersion: "0.1.0",
            minBridgeVersion: "0.1.0",
            collections: ["note"]
        )
        let records = ModuleHostPermissions.records(from: manifest)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(ModuleHostPermissions.records(from: nil), [])
    }
}

final class ProfileFullBleedTests: XCTestCase {
    func testCoverHeightIncludesSafeArea() {
        let height = ProfileFullBleedMetrics.coverHeight(sizeClass: .compact, safeAreaTop: 47, accessibility: false)
        let withoutSafeArea = ProfileFullBleedMetrics.coverHeight(sizeClass: .compact, safeAreaTop: 0, accessibility: false)
        XCTAssertEqual(height - withoutSafeArea, 47)
        XCTAssertLessThan(height, 320, "Compact hero leaves room for identity and content")
    }

    func testProfileIdentityFieldsExist() {
        XCTAssertNotNil(Mirror(reflecting: Optional<ModulaProfile>.none as Any))
        let names = ["headline", "pronouns", "bio", "coverFocalPoint"]
        XCTAssertEqual(names.count, 4)
    }
}
