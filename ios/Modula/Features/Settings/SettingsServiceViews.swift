import MessageUI
import SwiftUI
import UIKit

// MARK: - Help → Status (live, `GET /v1/status`)

struct HelpStatusView: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model = ServiceStatusModel()
    @State private var network = DeviceNetworkMonitor()

    var body: some View {
        SettingsScrollCanvas {
            statusHero
            componentsGroup
            deviceGroup
            SettingsAPIFootnote(text: footnote)
        }
        .refreshable { await model.refresh(client: app.client) }
        .task {
            network.start()
            // Live while visible: refresh every 30 s, cancelled when the page goes away.
            while !Task.isCancelled {
                await model.refresh(client: app.client)
                try? await Task.sleep(for: .seconds(30))
            }
        }
        .onDisappear { network.stop() }
        .navigationTitle("Status")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("settings.help.status")
    }

    private var overall: ServiceComponentState { model.overall }
    private var radarTint: Color { overall == .unknown ? app.appearance.accent.color : overall.tint }

    private var statusHero: some View {
        ModulaCard {
            HStack(spacing: 18) {
                ModulaRadarScope(tint: radarTint, energy: overall.radarEnergy)
                    .frame(width: 118, height: 118)
                    .overlay {
                        Image(systemName: overall.symbol)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(radarTint)
                            .contentTransition(.symbolEffect(.replace))
                            .symbolEffect(.bounce, value: overall)
                            .padding(10)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                VStack(alignment: .leading, spacing: 6) {
                    Text(headline)
                        .font(.title3.weight(.semibold))
                        .contentTransition(.opacity)
                    Text(subheadline)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if case .loaded(_, let ms) = model.phase {
                        Label("\(ms) ms round trip", systemImage: "stopwatch")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText(value: Double(ms)))
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .animation(ModulaMotion.animation(.contentTransition, personality: app.appearance.motion, reduceMotion: reduceMotion), value: model.phase)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Modula status: \(headline). \(subheadline)")
    }

    private var headline: String {
        switch model.phase {
        case .idle, .loading: "Checking Modula…"
        case .failed: network.snapshot?.satisfied == false ? "You’re offline" : "Can’t reach Modula"
        case .loaded(let snapshot, _):
            switch snapshot.status {
            case .operational: "All systems operational"
            case .degraded: "Some services are degraded"
            case .outage: "Service outage"
            case .unknown: "Status unknown"
            }
        }
    }

    private var subheadline: String {
        switch model.phase {
        case .idle, .loading: "Measuring live from Modula’s servers."
        case .failed(let message):
            network.snapshot?.satisfied == false ? "Connect to the internet to check service health." : message
        case .loaded(let snapshot, _):
            if let date = snapshot.checkedDate {
                "Checked \(date.formatted(date: .omitted, time: .standard))"
            } else {
                "Checked just now"
            }
        }
    }

    @ViewBuilder
    private var componentsGroup: some View {
        if let snapshot = model.snapshot {
            SettingsGroup(title: "Services", subtitle: "Measured by the server at request time.") {
                VStack(spacing: 0) {
                    ForEach(Array(snapshot.components.enumerated()), id: \.element.id) { index, component in
                        StatusComponentRow(component: component, index: index)
                        if index < snapshot.components.count - 1 { SettingsDivider() }
                    }
                }
            }
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        } else if case .loading = model.phase {
            SettingsGroup(title: "Services") {
                VStack(spacing: 0) {
                    ForEach(0..<4, id: \.self) { index in
                        StatusComponentRow.placeholder
                        if index < 3 { SettingsDivider() }
                    }
                }
                .redacted(reason: .placeholder)
            }
        } else if case .failed = model.phase {
            SettingsGroup(title: "Services") {
                Button {
                    Task { await model.refresh(client: app.client) }
                } label: {
                    Label("Try again", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity, minHeight: ModulaLayout.minimumTouch)
                }
            }
        }
    }

    private var deviceGroup: some View {
        SettingsGroup(title: "This device") {
            VStack(spacing: 0) {
                StatusFactRow(
                    title: "Network",
                    value: network.snapshot?.summary ?? "Checking…",
                    symbol: network.snapshot?.satisfied == false ? "wifi.slash" : "wifi",
                    tint: network.snapshot?.satisfied == false ? .red : app.appearance.accent.color
                )
                SettingsDivider()
                StatusFactRow(
                    title: "Server",
                    value: SettingsEnvironmentInfo.apiHost,
                    symbol: "globe",
                    tint: app.appearance.accent.color
                )
                if let release = model.snapshot?.release, let commit = release.commit {
                    SettingsDivider()
                    StatusFactRow(title: "Server release", value: commit, symbol: "shippingbox", tint: app.appearance.accent.color)
                }
            }
        }
    }

    private var footnote: String {
        "Status is measured live each time this page refreshes: API and database round trips, background worker heartbeat, and queue age. Pull to refresh."
    }
}

private struct StatusComponentRow: View {
    let component: ServiceStatusComponent
    var index: Int = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    static var placeholder: some View {
        StatusComponentRow(component: .init(id: "api", name: "Service name", state: .unknown, latencyMs: nil, lastSeenAt: nil, ageSeconds: nil, pending: nil))
    }

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: component.symbol)
                .frame(width: 28)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(component.name).font(.body.weight(.medium))
                Text(component.detail).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Label(component.state.title, systemImage: component.state.symbol)
                .font(.caption.weight(.semibold))
                .labelStyle(.titleAndIcon)
                .foregroundStyle(component.state.tint)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(component.state.tint.opacity(0.12), in: Capsule())
                .symbolEffect(.pulse, options: .repeating, isActive: component.state == .degraded && !reduceMotion)
        }
        .frame(minHeight: 52)
        .opacity(shown || reduceMotion ? 1 : 0)
        .offset(y: shown || reduceMotion ? 0 : 8)
        .onAppear {
            guard !shown else { return }
            withAnimation(reduceMotion ? nil : .spring(duration: 0.42, bounce: 0.2).delay(Double(index) * 0.05)) { shown = true }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct StatusFactRow: View {
    var title: String
    var value: String
    var symbol: String
    var tint: Color

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: symbol)
                .frame(width: 28)
                .foregroundStyle(tint)
                .contentTransition(.symbolEffect(.replace))
            Text(title).font(.body.weight(.medium))
            Spacer(minLength: 8)
            Text(value)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .frame(minHeight: 48)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Help → Contact (`/v1/support/*`)

struct HelpContactView: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.openURL) private var openURL
    @State private var contact: SupportContactInfo?
    @State private var contactError: String?
    @State private var cases: [SupportCaseSummary] = []
    @State private var composing = false
    @State private var mailing = false
    @State private var lastOpened: SupportCaseSummary?

    var body: some View {
        SettingsScrollCanvas {
            SettingsHeroBanner(title: "Contact support", subtitle: "Write to the Modula team. Every request gets a reference.", symbol: "envelope.badge")
            caseGroup
            emailGroup
            privacyGroup
            if app.auth.isSignedIn { requestsGroup }
            SettingsAPIFootnote(text: "Requests go to the Modula support mailbox. Diagnostics are optional, shown to you before sending, and never include messages, contacts, or tokens.")
        }
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $composing) {
            SupportCaseComposer(contact: contact) { opened in
                lastOpened = opened
                cases.insert(opened, at: 0)
            }
        }
        .sheet(isPresented: $mailing) {
            if let email = contact?.supportEmail {
                SupportMailComposer(recipient: email, subject: "Modula support", body: "")
                    .ignoresSafeArea()
            }
        }
        .navigationTitle("Contact")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("settings.help.contact")
    }

    private var caseGroup: some View {
        SettingsGroup(title: "Open a case", subtitle: "Tracked in the app with a reference you can quote.") {
            VStack(alignment: .leading, spacing: 12) {
                if let lastOpened {
                    Label("Sent · \(lastOpened.reference)", systemImage: "checkmark.seal.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                        .symbolEffect(.bounce, value: lastOpened.reference)
                        .transition(.scale.combined(with: .opacity))
                }
                if !app.auth.isSignedIn {
                    Text("Sign in to open a case from the app, or email support below.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    ModulaButton(title: "Sign In", symbol: "person.crop.circle") {
                        app.navigation.open(.auth(.login))
                    }
                } else if contact?.inAppCases == false {
                    Text("In-app requests are paused right now. Email support instead.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ModulaButton(title: "Write to Support", symbol: "square.and.pencil") {
                        composing = true
                        HapticEngine.shared.play(.selection)
                    }
                    .disabled(contact == nil)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var emailGroup: some View {
        SettingsGroup(title: "Email") {
            if let email = contact?.supportEmail {
                Button {
                    if MFMailComposeViewController.canSendMail() {
                        mailing = true
                    } else if let url = URL(string: "mailto:\(email)") {
                        openURL(url)
                    }
                } label: {
                    HStack(spacing: 13) {
                        Image(systemName: "envelope").frame(width: 28).foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(email).font(.body.weight(.medium))
                            Text("Opens your mail app").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                    .frame(minHeight: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Copy Address", systemImage: "doc.on.doc") {
                        UIPasteboard.general.string = email
                        app.navigation.flash("Address copied", symbol: "doc.on.doc")
                    }
                }
                .modulaTapRipple()
            } else if let contactError {
                VStack(alignment: .leading, spacing: 8) {
                    Text(contactError).font(.subheadline).foregroundStyle(.secondary)
                    Button("Try Again") { Task { await load() } }
                }
                .padding(.vertical, 6)
            } else {
                HStack { ProgressView(); Text("Loading contact options…").foregroundStyle(.secondary) }
                    .frame(minHeight: 48)
            }
        }
    }

    private var privacyGroup: some View {
        SettingsGroup(title: "Privacy & data") {
            VStack(spacing: 0) {
                SettingsNavigationRow(title: "Export your data", subtitle: "Download a copy of your account data", symbol: "square.and.arrow.up") {
                    app.navigation.open(.settings(.dataStorage(.export)))
                }
                SettingsDivider()
                SettingsNavigationRow(title: "Privacy request", subtitle: "Open a privacy case with the team", symbol: "hand.raised") {
                    if app.auth.isSignedIn { composing = true } else { app.navigation.open(.auth(.login)) }
                }
            }
        }
    }

    private var requestsGroup: some View {
        SettingsGroup(title: "Your requests") {
            if cases.isEmpty {
                Text("No support requests yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(cases.prefix(8).enumerated()), id: \.element.id) { index, item in
                        HStack(spacing: 13) {
                            Image(systemName: SupportCategory(rawValue: item.category)?.symbol ?? "bubble.left")
                                .frame(width: 28).foregroundStyle(.tint)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.subject).font(.body.weight(.medium)).lineLimit(1)
                                Text([item.reference, item.createdDate?.formatted(date: .abbreviated, time: .shortened)].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(item.state.capitalized)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Color.primary.opacity(0.06), in: Capsule())
                        }
                        .frame(minHeight: 52)
                        .accessibilityElement(children: .combine)
                        if index < min(cases.count, 8) - 1 { SettingsDivider() }
                    }
                }
            }
        }
    }

    private func load() async {
        do {
            let value = try await app.client.publicJSON("GET", path: "/v1/support/contact")
            contact = try GreenfieldValueDecoder.decode(SupportContactInfo.self, from: value)
            contactError = nil
        } catch {
            contactError = "Contact options couldn’t load. Check your connection."
        }
        guard app.auth.isSignedIn else { return }
        if let value = try? await app.client.authenticatedJSON("GET", path: "/v1/support/cases"),
           let list = try? GreenfieldValueDecoder.decode(SupportCaseList.self, from: value) {
            cases = list.items
        }
    }
}

struct SupportCaseComposer: View {
    var contact: SupportContactInfo?
    var onOpened: (SupportCaseSummary) -> Void
    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var draft = SupportCaseDraft()
    @State private var network = DeviceNetworkMonitor()
    @State private var sending = false
    @State private var error: String?
    @State private var showProblems = false
    @State private var idempotencyKey = "case-\(UUID().uuidString.lowercased())"
    @State private var opened: SupportCaseSummary?
    @FocusState private var focus: Field?

    private enum Field { case subject, message }

    var body: some View {
        NavigationStack {
            Group {
                if let opened {
                    confirmation(opened)
                        .transition(.scale(scale: 0.94).combined(with: .opacity))
                } else {
                    form
                }
            }
            .animation(ModulaMotion.animation(.presentation, personality: app.appearance.motion, reduceMotion: reduceMotion), value: opened)
            .navigationTitle(opened == nil ? "New Request" : "Request Sent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(opened == nil ? "Cancel" : "Done") { dismiss() }
                }
                if opened == nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Send") { Task { await send() } }
                            .disabled(sending)
                            .fontWeight(.semibold)
                    }
                }
            }
        }
        .onAppear { network.start() }
        .onDisappear { network.stop() }
        .interactiveDismissDisabled(sending)
    }

    private var form: some View {
        Form {
            Section("About") {
                Picker("Topic", selection: $draft.category) {
                    ForEach(SupportCategory.allCases) { category in
                        Label(category.title, systemImage: category.symbol).tag(category)
                    }
                }
                .pickerStyle(.navigationLink)
            }
            Section {
                TextField("Subject", text: $draft.subject)
                    .focused($focus, equals: .subject)
                    .submitLabel(.next)
                    .onSubmit { focus = .message }
                if showProblems, let problem = draft.subjectProblem {
                    Text(problem).font(.caption).foregroundStyle(.red)
                }
                TextField("What happened? Include steps if something broke.", text: $draft.message, axis: .vertical)
                    .lineLimit(6...14)
                    .focused($focus, equals: .message)
                if showProblems, let problem = draft.messageProblem {
                    Text(problem).font(.caption).foregroundStyle(.red)
                }
            } header: {
                Text("Message")
            } footer: {
                Text("\(draft.trimmedMessage.count) / \(contact?.limits.messageMax ?? SupportCaseDraft.messageRange.upperBound)")
                    .monospacedDigit()
            }
            Section {
                Toggle("Attach diagnostics", isOn: $draft.attachDiagnostics.animation())
                    .tint(app.appearance.accent.color)
                if draft.attachDiagnostics {
                    DisclosureGroup("Review what’s sent (\(diagnostics.count))") {
                        ForEach(diagnostics) { item in
                            LabeledContent(item.label, value: item.value)
                                .font(.footnote)
                        }
                    }
                }
            } footer: {
                Text("Device facts only: app version, iOS version, device model, network type, and display settings. No messages, contacts, location, or tokens.")
            }
            if let error {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
            if sending {
                Section {
                    HStack { ProgressView(); Text("Sending…") }
                }
            }
        }
        .modulaSoftScrollEdge()
        .onAppear { focus = .subject }
    }

    private func confirmation(_ opened: SupportCaseSummary) -> some View {
        VStack(spacing: 18) {
            Spacer(minLength: 20)
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(app.appearance.accent.color)
                .symbolEffect(.bounce, value: opened.reference)
                .modulaHeroSheen(intensity: 0.8)
            Text("We’ve got it")
                .font(.title2.weight(.semibold))
            Text("Your reference is")
                .foregroundStyle(.secondary)
            Text(opened.reference)
                .font(.title3.monospaced().weight(.semibold))
                .textSelection(.enabled)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(app.appearance.accent.color.opacity(0.12), in: Capsule())
            if let email = contact?.supportEmail {
                Text("Replies come from \(email) to the email on your account.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .modulaCanvas()
    }

    private var diagnostics: [SupportDiagnostic] {
        let info = Bundle.main.infoDictionary
        #if DEBUG
        let debug = true
        #else
        let debug = false
        #endif
        return SupportDiagnostics.make(
            .init(
                appVersion: info?["CFBundleShortVersionString"] as? String,
                appBuild: info?["CFBundleVersion"] as? String,
                debugBuild: debug,
                osVersion: UIDevice.current.systemVersion,
                deviceModel: SupportDiagnostics.deviceModelIdentifier(),
                locale: Locale.current.identifier,
                timeZone: TimeZone.current.identifier,
                apiHost: SettingsEnvironmentInfo.apiHost,
                networkPath: network.snapshot?.summary,
                lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
                reduceMotion: reduceMotion,
                dynamicType: dynamicTypeSize.settingsLabel,
                theme: app.appearance.theme.rawValue,
                installedModules: app.runtime.manifests.count,
                storageFreeBytes: SupportDiagnostics.freeStorageBytes()
            ),
            allowed: contact?.diagnosticKeys ?? SupportDiagnostics.allowedKeys
        )
    }

    private func send() async {
        guard draft.isValid else {
            withAnimation { showProblems = true }
            HapticEngine.shared.play(.warning)
            return
        }
        sending = true
        error = nil
        defer { sending = false }
        do {
            let value = try await app.client.authenticatedJSON(
                "POST",
                path: "/v1/support/cases",
                body: draft.body(diagnostics: diagnostics),
                idempotencyKey: idempotencyKey
            )
            let summary = try GreenfieldValueDecoder.decode(SupportCaseSummary.self, from: value)
            HapticEngine.shared.play(.success)
            AccessibilityNotification.Announcement("Request sent. Reference \(summary.reference)").post()
            onOpened(summary)
            opened = summary
        } catch let apiError as APIError {
            error = apiError.errorDescription
            HapticEngine.shared.play(.failure)
        } catch {
            self.error = "The request couldn’t be sent. Try again."
            HapticEngine.shared.play(.failure)
        }
    }
}

/// System mail sheet. Only presented when `MFMailComposeViewController.canSendMail()`.
struct SupportMailComposer: UIViewControllerRepresentable {
    var recipient: String
    var subject: String
    var body: String
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(dismiss: dismiss) }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.setToRecipients([recipient])
        controller.setSubject(subject)
        controller.setMessageBody(body, isHTML: false)
        controller.mailComposeDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: MFMailComposeViewController, context: Context) {}

    @MainActor final class Coordinator: NSObject, @preconcurrency MFMailComposeViewControllerDelegate {
        let dismiss: DismissAction
        init(dismiss: DismissAction) { self.dismiss = dismiss }
        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            dismiss()
        }
    }
}

// MARK: - Data & Storage → Export (`/v1/account/data-exports`)

struct AccountDataExportView: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model = AccountExportModel()

    var body: some View {
        SettingsScrollCanvas {
            SettingsHeroBanner(title: "Export your data", subtitle: "A machine-readable copy of your Modula account.", symbol: "square.and.arrow.up.on.square")
            SettingsGroup(title: "What’s included") {
                VStack(spacing: 0) {
                    includedRow("Account & profile", "Handle, display name, settings", "person.text.rectangle")
                    SettingsDivider()
                    includedRow("Your content", "Posts and activity stored by Modula", "square.stack")
                    SettingsDivider()
                    includedRow("Module data", "Data modules keep on Modula, when they support export", "shippingbox")
                }
            }
            SettingsGroup(title: "Export") {
                VStack(alignment: .leading, spacing: 12) {
                    switch model.state {
                    case .idle:
                        if app.auth.isSignedIn {
                            Text("Modula prepares the export now and hands you a JSON file you can save to Files or share.")
                                .font(.subheadline).foregroundStyle(.secondary)
                            ModulaButton(title: "Prepare Export", symbol: "arrow.down.doc") {
                                HapticEngine.shared.play(.selection)
                                Task { await model.start(client: app.client) }
                            }
                        } else {
                            Text("Sign in to export your account data.")
                                .font(.subheadline).foregroundStyle(.secondary)
                            ModulaButton(title: "Sign In", symbol: "person.crop.circle") { app.navigation.open(.auth(.login)) }
                        }
                    case .working(let step):
                        HStack(spacing: 12) {
                            ProgressView()
                            Text(step).font(.subheadline.weight(.medium)).contentTransition(.opacity)
                        }
                        .frame(minHeight: 48)
                    case .ready(let url, let count, let bytes):
                        Label("Ready · \(count) part\(count == 1 ? "" : "s") · \(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.subheadline.weight(.semibold))
                            .symbolEffect(.bounce, value: bytes)
                        ShareLink(item: url) {
                            Label("Save or Share", systemImage: "square.and.arrow.up")
                                .font(.headline)
                                .frame(maxWidth: .infinity, minHeight: 52)
                        }
                        .buttonStyle(ModulaPrimaryButtonStyle(accent: app.appearance.accent.color))
                        Button("Prepare Again") { model.reset() }
                            .font(.subheadline)
                    case .failed(let message):
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.subheadline)
                        Button("Try Again") { Task { await model.start(client: app.client) } }
                    }
                }
                .animation(ModulaMotion.animation(.contentTransition, personality: app.appearance.motion, reduceMotion: reduceMotion), value: model.state)
                .padding(.vertical, 4)
            }
            SettingsAPIFootnote(text: "Exports are generated for your account only and expire after 7 days on the server. The file stays on this device until you share it.")
        }
        .navigationTitle("Export")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("settings.data.export")
    }

    private func includedRow(_ title: String, _ subtitle: String, _ symbol: String) -> some View {
        HStack(spacing: 13) {
            Image(systemName: symbol).frame(width: 28).foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 48)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Help → Guides (real destinations, no placeholder articles)

struct HelpGuidesView: View {
    @Environment(AppEnvironment.self) private var app

    private struct Guide: Identifiable {
        let id: String
        let title: String
        let summary: String
        let symbol: String
        let action: String
        let route: SettingsRoute
    }

    private var guides: [Guide] {
        [
            Guide(id: "modules", title: "Modules", summary: "Modules are apps that run inside Modula. Each one asks for permissions when you install it, and you can review or revoke them at any time.", symbol: "shippingbox", action: "Open Modules", route: .modules(.root)),
            Guide(id: "app-lock", title: "App Lock", summary: "App Lock hides Modula behind Face ID, Touch ID, or your passcode when you leave the app, and covers it in the app switcher.", symbol: "lock.shield", action: "Set Up App Lock", route: .privacy(.appLock)),
            Guide(id: "appearance", title: "Make it yours", summary: "Theme, accent colour, density, motion, and haptics change across the whole app. Motion always respects iOS Reduce Motion.", symbol: "paintpalette", action: "Open Appearance", route: .appearance(.root)),
            Guide(id: "notifications", title: "Notifications", summary: "Modula asks for notification permission only when you turn notifications on. You can change it later in iOS Settings.", symbol: "bell.badge", action: "Open Notifications", route: .notifications(.root)),
            Guide(id: "data", title: "Your data", summary: "Export a copy of your account data as a file, check how much space Modula uses on this device, and clear cache safely.", symbol: "internaldrive", action: "Open Data & Storage", route: .dataStorage(.root)),
        ]
    }

    var body: some View {
        SettingsScrollCanvas {
            SettingsHeroBanner(title: "Guides", subtitle: "Quick explanations, each linked to the setting it covers.", symbol: "book")
            ForEach(guides) { guide in
                ModulaCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(guide.title, systemImage: guide.symbol)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(guide.summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button {
                            app.navigation.open(.settings(guide.route))
                        } label: {
                            Label(guide.action, systemImage: "arrow.right")
                                .font(.subheadline.weight(.semibold))
                                .labelStyle(.titleAndIcon)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .modulaTapRipple(amplitude: 6)
            }
            SettingsGroup(title: "Still stuck?") {
                SettingsNavigationRow(title: "Contact support", subtitle: "Open a case or email the team", symbol: "envelope") {
                    app.navigation.open(.settings(.help(.contact)))
                }
            }
        }
        .navigationTitle("Guides")
        .navigationBarTitleDisplayMode(.inline)
    }
}
