import SwiftUI

/// Telegram-style media panel shown in place of the keyboard: Emoji and GIFs.
/// Stickers are omitted until Greenfield has a sticker source (no placeholder packs).
struct ModulaComposerMediaPanel: View {
    enum Tab: String, CaseIterable, Identifiable {
        case emoji = "Emoji", gifs = "GIFs"
        var id: String { rawValue }
        var systemImage: String { self == .emoji ? "face.smiling" : "play.square.stack" }
    }

    var client: GreenfieldClient
    var initialTab: Tab = .emoji
    var allowsGifs = true
    var onEmoji: (String) -> Void
    var onGif: (ModulaGif) -> Void

    @State private var tab: Tab = .emoji
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 8) {
            if allowsGifs {
                ModulaGlassGroup(spacing: 6) {
                    HStack(spacing: 6) {
                        ForEach(Tab.allCases) { item in
                            Button {
                                tab = item
                                HapticEngine.shared.play(.selection)
                            } label: {
                                Label(item.rawValue, systemImage: item.systemImage)
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 14)
                                    .frame(minHeight: 36)
                                    .foregroundStyle(tab == item ? Color.primary : Color.secondary)
                            }
                            .buttonStyle(.plain)
                            .modulaGlass(in: Capsule(), tint: tab == item ? .accentColor : nil)
                            .accessibilityAddTraits(tab == item ? .isSelected : [])
                            .accessibilityIdentifier("composer.panel.\(item.rawValue.lowercased())")
                        }
                    }
                }
                .padding(.top, 8)
            }
            Group {
                switch tab {
                case .emoji: ModulaEmojiGrid(onPick: onEmoji)
                case .gifs: ModulaGifPicker(repository: GreenfieldGifRepository(client: client), onPick: onGif)
                }
            }
            .transition(.opacity)
        }
        .frame(height: 300)
        .frame(maxWidth: .infinity)
        .modulaGlass(in: UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous), interactive: false)
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: tab)
        .onAppear { tab = allowsGifs ? initialTab : .emoji }
        .accessibilityIdentifier("composer.panel")
    }
}

struct ModulaEmojiGrid: View {
    var onPick: (String) -> Void
    @AppStorage("composer.recentEmoji") private var recentRaw = ""

    private static let sections: [(String, [ClosedRange<UInt32>])] = [
        ("Smileys & people", [0x1F600...0x1F64F, 0x1F910...0x1F92F, 0x1F970...0x1F97F, 0x1F44A...0x1F450]),
        ("Animals & nature", [0x1F400...0x1F43F, 0x1F330...0x1F343]),
        ("Food & drink", [0x1F345...0x1F37F, 0x1F950...0x1F96F]),
        ("Activities & travel", [0x1F380...0x1F3FF, 0x1F680...0x1F6C5]),
        ("Objects & symbols", [0x1F4A0...0x1F4FF, 0x2600...0x26FF, 0x1F9E0...0x1F9FF])
    ]

    private static let emoji: [(String, [String])] = sections.map { title, ranges in
        (title, ranges.flatMap { range in
            range.compactMap { value -> String? in
                guard let scalar = Unicode.Scalar(value), scalar.properties.isEmojiPresentation else { return nil }
                return String(Character(scalar))
            }
        })
    }

    private var recents: [String] { recentRaw.split(separator: " ").map(String.init) }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 8), alignment: .leading, spacing: 4, pinnedViews: [.sectionHeaders]) {
                if !recents.isEmpty { section("Recent", recents) }
                ForEach(Self.emoji, id: \.0) { title, items in section(title, items) }
            }
            .padding(.horizontal, 10)
        }
        .accessibilityIdentifier("composer.panel.emoji.grid")
    }

    private func section(_ title: String, _ items: [String]) -> some View {
        Section {
            ForEach(items, id: \.self) { emoji in
                Button {
                    onPick(emoji)
                    var list = recents.filter { $0 != emoji }
                    list.insert(emoji, at: 0)
                    recentRaw = list.prefix(24).joined(separator: " ")
                    HapticEngine.shared.play(.selection)
                } label: {
                    Text(emoji).font(.system(size: 30)).frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(emoji)
            }
        } header: {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
        }
    }
}

struct ModulaGifPicker: View {
    var repository: GreenfieldGifRepository
    var onPick: (ModulaGif) -> Void

    @State private var query = ""
    @State private var items: [ModulaGif] = []
    @State private var nextOffset: Int?
    @State private var state: LoadState = .idle

    enum LoadState: Equatable { case idle, loading, loaded, notConfigured, failed(String) }

    var body: some View {
        VStack(spacing: 8) {
            ModulaGlassSearchField(prompt: "Search GIFs", text: $query).padding(.horizontal, 12)
            content
        }
        .task(id: query) {
            // Debounce typing; empty query shows trending.
            if !query.isEmpty { try? await Task.sleep(for: .milliseconds(350)) }
            guard !Task.isCancelled else { return }
            await load(reset: true)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .notConfigured:
            ContentUnavailableView {
                Label("GIFs aren’t set up yet", systemImage: "play.square.stack")
            } description: {
                Text("GIF search turns on once the Modula server has a GIF provider key.")
            }
            .accessibilityIdentifier("composer.gifs.unconfigured")
        case .failed(let message):
            ContentUnavailableView {
                Label("Couldn’t load GIFs", systemImage: "wifi.exclamationmark")
            } description: { Text(message) } actions: {
                Button("Retry") { Task { await load(reset: true) } }
            }
        default:
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 4), GridItem(.flexible(), spacing: 4), GridItem(.flexible(), spacing: 4)], spacing: 4) {
                    ForEach(items) { gif in
                        Button { onPick(gif) } label: {
                            ModulaAnimatedRemoteImage(url: gif.previewURL)
                                .frame(height: 96)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(gif.title ?? "GIF")
                        .onAppear {
                            if gif.id == items.last?.id, nextOffset != nil { Task { await load(reset: false) } }
                        }
                    }
                }
                .padding(.horizontal, 10)
                if state == .loading { ProgressView().padding() }
                Text("Powered by GIPHY").font(.caption2).foregroundStyle(.tertiary).padding(.bottom, 6)
            }
        }
    }

    private func load(reset: Bool) async {
        guard state != .loading || reset else { return }
        let offset = reset ? 0 : (nextOffset ?? 0)
        state = .loading
        do {
            let result = query.trimmingCharacters(in: .whitespaces).isEmpty
                ? try await repository.trending(offset: offset)
                : try await repository.search(query, offset: offset)
            items = reset ? result.items : items + result.items.filter { gif in !items.contains { $0.id == gif.id } }
            nextOffset = result.nextOffset
            state = .loaded
        } catch ModulaGifError.notConfigured {
            state = .notConfigured
        } catch ModulaGifError.failed(let message) {
            state = .failed(message)
        } catch {
            state = .failed("Try again in a moment.")
        }
    }
}
