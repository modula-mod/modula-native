import SwiftUI

extension AppLockMethod: Identifiable {
    var id: String { rawValue }
}

struct AppLockView: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var digits = ""
    @State private var busy = false
    @State private var shakes = 0
    @State private var unlocking = false
    @State private var unlockedIcon = false
    @State private var appeared = false
    @State private var confirmsForgot = false
    /// Passcode is always one tap away, whatever the chosen method.
    @State private var forcePasscode = false
    @State private var hint: String?
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var compact: Bool {
        verticalSizeClass == .compact || dynamicTypeSize.isAccessibilitySize
    }

    private var lock: AppLockStore { app.appLock }
    private var method: AppLockMethod { forcePasscode ? .passcode : lock.settings.method }
    /// Decorative motion only when the user wants it and Reduce Motion is off.
    private var effects: Bool { lock.settings.effectsEnabled && !reduceMotion }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    content(now: context.date, cooldown: lock.remainingCooldown())
                }
                .padding(compact ? ModulaSpacing.md : ModulaSpacing.lg)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
            .scrollDisabled(method != .passcode)
        }
        .background { LockAmbientBackground(animated: effects).ignoresSafeArea() }
        .overlay { successBloom.allowsHitTesting(false) }
        // Glass blur dissolve into the app.
        .scaleEffect(unlocking && effects ? 1.1 : 1)
        .blur(radius: unlocking && effects ? 24 : 0)
        .opacity(unlocking ? 0 : 1)
        .accessibilityIdentifier("applock.lock")
        .confirmationDialog("Forgot how to unlock?", isPresented: $confirmsForgot, titleVisibility: .visible) {
            Button("Sign Out and Reset App Lock", role: .destructive) {
                Task { await app.performSignOut(resetAppLock: true) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Sign out to remove App Lock from this device, then sign back in. Drafts on this device are kept.")
        }
        .onAppear {
            withAnimation(effects ? .spring(response: 0.7, dampingFraction: 0.8) : .easeOut(duration: 0.2)) { appeared = true }
        }
        .task {
            if lock.consumeAutoPrompt() {
                await biometric()
            }
        }
    }

    @ViewBuilder
    private var successBloom: some View {
        if effects {
            Circle()
                .fill(RadialGradient(colors: [Color.accentColor.opacity(0.35), .clear], center: .center, startRadius: 0, endRadius: 220))
                .scaleEffect(unlocking ? 6 : 0.1)
                .opacity(unlocking ? 0 : (unlockedIcon ? 1 : 0))
        }
    }

    // MARK: Header

    private var displayName: String? {
        if let name = app.profile.ownProfile?.displayName, !name.isEmpty {
            return name.split(separator: " ").first.map(String.init) ?? name
        }
        if let handle = app.auth.account?.primaryHandle, !handle.isEmpty { return handle }
        return nil
    }

    private func greeting(_ date: Date) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        let part = switch hour {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        case 17..<22: "Good evening"
        default: "Hello, night owl"
        }
        if let displayName { return "\(part), \(displayName)" }
        return part
    }

    @ViewBuilder
    private func header(now: Date) -> some View {
        VStack(spacing: compact ? 6 : 10) {
            if lock.settings.showsGreeting {
                Text(now, format: .dateTime.hour().minute())
                    .font(.system(size: compact ? 52 : 72, weight: .semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .accessibilityAddTraits(.updatesFrequently)
                Text(now, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .offset(y: appeared ? 0 : -8)
            }
            ZStack(alignment: .bottomTrailing) {
                ModulaAvatar(
                    initials: ProfileTabAvatarRenderer.initials(profile: app.profile.ownProfile, account: app.auth.account),
                    url: app.profile.ownProfile?.avatarURL,
                    size: compact ? 48 : 64,
                    name: displayName
                )
                .padding(5)
                .modulaGlass(in: Circle(), interactive: false, specular: true)
                .scaleEffect(appeared ? 1 : (effects ? 0.6 : 1))
                Image(systemName: unlockedIcon ? "lock.open.fill" : "lock.fill")
                    .font(.caption.weight(.bold))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 26, height: 26)
                    .modulaGlass(in: Circle(), interactive: false, tint: unlockedIcon ? .green : nil, prominent: unlockedIcon)
                    .symbolEffect(.bounce, value: unlockedIcon)
            }
            .padding(.top, compact ? 4 : 10)
            .accessibilityHidden(true)
            if lock.settings.showsGreeting {
                Text(greeting(now))
                    .font(.title3.bold())
                    .multilineTextAlignment(.center)
            } else {
                HStack(spacing: 8) {
                    ModulaWordmark(height: compact ? 18 : 22, onDark: colorScheme == .dark)
                    Text("is locked").font(.title3.bold())
                }
            }
            Text(instruction)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .offset(y: appeared ? 0 : (effects ? -24 : 0))
        .opacity(appeared ? 1 : 0)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Modula is locked. \(instruction)")
        .accessibilityAddTraits(.isHeader)
    }

    private var instruction: String {
        switch method {
        case .passcode: "Enter your 6-digit Modula passcode."
        case .pattern: "Draw your unlock pattern."
        case .orbit: "Spin each ring to your glyph, then tap the centre."
        }
    }

    // MARK: Body

    @ViewBuilder
    private func content(now: Date, cooldown: Duration) -> some View {
        let coolingDown = cooldown > .seconds(0)
        let disabled = busy || coolingDown || unlocking
        VStack(spacing: compact ? ModulaSpacing.md : 22) {
            Spacer(minLength: 0)
            header(now: now)
            Group {
                switch method {
                case .passcode:
                    VStack(spacing: compact ? ModulaSpacing.md : 22) {
                        PasscodeDots(filled: digits.count, shakes: shakes,
                                     error: shakes > 0 && digits.isEmpty && lock.lastError != nil,
                                     ripple: effects)
                            .accessibilityLabel("Passcode, \(digits.count) of 6 digits entered")
                        PasscodeKeypad(value: $digits, disabled: disabled, keySize: compact ? 62 : 76) { complete in
                            busy = true
                            Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(reduceMotion ? 60 : 180))
                                attempt(complete)
                            }
                        }
                    }
                case .pattern:
                    PatternPad(hideTrail: lock.settings.hidesPatternTrail, disabled: disabled,
                               haptics: lock.settings.hapticsEnabled) { nodes in
                        guard nodes.count >= PatternLock.minimumDots else {
                            hint = "Connect at least \(PatternLock.minimumDots) dots."
                            lock.haptic(.warning)
                            withAnimation(effects ? .linear(duration: 0.45) : nil) { shakes += 1 }
                            return
                        }
                        hint = nil
                        attempt(PatternLock.encode(nodes))
                    }
                    .frame(maxWidth: compact ? 240 : 300)
                    .modifier(ShakeEffect(animatableData: CGFloat(shakes)))
                case .orbit:
                    OrbitDial(randomizes: true, disabled: disabled, haptics: lock.settings.hapticsEnabled,
                              actionLabel: "Unlock") { indices in
                        attempt(OrbitLock.encode(indices))
                    }
                    .frame(maxWidth: compact ? 260 : 320)
                    .modifier(ShakeEffect(animatableData: CGFloat(shakes)))
                }
            }
            .opacity(coolingDown ? 0.45 : 1)
            .scaleEffect(appeared ? 1 : (effects ? 0.94 : 1))
            .opacity(appeared ? 1 : 0)
            .transition(.blurReplace)
            statusLine(cooldown: cooldown, coolingDown: coolingDown)
            footerButtons
            Spacer(minLength: 0)
        }
        .animation(effects ? .spring(response: 0.45, dampingFraction: 0.85) : nil, value: method)
    }

    @ViewBuilder
    private func statusLine(cooldown: Duration, coolingDown: Bool) -> some View {
        if coolingDown {
            let seconds = Int((Double(cooldown.components.seconds) + Double(cooldown.components.attoseconds) / 1e18).rounded(.up))
            Label(seconds >= 60 ? "Locked for \(seconds / 60)m \(seconds % 60)s after too many attempts." : "Too many attempts. Try again in \(seconds)s.",
                  systemImage: "hourglass")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
                .monospacedDigit()
                .accessibilityIdentifier("applock.cooldown")
        } else if let message = hint ?? lock.lastError {
            VStack(spacing: 2) {
                Text(message)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.red)
                if lock.failedAttempts > 0 {
                    let left = lock.attemptsBeforeCooldown
                    Text(left > 0 ? "\(left) \(left == 1 ? "try" : "tries") left before a cooldown" : "Each wrong try adds a longer wait")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .multilineTextAlignment(.center)
            .accessibilityIdentifier("applock.error")
        }
    }

    private var footerButtons: some View {
        ModulaGlassGroup(spacing: 12) {
            HStack(spacing: 10) {
                if lock.canUseBiometrics {
                    Button {
                        lock.haptic(.lightImpact)
                        Task { await biometric() }
                    } label: {
                        Image(systemName: lock.biometricAvailability.kind.systemImage)
                            .font(.title3.weight(.semibold))
                            .frame(width: ModulaLayout.minimumTouch + 6, height: ModulaLayout.minimumTouch + 6)
                            .modulaGlass(in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(lock.isAuthenticating || unlocking)
                    .accessibilityLabel(lock.biometricAvailability.kind.unlockLabel)
                    .accessibilityIdentifier("applock.biometrics")
                }
                if lock.settings.method != .passcode {
                    Button {
                        lock.haptic(.selection)
                        hint = nil
                        forcePasscode.toggle()
                        digits = ""
                    } label: {
                        Text(forcePasscode ? "Use \(lock.settings.method.title)" : "Use Passcode")
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 14)
                            .frame(minHeight: ModulaLayout.minimumTouch)
                            .modulaGlass(in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("applock.switch-method")
                }
                Button {
                    lock.haptic(.selection)
                    confirmsForgot = true
                } label: {
                    Text("Forgot?")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .frame(minHeight: ModulaLayout.minimumTouch)
                        .modulaGlass(in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Forgot passcode? Sign out")
                .accessibilityIdentifier("applock.forgot")
            }
        }
        .opacity(appeared ? 1 : 0)
    }

    private func attempt(_ secret: String) {
        busy = true
        let ok = lock.unlock(withSecret: secret, method: method)
        busy = false
        if ok {
            lock.haptic(.success)
            finishUnlock()
        } else {
            lock.haptic(.failure)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { digits = "" }
            withAnimation(effects ? .linear(duration: 0.45) : nil) { shakes += 1 }
        }
    }

    /// Success morph: lock pops open, a soft bloom expands, then the glass dissolves into the app.
    private func finishUnlock() {
        digits = ""
        hint = nil
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { unlockedIcon = true }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(effects ? 220 : 0))
            withAnimation(.easeIn(duration: effects ? 0.38 : 0.15)) { unlocking = true }
            try? await Task.sleep(for: .milliseconds(effects ? 380 : 150))
            app.refreshLaunchState()
        }
    }

    private func biometric() async {
        let ok = await lock.unlockWithBiometrics()
        if ok {
            lock.haptic(.success)
            finishUnlock()
        } else if lock.lastError != nil {
            lock.haptic(.failure)
            withAnimation(effects ? .linear(duration: 0.45) : nil) { shakes += 1 }
        }
    }
}

/// Drifting aurora; adapts to light/dark, static with Reduce Motion, solid with Reduce Transparency.
private struct LockAmbientBackground: View {
    var animated: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let dark = colorScheme == .dark
        ZStack {
            Color(uiColor: .systemBackground)
            if !reduceTransparency {
                TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !animated)) { context in
                    let t = animated ? context.date.timeIntervalSinceReferenceDate : 0
                    Canvas(rendersAsynchronously: true) { ctx, size in
                        let blobs: [(Color, Double, Double, Double)] = [
                            (Color(red: 0.35, green: 0.25, blue: 0.95), 0.11, 0.0, 0.55),
                            (Color(red: 0.10, green: 0.65, blue: 0.95), 0.08, 2.1, 0.45),
                            (Color(red: 0.85, green: 0.30, blue: 0.75), 0.06, 4.2, 0.40),
                        ]
                        ctx.addFilter(.blur(radius: min(size.width, size.height) * 0.18))
                        for (color, speed, phase, scale) in blobs {
                            let x = size.width * (0.5 + 0.32 * cos(t * speed + phase))
                            let y = size.height * (0.45 + 0.28 * sin(t * speed * 1.3 + phase))
                            let r = size.width * scale
                            ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                                     with: .color(color.opacity(dark ? 0.45 : 0.28)))
                        }
                    }
                }
                LinearGradient(
                    colors: dark ? [.black.opacity(0.1), .black.opacity(0.55)] : [.white.opacity(0.05), .white.opacity(0.5)],
                    startPoint: .top, endPoint: .bottom
                )
            }
        }
        .drawingGroup()
        .accessibilityHidden(true)
    }
}

private struct ShakeEffect: GeometryEffect {
    var animatableData: CGFloat
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 10 * sin(animatableData * .pi * 6), y: 0))
    }
}

struct PasscodeDots: View {
    var filled: Int
    var shakes: Int = 0
    var error: Bool = false
    var ripple: Bool = false
    var body: some View {
        HStack(spacing: 16) {
            ForEach(0..<6, id: \.self) { index in
                let on = index < filled
                Circle()
                    .strokeBorder((error ? Color.red : .primary).opacity(on ? 0 : 0.4), lineWidth: 1.5)
                    .background {
                        Circle()
                            .fill(Color.primary)
                            .scaleEffect(on ? 1 : 0.2)
                            .opacity(on ? 1 : 0)
                            .shadow(color: Color.accentColor.opacity(on ? 0.5 : 0), radius: 6)
                    }
                    .frame(width: 14, height: 14)
                    .overlay {
                        // Ripple ring as each dot fills.
                        if ripple {
                            Circle()
                                .stroke(Color.accentColor, lineWidth: 1.5)
                                .keyframeAnimator(initialValue: 1.0, trigger: on) { view, t in
                                    view.scaleEffect(1 + 1.6 * t).opacity(on ? (1 - t) * 0.8 : 0)
                                } keyframes: { _ in
                                    LinearKeyframe(0.0, duration: 0.001)
                                    CubicKeyframe(1.0, duration: 0.45)
                                }
                                .allowsHitTesting(false)
                        }
                    }
                    .animation(.spring(response: 0.28, dampingFraction: 0.55), value: on)
            }
        }
        .modifier(ShakeEffect(animatableData: CGFloat(shakes)))
        .accessibilityIdentifier("applock.dots")
    }
}

/// Press feedback for glass keys: scale down plus a soft glow.
private struct GlassKeyStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .background {
                Circle()
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.14 : 0))
                    .blur(radius: 12)
                    .scaleEffect(1.15)
            }
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

struct PasscodeKeypad: View {
    @Binding var value: String
    var disabled: Bool = false
    var keySize: CGFloat = 72
    var onComplete: (String) -> Void

    private let rows: [[String]] = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["", "0", "delete"]]
    private let letters = ["2": "ABC", "3": "DEF", "4": "GHI", "5": "JKL", "6": "MNO", "7": "PQRS", "8": "TUV", "9": "WXYZ"]

    var body: some View {
        ModulaGlassGroup(spacing: 14) {
            VStack(spacing: 14) {
                ForEach(rows, id: \.self) { row in
                    HStack(spacing: 22) {
                        ForEach(row, id: \.self) { key in
                            keyButton(key)
                        }
                    }
                }
            }
        }
        .disabled(disabled)
        .accessibilityIdentifier("applock.keypad")
    }

    @ViewBuilder
    private func keyButton(_ key: String) -> some View {
        if key.isEmpty {
            Color.clear.frame(width: keySize, height: keySize)
        } else if key == "delete" {
            Button {
                guard !value.isEmpty else { return }
                HapticEngine.shared.play(.lightImpact)
                withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) { _ = value.removeLast() }
            } label: {
                Image(systemName: "delete.left.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.primary.opacity(value.isEmpty ? 0.35 : 0.9))
                    .frame(width: keySize * 0.78, height: keySize * 0.78)
                    .modulaGlass(in: Circle())
                    .frame(width: keySize, height: keySize)
                    .contentShape(Circle())
            }
            .buttonStyle(GlassKeyStyle())
            .accessibilityLabel("Delete")
        } else {
            Button {
                guard value.count < 6 else { return }
                HapticEngine.shared.play(.selection)
                withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) { value.append(key) }
                if value.count == 6 {
                    onComplete(value)
                }
            } label: {
                VStack(spacing: 0) {
                    Text(key)
                        .font(.title.weight(.semibold))
                    if let sub = letters[key] {
                        Text(sub)
                            .font(.caption2.weight(.semibold))
                            .tracking(1.5)
                            .foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle(.primary)
                .frame(width: keySize, height: keySize)
                .modulaGlass(in: Circle(), specular: true)
                .contentShape(Circle())
            }
            .buttonStyle(GlassKeyStyle())
            .accessibilityLabel(digitName(key))
        }
    }

    private func digitName(_ key: String) -> String {
        switch key {
        case "0": "Zero"
        case "1": "One"
        case "2": "Two"
        case "3": "Three"
        case "4": "Four"
        case "5": "Five"
        case "6": "Six"
        case "7": "Seven"
        case "8": "Eight"
        case "9": "Nine"
        default: key
        }
    }
}

struct PrivacyCoverView: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.92)
            VStack(spacing: 12) {
                Image(systemName: "lock.fill")
                    .font(.largeTitle)
                ModulaWordmark(height: 20, onDark: true)
            }
            .foregroundStyle(.white)
        }
        .ignoresSafeArea()
        .accessibilityLabel("Modula is hidden")
        .accessibilityIdentifier("applock.privacy-cover")
    }
}

struct PasscodeSetupView: View {
    var title: String
    var onComplete: (String) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var first = ""
    @State private var second = ""
    @State private var stage = 0
    @State private var error: String?

    var body: some View {
        VStack(spacing: 24) {
            Text(stage == 0 ? "Create a 6-digit passcode" : "Confirm passcode")
                .font(.title2.bold())
            PasscodeDots(filled: (stage == 0 ? first : second).count)
            PasscodeKeypad(value: Binding(
                get: { stage == 0 ? first : second },
                set: { if stage == 0 { first = $0 } else { second = $0 } }
            )) { value in
                if stage == 0 {
                    first = value
                    stage = 1
                    second = ""
                } else {
                    if value == first {
                        do {
                            try onComplete(value)
                            first = ""
                            second = ""
                            dismiss()
                        } catch {
                            self.error = "Could not store the passcode."
                            stage = 0
                            first = ""
                            second = ""
                        }
                    } else {
                        error = "Passcodes didn’t match."
                        stage = 0
                        first = ""
                        second = ""
                    }
                }
            }
            if let error {
                Text(error).foregroundStyle(.red).font(.footnote)
            }
            Button("Cancel") { dismiss() }
                .accessibilityLabel("Cancel")
        }
        .padding(24)
        .modulaSoftScrollEdge()
        .navigationTitle(title)
        .accessibilityIdentifier("applock.setup")
    }
}

// MARK: - Pattern

/// 3×3 dot grid. Drag through dots; passing over a skipped middle dot picks it up too.
struct PatternPad: View {
    var hideTrail = false
    var disabled = false
    var haptics = true
    var onComplete: ([Int]) -> Void

    @State private var nodes: [Int] = []
    @State private var finger: CGPoint?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let cell = side / 3
            let centers = (0..<9).map { CGPoint(x: cell * (CGFloat($0 % 3) + 0.5), y: cell * (CGFloat($0 / 3) + 0.5)) }
            ZStack {
                if !hideTrail, !nodes.isEmpty {
                    Path { path in
                        for (k, node) in nodes.enumerated() {
                            if k == 0 { path.move(to: centers[node]) } else { path.addLine(to: centers[node]) }
                        }
                        if let finger { path.addLine(to: finger) }
                    }
                    .stroke(Color.accentColor.opacity(0.85), style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                }
                ForEach(0..<9, id: \.self) { index in
                    let on = !hideTrail && nodes.contains(index)
                    Circle()
                        .fill(on ? Color.accentColor : Color.primary.opacity(0.4))
                        .frame(width: on ? 20 : 12, height: on ? 20 : 12)
                        .frame(width: cell * 0.5, height: cell * 0.5)
                        .modulaGlass(in: Circle(), interactive: false, specular: true)
                        .scaleEffect(on && !reduceMotion ? 1.1 : 1)
                        .animation(.spring(response: 0.25, dampingFraction: 0.55), value: on)
                        .position(centers[index])
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard !disabled else { return }
                        finger = value.location
                        for index in 0..<9 where !nodes.contains(index) {
                            let c = centers[index]
                            if hypot(c.x - value.location.x, c.y - value.location.y) < cell * 0.32 {
                                add(index)
                            }
                        }
                    }
                    .onEnded { _ in
                        let result = nodes
                        finger = nil
                        withAnimation(.easeOut(duration: 0.2)) { nodes = [] }
                        if !result.isEmpty, !disabled { onComplete(result) }
                    }
            )
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel("Pattern grid. Draw your pattern, or use the passcode button.")
        .accessibilityIdentifier("applock.pattern")
    }

    private func add(_ index: Int) {
        if let last = nodes.last {
            let (r1, c1, r2, c2) = (last / 3, last % 3, index / 3, index % 3)
            if (r1 + r2) % 2 == 0, (c1 + c2) % 2 == 0 {
                let mid = ((r1 + r2) / 2) * 3 + (c1 + c2) / 2
                if !nodes.contains(mid) { nodes.append(mid) }
            }
        }
        nodes.append(index)
        if haptics { HapticEngine.shared.play(.selection) }
    }
}

// MARK: - Orbit (Modula's own unlock)

/// Three concentric glass rings of glyphs, spun like a combination dial. The secret is one
/// glyph per ring lined up under the top marker. Rings start at random positions on every
/// unlock, so smudges and the motion someone sees over your shoulder reveal nothing.
struct OrbitDial: View {
    var randomizes: Bool
    var disabled = false
    var haptics = true
    var actionLabel: String
    var onSubmit: ([Int]) -> Void

    @State private var rotation: [Double] = [0, 0, 0]
    @State private var dragBase: Double = 0
    @State private var dragStartAngle: Double = 0
    @State private var activeRing: Int?
    @State private var lastIndex: [Int] = [0, 0, 0]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let radiiFraction: [CGFloat] = [0.84, 0.6, 0.38]
    private let bandFraction: [CGFloat] = [0.98, 0.72, 0.5]

    private func step(_ ring: Int) -> Double { 360 / Double(OrbitLock.rings[ring].count) }

    /// Glyph index currently under the top marker.
    private func indexAtMarker(_ ring: Int) -> Int {
        let count = OrbitLock.rings[ring].count
        let raw = Int((-rotation[ring] / step(ring)).rounded())
        return ((raw % count) + count) % count
    }

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let half = size / 2
            let center = CGPoint(x: half, y: half)
            ZStack {
                ForEach(0..<3, id: \.self) { ring in
                    Circle()
                        .fill(.clear)
                        .frame(width: size * bandFraction[ring], height: size * bandFraction[ring])
                        .modulaGlass(in: Circle(), interactive: false, specular: ring == 0)
                        .position(center)
                    let glyphs = OrbitLock.rings[ring]
                    ForEach(glyphs.indices, id: \.self) { i in
                        let angle = (Double(i) * step(ring) + rotation[ring] - 90) * .pi / 180
                        let r = half * radiiFraction[ring]
                        let selected = indexAtMarker(ring) == i
                        Image(systemName: glyphs[i])
                            .font(.system(size: [17, 15, 13][ring], weight: .semibold))
                            .foregroundStyle(selected ? Color.accentColor : Color.primary.opacity(0.7))
                            .scaleEffect(selected && !reduceMotion ? 1.25 : 1)
                            .position(x: center.x + r * cos(angle), y: center.y + r * sin(angle))
                    }
                }
                // Marker at 12 o'clock.
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: 4, height: size * 0.5 - size * 0.14)
                    .opacity(0.25)
                    .position(x: center.x, y: (size * 0.5 - size * 0.14) / 2 + size * 0.01)
                    .allowsHitTesting(false)
                Button {
                    guard !disabled else { return }
                    onSubmit((0..<3).map(indexAtMarker))
                } label: {
                    Image(systemName: "lock.open.fill")
                        .font(.title3.weight(.bold))
                        .frame(width: size * 0.26, height: size * 0.26)
                        .modulaGlass(in: Circle(), tint: .accentColor, specular: true)
                }
                .buttonStyle(.plain)
                .position(center)
                .accessibilityLabel(actionLabel)
                .accessibilityIdentifier("applock.orbit.submit")
            }
            .contentShape(Circle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { value in
                        guard !disabled else { return }
                        let start = value.startLocation
                        if activeRing == nil {
                            let d = hypot(start.x - center.x, start.y - center.y) / half
                            let ring: Int? = d > 0.72 ? 0 : d > 0.5 ? 1 : d > 0.28 ? 2 : nil
                            guard let ring else { return }
                            activeRing = ring
                            dragBase = rotation[ring]
                            dragStartAngle = atan2(start.y - center.y, start.x - center.x) * 180 / .pi
                        }
                        guard let ring = activeRing else { return }
                        let now = atan2(value.location.y - center.y, value.location.x - center.x) * 180 / .pi
                        var delta = now - dragStartAngle
                        if delta > 180 { delta -= 360 } else if delta < -180 { delta += 360 }
                        rotation[ring] = dragBase + delta
                        if abs(delta) > 170 { dragBase = rotation[ring]; dragStartAngle = now }
                        let idx = indexAtMarker(ring)
                        if idx != lastIndex[ring] {
                            lastIndex[ring] = idx
                            if haptics { HapticEngine.shared.play(.selection) }
                        }
                    }
                    .onEnded { _ in
                        guard let ring = activeRing else { return }
                        activeRing = nil
                        let snapped = (rotation[ring] / step(ring)).rounded() * step(ring)
                        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7)) { rotation[ring] = snapped }
                    }
            )
        }
        .aspectRatio(1, contentMode: .fit)
        .onAppear {
            guard randomizes else { return }
            rotation = (0..<3).map { Double(Int.random(in: 0..<OrbitLock.rings[$0].count)) * step($0) }
            lastIndex = (0..<3).map(indexAtMarker)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("applock.orbit")
    }
}

// MARK: - Pattern / Orbit setup (confirm twice)

struct LockSecretSetupView: View {
    var method: AppLockMethod
    var onComplete: (String) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var first: String?
    @State private var error: String?
    @State private var shakes = 0
    @State private var round = 0

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 6) {
                Text(first == nil ? "Create your \(method.title.lowercased())" : "Confirm your \(method.title.lowercased())")
                    .font(.title2.bold())
                Text(setupInstruction)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Group {
                switch method {
                case .pattern:
                    PatternPad { nodes in
                        guard nodes.count >= PatternLock.minimumDots else {
                            fail("Connect at least \(PatternLock.minimumDots) dots.")
                            return
                        }
                        submit(PatternLock.encode(nodes))
                    }
                    .frame(maxWidth: 280)
                default:
                    OrbitDial(randomizes: first != nil, actionLabel: first == nil ? "Set" : "Confirm") { indices in
                        submit(OrbitLock.encode(indices))
                    }
                    .frame(maxWidth: 320)
                }
            }
            .id(round)
            .modifier(ShakeEffect(animatableData: CGFloat(shakes)))
            if let error {
                Text(error).foregroundStyle(.red).font(.footnote)
            }
            Text("Your passcode always works as a backup.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Cancel") { dismiss() }
        }
        .padding(24)
        .navigationTitle(method.title)
        .accessibilityIdentifier("applock.setup.\(method.rawValue)")
    }

    private var setupInstruction: String {
        switch method {
        case .orbit: first == nil ? "Spin each ring so your chosen glyph sits under the top marker, then tap the centre." : "The rings were shuffled. Line up the same glyphs again."
        default: first == nil ? "Connect at least \(PatternLock.minimumDots) dots." : "Draw it once more."
        }
    }

    private func fail(_ message: String) {
        error = message
        HapticEngine.shared.play(.failure)
        withAnimation(.linear(duration: 0.45)) { shakes += 1 }
    }

    private func submit(_ value: String) {
        guard let first else {
            self.first = value
            error = nil
            round += 1
            HapticEngine.shared.play(.selection)
            return
        }
        if value == first {
            do {
                try onComplete(value)
                HapticEngine.shared.play(.success)
                dismiss()
            } catch {
                self.first = nil
                round += 1
                fail("Could not store it securely. Try again.")
            }
        } else {
            self.first = nil
            round += 1
            fail("They didn’t match. Start again.")
        }
    }
}

