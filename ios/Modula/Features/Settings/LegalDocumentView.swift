import SwiftUI

/// Native in-app rendering of a `LegalDocument` (Privacy Policy, Terms of Service).
///
/// Content lives in `Core/Settings/LegalDocuments.swift`; this view only presents it
/// with the Settings visual system. Text scales with Dynamic Type, is selectable, and
/// section titles are exposed as headers for VoiceOver rotor navigation.
struct LegalDocumentView: View {
    let document: LegalDocument
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        SettingsScrollCanvas {
            SettingsHeroBanner(title: document.title, subtitle: document.summary, symbol: document.symbol)
            if document.isDraft { draftNotice }
            metadata
            ForEach(document.sections) { section in
                sectionView(section)
                    .id(section.id)
            }
            SettingsGroup(title: "Related") {
                VStack(spacing: 0) {
                    let other: LegalDocument.Kind = document.kind == .privacy ? .terms : .privacy
                    let otherDocument = LegalDocument.document(other)
                    SettingsNavigationRow(title: otherDocument.title, subtitle: otherDocument.summary, symbol: otherDocument.symbol) {
                        app.navigation.open(.settings(.about(other == .privacy ? .privacy : .terms)))
                    }
                    SettingsDivider()
                    SettingsNavigationRow(title: "Questions?", subtitle: "Open a case with the Modula team", symbol: "envelope") {
                        app.navigation.open(.settings(.help(.contact)))
                    }
                }
            }
            SettingsAPIFootnote(text: "This document is part of the app, so you can read it offline. A web copy will follow when Modula on the web launches.")
        }
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("settings.about.\(document.kind.rawValue)")
    }

    private var draftNotice: some View {
        ModulaCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "pencil.and.outline")
                    .font(.title3)
                    .foregroundStyle(app.appearance.liveAccent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Draft")
                        .font(.headline)
                    Text("This is a working draft that describes how Modula works today. It hasn’t been finalised and may change before release.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("settings.legal.draft")
    }

    private var metadata: some View {
        ModulaCard {
            VStack(spacing: 0) {
                LabeledContent("Version", value: document.version)
                    .frame(minHeight: ModulaLayout.minimumTouch)
                Divider()
                LabeledContent("Last updated", value: formattedDate)
                    .frame(minHeight: ModulaLayout.minimumTouch)
            }
            .font(.subheadline)
        }
    }

    private var formattedDate: String {
        guard let date = document.lastUpdatedDate else { return document.lastUpdated }
        return date.formatted(Date.FormatStyle(date: .long, time: .omitted, timeZone: TimeZone(identifier: "UTC") ?? .current))
    }

    private func sectionView(_ section: LegalDocument.Section) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Label(section.title, systemImage: section.symbol)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            ModulaCard {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(section.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                        Text(paragraph)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !section.bullets.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(section.bullets.enumerated()), id: \.offset) { _, bullet in
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    Circle()
                                        .fill(app.appearance.liveAccent)
                                        .frame(width: 6, height: 6)
                                        .accessibilityHidden(true)
                                    Text(bullet)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                    if let related = section.related {
                        Button {
                            app.navigation.open(.settings(related.route))
                        } label: {
                            Label(related.title, systemImage: "arrow.right")
                                .font(.subheadline.weight(.semibold))
                                .labelStyle(.titleAndIcon)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityHint(related.subtitle)
                    }
                }
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
