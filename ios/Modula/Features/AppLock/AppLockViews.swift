import SwiftUI

struct AppLockView: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var digits = ""
    @State private var busy = false
    @State private var shakes = 0
    @State private var unlocking = false
    @State private var appeared = false

    @State private var confirmsForgot = false
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Tighter layout on short screens (iPhone SE) and at accessibility text sizes.
    private var compact: Bool {
        verticalSizeClass == .compact || dynamicTypeSize.isAccessibilitySize
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                // TimelineView ticks once a second so the cooldown countdown
                // updates and the keypad re-enables by itself when it ends.
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    content(cooldown: app.appLock.remainingCooldown())
                }
                .padding(compact ? ModulaSpacing.md : ModulaSpacing.lg)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
        }
        .background { LockAmbientBackground().ignoresSafeArea() }
        .scaleEffect(unlocking && !reduceMotion ? 1.08 : 1)
        .blur(radius: unlocking && !reduceMotion ? 18 : 0)
        .opacity(unlocking ? 0 : 1)
        .accessibilityIdentifier("applock.lock")
        .confirmationDialog("Forgot your passcode?", isPresented: $confirmsForgot, titleVisibility: .visible) {
            Button("Sign Out and Reset App Lock", role: .destructive) {
                Task { await app.performSignOut(resetAppLock: true) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Sign out to remove App Lock from this device, then sign back in. Drafts on this device are kept.")
        }
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.6, dampingFraction: 0.85)) { appeared = true }
        }
        .task {
            // Auto-prompt at most once per foreground; failures fall back to the keypad.
            if app.appLock.consumeAutoPrompt() {
                await biometric()
            }
        }
    }

    @ViewBuilder
    private func content(cooldown: Duration) -> some View {
        let coolingDown = cooldown > .seconds(0)
        VStack(spacing: compact ? ModulaSpacing.md : 26) {
            Spacer(minLength: 0)
            VStack(spacing: compact ? 10 : 14) {
                Image(systemName: unlocking ? "lock.open.fill" : "lock.fill")
                    .font(.system(size: compact ? 24 : 30, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: compact ? 56 : 68, height: compact ? 56 : 68)
                    .modulaGlass(in: Circle(), interactive: false, specular: true)
                    .accessibilityHidden(true)
                HStack(spacing: 8) {
                    ModulaWordmark(height: compact ? 20 : 26, onDark: true)
                    Text("is locked").font(.title.bold())
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Modula is locked")
                .accessibilityAddTraits(.isHeader)
                Text("Enter your 6-digit Modula passcode.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .offset(y: appeared ? 0 : -12)
            .opacity(appeared ? 1 : 0)
            PasscodeDots(filled: digits.count, shakes: shakes, error: shakes > 0 && digits.isEmpty && app.appLock.lastError != nil)
                .accessibilityLabel("Passcode, \(digits.count) of 6 digits entered")
            PasscodeKeypad(value: $digits, disabled: busy || coolingDown || unlocking, keySize: compact ? 62 : 76) { complete in
                attempt(complete)
            }
            .opacity(coolingDown ? 0.45 : 1)
            .scaleEffect(appeared ? 1 : 0.96)
            .opacity(appeared ? 1 : 0)
            if coolingDown {
                let seconds = Int((Double(cooldown.components.seconds) + Double(cooldown.components.attoseconds) / 1e18).rounded(.up))
                Text("Too many attempts. Try again in \(seconds) \(seconds == 1 ? "second" : "seconds").")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .monospacedDigit()
                    .accessibilityIdentifier("applock.cooldown")
            } else if let error = app.appLock.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("applock.error")
            }
            HStack(spacing: 12) {
                if app.appLock.canUseBiometrics {
                    Button {
                        HapticEngine.shared.play(.lightImpact)
                        Task { await biometric() }
                    } label: {
                        Label(app.appLock.biometricAvailability.kind.unlockLabel, systemImage: app.appLock.biometricAvailability.kind.systemImage)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 16)
                            .frame(minHeight: ModulaLayout.minimumTouch)
                            .modulaGlass(in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(app.appLock.isAuthenticating || unlocking)
                    .accessibilityIdentifier("applock.biometrics")
                }
                Button {
                    HapticEngine.shared.play(.selection)
                    // The lock covers Settings, so offer the reset right here.
                    confirmsForgot = true
                } label: {
                    Text("Forgot Passcode?")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .frame(minHeight: ModulaLayout.minimumTouch)
                        .modulaGlass(in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("applock.forgot")
            }
            Spacer(minLength: 0)
        }
    }

    private func attempt(_ passcode: String) {
        busy = true
        let ok = app.appLock.unlock(withPasscode: passcode)
        busy = false
        if ok {
            HapticEngine.shared.play(.success)
            finishUnlock()
        } else {
            HapticEngine.shared.play(.failure)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { digits = "" }
            withAnimation(reduceMotion ? nil : .linear(duration: 0.45)) { shakes += 1 }
        }
    }

    /// Plays a short open/fade before handing control back; the unlock itself already happened.
    private func finishUnlock() {
        digits = ""
        withAnimation(.easeIn(duration: reduceMotion ? 0.15 : 0.32)) { unlocking = true }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 150 : 320))
            app.refreshLaunchState()
        }
    }

    private func biometric() async {
        let ok = await app.appLock.unlockWithBiometrics()
        if ok {
            HapticEngine.shared.play(.success)
            finishUnlock()
        } else if app.appLock.lastError != nil {
            HapticEngine.shared.play(.failure)
            withAnimation(reduceMotion ? nil : .linear(duration: 0.45)) { shakes += 1 }
        }
    }
}

/// Slow drifting aurora blobs; capped at ~20fps, static when Reduce Motion is on.
private struct LockAmbientBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.black
            TimelineView(.animation(minimumInterval: 1.0 / 20, paused: reduceMotion)) { context in
                let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
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
                                 with: .color(color.opacity(0.45)))
                    }
                }
            }
            LinearGradient(colors: [.black.opacity(0.1), .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
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
                            .shadow(color: .white.opacity(on ? 0.6 : 0), radius: 6)
                    }
                    .frame(width: 14, height: 14)
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
                    .fill(Color.white.opacity(configuration.isPressed ? 0.22 : 0))
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
                    .foregroundStyle(.white.opacity(value.isEmpty ? 0.35 : 0.9))
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
                .foregroundStyle(.white)
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
