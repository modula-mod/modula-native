import Foundation
import SwiftUI

/// MOL-03 Living World: what the companion is feeling. Drives the stage pose, glow and copy.
enum MolibooEmotion: String, CaseIterable, Codable, Sendable {
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
        case .sleep: "Rest to regain energy"; case .play: "Fun and minigames"
        case .clean: "Keep them happy"; case .feed: "Give a treat"
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
        let h = max(0, now.timeIntervalSince(lastUpdate) / 3600)
        guard h > 0 else { return }
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

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults; self.now = now
    }

    static func key(_ id: String) -> String { "moliboo.care.v1.\(id)" }

    func state(for id: String) -> MolibooCareState {
        if let s = states[id] { return s }
        var s = MolibooCareState()
        if let d = defaults.data(forKey: Self.key(id)), let decoded = try? JSONDecoder().decode(MolibooCareState.self, from: d) { s = decoded }
        s.advance(to: now())
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

    func refresh(_ id: String) { var s = state(for: id); s.advance(to: now()); save(s, for: id) }

    private func save(_ s: MolibooCareState, for id: String) {
        states[id] = s
        if let d = try? JSONEncoder().encode(s) { defaults.set(d, forKey: Self.key(id)) }
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
