import Foundation
import SwiftUI

/// MOL-03 Living World: what the companion is feeling. Drives the stage pose, glow and copy.
enum MolibooEmotion: String, CaseIterable, Codable, Sendable {
    /// Emoji the composer's attach button inserts (a real draft edit, not a fake attachment).
    var emoji: String {
        switch self {
        case .calm: "😌"; case .happy: "😊"; case .excited: "🤩"; case .curious: "🤔"
        case .thinking: "💭"; case .sleepy: "😴"; case .tired: "🥱"; case .sad: "🥺"
        }
    }

    case calm, happy, excited, curious, thinking, sleepy, tired, sad

    var label: String {
        switch self {
        case .calm: "Calm"; case .happy: "Happy"; case .excited: "Excited"; case .curious: "Curious"
        case .thinking: "Thinking"; case .sleepy: "Sleepy"; case .tired: "Low energy"; case .sad: "Lonely"
        }
    }
    var symbol: String {
        switch self {
        case .calm: "leaf.fill"; case .happy: "heart.fill"; case .excited: "sparkles"; case .curious: "eyes"
        case .thinking: "ellipsis.bubble.fill"; case .sleepy: "moon.zzz.fill"; case .tired: "battery.25"; case .sad: "cloud.drizzle.fill"
        }
    }
    /// Mapping onto the renderer's expression clips (3D stage).
    var expression: MolibooExpression {
        switch self {
        case .calm, .curious: .idle
        case .happy: .happy
        case .excited: .excited
        case .thinking: .surprised
        case .sleepy, .tired: .sleepy
        case .sad: .sad
        }
    }
    /// Breathing period in seconds; low energy breathes slower.
    var breathPeriod: Double {
        switch self {
        case .excited: 1.4; case .happy: 2.0; case .sleepy, .tired: 3.6; default: 2.6
        }
    }
}

/// Care activities. Each one is a real, persisted state change.
enum MolibooActivity: String, CaseIterable, Identifiable, Codable, Sendable {
    case sleep, play, clean, feed
    var id: String { rawValue }
    var title: String { switch self { case .sleep: "Sleep"; case .play: "Play"; case .clean: "Clean"; case .feed: "Feed" } }
    var subtitle: String {
        switch self {
        case .sleep: "Regain energy"
        case .play: "Fun & games"
        case .clean: "Fresh & clean"
        case .feed: "A little treat"
        }
    }
    var symbol: String { switch self { case .sleep: "moon.fill"; case .play: "gamecontroller.fill"; case .clean: "bubbles.and.sparkles.fill"; case .feed: "carrot.fill" } }
    var tint: Color {
        switch self {
        case .sleep: Color(red: 0.45, green: 0.45, blue: 0.85); case .play: Color(red: 0.36, green: 0.72, blue: 0.45)
        case .clean: Color(red: 0.35, green: 0.70, blue: 0.92); case .feed: Color(red: 0.96, green: 0.58, blue: 0.42)
        }
    }
}

/// Four lighting periods of the illustrated world.
enum MolibooTimeOfDay: String, CaseIterable, Codable, Sendable {
    case morning, afternoon, evening, night
    static func at(_ date: Date, calendar: Calendar = .current) -> MolibooTimeOfDay {
        switch calendar.component(.hour, from: date) {
        case 5..<12: .morning
        case 12..<17: .afternoon
        case 17..<21: .evening
        default: .night
        }
    }
    var sky: [Color] {
        switch self {
        case .morning: [Color(red: 0.99, green: 0.83, blue: 0.80), Color(red: 0.74, green: 0.86, blue: 0.98)]
        case .afternoon: [Color(red: 0.55, green: 0.80, blue: 0.98), Color(red: 0.86, green: 0.94, blue: 0.99)]
        case .evening: [Color(red: 0.98, green: 0.62, blue: 0.48), Color(red: 0.44, green: 0.33, blue: 0.62)]
        case .night: [Color(red: 0.06, green: 0.08, blue: 0.22), Color(red: 0.20, green: 0.18, blue: 0.42)]
        }
    }
    var ground: Color {
        switch self {
        case .morning: Color(red: 0.55, green: 0.78, blue: 0.48); case .afternoon: Color(red: 0.46, green: 0.74, blue: 0.40)
        case .evening: Color(red: 0.36, green: 0.48, blue: 0.36); case .night: Color(red: 0.12, green: 0.20, blue: 0.24)
        }
    }
    var isDark: Bool { self == .evening || self == .night }
    var particleName: String { switch self { case .morning: "petals"; case .afternoon: "motes"; case .evening: "fireflies"; case .night: "stars" } }
}

/// Persistent per-character care state. Values are 0…100 (bond is XP; level = 1 + xp/100).
struct MolibooCareState: Codable, Equatable, Sendable {
    var mood: Double = 80
    var energy: Double = 80
    var bondXP: Double = 0
    var cleanliness: Double = 80
    var hunger: Double = 30        // 0 = full, 100 = starving
    var asleep = false
    var lastUpdate: Date = .distantPast
    var lastActivity: MolibooActivity?

    /// Friendly floor for states saved by older builds (which could decay to 0%).
    mutating func normalizeForDisplay() {
        energy = max(energy, 35); mood = max(mood, 45)
    }
    var activityCount: [String: Int] = [:]

    var bondLevel: Int { 1 + Int(bondXP / 100) }

    var emotion: MolibooEmotion {
        if asleep { return .sleepy }
        if energy < 25 { return .tired }
        if mood < 35 || cleanliness < 25 || hunger > 80 { return .sad }
        if mood > 85 && energy > 60 { return .happy }
        return .calm
    }

    private static func clamp(_ v: Double) -> Double { min(100, max(0, v)) }

    /// Slow, wall-clock decay so leaving the app for a while is visible (but never punishing).
    mutating func advance(to now: Date) {
        guard lastUpdate != .distantPast else { lastUpdate = now; return }
        // Capped and floored: time away shows, but a pet never reads as neglected (0% / red).
        let h = min(12, max(0, now.timeIntervalSince(lastUpdate) / 3600))
        guard h > 0 else { return }
        // Floors apply to real time away (15 min+) only. Applying them on every sub-second tick meant energy could
        // never stay below 35, so "too tired to play" could never happen (MOL03WorldTests.testTooTiredToPlay).
        let away = h >= 0.25
        defer {
            if away {
                energy = max(energy, 35); mood = max(mood, 45)
                cleanliness = max(cleanliness, 35); hunger = min(hunger, 70)
            }
        }
        if asleep {
            energy = Self.clamp(energy + 25 * h)
            if energy >= 100 { asleep = false }
        } else {
            energy = Self.clamp(energy - 4 * h)
        }
        mood = Self.clamp(mood - 2 * h)
        cleanliness = Self.clamp(cleanliness - 3 * h)
        hunger = Self.clamp(hunger + 5 * h)
        lastUpdate = now
    }

    /// Applies an activity. Returns false when it can't happen right now (e.g. too tired to play).
    @discardableResult
    mutating func apply(_ a: MolibooActivity, at now: Date) -> Bool {
        advance(to: now)
        switch a {
        case .sleep:
            asleep.toggle()
            if !asleep { mood = Self.clamp(mood + 4) }
        case .play:
            guard !asleep, energy >= 10 else { return false }
            energy = Self.clamp(energy - 12); mood = Self.clamp(mood + 14); bondXP += 15; cleanliness = Self.clamp(cleanliness - 6)
        case .clean:
            guard !asleep else { return false }
            cleanliness = 100; mood = Self.clamp(mood + 6); bondXP += 6
        case .feed:
            guard !asleep else { return false }
            hunger = Self.clamp(hunger - 40); energy = Self.clamp(energy + 8); mood = Self.clamp(mood + 8); bondXP += 8
        }
        lastActivity = a
        activityCount[a.rawValue, default: 0] += 1
        return true
    }

    /// Quick interactions (Say hi, Give treat, petting) nudge mood and bond.
    mutating func interact(mood dm: Double, bond db: Double, at now: Date) {
        advance(to: now)
        guard !asleep else { return }
        mood = Self.clamp(mood + dm); bondXP += db
    }
}

/// Persistence for care state, one JSON blob per character in UserDefaults (no second character system:
/// the key is the registry / mascot kind id).
@MainActor
@Observable
final class MolibooCareStore {
    static let shared = MolibooCareStore()
    private let defaults: UserDefaults
    private let now: () -> Date
    private(set) var states: [String: MolibooCareState] = [:]
    /// Cooldowns / streak / moments per character (see `MolibooLifeState`).
    var lives: [String: MolibooLifeState] = [:]

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults; self.now = now
    }

    static func key(_ id: String) -> String { "moliboo.care.v1.\(id)" }

    func state(for id: String) -> MolibooCareState {
        if let s = states[id] { return s }
        var s = MolibooCareState()
        if let d = defaults.data(forKey: Self.key(id)), let decoded = try? JSONDecoder().decode(MolibooCareState.self, from: d) { s = decoded }
        s.advance(to: now())
        s.normalizeForDisplay()
        states[id] = s
        return s
    }

    @discardableResult
    func perform(_ a: MolibooActivity, for id: String) -> Bool {
        var s = state(for: id)
        let ok = s.apply(a, at: now())
        if ok { save(s, for: id) }
        return ok
    }

    func interact(_ id: String, mood: Double, bond: Double) {
        var s = state(for: id); s.interact(mood: mood, bond: bond, at: now()); save(s, for: id)
    }

    /// Applies a state change and saves it only if it happened.
    func adjustState(_ id: String, _ change: (inout MolibooCareState) -> Bool) -> Bool {
        var s = state(for: id)
        guard change(&s) else { return false }
        save(s, for: id)
        return true
    }

    func refresh(_ id: String) { var s = state(for: id); s.advance(to: now()); save(s, for: id) }

    private func save(_ s: MolibooCareState, for id: String) {
        states[id] = s
        if let d = try? JSONEncoder().encode(s) { defaults.set(d, forKey: Self.key(id)) }
    }
}

// MARK: - Care actions (single source of truth for Home tiles and the Care sheet)

/// The expanded, local-only care actions. Stat effects go through `MolibooCareState` (the same persisted state
/// the stage reads); cooldowns, streak and recent moments live in `MolibooLifeState` under a separate key, so
/// existing care data is never rewritten or reset.
enum MolibooCareAction: String, CaseIterable, Identifiable, Codable, Sendable {
    case feed, play, cuddle, nap, bath, dance, photo
    var id: String { rawValue }
    var title: String {
        switch self {
        case .feed: "Feed"; case .play: "Play"; case .cuddle: "Cuddle"; case .nap: "Nap"
        case .bath: "Bath"; case .dance: "Dance"; case .photo: "Photo"
        }
    }
    var symbol: String {
        switch self {
        case .feed: "carrot.fill"; case .play: "gamecontroller.fill"; case .cuddle: "heart.fill"; case .nap: "moon.zzz.fill"
        case .bath: "bubbles.and.sparkles.fill"; case .dance: "music.note"; case .photo: "camera.fill"
        }
    }
    /// What the action changes, as (need symbol, raises?) pairs: the tile draws these as tiny stat icons
    /// matching the status rings (heart = Mood, bolt = Energy, drop = Clean, fork = Full, star = Bond).
    var effectIcons: [(symbol: String, up: Bool)] {
        switch self {
        case .feed: [("fork.knife", true), ("bolt.fill", true)]
        case .play: [("heart.fill", true), ("bolt.fill", false)]
        case .cuddle: [("heart.fill", true), ("star.fill", true)]
        case .nap: [("bolt.fill", true)]
        case .bath: [("drop.fill", true)]
        case .dance: [("heart.fill", true), ("star.fill", true)]
        case .photo: []
        }
    }
    /// Short effect line (VoiceOver value; Photo's tile caption).
    var effect: String {
        switch self {
        case .feed: "Full · +Energy"; case .play: "+Mood · −Energy"; case .cuddle: "+Mood · +Bond"; case .nap: "Restores energy"
        case .bath: "Fresh & clean"; case .dance: "+Mood · +Bond"; case .photo: "Open camera"
        }
    }
    var tint: Color {
        switch self {
        case .feed: Color(red: 0.95, green: 0.55, blue: 0.30); case .play: Color(red: 0.30, green: 0.68, blue: 0.42)
        case .cuddle: Color(red: 0.92, green: 0.36, blue: 0.52); case .nap: Color(red: 0.42, green: 0.42, blue: 0.86)
        case .bath: Color(red: 0.24, green: 0.62, blue: 0.90); case .dance: Color(red: 0.62, green: 0.40, blue: 0.90)
        case .photo: Color(red: 0.20, green: 0.66, blue: 0.70)
        }
    }
    /// Seconds before it can be repeated (keeps it calm, not a tapping game).
    var cooldown: TimeInterval {
        switch self {
        case .feed: 10 * 60; case .play: 2 * 60; case .cuddle: 15; case .nap: 0
        case .bath: 15 * 60; case .dance: 90; case .photo: 0
        }
    }
    var reaction: MolibooEmotion {
        switch self {
        case .feed, .bath: .happy; case .play, .dance: .excited; case .cuddle: .calm; case .nap: .sleepy; case .photo: .curious
        }
    }
    var line: String {
        switch self {
        case .feed: "Yum, thank you!"; case .play: "That was so fun!"; case .cuddle: "Warm and cosy…"; case .nap: "Night night…"
        case .bath: "Squeaky clean!"; case .dance: "Look at my moves!"; case .photo: "Say cheese!"
        }
    }
}

extension MolibooEmotion {
    /// Mood-reactive speech bubble line.
    var speech: String {
        switch self {
        case .calm: "I'm right here."; case .happy: "Best day ever!"; case .excited: "Again! Again!"; case .curious: "Ooh, what's that?"
        case .thinking: "Hmm…"; case .sleepy: "Zzz…"; case .tired: "So sleepy…"; case .sad: "Stay with me?"
        }
    }
}

struct MolibooMoment: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var symbol: String
    var text: String
    var date: Date
}

/// Cooldowns, daily check-in streak and a short moments log. Decoded leniently (every field optional on disk).
struct MolibooLifeState: Codable, Equatable, Sendable {
    var lastUsed: [String: Date] = [:]
    var streak = 0
    var lastCheckIn: Date?
    var moments: [MolibooMoment] = []
    static let maxMoments = 12

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lastUsed = (try? c.decodeIfPresent([String: Date].self, forKey: .lastUsed)) ?? [:]
        streak = (try? c.decodeIfPresent(Int.self, forKey: .streak)) ?? 0
        lastCheckIn = try? c.decodeIfPresent(Date.self, forKey: .lastCheckIn)
        moments = (try? c.decodeIfPresent([MolibooMoment].self, forKey: .moments)) ?? []
    }

    func remaining(_ a: MolibooCareAction, at now: Date) -> TimeInterval {
        guard a.cooldown > 0, let last = lastUsed[a.rawValue] else { return 0 }
        return max(0, a.cooldown - now.timeIntervalSince(last))
    }
    func checkedIn(on now: Date, calendar: Calendar = .current) -> Bool {
        lastCheckIn.map { calendar.isDate($0, inSameDayAs: now) } ?? false
    }
    /// Streak shown today: a missed day breaks it.
    func currentStreak(at now: Date, calendar: Calendar = .current) -> Int {
        guard let last = lastCheckIn else { return 0 }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: last), to: calendar.startOfDay(for: now)).day ?? 99
        return days <= 1 ? streak : 0
    }
    mutating func log(_ symbol: String, _ text: String, at now: Date) {
        moments.insert(MolibooMoment(symbol: symbol, text: text, date: now), at: 0)
        if moments.count > Self.maxMoments { moments.removeLast(moments.count - Self.maxMoments) }
    }
}

enum MolibooActionOutcome: Equatable, Sendable {
    case done(String)
    case blocked(String)
}

extension MolibooCareState {
    /// Generic small stat change for actions without a dedicated activity (cuddle, dance).
    @discardableResult
    mutating func adjust(mood dm: Double, energy de: Double, bond db: Double, minEnergy: Double = 0, at now: Date) -> Bool {
        advance(to: now)
        guard !asleep, energy >= minEnergy else { return false }
        mood = min(100, max(0, mood + dm)); energy = min(100, max(0, energy + de)); bondXP += db
        return true
    }
    /// XP progress inside the current bond level (0…1) and XP still needed for the next level.
    var bondProgress: Double { bondXP.truncatingRemainder(dividingBy: 100) / 100 }
    var xpToNextLevel: Int { max(1, 100 - Int(bondXP.truncatingRemainder(dividingBy: 100))) }
}

extension MolibooCareStore {
    static func lifeKey(_ id: String) -> String { "moliboo.life.v1.\(id)" }

    func life(for id: String) -> MolibooLifeState {
        if let l = lives[id] { return l }
        let l = defaults.data(forKey: Self.lifeKey(id)).flatMap { try? JSONDecoder().decode(MolibooLifeState.self, from: $0) } ?? MolibooLifeState()
        lives[id] = l
        return l
    }

    private func saveLife(_ l: MolibooLifeState, for id: String) {
        lives[id] = l
        if let d = try? JSONEncoder().encode(l) { defaults.set(d, forKey: Self.lifeKey(id)) }
    }

    /// The one place every care action runs, from Home tiles or the Care sheet.
    func perform(_ a: MolibooCareAction, for id: String, name: String, now: Date = Date()) -> MolibooActionOutcome {
        var life = life(for: id)
        let left = life.remaining(a, at: now)
        if left > 0 { return .blocked("\(a.title) again in \(Self.short(left))") }
        let asleep = state(for: id).asleep
        if asleep && a != .nap && a != .photo { return .blocked("\(name) is asleep. Wake them first.") }
        let ok: Bool
        var text = "\(a.title) with \(name)"
        switch a {
        case .feed: ok = perform(.feed, for: id); text = "Fed \(name) a treat"
        case .play: ok = perform(.play, for: id); text = "Played with \(name)"
        case .bath: ok = perform(.clean, for: id); text = "Gave \(name) a bath"
        case .nap: ok = perform(.sleep, for: id); text = state(for: id).asleep ? "\(name) took a nap" : "\(name) woke up"
        case .cuddle: ok = adjustState(id) { $0.adjust(mood: 6, energy: 0, bond: 5, at: now) }; text = "Cuddled \(name)"
        case .dance: ok = adjustState(id) { $0.adjust(mood: 10, energy: -6, bond: 6, minEnergy: 10, at: now) }; text = "Danced with \(name)"
        case .photo: ok = true; text = "Took a photo of \(name)"
        }
        guard ok else { return .blocked("\(name) is too tired. Try a nap.") }
        life.lastUsed[a.rawValue] = now
        life.log(a.symbol, text, at: now)
        saveLife(life, for: id)
        return .done(a == .nap && !state(for: id).asleep ? "I'm awake!" : a.line)
    }

    /// Daily check-in: once per day, extends the streak (a missed day restarts it) and adds a little bond.
    @discardableResult
    func checkIn(_ id: String, name: String, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        var life = life(for: id)
        guard !life.checkedIn(on: now, calendar: calendar) else { return false }
        life.streak = life.currentStreak(at: now, calendar: calendar) + 1
        life.lastCheckIn = now
        life.log("flame.fill", "Day \(life.streak) check-in with \(name)", at: now)
        saveLife(life, for: id)
        _ = adjustState(id) { $0.adjust(mood: 4, energy: 0, bond: 10, at: now) || true }
        return true
    }

    static func short(_ t: TimeInterval) -> String {
        let s = Int(t.rounded(.up))
        return s >= 60 ? "\((s + 59) / 60)m" : "\(s)s"
    }
}

/// Chat: real states only. Replies come from Modula's intelligence façade; when the only provider is the
/// deterministic test provider (or none), the composer says the feature is unavailable instead of faking a reply.
enum MolibooChatPhase: Equatable, Sendable {
    case composing
    case submitting
    case awaiting
    case done(reply: String, provider: String)
    case failed(String)
    case unavailable(String)

    var key: String {
        switch self {
        case .composing: "compose"; case .submitting: "submit"; case .awaiting: "await"
        case .done: "done"; case .failed: "fail"; case .unavailable: "unavailable"
        }
    }
}

protocol MolibooChatBackend: Sendable {
    func reply(to text: String, as character: String) async throws -> (text: String, provider: String)
}

struct MolibooChatUnavailable: Error, Equatable { let reason: String }

/// Backed by `ModulaIntelligence` (`.generate`, local-only). The deterministic test provider is rejected.
struct MolibooIntelligenceChatBackend: MolibooChatBackend {
    let service: any ModulaIntelligenceService
    func reply(to text: String, as character: String) async throws -> (text: String, provider: String) {
        let prompt = "You are \(character), a small friendly Moliboo companion. Reply in one or two short, warm sentences.\nUser: \(text)"
        let req = IntelligenceRequest(capability: .generate, input: .string(prompt), privacy: .localOnly, source: .nativeFeature)
        let res: IntelligenceResponse
        do { res = try await service.execute(req) } catch let e as IntelligenceError {
            switch e {
            case .noEligibleProvider, .localProviderUnavailable, .capabilityUnsupported, .providerUnavailable, .providerNotFound, .remoteExecutionForbidden:
                throw MolibooChatUnavailable(reason: "No on-device model is available for chat yet.")
            default: throw e
            }
        }
        guard res.providerID != DeterministicLocalProvider.providerID else {
            throw MolibooChatUnavailable(reason: "No on-device model is available for chat yet.")
        }
        guard case .string(let s) = res.output, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MolibooChatUnavailable(reason: "The model returned no text.")
        }
        return (s, res.providerID)
    }
}

@MainActor
@Observable
final class MolibooChatModel {
    var draft = ""
    private(set) var phase: MolibooChatPhase = .composing
    private(set) var lastSent = ""
    private var task: Task<Void, Never>?
    let backend: (any MolibooChatBackend)?

    init(backend: (any MolibooChatBackend)?) { self.backend = backend }

    var isTyping: Bool { !draft.isEmpty && phase == .composing }
    var canSend: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && phase != .submitting && phase != .awaiting }

    func send(as character: String, onSent: @escaping () -> Void = {}) {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, canSend else { return }
        guard let backend else { phase = .unavailable("Chat isn't available in this build."); return }
        lastSent = text; draft = ""; phase = .submitting
        onSent()
        task?.cancel()
        task = Task { [weak self] in
            await Task.yield()
            self?.phase = .awaiting
            do {
                let r = try await backend.reply(to: text, as: character)
                guard !Task.isCancelled else { return }
                self?.phase = .done(reply: r.text, provider: r.provider)
            } catch let u as MolibooChatUnavailable {
                self?.phase = .unavailable(u.reason)
            } catch is CancellationError {
                self?.phase = .composing
            } catch {
                self?.phase = .failed("Couldn't reach your Moliboo. Try again.")
            }
        }
    }

    func reset() { task?.cancel(); phase = .composing }
    func cancel() { task?.cancel(); task = nil; if phase == .awaiting || phase == .submitting { phase = .composing } }
}
