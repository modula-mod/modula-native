import SwiftUI

// MARK: - Modula glass sheet kit (feed, summary and Discover option sheets)

/// Sheet body in the Modula look: a bold title, a glass close button and glass sections, in the app's
/// font design (sheets are a separate presentation tree, so the shell's `.fontDesign` is re-applied).
struct ModulaGlassSheetScaffold<Content: View>: View {
    let title: String
    var subtitle: String?
    var identifier: String
    @ViewBuilder var content: () -> Content
    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title).font(.title2.weight(.bold)).accessibilityAddTraits(.isHeader)
                        if let subtitle {
                            Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 8)
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.primary)
                            .frame(width: 38, height: 38)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .modulaGlass(in: Circle(), interactive: true, specular: true)
                    .accessibilityLabel("Close")
                    .accessibilityIdentifier("\(identifier).close")
                }
                content()
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 28)
        }
        .scrollBounceBehavior(.basedOnSize)
        .fontDesign(app.appearance.fontDesign)
        .accessibilityIdentifier(identifier)
    }
}

/// A titled glass group of rows.
struct ModulaGlassSheetSection<Content: View>: View {
    var title: String?
    var footer: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title).font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                    .padding(.leading, 4).accessibilityAddTraits(.isHeader)
            }
            VStack(spacing: 0) { content() }
                .frame(maxWidth: .infinity, alignment: .leading)
                .modulaGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous), interactive: false)
            if let footer {
                Text(footer).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Glass toggle row with an optional one-line explanation.
struct ModulaGlassToggleRow: View {
    let title: String
    var detail: String?
    var symbol: String
    @Binding var isOn: Bool
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 12) {
                ModulaGlassSheetIcon(symbol: symbol)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.medium))
                    if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
                }
            }
        }
        .tint(app.appearance.liveAccent)
        .padding(.horizontal, 16).padding(.vertical, 12)
    }
}

/// Glass action row: icon, title, optional detail and a chevron.
struct ModulaGlassActionRow: View {
    let title: String
    var detail: String?
    var symbol: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ModulaGlassSheetIcon(symbol: symbol)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.medium)).foregroundStyle(.primary)
                    if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct ModulaGlassSheetIcon: View {
    let symbol: String
    @Environment(AppEnvironment.self) private var app
    var body: some View {
        Image(systemName: symbol)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(app.appearance.liveAccent)
            .frame(width: 32, height: 32)
            .background(Circle().fill(app.appearance.liveAccent.opacity(0.12)))
            .accessibilityHidden(true)
    }
}

struct ModulaGlassRowDivider: View {
    var body: some View { Divider().padding(.leading, 60) }
}

extension HomeMode {
    var feedSymbol: String {
        switch self {
        case .following: "person.2.fill"
        case .forYou: "sparkles"
        case .modules: "shippingbox.fill"
        }
    }
    var feedBlurb: String {
        switch self {
        case .following: "People you follow"
        case .forYou: "Picked for you"
        case .modules: "Module updates"
        }
    }
}

enum ModulaPlural {
    /// "1 post", "2 posts".
    static func count(_ n: Int, _ singular: String, _ plural: String? = nil) -> String {
        "\(n.formatted()) \(n == 1 ? singular : (plural ?? singular + "s"))"
    }
}

// MARK: - Summary

struct HomeSummarySheet: View {
    @Environment(AppEnvironment.self) private var app

    private var mode: HomeMode {
        if case .home(let mode) = app.navigation.currentRoute { return mode }
        return .following
    }

    var body: some View {
        let summary = app.home.summary(for: mode)
        ModulaGlassSheetScaffold(
            title: "\(mode.heroSubtitle) at a glance",
            subtitle: summary.postCount == 0 ? nil : "Across the \(ModulaPlural.count(summary.postCount, "post")) loaded right now.",
            identifier: "home.summary"
        ) {
            if summary.postCount == 0 {
                VStack(spacing: 10) {
                    Image(systemName: "text.bubble").font(.largeTitle).foregroundStyle(.secondary)
                    Text("Nothing loaded yet").font(.headline)
                    Text("Pull to refresh \(mode.heroSubtitle), then check back here.")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 28)
                .modulaGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous), interactive: false)
            } else {
                ModulaGlassGroup(spacing: 10) {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        stat("Posts", summary.postCount, "text.alignleft")
                        stat("Likes", summary.likeCount, "heart.fill")
                        stat("Replies", summary.replyCount, "bubble.left.and.bubble.right.fill")
                        stat("With media", summary.mediaCount, "photo.fill")
                        if summary.moduleCount > 0 { stat("Module posts", summary.moduleCount, "shippingbox.fill") }
                    }
                }
                if !summary.authorNames.isEmpty {
                    ModulaGlassSheetSection(title: "Most active") {
                        ForEach(Array(summary.authorNames.enumerated()), id: \.offset) { i, name in
                            if i > 0 { ModulaGlassRowDivider() }
                            HStack(spacing: 12) {
                                ModulaAvatar(initials: String(name.prefix(2)).uppercased(), size: 32, name: name)
                                Text(name).font(.body.weight(.medium)).lineLimit(1)
                                Spacer()
                                if i == 0 { Image(systemName: "crown.fill").foregroundStyle(.yellow).accessibilityLabel("Most posts") }
                            }
                            .padding(.horizontal, 16).padding(.vertical, 10)
                        }
                    }
                }
            }
        }
    }

    private func stat(_ title: String, _ value: Int, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ModulaGlassSheetIcon(symbol: symbol)
            Text(value.formatted()).font(.title2.weight(.bold)).monospacedDigit().contentTransition(.numericText())
            Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .modulaGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous), interactive: false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(value)")
    }
}

// MARK: - Feeds (switcher + display options + following)

/// Former "Tools" sheet: refresh and Manage following now live in the Feeds sheet / accessory once each.
typealias HomeFeedToolsSheet = HomeFeedsSheet

struct HomeFeedsSheet: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss

    private var mode: HomeMode {
        if case .home(let mode) = app.navigation.currentRoute { return mode }
        return .following
    }

    var body: some View {
        let options = app.home.displayOptions(for: mode)
        ModulaGlassSheetScaffold(title: "Feeds", identifier: "home.feeds") {
            ModulaGlassGroup(spacing: 10) {
                HStack(spacing: 10) {
                    ForEach(HomeMode.allCases, id: \.self) { feed in feedCard(feed) }
                }
            }
            ModulaGlassSheetSection(title: "Show in \(mode.heroSubtitle)") {
                ModulaGlassToggleRow(title: "Media only", detail: "Photos and videos", symbol: "photo.on.rectangle", isOn: Binding(
                    get: { options.mediaOnly },
                    set: { value in
                        var next = options
                        next.mediaOnly = value
                        app.home.setDisplayOptions(next, for: mode)
                        HapticEngine.shared.play(.selection)
                    }
                ))
                .accessibilityIdentifier("home.feeds.media-only")
                ModulaGlassRowDivider()
                ModulaGlassToggleRow(title: "Hide module posts", detail: "Only posts from people", symbol: "shippingbox", isOn: Binding(
                    get: { options.hideModules },
                    set: { value in
                        var next = options
                        next.hideModules = value
                        app.home.setDisplayOptions(next, for: mode)
                        HapticEngine.shared.play(.selection)
                    }
                ))
                .accessibilityIdentifier("home.feeds.hide-modules")
            }
            ModulaGlassSheetSection {
                ModulaGlassActionRow(title: "Manage following", detail: "Find people to follow or unfollow", symbol: "person.2") {
                    dismiss()
                    app.navigation.open(.discover(.people))
                    HapticEngine.shared.play(.navigation)
                }
                .accessibilityIdentifier("home.feeds.following")
            }
        }
    }

    private func feedCard(_ feed: HomeMode) -> some View {
        let selected = feed == mode
        let accent = app.appearance.liveAccent
        return Button {
            app.navigation.replaceContext(with: .home(feed))
            HapticEngine.shared.play(.navigation)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: feed.feedSymbol)
                    .font(.headline)
                    .foregroundStyle(selected ? .white : accent)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(selected ? AnyShapeStyle(accent.gradient) : AnyShapeStyle(accent.opacity(0.12))))
                VStack(alignment: .leading, spacing: 2) {
                    Text(feed.heroSubtitle).font(.subheadline.weight(.bold)).foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.8)
                    Text(feed.feedBlurb).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
            .padding(12)
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill").font(.subheadline).foregroundStyle(accent).padding(10)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .modulaGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous), interactive: true,
                     tint: selected ? accent.opacity(0.18) : nil)
        .accessibilityLabel("\(feed.heroSubtitle). \(feed.feedBlurb)")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("home.feeds.\(feed.rawValue)")
    }
}
