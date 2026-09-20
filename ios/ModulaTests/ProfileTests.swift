import XCTest
@testable import Modula

final class ProfileTests: XCTestCase {
    func testProfileRoutesRoundTrip() {
        XCTAssertEqual(RouteParser.parse("/me"), .me(.overview))
        XCTAssertEqual(RouteSerializer.serialize(.me(.overview)), "/me")
        XCTAssertEqual(RouteParser.parse("/me/posts"), .me(.posts))
        XCTAssertEqual(RouteParser.parse("/profile/andrei.modula"), .profile("andrei.modula", .overview))
        XCTAssertEqual(
            RouteSerializer.serialize(.profile("andrei.modula", .overview)),
            "/profile/andrei.modula/overview"
        )
        for section in ProfileSection.allCases {
            let me = AppRoute.me(section)
            XCTAssertEqual(RouteParser.parse(RouteSerializer.serialize(me)), me)
            let other = AppRoute.profile("sophia", section)
            XCTAssertEqual(RouteParser.parse(RouteSerializer.serialize(other)), other)
        }
    }

    func testUniversalAndCustomSchemeProfileLinks() {
        XCTAssertEqual(RouteParser.parse("modula://profile/andrei.modula"), .profile("andrei.modula", .overview))
        XCTAssertEqual(
            RouteParser.parse("https://modula.digital/profile/andrei.modula/posts"),
            .profile("andrei.modula", .posts)
        )
        XCTAssertEqual(RouteParser.parse("https://modula.digital/me/edit"), .me(.edit))
    }

    func testProfileIdentityResolution() {
        XCTAssertEqual(ProfileIdentity.resolving(routeUserID: nil), .me)
        XCTAssertEqual(ProfileIdentity.resolving(routeUserID: ""), .me)
        XCTAssertEqual(ProfileIdentity.resolving(routeUserID: "andrei.modula"), .handle("andrei.modula"))
    }

    func testDecodeProfileDto() throws {
        let json: JSONValue = .object([
            "id": .string("profile-andrei"),
            "handle": .string("andrei.modula"),
            "displayName": .string("Andrei"),
            "kind": .string("person"),
            "bio": .string("Building Modula"),
            "pronouns": .string("he/him"),
            "avatarUri": .string("https://cdn.example/a.png"),
            "coverUri": .string("https://cdn.example/c.jpg"),
            "followerCount": .number(5),
            "followingCount": .number(4),
            "moduleCount": .number(14),
            "postCount": .number(5),
            "joinedAt": .string("2026-01-12T12:00:00.000Z"),
            "location": .object([
                "label": .string("United Kingdom"),
                "visibility": .string("public")
            ]),
            "website": .object([
                "id": .string("link-website"),
                "label": .string("Modula"),
                "url": .string("https://modula.digital"),
                "domain": .string("modula.digital"),
                "visibility": .string("public")
            ]),
            "links": .array([
                .object([
                    "id": .string("link-gh"),
                    "label": .string("GitHub"),
                    "url": .string("https://github.com/modula-labs"),
                    "domain": .string("github.com"),
                    "visibility": .string("public")
                ])
            ]),
            "featuredModuleIds": .array([.string("module-vault-notes")]),
            "identityClaims": .array([]),
            "isFollowing": .bool(false),
            "followsViewer": .bool(true),
            "version": .number(8),
            "focusStatus": .object([
                "id": .string("focused"),
                "label": .string("Focused"),
                "message": .string("Building"),
                "updatedAt": .string("2026-07-16T09:00:00.000Z")
            ])
        ])
        let profile = try XCTUnwrap(ProfilePayloadDecoder.profile(from: json))
        XCTAssertEqual(profile.handle, "andrei.modula")
        XCTAssertEqual(profile.displayName, "Andrei")
        XCTAssertEqual(profile.followerCount, 5)
        XCTAssertEqual(profile.postCount, 5)
        XCTAssertEqual(profile.pronouns, "he/him")
        XCTAssertEqual(profile.location?.label, "United Kingdom")
        XCTAssertEqual(profile.website?.url?.host, "modula.digital")
        XCTAssertEqual(profile.publicLinks.count, 2)
        XCTAssertEqual(profile.featuredModuleIds, ["module-vault-notes"])
        XCTAssertFalse(profile.isVerified)
        XCTAssertEqual(profile.followState, .none)
        XCTAssertEqual(profile.shareURL.absoluteString, "https://modula.digital/profile/andrei.modula")
        XCTAssertNotNil(profile.avatarURL)
        XCTAssertNotNil(profile.coverURL)
    }

    func testVerificationRequiresClaim() throws {
        let json: JSONValue = .object([
            "id": .string("p1"),
            "handle": .string("ada"),
            "displayName": .string("Ada"),
            "bio": .string(""),
            "followerCount": .number(0),
            "followingCount": .number(0),
            "moduleCount": .number(0),
            "postCount": .number(0),
            "joinedAt": .string("2026-01-01T00:00:00.000Z"),
            "identityClaims": .array([
                .object([
                    "kind": .string("modula"),
                    "label": .string("Verified"),
                    "verified": .bool(true)
                ])
            ]),
            "links": .array([]),
            "featuredModuleIds": .array([]),
            "isFollowing": .bool(false),
            "followsViewer": .bool(false),
            "focusStatus": .object([
                "id": .string("available"),
                "label": .string("Available"),
                "message": .string(""),
                "updatedAt": .string("2026-01-01T00:00:00.000Z")
            ])
        ])
        let profile = try XCTUnwrap(ProfilePayloadDecoder.profile(from: json))
        XCTAssertTrue(profile.isVerified)
    }

    func testCountFormattingAccessibility() {
        XCTAssertEqual(ProfileCountFormatter.compact(999), "999")
        XCTAssertTrue(ProfileCountFormatter.compact(1_200).contains("1"))
        XCTAssertTrue(ProfileCountFormatter.compact(1_200).uppercased().contains("K"))
        let voice = ProfileCountFormatter.accessibility(1_824, noun: "followers")
        XCTAssertTrue(voice.contains("1"))
        XCTAssertTrue(voice.contains("824") || voice.contains("1,824") || voice.contains("1824"))
        XCTAssertTrue(voice.lowercased().contains("followers"))
        XCTAssertFalse(voice.contains("K"))
    }

    func testShellChromeOwnVersusPushedProfile() {
        let meRoot = ShellChromePolicy.policy(for: .me(.overview), isTabRoot: true)
        XCTAssertTrue(meRoot.bottomBarVisible)
        XCTAssertTrue(meRoot.contextRailVisible)
        XCTAssertTrue(meRoot.shellAccessoryVisible)
        XCTAssertFalse(meRoot.showsBack)

        let pushed = ShellChromePolicy.policy(for: .profile("sophia", .overview), isTabRoot: false)
        XCTAssertTrue(pushed.bottomBarVisible)
        XCTAssertTrue(pushed.contextRailVisible)
        XCTAssertFalse(pushed.shellAccessoryVisible)
        XCTAssertTrue(pushed.showsBack)
    }

    @MainActor
    func testRailReplaceContextOrTopPreservesHomeStack() {
        let coordinator = NavigationCoordinator()
        coordinator.select(.home)
        coordinator.push(.profile("sophia", .overview))
        XCTAssertEqual(coordinator.selectedTab, .home)
        XCTAssertEqual(coordinator.currentRoute, .profile("sophia", .overview))
        coordinator.replaceContextOrTop(with: .profile("sophia", .posts))
        XCTAssertEqual(coordinator.selectedTab, .home)
        XCTAssertEqual(coordinator.currentRoute, .profile("sophia", .posts))
        XCTAssertFalse(coordinator.isAtTabRoot)
        coordinator.close()
        XCTAssertEqual(coordinator.currentRoute, .home(.following))
    }

    @MainActor
    func testHomeAuthorPushDoesNotStealProfileTab() {
        let coordinator = NavigationCoordinator()
        coordinator.select(.home)
        let homeRoot = coordinator.root(for: .home)
        coordinator.push(.profile("andrei.modula", .overview))
        XCTAssertEqual(coordinator.selectedTab, .home)
        XCTAssertEqual(coordinator.root(for: .profile), .me(.overview))
        XCTAssertEqual(coordinator.root(for: .home), homeRoot)
    }

    func testEditDraftFromProfile() {
        let profile = ModulaProfile(
            id: "p1",
            handle: "ada",
            displayName: "Ada",
            kind: "person",
            avatarURL: nil,
            coverURL: nil,
            coverColour: nil,
            bio: "Notes",
            pronouns: nil,
            location: nil,
            website: nil,
            followerCount: 0,
            followingCount: 0,
            moduleCount: 0,
            postCount: 0,
            joinedAt: nil,
            focusStatus: nil,
            identityClaims: [],
            links: [],
            featuredModuleIds: [],
            isFollowing: false,
            followsViewer: false,
            version: 3,
            visibility: .public
        )
        let draft = ProfileEditDraft.from(profile)
        XCTAssertEqual(draft.displayName, "Ada")
        XCTAssertEqual(draft.bio, "Notes")
        XCTAssertEqual(draft.expectedVersion, 3)
        XCTAssertEqual(draft.visibility, .public)
    }

    func testContextActionsOwnVersusOther() {
        let own = ProfileContextActions.moreMenu(isOwn: true)
        XCTAssertTrue(own.contains { $0.id == "edit" })
        XCTAssertTrue(own.contains { $0.id == "modula-code" })
        XCTAssertTrue(own.contains { $0.id == "preview-visitor" })
        XCTAssertFalse(own.contains { $0.id == "mute" })
        XCTAssertFalse(own.contains { $0.id == "block" })
        XCTAssertFalse(own.contains { $0.id == "report" })

        let other = ProfileContextActions.moreMenu(isOwn: false)
        XCTAssertTrue(other.contains { $0.id == "mute" })
        XCTAssertTrue(other.contains { $0.id == "block" })
        XCTAssertTrue(other.contains { $0.id == "report" })
        XCTAssertFalse(other.contains { $0.id == "edit" })
        XCTAssertFalse(other.contains { $0.id == "preview-visitor" })
    }

    func testMediaMenusExposeOwnerEdits() {
        let avatarOwn = ProfileContextActions.avatarMenu(isOwn: true, hasPhoto: true)
        XCTAssertTrue(avatarOwn.contains { $0.id == "view-photo" })
        XCTAssertTrue(avatarOwn.contains { $0.id == "change-photo" })
        XCTAssertTrue(avatarOwn.contains { $0.id == "edit-photo" })
        XCTAssertTrue(avatarOwn.contains { $0.id == "remove-photo" })

        let avatarEmpty = ProfileContextActions.avatarMenu(isOwn: true, hasPhoto: false)
        XCTAssertTrue(avatarEmpty.contains { $0.id == "change-photo" })
        XCTAssertFalse(avatarEmpty.contains { $0.id == "remove-photo" })

        let coverOwn = ProfileContextActions.coverMenu(isOwn: true, hasCover: true)
        XCTAssertTrue(coverOwn.contains { $0.id == "change-cover" })
        XCTAssertTrue(coverOwn.contains { $0.id == "reposition-cover" })
        XCTAssertTrue(coverOwn.contains { $0.id == "remove-cover" })

        let coverOther = ProfileContextActions.coverMenu(isOwn: false, hasCover: true)
        XCTAssertTrue(coverOther.contains { $0.id == "view-cover" })
        XCTAssertTrue(coverOther.contains { $0.id == "share" })
        XCTAssertFalse(coverOther.contains { $0.id == "reposition-cover" })
        XCTAssertFalse(coverOther.contains { $0.id == "change-cover" })
    }

    func testModulaCodePayloadIsCanonicalAndSecretFree() {
        let profile = ModulaProfile(
            id: "p1",
            handle: "andrei.modula",
            displayName: "Andrei",
            kind: "person",
            avatarURL: nil,
            coverURL: nil,
            coverColour: nil,
            bio: "",
            pronouns: nil,
            location: nil,
            website: nil,
            followerCount: 0,
            followingCount: 0,
            moduleCount: 0,
            postCount: 0,
            joinedAt: nil,
            focusStatus: nil,
            identityClaims: [],
            links: [],
            featuredModuleIds: [],
            isFollowing: false,
            followsViewer: false,
            version: 1,
            visibility: .public
        )
        let payload = ModulaProfileCodeView.qrPayload(for: profile)
        XCTAssertEqual(payload, "https://modula.digital/profile/andrei.modula")
        XCTAssertFalse(payload.lowercased().contains("token"))
        XCTAssertFalse(payload.lowercased().contains("authorization"))
        XCTAssertFalse(payload.lowercased().contains("password"))
        XCTAssertNotNil(ModulaProfileCodeView.qrImage(for: payload))
    }

    func testHapticSemanticsCoverProfileMap() {
        let required: [HapticSemantic] = [
            .selection, .navigation, .lightImpact, .mediumImpact, .confirmation,
            .success, .warning, .failure, .contextOpen, .reactionSelect,
            .dragThreshold, .drop, .followComplete, .saveComplete, .impact
        ]
        XCTAssertEqual(Set(HapticSemantic.allCases), Set(required))
    }

    @MainActor
    func testProfileAccessoryIsToolFocused() {
        let config = ShellAccessoryConfiguration.configuration(
            for: .me(.overview),
            activity: nil,
            signedIn: true
        )
        XCTAssertEqual(config.title, "Tools")
        XCTAssertEqual(Set(config.actions.map(\.id)), Set(["edit", "share", "more-profile"]))
        XCTAssertFalse(config.showsMore)
    }
}
