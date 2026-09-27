import SwiftUI

struct MediaCatalogPage: View {
    @State private var viewerPresented = false
    @State private var initialID = "portrait"

    private let items = [
        ModulaMediaViewerItem(id: "portrait", title: "Portrait", source: .symbol("person.crop.rectangle"), accessibilityDescription: "Portrait image fixture", allowsShare: false),
        ModulaMediaViewerItem(id: "landscape", title: "Landscape", source: .symbol("mountain.2"), accessibilityDescription: "Landscape image fixture", allowsShare: false),
        ModulaMediaViewerItem(id: "dark", title: "Dark Content", source: .symbol("moon.stars"), accessibilityDescription: "Dark content fixture", allowsShare: false),
        ModulaMediaViewerItem(id: "light", title: "Light Content", source: .symbol("sun.max"), accessibilityDescription: "Light content fixture", allowsShare: false)
    ]

    var body: some View {
        List {
            Section("Fixtures") {
                ForEach(items) { item in
                    Button {
                        initialID = item.id
                        viewerPresented = true
                    } label: {
                        Label(item.title, systemImage: mediaSymbol(item))
                    }
                }
            }
            Section("Gestures") {
                Text("Swipe to page, pinch or double-tap to zoom, pan while zoomed, and drag down to dismiss at rest. Paging is suspended during zoom to avoid gesture conflict.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .fullScreenCover(isPresented: $viewerPresented) {
            ModulaMediaViewer(items: items, initialID: initialID) { viewerPresented = false }
        }
        .navigationTitle("Media")
    }

    private func mediaSymbol(_ item: ModulaMediaViewerItem) -> String {
        if case .symbol(let symbol) = item.source { return symbol }
        return "photo"
    }
}

struct SharingCatalogPage: View {
    private let payload = SharePayload.module(id: "digital.modula.vault-notes", name: "Vault Notes", publisher: "Modula")

    private var destinations: [ShareDestination] {
        ShareDestinationRegistry.destinations(
            for: payload,
            messagingSend: true,
            inMailCompose: true,
            collectionsAvailable: true
        )
    }

    var body: some View {
        List {
            Section("Preview") { ModulaSharePreview(payload: payload) }
            Section("Pre-share actions") {
                ForEach(destinations) { destination in
                    ModulaShareActionRow(destination: destination) {
                        HapticEngine.shared.play(.actionConfirmed)
                    }
                }
            }
            Section {
                Text("Modula provides a focused pre-share surface, then hands external destinations to Apple's system share controller.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Sharing")
    }
}

struct ComposerCatalogPage: View {
    @State private var text = ""
    @State private var focused = false
    @State private var enabled = true
    @State private var sending = false
    @State private var multiline = false
    @State private var attachment = false
    @State private var sentMessage = ""

    private var attachments: [ModulaComposerAttachment] {
        attachment ? [.init(id: "document", title: "Project brief.pdf", systemImage: "doc")] : []
    }

    var body: some View {
        Form {
            Section("Lab") {
                Toggle("Focused", isOn: $focused)
                Toggle("Enabled", isOn: $enabled)
                Toggle("Sending", isOn: $sending)
                Toggle("Multiline sample", isOn: $multiline)
                Toggle("Attachment", isOn: $attachment)
            }
            Section("Composer") {
                ModulaComposer(
                    text: $text,
                    prompt: "Ask or reply…",
                    enabled: enabled,
                    sending: sending,
                    attachments: attachments,
                    externalFocus: $focused,
                    onAttachment: { attachment.toggle() },
                    onSend: {
                        sentMessage = text
                        text = ""
                    }
                )
                if !sentMessage.isEmpty {
                    Text("Sent: \(sentMessage)").font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("States") {
                Text("Empty, typing, multiline, focused, keyboard-visible, disabled, sending, and attachment states use the same production primitive.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onChange(of: multiline) { _, value in
            text = value ? "This is a longer composer fixture that wraps onto multiple lines while preserving a minimum forty-four point target." : ""
        }
        .navigationTitle("Composer")
    }
}
