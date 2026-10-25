import XCTest
@testable import Modula

/// MOL-03 Living World: emotion/activity/care/time-of-day/chat logic (no UI).
@MainActor
final class MOL03WorldTests: XCTestCase {
    private func defaults() -> UserDefaults {
        let name = "mol03world.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!; d.removePersistentDomain(forName: name); return d
    }

    func testTimeOfDayPeriods() {
        let cal = Calendar(identifier: .gregorian)
        func at(_ h: Int) -> MolibooTimeOfDay { MolibooTimeOfDay.at(cal.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: h))!, calendar: cal) }
        XCTAssertEqual(at(7), .morning); XCTAssertEqual(at(13), .afternoon); XCTAssertEqual(at(19), .evening)
        XCTAssertEqual(at(23), .night); XCTAssertEqual(at(3), .night)
        XCTAssertEqual(Set(MolibooTimeOfDay.allCases.map(\.particleName)), ["petals", "motes", "fireflies", "stars"])
    }

    func testCareActivitiesChangeStateAndPersist() {
        let d = defaults()
        var clock = Date(timeIntervalSince1970: 1_800_000_000)
        let store = MolibooCareStore(defaults: d, now: { clock })
        let s0 = store.state(for: "pebble")
        XCTAssertTrue(store.perform(.play, for: "pebble"))
        let s1 = store.state(for: "pebble")
        XCTAssertGreaterThan(s1.mood, s0.mood); XCTAssertLessThan(s1.energy, s0.energy); XCTAssertGreaterThan(s1.bondXP, s0.bondXP)
        XCTAssertTrue(store.perform(.feed, for: "pebble"))
        XCTAssertLessThan(store.state(for: "pebble").hunger, s1.hunger)
        XCTAssertTrue(store.perform(.clean, for: "pebble"))
        XCTAssertEqual(store.state(for: "pebble").cleanliness, 100)
        XCTAssertTrue(store.perform(.sleep, for: "pebble"))
        XCTAssertTrue(store.state(for: "pebble").asleep)
        XCTAssertEqual(store.state(for: "pebble").emotion, .sleepy)
        XCTAssertFalse(store.perform(.play, for: "pebble"), "can't play while asleep")
        // Sleeping over time refills energy and wakes up.
        clock = clock.addingTimeInterval(4 * 3600)
        store.refresh("pebble")
        XCTAssertEqual(store.state(for: "pebble").energy, 100, accuracy: 0.001)
        XCTAssertFalse(store.state(for: "pebble").asleep)
        // Persisted: a fresh store reads the same state; other characters are independent.
        let again = MolibooCareStore(defaults: d, now: { clock })
        XCTAssertEqual(again.state(for: "pebble").activityCount, store.state(for: "pebble").activityCount)
        XCTAssertEqual(again.state(for: "pip").activityCount, [:])
    }

    func testEmotionFromCareState() {
        var s = MolibooCareState(); s.energy = 10
        XCTAssertEqual(s.emotion, .tired)
        s.energy = 90; s.mood = 95
        XCTAssertEqual(s.emotion, .happy)
        s.mood = 20
        XCTAssertEqual(s.emotion, .sad)
        XCTAssertGreaterThan(MolibooEmotion.tired.breathPeriod, MolibooEmotion.happy.breathPeriod, "low energy breathes slower")
        for e in MolibooEmotion.allCases { _ = e.expression; XCTAssertFalse(e.label.isEmpty) }
    }

    func testTooTiredToPlay() {
        let store = MolibooCareStore(defaults: defaults())
        var s = store.state(for: "pip"); s.energy = 5
        XCTAssertFalse(s.apply(.play, at: Date()))
    }

    // MARK: Chat: real states only

    struct Echo: MolibooChatBackend { func reply(to t: String, as c: String) async throws -> (text: String, provider: String) { ("hi from model", "modula.nodus") } }
    struct Broken: MolibooChatBackend { func reply(to t: String, as c: String) async throws -> (text: String, provider: String) { throw URLError(.notConnectedToInternet) } }
    struct Gated: MolibooChatBackend { func reply(to t: String, as c: String) async throws -> (text: String, provider: String) { throw MolibooChatUnavailable(reason: "no model") } }

    private func run(_ b: (any MolibooChatBackend)?) async -> MolibooChatModel {
        let m = MolibooChatModel(backend: b)
        m.draft = "hello"
        var sent = false
        m.send(as: "Pebble") { sent = true }
        if b != nil { XCTAssertTrue(sent); XCTAssertEqual(m.phase, .submitting); XCTAssertEqual(m.draft, "") }
        for _ in 0..<50 where [.submitting, .awaiting].contains(m.phase) { try? await Task.sleep(for: .milliseconds(20)) }
        return m
    }

    func testChatDoneFailedUnavailable() async {
        let ok = await run(Echo())
        XCTAssertEqual(ok.phase, .done(reply: "hi from model", provider: "modula.nodus"))
        let bad = await run(Broken())
        XCTAssertEqual(bad.phase.key, "fail"); XCTAssertEqual(bad.lastSent, "hello")
        let gated = await run(Gated())
        XCTAssertEqual(gated.phase, .unavailable("no model"))
        let none = await run(nil)
        XCTAssertEqual(none.phase.key, "unavailable")
    }

    func testIntelligenceBackendRejectsDeterministicTestProvider() async {
        // Default app intelligence registers only the deterministic local provider unless Nodus/Apple are enabled:
        // that must surface as "unavailable", never as a fake reply.
        let backend = MolibooIntelligenceChatBackend(service: ModulaIntelligence())
        do {
            _ = try await backend.reply(to: "hi", as: "Pebble")
            XCTFail("deterministic provider must not produce a chat reply")
        } catch let e as MolibooChatUnavailable {
            XCTAssertFalse(e.reason.isEmpty)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testEmptyDraftCannotSend() {
        let m = MolibooChatModel(backend: Echo())
        m.draft = "   "
        XCTAssertFalse(m.canSend)
        m.send(as: "Pip")
        XCTAssertEqual(m.phase, .composing)
    }

    // MARK: Studio pose persistence

    func testStagePosePersists() {
        let d = defaults()
        var p = MolibooStagePose(); p.scale = 1.1; p.lift = 0.01
        p.save(for: "pebble", defaults: d)
        XCTAssertEqual(MolibooStagePose.load(for: "pebble", defaults: d), p)
        XCTAssertEqual(MolibooStagePose.load(for: "pip", defaults: d), MolibooStagePose())
    }

    func testCollectionShowsOnlyRegisteredCharacters() throws {
        throw XCTSkip("CORE-SIZE-01: retired Moliboo 3D USDZ/portrait/premium assets are no longer bundled; 2D is the only renderer")
        let ids = MolibooRegistry.available3D.map(\.id)
        XCTAssertFalse(ids.contains("bubbles"), "there is no Bubbles character")
        XCTAssertTrue(ids.contains("pebble"))
        for id in ids { XCTAssertNotNil(MolibooPortrait.image(for: id), id) }
    }
}

/// Expanded care actions: one store for Home and the Care sheet, cooldowns, streaks, moments, no data loss.
@MainActor
final class MolibooCareActionTests: XCTestCase {
    private func defaults() -> UserDefaults {
        let name = "molcare.\(UUID().uuidString)"
        return UserDefaults(suiteName: name)!
    }

    func testActionsChangeStatsRespectCooldownsAndLogMoments() {
        let d = defaults()
        let store = MolibooCareStore(defaults: d)
        let t0 = Date()
        let before = store.state(for: "pip")
        XCTAssertEqual(store.perform(.cuddle, for: "pip", name: "Pip", now: t0), .done(MolibooCareAction.cuddle.line))
        XCTAssertGreaterThan(store.state(for: "pip").bondXP, before.bondXP)
        if case .blocked = store.perform(.cuddle, for: "pip", name: "Pip", now: t0.addingTimeInterval(2)) {} else { XCTFail("cooldown") }
        XCTAssertEqual(store.perform(.cuddle, for: "pip", name: "Pip", now: t0.addingTimeInterval(20)), .done(MolibooCareAction.cuddle.line))
        XCTAssertEqual(store.life(for: "pip").moments.count, 2)
        // Persisted under its own key; the care state key is untouched in shape.
        let again = MolibooCareStore(defaults: d)
        XCTAssertEqual(again.life(for: "pip").moments.count, 2)
        XCTAssertEqual(again.state(for: "pip").bondXP, store.state(for: "pip").bondXP)
    }

    func testNapBlocksOtherActionsUntilWake() {
        let store = MolibooCareStore(defaults: defaults())
        _ = store.perform(.nap, for: "moss", name: "Moss")
        XCTAssertTrue(store.state(for: "moss").asleep)
        if case .blocked = store.perform(.dance, for: "moss", name: "Moss") {} else { XCTFail("asleep") }
        _ = store.perform(.nap, for: "moss", name: "Moss")
        XCTAssertFalse(store.state(for: "moss").asleep)
    }

    func testDailyCheckInStreak() {
        let store = MolibooCareStore(defaults: defaults())
        let cal = Calendar(identifier: .gregorian)
        let day1 = cal.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 10))!
        XCTAssertTrue(store.checkIn("pip", name: "Pip", now: day1, calendar: cal))
        XCTAssertFalse(store.checkIn("pip", name: "Pip", now: day1.addingTimeInterval(3600), calendar: cal))
        XCTAssertTrue(store.checkIn("pip", name: "Pip", now: day1.addingTimeInterval(86400), calendar: cal))
        XCTAssertEqual(store.life(for: "pip").streak, 2)
        XCTAssertTrue(store.checkIn("pip", name: "Pip", now: day1.addingTimeInterval(86400 * 4), calendar: cal))
        XCTAssertEqual(store.life(for: "pip").streak, 1, "a missed day restarts the streak")
    }

    func testLegacyCareStateStillDecodes() throws {
        let d = defaults()
        let legacy = #"{"mood":61,"energy":70,"bondXP":240,"cleanliness":50,"hunger":20,"asleep":false,"lastUpdate":0,"activityCount":{}}"#
        d.set(Data(legacy.utf8), forKey: MolibooCareStore.key("pip"))
        let s = MolibooCareStore(defaults: d).state(for: "pip")
        XCTAssertEqual(s.bondXP, 240)
        XCTAssertEqual(s.bondLevel, 3)
        XCTAssertEqual(s.xpToNextLevel, 60)
    }
}
