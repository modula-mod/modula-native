import SwiftUI

struct AppLockView: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var digits = ""
    @State private var busy = false

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
        }
        .modulaCanvas()
        .accessibilityIdentifier("applock.lock")
        .confirmationDialog("Forgot your passcode?", isPresented: $confirmsForgot, titleVisibility: .visible) {
            Button("Sign Out and Reset App Lock", role: .destructive) {
                Task { await app.performSignOut(resetAppLock: true) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Sign out to remove App Lock from this device, then sign back in. Drafts on this device are kept.")
        }
        .task {
            if app.appLock.canUseBiometrics {
                _ = await app.appLock.unlockWithBiometrics()
                if !app.appLock.isLocked {
                    app.refreshLaunchState()
                }
            }
        }
    }

    @ViewBuilder
    private func content(cooldown: Duration) -> some View {
        let coolingDown = cooldown > .seconds(0)
        VStack(spacing: compact ? ModulaSpacing.md : 28) {
            Spacer(minLength: 0)
            Image(systemName: "lock.fill")
                .font(.system(size: compact ? 32 : 44, weight: .semibold))
                .accessibilityHidden(true)
            Text("Modula is locked")
                .font(.title.bold())
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text("Enter your 6-digit Modula passcode.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            PasscodeDots(filled: digits.count)
                .accessibilityLabel("Passcode, \(digits.count) of 6 digits entered")
            PasscodeKeypad(value: $digits, disabled: busy || coolingDown, keySize: compact ? 60 : 72) { complete in
                attempt(complete)
            }
            .opacity(coolingDown ? 0.45 : 1)
            if app.appLock.canUseBiometrics {
                Button {
                    Task { await biometric() }
                } label: {
                    Label(app.appLock.biometricAvailability.kind.unlockLabel, systemImage: app.appLock.biometricAvailability.kind.systemImage)
                        .frame(minHeight: ModulaLayout.minimumTouch)
                }
                .accessibilityIdentifier("applock.biometrics")
            }
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
            Button("Forgot Passcode?") {
                // The lock covers Settings, so offer the reset right here.
                confirmsForgot = true
            }
            .font(.footnote)
            .frame(minHeight: ModulaLayout.minimumTouch)
            .accessibilityIdentifier("applock.forgot")
            Spacer(minLength: 0)
        }
    }

    private func attempt(_ passcode: String) {
        busy = true
        let ok = app.appLock.unlock(withPasscode: passcode)
        digits = ""
        busy = false
        if ok {
            HapticEngine.shared.play(.success)
            app.refreshLaunchState()
        } else {
            HapticEngine.shared.play(.failure)
        }
    }

    private func biometric() async {
        let ok = await app.appLock.unlockWithBiometrics()
        if ok {
            HapticEngine.shared.play(.success)
            app.refreshLaunchState()
        } else if app.appLock.lastError != nil {
            HapticEngine.shared.play(.failure)
        }
    }
}

struct PasscodeDots: View {
    var filled: Int
    var body: some View {
        HStack(spacing: 14) {
            ForEach(0..<6, id: \.self) { index in
                Circle()
                    .strokeBorder(.primary.opacity(0.35), lineWidth: 1.5)
                    .background {
                        Circle().fill(index < filled ? Color.primary : Color.clear)
                    }
                    .frame(width: 14, height: 14)
            }
        }
        .accessibilityIdentifier("applock.dots")
    }
}

struct PasscodeKeypad: View {
    @Binding var value: String
    var disabled: Bool = false
    var keySize: CGFloat = 72
    var onComplete: (String) -> Void

    private let rows: [[String]] = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["", "0", "delete"]]

    var body: some View {
        VStack(spacing: 12) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 18) {
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
                if !value.isEmpty { value.removeLast() }
            } label: {
                Image(systemName: "delete.left")
                    .font(.title2)
                    .frame(width: keySize, height: keySize)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete")
        } else {
            Button {
                guard value.count < 6 else { return }
                value.append(key)
                if value.count == 6 {
                    onComplete(value)
                }
            } label: {
                Text(key)
                    .font(.title.weight(.semibold))
                    .frame(width: keySize, height: keySize)
                    .background(.thinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
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
