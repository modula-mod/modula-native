import SwiftUI

extension AppLockMethod: Identifiable {
    var id: String { rawValue }
}

struct AppLockView: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @State private var digits = ""
    @State private var busy = false
    @State private var shakes = 0
    @State private var unlocking = false
    @State private var unlockedIcon = false
    @State private var appeared = false
    /// Set once the header has real, on-screen geometry. If it never does within 1.5s we
    /// switch to `safeMode`: a plain keypad with no scroll view, timeline or Metal effects.
    @State private var contentVisible = false
    @AppStorage("modula.lock.drapeBackdrop") private var drapeBackdrop = false
    @State private var safeMode = UserDefaults.standard.bool(forKey: AppLockView.pendingKey)
    /// Set when the animated lock appears, cleared once the app is unlocked. Still set on the
    /// next launch means the user got stuck last time: open straight into the plain keypad.
    static let pendingKey = "modula.applock.fancyPending"
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
        if safeMode {
            safeLock
        } else {
            fancyLock
        }
    }

    // MARK: Safe mode (guaranteed escape)

    private var safeLock: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 0)
            Image(systemName: "lock.fill").font(.title2.weight(.bold))
            Text(lock.isSlideOnly ? "Modula is locked" : "Enter your Modula passcode")
                .font(.title3.bold())
            if lock.isSlideOnly {
                Button("Unlock") {
                    if lock.unlockBySlide() { lock.haptic(.success); app.refreshLaunchState() }
                }
                .buttonStyle(.borderedProminent)
            } else if lock.settings.method == .pattern {
                PatternPad(hideTrail: lock.settings.hidesPatternTrail, disabled: busy,
                           haptics: lock.settings.hapticsEnabled) { nodes in
                    guard nodes.count >= PatternLock.minimumDots else { lock.haptic(.warning); shakes += 1; return }
                    safeAttempt(PatternLock.encode(nodes), .pattern)
                }
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: 260)
                .modifier(ShakeEffect(animatableData: CGFloat(shakes)))
            } else if lock.settings.method == .orbit {
                OrbitDial(randomizes: true, disabled: busy, haptics: lock.settings.hapticsEnabled,
                          actionLabel: "Unlock") { indices in
                    safeAttempt(OrbitLock.encode(indices), .orbit)
                }
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: 280)
            } else if lock.hasPasscode {
                PasscodeDots(filled: digits.count, shakes: shakes, error: lock.lastError != nil && digits.isEmpty, ripple: false)
                PasscodeKeypad(value: $digits, disabled: busy, keySize: 70) { complete in
                    let ok = lock.unlock(withPasscode: complete)
                    digits = ""
                    if ok { lock.haptic(.success); app.refreshLaunchState() } else { lock.haptic(.failure); shakes += 1 }
                }
            }
            if let message = lock.lastError {
                Text(message).font(.footnote.weight(.semibold)).foregroundStyle(.red)
            }
            HStack(spacing: 12) {
                if lock.canUseBiometrics {
                    Button {
                        Task { if await lock.unlockWithBiometrics() { lock.haptic(.success); app.refreshLaunchState() } }
                    } label: {
                        Label(lock.biometricAvailability.kind.unlockLabel, systemImage: lock.biometricAvailability.kind.systemImage)
                    }
                    .buttonStyle(.bordered)
                }
                Button("Forgot?") { confirmsForgot = true }
                    .buttonStyle(.bordered)
            }
            Spacer(minLength: 0)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .accessibilityIdentifier("applock.safe")
        .confirmationDialog("Forgot how to unlock?", isPresented: $confirmsForgot, titleVisibility: .visible) {
            Button("Sign Out and Reset App Lock", role: .destructive) {
                Task { await app.performSignOut(resetAppLock: true) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .task { await autoPromptIfNeeded() }
    }

    private func safeAttempt(_ secret: String, _ m: AppLockMethod) {
        if lock.unlock(withSecret: secret, method: m) {
            lock.haptic(.success); app.refreshLaunchState()
        } else {
            lock.haptic(.failure); shakes += 1
        }
    }

    private var fancyLock: some View {
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
            .scrollDisabled(method != .passcode || lock.isSlideOnly)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if lock.isSlideOnly {
                SlideToUnlockTrack(disabled: unlocking, haptics: lock.settings.hapticsEnabled) {
                    if lock.unlockBySlide() {
                        lock.haptic(.success)
                        finishUnlock()
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
        }
        // Fail-safe: a solid base under the shader so a failed/slow Metal effect still leaves
        // a normal background, never a blank or garbled screen.
        // Backdrop only: lock content renders independently of it.
        .background {
            if drapeBackdrop {
                SpectralDrapeView(interactive: false).ignoresSafeArea()
            } else {
                LockShaderAurora(animated: effects).ignoresSafeArea()
            }
        }
        .background { Color(uiColor: .systemBackground).ignoresSafeArea() }
        .overlay { successBloom.allowsHitTesting(false) }
        // No full-screen shader wrappers around the lock content (ripple/dissolve wrapped the
        // whole keypad in GeometryReader + TimelineView + layer effects; on device only the
        // aurora was visible). Plain fade into the app.
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
        .task {
            // Guaranteed escape: no on-screen lock content after 1.5s → plain safe mode.
            try? await Task.sleep(for: .milliseconds(1500))
            print("[AppLock] watchdog contentVisible=\(contentVisible) locked=\(lock.isLocked) slideOnly=\(lock.isSlideOnly) method=\(lock.settings.method)")
            if !contentVisible { safeMode = true }
        }
        .onAppear {
            print("[AppLock] fancy onAppear")
            UserDefaults.standard.set(true, forKey: AppLockView.pendingKey)
            // Content is always visible; `appeared` only drives a small entry motion.
            withAnimation(effects ? .spring(response: 0.7, dampingFraction: 0.8) : .easeOut(duration: 0.2)) { appeared = true }
        }
        .task {
            appeared = true
            await autoPromptIfNeeded()
        }
        // Cold launch can build this view while the scene is still inactive; Face ID can't
        // present then, so try again once the app is actually active.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                appeared = true
                Task { await autoPromptIfNeeded() }
            }
        }
        // Re-locked while a previous unlock animation was in flight: reset so the keypad is
        // usable again (a stuck `unlocking` dissolved the whole lock content).
        .onChange(of: lock.isLocked) { _, locked in
            if locked {
                unlocking = false
                unlockedIcon = false
                busy = false
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
            // Success ripple, restored as a plain overlay ring (no layer effect on the content,
            // so it can never hide the keypad).
            Circle()
                .stroke(Color.accentColor.opacity(0.6), lineWidth: 3)
                .frame(width: 120, height: 120)
                .keyframeAnimator(initialValue: CGFloat(0), trigger: unlockedIcon) { ring, p in
                    ring.scaleEffect(0.6 + 6 * p).opacity(p > 0 && p < 1 ? Double(1 - p) : 0)
                } keyframes: { _ in
                    LinearKeyframe(CGFloat(0), duration: 0)
                    CubicKeyframe(CGFloat(1), duration: 0.6)
                }
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
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
            let screen = UIScreen.main.bounds
            let ok = frame.width > 10 && frame.height > 10 && frame.intersects(screen)
            print("[AppLock] header frame \(frame) visible=\(ok)")
            if ok { contentVisible = true }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Modula is locked. \(instruction)")
        .accessibilityAddTraits(.isHeader)
    }

    private var instruction: String {
        if lock.isSlideOnly { return "Slide to open Modula." }
        switch method {
        case .passcode: return "Enter your 6-digit Modula passcode."
        case .pattern: return "Draw your unlock pattern."
        case .orbit: return "Spin each ring to your glyph, then tap the centre."
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
                if lock.isSlideOnly {
                    EmptyView()
                } else {
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
                                try? await Task.sleep(for: .milliseconds(reduceMotion ? 30 : 90))
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
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: compact ? 240 : 300)
                    .modifier(ShakeEffect(animatableData: CGFloat(shakes)))
                case .orbit:
                    OrbitDial(randomizes: true, disabled: disabled, haptics: lock.settings.hapticsEnabled,
                              actionLabel: "Unlock") { indices in
                        attempt(OrbitLock.encode(indices))
                    }
                    // GeometryReader-based dial: inside the ScrollView it got no height and drew
                    // up into the status bar. A square frame keeps it centred under the header.
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: compact ? 260 : 320)
                    .modifier(ShakeEffect(animatableData: CGFloat(shakes)))
                }
                }
            }
            .modifier(LockChromaticShake(trigger: shakes, enabled: effects))
            .opacity(coolingDown ? 0.45 : 1)
            .scaleEffect(appeared ? 1 : (effects ? 0.94 : 1))
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
                if lock.settings.method != .passcode, lock.hasPasscode, !lock.isSlideOnly {
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
                if !lock.isSlideOnly {
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
        }
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
    /// Timing: before, success waited 220ms + 380ms of fixed sleeps (effects on) and *then* built
    /// RootView from scratch. Now there are no sleeps: the lock fades over 0.28s (0.15s calm) in
    /// the same transaction that flips the gate, and the app is already built underneath.
    private func finishUnlock() {
        let started = ContinuousClock.now
        digits = ""
        hint = nil
        unlockedIcon = true
        withAnimation(.easeOut(duration: effects ? 0.28 : 0.15)) {
            unlocking = true
            app.refreshLaunchState()
        }
        #if DEBUG
        let elapsed = ContinuousClock.now - started
        print("[AppLock] success → dismiss started in \(elapsed.components.attoseconds / 1_000_000_000_000_000)ms (fade \(effects ? 280 : 150)ms)")
        #endif
    }

    private func autoPromptIfNeeded() async {
        guard UIApplication.shared.applicationState == .active else { return }
        if lock.consumeAutoPrompt() {
            await biometric()
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
                                .stroke(Color.primary.opacity(0.5), lineWidth: 1)
                                .keyframeAnimator(initialValue: 1.0, trigger: on) { view, t in
                                    view.scaleEffect(1 + 0.45 * t).opacity(on ? (1 - t) * 0.7 : 0)
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

/// Press feedback for glass keys: a slight scale plus a caustic shimmer clipped to the key.
private struct GlassKeyStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay { LockKeyShimmer(pressed: configuration.isPressed).clipShape(Circle()).allowsHitTesting(false) }
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
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
        // No GlassEffectContainer and no interactive glass here: interactive Liquid Glass inside a
        // merging container bloomed the touch into a huge unclipped tinted blob across the pad.
        VStack(spacing: 14) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 22) {
                    ForEach(row, id: \.self) { key in
                        keyButton(key)
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
                Image(systemName: "delete.left")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(Color.primary.opacity(value.isEmpty ? 0.3 : 0.8))
                    .frame(width: keySize, height: keySize)
                    .modulaGlass(in: Circle(), interactive: false, specular: true)
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
                .modulaGlass(in: Circle(), interactive: false, specular: true)
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
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ZStack {
            // Follows the app's light/dark appearance (was always a dark slab).
            Rectangle().fill(.regularMaterial)
            Color(uiColor: .systemBackground).opacity(0.55)
            VStack(spacing: 12) {
                Image(systemName: "lock.fill")
                    .font(.largeTitle)
                ModulaWordmark(height: 20, onDark: scheme == .dark)
            }
            .foregroundStyle(.primary)
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



// MARK: - Lock shader effects (ModulaEffectKit.metal)

/// Domain-warped noise aurora. Static under Reduce Motion, solid under Reduce Transparency.
private struct LockShaderAurora: View {
    var animated: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if reduceTransparency {
            Color(uiColor: .systemBackground)
        } else {
            GeometryReader { geo in
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !animated)) { context in
                    let t = animated ? context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600) : 12
                    Rectangle()
                        .colorEffect(ShaderLibrary.lockAurora(.float2(geo.size), .float(t), .float(colorScheme == .dark ? 1 : 0)))
                }
            }
            .accessibilityHidden(true)
        }
    }
}

/// Short caustic shimmer while a key is held / just released; clipped by the caller.
private struct LockKeyShimmer: View {
    var pressed: Bool
    @State private var start: Date = .distantPast
    @State private var settled = 0
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let _ = settled
        if reduceMotion {
            Color.primary.opacity(pressed ? 0.12 : 0)
        } else {
            let active = Date().timeIntervalSince(start) < 0.6 || pressed
            GeometryReader { geo in
                TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !active)) { ctx in
                    let t = min(1, max(0, ctx.date.timeIntervalSince(start) / 0.55))
                    Rectangle()
                        .colorEffect(ShaderLibrary.lockKeyCaustic(.float2(geo.size), .float(pressed ? min(t, 0.35) : t),
                                                                  .float(colorScheme == .dark ? 1 : 0)))
                        .opacity(active ? 1 : 0)
                }
            }
            .onChange(of: pressed) { _, now in
                if now { start = Date() } else {
                    // Re-render after the shimmer ends so the timeline pauses (no idle 60 fps).
                    Task { @MainActor in try? await Task.sleep(for: .milliseconds(620)); settled &+= 1 }
                }
            }
        }
    }
}

/// Distortion ripple from the lock badge, once, when `trigger` turns on.
private struct LockSuccessRipple: ViewModifier {
    var trigger: Bool
    @State private var start: Date?

    func body(content: Content) -> some View {
        GeometryReader { geo in
            let origin = CGPoint(x: geo.size.width / 2, y: geo.size.height * 0.24)
            TimelineView(.animation(minimumInterval: 1.0 / 60, paused: start == nil)) { ctx in
                let t = start.map { min(1, ctx.date.timeIntervalSince($0) / 0.6) } ?? 1
                content
                    .distortionEffect(ShaderLibrary.lockRipple(.float2(origin), .float(t), .float(10)),
                                      maxSampleOffset: CGSize(width: 12, height: 12), isEnabled: t < 1)
            }
        }
        .onChange(of: trigger) { _, on in
            guard on else { return }
            start = Date()
            Task { @MainActor in try? await Task.sleep(for: .milliseconds(650)); start = nil }
        }
    }
}

/// Animatable noise dissolve with a glowing edge.
private struct LockDissolve: ViewModifier, @MainActor Animatable {
    var progress: CGFloat
    var animatableData: CGFloat { get { progress } set { progress = newValue } }

    func body(content: Content) -> some View {
        GeometryReader { geo in
            content.colorEffect(ShaderLibrary.lockDissolve(.float2(geo.size), .float(progress)), isEnabled: progress > 0.001)
        }
    }
}

/// Wrong code: a brief RGB split that rides on the shake.
private struct LockChromaticShake: ViewModifier {
    var trigger: Int
    var enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.keyframeAnimator(initialValue: 0.0, trigger: trigger) { view, amount in
                view.layerEffect(ShaderLibrary.lockChromatic(.float(amount)),
                                 maxSampleOffset: CGSize(width: 8, height: 0), isEnabled: amount > 0.01)
            } keyframes: { _ in
                LinearKeyframe(6.0, duration: 0.08)
                CubicKeyframe(0.0, duration: 0.38)
            }
        } else {
            content
        }
    }
}


/// Classic iPhone "slide to unlock": dark inset rounded track, glossy knob with an arrow,
/// light-grey label with a white shimmer sweeping left to right; the label fades as the knob
/// moves. Reaching the end unlocks at once (haptic); letting go early springs back.
/// Reduce Motion: static label, no spring.
struct SlideToUnlockTrack: View {
    var disabled = false
    var haptics = true
    var onUnlock: () -> Void

    @State private var offset: CGFloat = 0
    @State private var done = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let height: CGFloat = 72
    private let inset: CGFloat = 5
    private let radius: CGFloat = 14

    var body: some View {
        GeometryReader { geo in
            let knobW: CGFloat = 86
            let maxX = max(1, geo.size.width - knobW - inset * 2)
            let progress = min(1, offset / maxX)
            ZStack(alignment: .leading) {
                // Dark inset track.
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(LinearGradient(colors: [Color(white: 0.08), Color(white: 0.2)], startPoint: .top, endPoint: .bottom))
                    .overlay(
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(LinearGradient(colors: [.black.opacity(0.8), .white.opacity(0.25)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                label
                    .frame(maxWidth: .infinity)
                    .padding(.leading, knobW)
                    .opacity(Double(max(0, 1 - progress * 2.2)))
                knob
                    .frame(width: knobW, height: height - inset * 2)
                    .offset(x: inset + offset)
                    .gesture(
                        DragGesture(minimumDistance: 2)
                            .onChanged { value in
                                guard !disabled, !done else { return }
                                offset = min(max(0, value.translation.width), maxX)
                                if offset >= maxX {
                                    done = true
                                    if haptics { HapticEngine.shared.play(.success) }
                                    onUnlock()
                                }
                            }
                            .onEnded { _ in
                                guard !done else { return }
                                withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.75)) {
                                    offset = 0
                                }
                            }
                    )
            }
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Slide to unlock")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { if !disabled { onUnlock() } }
        .accessibilityIdentifier("applock.slide")
    }

    private var knob: some View {
        RoundedRectangle(cornerRadius: radius - 3, style: .continuous)
            .fill(LinearGradient(colors: [Color(white: 0.98), Color(white: 0.78)], startPoint: .top, endPoint: .bottom))
            .overlay(alignment: .top) {
                // Gloss on the upper half.
                RoundedRectangle(cornerRadius: radius - 3, style: .continuous)
                    .fill(LinearGradient(colors: [.white.opacity(0.9), .white.opacity(0.15)], startPoint: .top, endPoint: .bottom))
                    .frame(maxHeight: .infinity)
                    .mask(VStack(spacing: 0) { Rectangle(); Color.clear })
            }
            .overlay(
                RoundedRectangle(cornerRadius: radius - 3, style: .continuous)
                    .strokeBorder(Color(white: 0.55), lineWidth: 0.5)
            )
            .overlay(
                Image(systemName: "arrow.right")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Color(white: 0.55))
            )
            .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
    }

    @ViewBuilder
    private var label: some View {
        let text = Text("slide to unlock").font(.system(size: 22, weight: .regular))
        let grey = Color(white: 0.55)
        if reduceMotion {
            text.foregroundStyle(grey)
        } else {
            TimelineView(.animation) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.6) / 2.6
                let x = -0.25 + 1.5 * t
                text
                    .foregroundStyle(grey)
                    .overlay {
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: min(1, max(0, x - 0.12))),
                                .init(color: .white, location: min(1, max(0, x))),
                                .init(color: .clear, location: min(1, max(0, x + 0.12))),
                            ],
                            startPoint: .leading, endPoint: .trailing
                        )
                        .mask(text)
                    }
            }
        }
    }
}
