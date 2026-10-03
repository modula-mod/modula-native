import Foundation

// MARK: - Modula legal documents (single source of truth)
//
// ⚠️ DRAFT — PENDING OWNER / LEGAL REVIEW.
// Every document below is a working draft. The copy describes only what this
// codebase actually does today (data export, support cases, diagnostics, sign-in,
// Keychain storage, App Lock, modules, privacy manifest). It is NOT final legal
// text: it has not been reviewed by the owner or a lawyer, and items marked
// "To be confirmed" are deliberate gaps (operator identity, jurisdiction, retention
// periods, liability, governing law) that must be decided by the owner, not guessed.
//
// Keep this file free of SwiftUI so the same content can be reused when the
// Modula web version is built (`markdown` renders a portable copy). When the
// text changes, bump `version` and `lastUpdated`; when it is approved, switch
// `status` to `.published` (which removes the draft notice in the app).

struct LegalDocument: Identifiable, Hashable, Sendable {
    enum Kind: String, CaseIterable, Sendable {
        case privacy, terms
    }

    enum Status: String, Sendable {
        /// Working copy, shown in the app with a visible draft notice.
        case draft
        /// Owner/legal approved.
        case published
    }

    struct Section: Identifiable, Hashable, Sendable {
        let id: String
        let title: String
        let symbol: String
        var paragraphs: [String] = []
        var bullets: [String] = []
        /// Settings destination that lets the reader act on this section, if any.
        var related: RelatedLink?
    }

    struct RelatedLink: Hashable, Sendable {
        let title: String
        let subtitle: String
        let symbol: String
        let route: SettingsRoute
    }

    let kind: Kind
    let title: String
    let summary: String
    let symbol: String
    /// Semantic document version. Bump on every wording change.
    let version: String
    /// ISO 8601 calendar date (`yyyy-MM-dd`) of the last wording change.
    let lastUpdated: String
    let status: Status
    let sections: [Section]

    var id: String { kind.rawValue }
    var isDraft: Bool { status == .draft }

    var lastUpdatedDate: Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: lastUpdated)
    }

    /// Portable Markdown copy for reuse outside the iOS app (e.g. the future web version).
    var markdown: String {
        var lines: [String] = ["# \(title)", ""]
        if isDraft {
            lines += ["> **DRAFT — pending owner and legal review.** Not final terms.", ""]
        }
        lines += ["Version \(version) · Last updated \(lastUpdated)", "", summary, ""]
        for section in sections {
            lines += ["## \(section.title)", ""]
            for paragraph in section.paragraphs { lines += [paragraph, ""] }
            if !section.bullets.isEmpty {
                lines += section.bullets.map { "- \($0)" }
                lines.append("")
            }
        }
        return lines.joined(separator: "\n")
    }

    static func document(_ kind: Kind) -> LegalDocument {
        switch kind {
        case .privacy: privacyPolicy
        case .terms: termsOfService
        }
    }
}

extension LegalDocument {
    // DRAFT — pending owner/legal review. Facts only; see file header.
    static let privacyPolicy = LegalDocument(
        kind: .privacy,
        title: "Privacy Policy",
        summary: "What Modula keeps, where it lives, and how you stay in control of it.",
        symbol: "hand.raised",
        version: "0.1.0-draft",
        lastUpdated: "2026-10-03",
        status: .draft,
        sections: [
            Section(
                id: "overview",
                title: "In short",
                symbol: "text.quote",
                paragraphs: [
                    "Modula is a native iOS app with installable modules. We keep the data needed to run your account and the content you choose to post, and we give you tools to export it or ask us about it.",
                ],
                bullets: [
                    "No third-party advertising or analytics SDKs are included in the app.",
                    "Modula does not track you across other companies’ apps or websites.",
                    "Diagnostics are only sent when you choose to include them in a support request.",
                ]
            ),
            Section(
                id: "account",
                title: "Your account",
                symbol: "person.crop.circle",
                paragraphs: [
                    "You sign in with your email address and a password. Modula’s servers store your account and profile: your handle, display name and the settings you sync to your account.",
                    "On this iPhone, your sign-in session is kept in the iOS Keychain, limited to this device and not included in backups to other devices. Signing out removes it.",
                ],
                related: RelatedLink(title: "Sessions", subtitle: "Devices signed into this account", symbol: "laptopcomputer.and.iphone", route: .account(.sessions))
            ),
            Section(
                id: "content",
                title: "Content and modules",
                symbol: "shippingbox",
                paragraphs: [
                    "Posts and activity you create are stored by Modula so they can be shown to you and to the people you share them with.",
                    "Modules are apps that run inside Modula. Each module asks for permissions when you install it, and you can review or revoke them at any time. Modules never receive your account credentials; they ask Modula for specific actions, and Modula decides whether they are allowed.",
                ],
                related: RelatedLink(title: "Modules", subtitle: "Installed modules and their permissions", symbol: "shippingbox", route: .modules(.root))
            ),
            Section(
                id: "device",
                title: "On this device",
                symbol: "iphone",
                paragraphs: [
                    "App Lock uses Face ID, Touch ID or your passcode through iOS. Modula never receives your biometric data.",
                    "Local Intelligence features run on this iPhone. Appearance and many other preferences are saved only on this device.",
                    "Modula asks for permissions such as notifications only when you turn on a feature that needs them. You can change them at any time in iOS Settings.",
                ],
                related: RelatedLink(title: "App Lock", subtitle: "Protect Modula on this device", symbol: "lock.fill", route: .privacy(.appLock))
            ),
            Section(
                id: "support",
                title: "Support requests and diagnostics",
                symbol: "envelope",
                paragraphs: [
                    "When you open a support case, we keep its category, subject, your message and a reference number so the team can reply.",
                    "You can optionally attach diagnostics. You see them before sending, and they are limited to technical details: app version and build, iOS version, device model, language and time zone, network type, Low Power Mode, accessibility and theme settings, installed modules, runtime state and free storage. They never include your messages, contacts or sign-in tokens.",
                ],
                related: RelatedLink(title: "Contact", subtitle: "Open a case or email support", symbol: "envelope", route: .help(.contact))
            ),
            Section(
                id: "rights",
                title: "Your choices",
                symbol: "slider.horizontal.3",
                paragraphs: [
                    "You can export a machine-readable copy of your account, profile, content and supported module data at any time. Exports are prepared for your account only and expire on our servers after 7 days; the file stays on your device until you share it.",
                    "For any other privacy question, including correcting or deleting your data, open a Privacy & data case from Contact. Deleting your account directly from the app isn’t available yet.",
                ],
                related: RelatedLink(title: "Export your data", subtitle: "Download a copy of your account data", symbol: "square.and.arrow.up", route: .dataStorage(.export))
            ),
            Section(
                id: "to-confirm",
                title: "To be confirmed",
                symbol: "pencil.and.list.clipboard",
                paragraphs: [
                    "This policy is a draft. The following will be added after review:",
                ],
                bullets: [
                    "Who operates Modula and how to reach the data controller.",
                    "How long account, content and support data are kept.",
                    "Where servers are located and any service providers involved.",
                    "Legal bases for processing and region-specific rights.",
                ]
            ),
        ]
    )

    // DRAFT — pending owner/legal review. Describes the service; legal terms are left
    // as explicit gaps for the owner to decide.
    static let termsOfService = LegalDocument(
        kind: .terms,
        title: "Terms of Service",
        summary: "The ground rules for using Modula and its modules.",
        symbol: "doc.text",
        version: "0.1.0-draft",
        lastUpdated: "2026-10-03",
        status: .draft,
        sections: [
            Section(
                id: "service",
                title: "The service",
                symbol: "square.grid.2x2",
                paragraphs: [
                    "Modula is a native iOS app made of a core shell and installable modules. Some features depend on Modula’s servers; you can check their health at any time in Service Status.",
                ],
                related: RelatedLink(title: "Service Status", subtitle: "Live service health", symbol: "waveform.path.ecg", route: .help(.status))
            ),
            Section(
                id: "account",
                title: "Your account",
                symbol: "person.crop.circle",
                paragraphs: [
                    "You need an account to post, open support cases and export your data. Keep your password private and sign out of devices you no longer use. App Lock adds protection on shared devices.",
                ],
                related: RelatedLink(title: "Account", subtitle: "Personal information, sessions and sign out", symbol: "person.crop.circle", route: .account(.root))
            ),
            Section(
                id: "modules",
                title: "Modules",
                symbol: "shippingbox",
                paragraphs: [
                    "Modules are installed from Modula’s module catalogue. A module can only do what you have allowed it to, and you can remove its permissions or the module itself at any time.",
                ]
            ),
            Section(
                id: "content",
                title: "Your content",
                symbol: "square.stack",
                paragraphs: [
                    "You can export what you have posted at any time from Data & Storage.",
                ]
            ),
            Section(
                id: "support",
                title: "Support",
                symbol: "envelope",
                paragraphs: [
                    "If something goes wrong, open a case from Contact. Each case gets a reference you can quote.",
                ],
                related: RelatedLink(title: "Contact", subtitle: "Open a case or email support", symbol: "envelope", route: .help(.contact))
            ),
            Section(
                id: "to-confirm",
                title: "To be confirmed",
                symbol: "pencil.and.list.clipboard",
                paragraphs: [
                    "These terms are a draft. The following will be added after review:",
                ],
                bullets: [
                    "Who provides Modula and eligibility to use it.",
                    "Acceptable use and content rules, and how they are enforced.",
                    "Ownership of and licence to content you post.",
                    "Rules for third-party module developers.",
                    "Paid features, if any.",
                    "Disclaimers, limitation of liability and governing law.",
                    "How changes to these terms are announced.",
                ]
            ),
        ]
    )
}
