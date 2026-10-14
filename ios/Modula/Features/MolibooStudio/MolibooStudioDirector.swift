import Foundation
import Observation

/// MOL-03 lightweight animation scheduler for the Living Studio.
/// One idle loop + one-shot reactions, gated by cooldowns and by the motion policy. It only *drives* the scene controller
/// through its public API (clips, expressions, wobble/bounce); controller lifecycle/teardown stays with the controller.
@MainActor @Observable
final class MolibooStudioDirector {
    let controller: MolibooSceneController
    let personality: MolibooIdlePersonality
    private(set) var policy: MolibooMotionPolicy
    private(set) var reactionCount = 0
    private(set) var idleFired = 0
    private(set) var lastReaction = ""
    private(set) var napping = false
    private(set) var paused = false
    @ObservationIgnored private var gate = MolibooReactionGate()
    @ObservationIgnored private var idleTask: Task<Void, Never>?
    @ObservationIgnored private var pending: [Task<Void, Never>] = []
    @ObservationIgnored private var busyUntil: Double = 0
    @ObservationIgnored private var stopped = false
    @ObservationIgnored private let clock: () -> Double

    init(controller: MolibooSceneController, reduceMotion: Bool, clock: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime }) {
        self.controller = controller
        self.personality = .for(controller.descriptor)
        self.policy = MolibooMotionPolicy(reduceMotion: reduceMotion)
        self.clock = clock
    }

    func setReduceMotion(_ on: Bool) { policy = MolibooMotionPolicy(reduceMotion: on) }
    func setPaused(_ on: Bool) { paused = on }

    // MARK: Idle personality loop
    func start() {
        guard !stopped, idleTask == nil else { return }
        idleTask = Task { [weak self] in
            while !Task.isCancelled {
                let wait = self.map { Double.random(in: $0.personality.interval) } ?? 10
                try? await Task.sleep(for: .seconds(wait))
                guard !Task.isCancelled, let self else { return }
                self.fireIdle()
            }
        }
    }

    /// Exposed for tests: fires one idle personality beat if allowed now.
    @discardableResult
    func fireIdle() -> Bool {
        guard !stopped, !paused, !napping, policy.idlePersonality, clock() >= busyUntil,
              let clip = personality.clips.randomElement() else { return false }
        let ok = clip == "wobble" ? { controller.wobble(); return true }() : controller.playClip(clip)
        if ok { idleFired += 1; settle(after: 1.6) }
        return ok
    }

    // MARK: Reactions
    @discardableResult
    func request(_ r: MolibooReaction) -> MolibooReaction? {
        guard !stopped else { return nil }
        if napping, r == .tap { wake(); return .tap }
        guard let actual = gate.request(r, at: clock()) else { return nil }
        perform(actual)
        reactionCount += 1; lastReaction = actual.rawValue
        busyUntil = clock() + 2.0   // idle personality waits until the user's moment is over
        return actual
    }

    private func perform(_ r: MolibooReaction) {
        let c = controller, motion = policy.bodyMotion
        switch r {
        case .tap:
            if motion { c.react() } else { c.setExpression(.happy); settle(after: 1.2) }
        case .pet:
            c.setExpression(.happy)
            if motion, let clip = personality.clips.first { later(0.25) { $0.controller.playClip(clip) } }
            settle(after: 1.8)
        case .hop:
            if motion { if !(c.playClip("measured_hop") || c.playClip("exuberant_bounce")) { c.bounce() } } else { c.setExpression(.excited) }
            settle(after: 1.4)
        case .dance:
            if motion { c.wobble(); later(0.9) { $0.controller.bounce() }; later(1.6) { $0.controller.wobble() } } else { c.setExpression(.excited) }
            settle(after: 2.4)
        case .peekaboo:
            c.setExpression(.surprised); later(0.8) { $0.controller.setExpression(.happy) }; settle(after: 2.0)
        case .nap:
            napping = true; c.setExpression(.sleepy)
        case .dizzy:
            c.setExpression(.surprised); if motion { c.wobble() }; settle(after: 1.5)
        }
    }

    private func wake() {
        napping = false; lastReaction = "wake"; reactionCount += 1
        controller.setExpression(.surprised); later(0.6) { $0.controller.setExpression(.happy) }; settle(after: 1.6)
    }

    private func settle(after s: Double) {
        later(s) { me in if !me.napping { me.controller.setExpression(.idle) } }
    }

    private func later(_ s: Double, _ body: @escaping @MainActor (MolibooStudioDirector) -> Void) {
        pending.removeAll { $0.isCancelled }
        pending.append(Task { [weak self] in
            try? await Task.sleep(for: .seconds(s))
            guard !Task.isCancelled, let self, !self.stopped else { return }
            body(self)
        })
        if pending.count > 24 { pending.removeFirst(pending.count - 24) }
    }

    func stop() {
        stopped = true
        idleTask?.cancel(); idleTask = nil
        pending.forEach { $0.cancel() }; pending.removeAll()
    }
}
