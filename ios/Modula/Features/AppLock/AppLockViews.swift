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
        case .seek: "Find your objects with the lens and tap them in order."
        case .cube: "Turn the cube and tap your glyphs in order."
        case .constellation: "Connect your stars in order."
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
                case .seek:
                    SeekScene(disabled: disabled, haptics: lock.settings.hapticsEnabled, actionLabel: "Unlock") { ids in
                        attempt(SeekLock.encode(ids))
                    }
                    .frame(maxWidth: compact ? 270 : 330)
                    .modifier(ShakeEffect(animatableData: CGFloat(shakes)))
                case .cube:
                    GlyphCube(disabled: disabled, haptics: lock.settings.hapticsEnabled, actionLabel: "Unlock") { ids in
                        attempt(CubeLock.encode(ids))
                    }
                    .frame(maxWidth: compact ? 240 : 290)
                    .modifier(ShakeEffect(animatableData: CGFloat(shakes)))
                case .constellation:
                    ConstellationSky(disabled: disabled, haptics: lock.settings.hapticsEnabled, actionLabel: "Unlock") { ids in
                        attempt(ConstellationLock.encode(ids))
                    }
                    .frame(maxWidth: compact ? 280 : 340)
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
                case .seek:
                    SeekScene(actionLabel: first == nil ? "Set" : "Confirm", showsStrength: first == nil) { ids in
                        submit(SeekLock.encode(ids))
                    }
                    .frame(maxWidth: 320)
                case .cube:
                    GlyphCube(actionLabel: first == nil ? "Set" : "Confirm", showsStrength: first == nil) { ids in
                        submit(CubeLock.encode(ids))
                    }
                    .frame(maxWidth: 280)
                case .constellation:
                    ConstellationSky(actionLabel: first == nil ? "Set" : "Confirm", showsStrength: first == nil) { ids in
                        submit(ConstellationLock.encode(ids))
                    }
                    .frame(maxWidth: 330)
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
        case .seek: first == nil ? "Drag the lens over the frosted scene to find objects, then tap 4–6 of them in your secret order." : "Everything moved. Find and tap the same objects in the same order."
        case .constellation: first == nil ? "Drag through 4–7 stars in your secret order (or tap them one by one), then tap Set." : "The sky moved. Connect the same stars again."
        case .cube: first == nil ? "Drag to turn the cube. Tap the front face to pick a glyph. Pick 4–6 in your secret order." : "The faces were shuffled. Pick the same glyphs again."
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

// MARK: - Shared controls for sequence-based unlocks (Seek, Cube, Constellation)

private struct LockSequenceControls: View {
    var count: Int
    var maximum: Int
    var minimum: Int
    var strength: Int?
    var actionLabel: String
    var disabled: Bool
    var onClear: () -> Void
    var onSubmit: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                ForEach(0..<maximum, id: \.self) { i in
                    Circle()
                        .fill(i < count ? Color.accentColor : Color.primary.opacity(0.15))
                        .frame(width: 10, height: 10)
                        .scaleEffect(i == count - 1 && !reduceMotion ? 1.25 : 1)
                }
            }
            .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.55), value: count)
            .accessibilityHidden(true)
            if let strength, count >= minimum {
                Label(["Weak: add more, different picks", "Okay", "Strong"][strength],
                      systemImage: ["exclamationmark.triangle.fill", "checkmark.circle", "checkmark.seal.fill"][strength])
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle([Color.orange, .secondary, .green][strength])
            }
            HStack(spacing: 12) {
                Button("Clear", action: onClear)
                    .buttonStyle(.plain)
                    .padding(.horizontal, 18).frame(height: 40)
                    .modulaGlass(in: Capsule())
                    .opacity(count == 0 ? 0.4 : 1)
                    .disabled(count == 0)
                Button(actionLabel, action: onSubmit)
                    .buttonStyle(.plain)
                    .font(.body.weight(.semibold))
                    .padding(.horizontal, 22).frame(height: 40)
                    .modulaGlass(in: Capsule(), tint: .accentColor)
                    .opacity(count >= minimum ? 1 : 0.4)
                    .disabled(count < minimum || disabled)
                    .accessibilityIdentifier("applock.sequence.submit")
            }
        }
    }
}

// MARK: - Seek (find hidden objects under frosted glass with a lens)

struct SeekScene: View {
    var disabled = false
    var haptics = true
    var actionLabel: String
    var showsStrength = false
    var onSubmit: ([Int]) -> Void

    /// slots[i] = unit position of object i; reshuffled every appearance / submit.
    @State private var slots: [CGPoint] = SeekScene.shuffledSlots()
    @State private var lens = CGPoint(x: 0.5, y: 0.5)
    @State private var lensBase: CGPoint?
    @State private var picks: [Int] = []
    @State private var popped: Int?
    @State private var lastHover: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static func shuffledSlots() -> [CGPoint] {
        var grid: [CGPoint] = []
        for row in 0..<4 { for col in 0..<4 {
            grid.append(CGPoint(x: 0.14 + CGFloat(col) * 0.24 + .random(in: -0.04...0.04),
                                y: 0.14 + CGFloat(row) * 0.24 + .random(in: -0.04...0.04)))
        } }
        grid.shuffle()
        return Array(grid.prefix(SeekLock.objects.count))
    }

    private let lensFraction: CGFloat = 0.36

    var body: some View {
        VStack(spacing: 16) {
            GeometryReader { geo in
                let size = min(geo.size.width, geo.size.height)
                let lensSize = size * lensFraction
                let lensPoint = CGPoint(x: lens.x * size, y: lens.y * size)
                let shape = RoundedRectangle(cornerRadius: 30, style: .continuous)
                ZStack {
                    scene(size: size)
                        .blur(radius: 9)
                        .overlay(shape.fill(.ultraThinMaterial).opacity(0.85))
                    // The lens: the sharp scene, magnified around the lens centre.
                    scene(size: size)
                        .scaleEffect(reduceMotion ? 1 : 1.35, anchor: UnitPoint(x: lens.x, y: lens.y))
                        .mask(Circle().frame(width: lensSize, height: lensSize).position(lensPoint))
                        .allowsHitTesting(false)
                    Circle()
                        .fill(.clear)
                        .frame(width: lensSize, height: lensSize)
                        .modulaGlass(in: Circle(), interactive: false, specular: true)
                        .opacity(0.35)
                        .overlay(Circle().stroke(.white.opacity(0.7), lineWidth: 2))
                        .shadow(color: .black.opacity(0.25), radius: 10, y: 6)
                        .overlay(alignment: .bottomTrailing) {
                            Capsule().fill(.white.opacity(0.75)).frame(width: 9, height: lensSize * 0.34)
                                .rotationEffect(.degrees(-45)).offset(x: lensSize * 0.12, y: lensSize * 0.12)
                        }
                        .position(lensPoint)
                        .allowsHitTesting(false)
                }
                .frame(width: size, height: size)
                .clipShape(shape)
                .contentShape(shape)
                .gesture(
                    DragGesture(minimumDistance: 6)
                        .onChanged { v in
                            if lensBase == nil { lensBase = lens }
                            guard let base = lensBase else { return }
                            lens = CGPoint(x: min(0.92, max(0.08, base.x + v.translation.width / size)),
                                           y: min(0.92, max(0.08, base.y + v.translation.height / size)))
                            let hover = objectAt(lens, size: size, radius: 0.08)
                            if hover != lastHover {
                                lastHover = hover
                                if hover != nil, haptics { HapticEngine.shared.play(.selection) }
                            }
                        }
                        .onEnded { _ in lensBase = nil }
                )
                .simultaneousGesture(
                    SpatialTapGesture().onEnded { v in
                        let p = CGPoint(x: v.location.x / size, y: v.location.y / size)
                        // Only objects you can actually see (inside the lens) are tappable.
                        guard hypot(p.x - lens.x, p.y - lens.y) < lensFraction / 2 else {
                            withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8)) { lens = p }
                            return
                        }
                        if let id = objectAt(p, size: size, radius: 0.09) { pick(id) }
                    }
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Frosted scene with a magnifier lens. \(picks.count) objects chosen.")
            }
            .aspectRatio(1, contentMode: .fit)
            LockSequenceControls(count: picks.count, maximum: SeekLock.maximumPicks, minimum: SeekLock.minimumPicks,
                                 strength: showsStrength ? SeekLock.strength(picks) : nil, actionLabel: actionLabel,
                                 disabled: disabled, onClear: { picks = [] }, onSubmit: submit)
        }
        .onAppear { slots = SeekScene.shuffledSlots() }
        .accessibilityIdentifier("applock.seek")
    }

    private func objectAt(_ p: CGPoint, size: CGFloat, radius: CGFloat) -> Int? {
        slots.indices.min { hypot(slots[$0].x - p.x, slots[$0].y - p.y) < hypot(slots[$1].x - p.x, slots[$1].y - p.y) }
            .flatMap { hypot(slots[$0].x - p.x, slots[$0].y - p.y) < radius ? $0 : nil }
    }

    private func pick(_ id: Int) {
        guard !disabled, picks.count < SeekLock.maximumPicks else { return }
        picks.append(id)
        if haptics { HapticEngine.shared.play(.mediumImpact) }
        withAnimation(reduceMotion ? nil : .spring(response: 0.2, dampingFraction: 0.4)) { popped = id }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.6)) { popped = nil }
        }
        if picks.count == SeekLock.maximumPicks { submit() }
    }

    private func submit() {
        guard !disabled, picks.count >= SeekLock.minimumPicks else { return }
        let captured = picks
        picks = []
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) { slots = SeekScene.shuffledSlots() }
        onSubmit(captured)
    }

    /// Moliboo's little world: sky, sun, hills, Moliboo, and 14 hidden objects.
    private func scene(size: CGFloat) -> some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.55, green: 0.82, blue: 0.98), Color(red: 0.98, green: 0.86, blue: 0.75)],
                           startPoint: .top, endPoint: .bottom)
            Circle().fill(Color(red: 1, green: 0.85, blue: 0.4)).frame(width: size * 0.22).position(x: size * 0.82, y: size * 0.16)
            Ellipse().fill(Color(red: 0.42, green: 0.75, blue: 0.5)).frame(width: size * 1.1, height: size * 0.6).position(x: size * 0.25, y: size * 1.0)
            Ellipse().fill(Color(red: 0.32, green: 0.66, blue: 0.45)).frame(width: size * 1.0, height: size * 0.5).position(x: size * 0.85, y: size * 1.02)
            SeekMolibooFace().frame(width: size * 0.2, height: size * 0.2).position(x: size * 0.5, y: size * 0.8)
            ForEach(SeekLock.objects.indices, id: \.self) { id in
                Image(systemName: SeekLock.objects[id])
                    .font(.system(size: size * 0.075, weight: .semibold))
                    .foregroundStyle(Self.tints[id % Self.tints.count])
                    .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
                    .scaleEffect(popped == id ? 1.5 : 1)
                    .position(x: slots[id].x * size, y: slots[id].y * size)
            }
        }
        .frame(width: size, height: size)
    }

    private static let tints: [Color] = [.orange, .indigo, .green, .yellow, .pink, .red, .purple, .teal, .brown, .blue, .mint, .cyan]
}

private struct SeekMolibooFace: View {
    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [Color(red: 0.36, green: 0.86, blue: 0.84), Color(red: 0.16, green: 0.58, blue: 0.66)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            HStack(spacing: 10) {
                Capsule().fill(.black.opacity(0.8)).frame(width: 5, height: 9)
                Capsule().fill(.black.opacity(0.8)).frame(width: 5, height: 9)
            }.offset(y: -3)
            Capsule().fill(.black.opacity(0.7)).frame(width: 9, height: 3).offset(y: 9)
        }
    }
}

// MARK: - Cube (turn a glass cube, tap the front glyph)

struct GlyphCube: View {
    var disabled = false
    var haptics = true
    var actionLabel: String
    var showsStrength = false
    var onSubmit: ([Int]) -> Void

    /// faces: [front, right, back, left, top, bottom] → glyph index.
    @State private var faces: [Int] = Array(0..<6).shuffled()
    @State private var drag: CGSize = .zero
    @State private var axis: Axis?
    @State private var picks: [Int] = []
    @State private var flash = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 18) {
            GeometryReader { geo in
                let w = min(geo.size.width, geo.size.height) * 0.78
                let t: CGFloat = axis == .horizontal ? drag.width / w : axis == .vertical ? drag.height / w : 0
                ZStack {
                    if reduceMotion || axis == nil || t == 0 {
                        face(faces[0], w: w, lit: true)
                    } else if axis == .horizontal {
                        let neighbor = t < 0 ? faces[1] : faces[3]
                        let p: CGFloat = t < 0 ? 1 : -1
                        cubeFace(faces[0], w: w, pos: t, horizontal: true)
                        cubeFace(neighbor, w: w, pos: p + t, horizontal: true)
                    } else {
                        let neighbor = t < 0 ? faces[5] : faces[4]
                        let p: CGFloat = t < 0 ? 1 : -1
                        cubeFace(faces[0], w: w, pos: t, horizontal: false)
                        cubeFace(neighbor, w: w, pos: p + t, horizontal: false)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 8)
                        .onChanged { v in
                            guard !disabled else { return }
                            if axis == nil { axis = abs(v.translation.width) > abs(v.translation.height) ? .horizontal : .vertical }
                            drag = CGSize(width: max(-w, min(w, v.translation.width)), height: max(-w, min(w, v.translation.height)))
                        }
                        .onEnded { v in
                            let d = axis == .horizontal ? v.predictedEndTranslation.width : v.predictedEndTranslation.height
                            let along = axis == .horizontal ? drag.width : drag.height
                            let turn = abs(d) > w * 0.45 || abs(along) > w * 0.4 ? (d < 0 ? -1 : 1) : 0
                            let ax = axis
                            withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.82)) {
                                if turn != 0, let ax {
                                    drag = ax == .horizontal ? CGSize(width: CGFloat(turn) * w, height: 0) : CGSize(width: 0, height: CGFloat(turn) * w)
                                } else { drag = .zero }
                            } completion: {
                                if turn != 0, let ax { rotate(ax, turn) }
                                drag = .zero
                                axis = nil
                            }
                            if turn != 0, haptics { HapticEngine.shared.play(.selection) }
                        }
                )
                .onTapGesture { pickFront() }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Glass cube. Front face shows \(GlyphNames.name(CubeLock.glyphs[faces[0]])).")
                .accessibilityHint("Swipe to turn, double-tap to pick.")
                .accessibilityAction(named: "Turn left") { rotate(.horizontal, -1) }
                .accessibilityAction(named: "Turn up") { rotate(.vertical, -1) }
            }
            .aspectRatio(1, contentMode: .fit)
            LockSequenceControls(count: picks.count, maximum: CubeLock.maximumPicks, minimum: CubeLock.minimumPicks,
                                 strength: showsStrength ? CubeLock.strength(picks) : nil, actionLabel: actionLabel,
                                 disabled: disabled, onClear: { picks = [] }, onSubmit: submit)
        }
        .onAppear { faces = Array(0..<6).shuffled() }
        .accessibilityIdentifier("applock.cube")
    }

    private func rotate(_ ax: Axis, _ dir: Int) {
        var f = faces
        if ax == .horizontal {
            // dir -1: swiped left, right face comes to the front.
            f = dir < 0 ? [faces[1], faces[2], faces[3], faces[0], faces[4], faces[5]]
                        : [faces[3], faces[0], faces[1], faces[2], faces[4], faces[5]]
        } else {
            f = dir < 0 ? [faces[5], faces[1], faces[4], faces[3], faces[0], faces[2]]
                        : [faces[4], faces[1], faces[5], faces[3], faces[2], faces[0]]
        }
        faces = f
    }

    private func pickFront() {
        guard !disabled, picks.count < CubeLock.maximumPicks, axis == nil else { return }
        picks.append(faces[0])
        if haptics { HapticEngine.shared.play(.mediumImpact) }
        withAnimation(reduceMotion ? nil : .spring(response: 0.18, dampingFraction: 0.5)) { flash = true }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            // Reshuffle every face so rotation directions reveal nothing.
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { flash = false; faces = Array(0..<6).shuffled() }
            if picks.count == CubeLock.maximumPicks { submit() }
        }
    }

    private func submit() {
        guard !disabled, picks.count >= CubeLock.minimumPicks else { return }
        let captured = picks
        picks = []
        faces = Array(0..<6).shuffled()
        onSubmit(captured)
    }

    private func cubeFace(_ glyph: Int, w: CGFloat, pos: CGFloat, horizontal: Bool) -> some View {
        face(glyph, w: w, lit: abs(pos) < 0.5)
            .brightness(-Double(abs(pos)) * 0.25)
            .rotation3DEffect(.degrees(Double(pos) * 90 * (horizontal ? 1 : -1)),
                              axis: horizontal ? (0, 1, 0) : (1, 0, 0),
                              anchor: horizontal ? (pos < 0 ? .trailing : .leading) : (pos < 0 ? .bottom : .top),
                              perspective: 0.55)
            .offset(x: horizontal ? pos * w : 0, y: horizontal ? 0 : pos * w)
    }

    private func face(_ glyph: Int, w: CGFloat, lit: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: w * 0.16, style: .continuous)
        return ZStack {
            shape.fill(LinearGradient(colors: [Color.accentColor.opacity(0.28), Color.accentColor.opacity(0.08)],
                                      startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(systemName: CubeLock.glyphs[glyph])
                .font(.system(size: w * 0.34, weight: .bold))
                .foregroundStyle(Color.accentColor)
                .shadow(color: Color.accentColor.opacity(lit ? 0.6 : 0), radius: 10)
                .scaleEffect(flash && lit && !reduceMotion ? 1.2 : 1)
        }
        .frame(width: w, height: w)
        .modulaGlass(in: shape, interactive: false, specular: true)
        .overlay(shape.stroke(.white.opacity(0.45), lineWidth: 1.5))
    }
}

private enum GlyphNames {
    static func name(_ symbol: String) -> String {
        symbol.replacingOccurrences(of: ".fill", with: "").replacingOccurrences(of: ".", with: " ")
    }
}

// MARK: - Constellation (connect secret stars in a shuffled night sky)

struct ConstellationSky: View {
    var disabled = false
    var haptics = true
    var actionLabel: String
    var showsStrength = false
    var onSubmit: ([Int]) -> Void

    @State private var stars: [CGPoint] = ConstellationSky.scatter()
    @State private var path: [Int] = []
    @State private var finger: CGPoint?
    @State private var fading = false
    @State private var dragMoved = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static func scatter() -> [CGPoint] {
        var pts: [CGPoint] = []
        var tries = 0
        while pts.count < ConstellationLock.stars.count && tries < 4000 {
            tries += 1
            let p = CGPoint(x: .random(in: 0.1...0.9), y: .random(in: 0.1...0.9))
            if pts.allSatisfy({ hypot($0.x - p.x, $0.y - p.y) > 0.17 }) { pts.append(p) }
        }
        while pts.count < ConstellationLock.stars.count { pts.append(CGPoint(x: .random(in: 0.1...0.9), y: .random(in: 0.1...0.9))) }
        return pts
    }

    var body: some View {
        VStack(spacing: 16) {
            GeometryReader { geo in
                let size = min(geo.size.width, geo.size.height)
                let shape = RoundedRectangle(cornerRadius: 30, style: .continuous)
                TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { ctx in
                    let time = ctx.date.timeIntervalSinceReferenceDate
                    ZStack {
                        LinearGradient(colors: [Color(red: 0.04, green: 0.05, blue: 0.16), Color(red: 0.12, green: 0.08, blue: 0.3)],
                                       startPoint: .top, endPoint: .bottom)
                        Canvas { g, sz in
                            // Faint background dust with slow parallax drift.
                            for i in 0..<40 {
                                let seed = Double(i) * 12.9898
                                let x = (sin(seed) * 0.5 + 0.5 + (reduceMotion ? 0 : time * 0.002 * Double(i % 3 + 1))).truncatingRemainder(dividingBy: 1)
                                let y = cos(seed * 1.7) * 0.5 + 0.5
                                g.fill(Path(ellipseIn: CGRect(x: x * sz.width, y: y * sz.height, width: 1.5, height: 1.5)), with: .color(.white.opacity(0.35)))
                            }
                            // Constellation lines.
                            var line = Path()
                            for (n, id) in path.enumerated() {
                                let p = CGPoint(x: stars[id].x * sz.width, y: stars[id].y * sz.height)
                                if n == 0 { line.move(to: p) } else { line.addLine(to: p) }
                            }
                            if let finger, !path.isEmpty { line.addLine(to: finger) }
                            g.stroke(line, with: .color(Color(red: 0.6, green: 0.85, blue: 1).opacity(fading ? 0 : 0.85)),
                                     style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                            g.addFilter(.blur(radius: 0))
                        }
                        ForEach(stars.indices, id: \.self) { id in
                            let on = path.contains(id)
                            let twinkle = reduceMotion ? 1 : 0.75 + 0.25 * sin(time * 2.2 + Double(id) * 1.3)
                            VStack(spacing: 2) {
                                Image(systemName: "star.fill")
                                    .font(.system(size: on ? 18 : 13, weight: .bold))
                                    .foregroundStyle(on ? Color(red: 0.7, green: 0.9, blue: 1) : .white)
                                    .shadow(color: .white.opacity(on ? 0.9 : 0.5), radius: on ? 8 : 4)
                                    .opacity(twinkle)
                                Text(ConstellationLock.stars[id])
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                            .position(x: stars[id].x * size, y: stars[id].y * size + 6)
                        }
                    }
                }
                .frame(width: size, height: size)
                .clipShape(shape)
                .overlay(shape.stroke(.white.opacity(0.18), lineWidth: 1))
                .contentShape(shape)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            guard !disabled, !fading else { return }
                            if hypot(v.translation.width, v.translation.height) > 10 { dragMoved = true }
                            finger = dragMoved ? v.location : nil
                            hit(CGPoint(x: v.location.x / size, y: v.location.y / size))
                        }
                        .onEnded { _ in
                            finger = nil
                            // A drawn line submits on lift; taps (accessibility) build up and use the button.
                            if dragMoved && path.count >= ConstellationLock.minimumStars { submit() }
                            dragMoved = false
                        }
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Night sky. \(path.count) stars connected.")
            }
            .aspectRatio(1, contentMode: .fit)
            LockSequenceControls(count: path.count, maximum: ConstellationLock.maximumStars, minimum: ConstellationLock.minimumStars,
                                 strength: showsStrength ? ConstellationLock.strength(path) : nil, actionLabel: actionLabel,
                                 disabled: disabled, onClear: { path = [] }, onSubmit: submit)
        }
        .onAppear { stars = ConstellationSky.scatter() }
        .accessibilityIdentifier("applock.constellation")
    }

    private func hit(_ p: CGPoint) {
        guard path.count < ConstellationLock.maximumStars,
              let id = stars.indices.first(where: { hypot(stars[$0].x - p.x, stars[$0].y - p.y) < 0.07 }),
              !path.contains(id) else { return }
        path.append(id)
        if haptics { HapticEngine.shared.play(.lightImpact) }
    }

    private func submit() {
        guard !disabled, path.count >= ConstellationLock.minimumStars else { return }
        let captured = path
        if haptics { HapticEngine.shared.play(.mediumImpact) }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.45)) { fading = true }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 50 : 450))
            path = []
            fading = false
            stars = ConstellationSky.scatter()
            onSubmit(captured)
        }
    }
}
