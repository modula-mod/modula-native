import SwiftUI

struct ProfileAboutField: View {
    let title: String
    let value: String
    var action: (() -> Void)? = nil
    @Environment(\.profileAccentColor) private var profileAccent
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if let action {
                Button(value, action: action)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(profileAccent ?? app.appearance.accent.color)
                    .buttonStyle(.plain)
            } else {
                Text(value)
                    .font(.subheadline.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct ProfileAccentPicker: View {
    @Binding var selection: ProfileAccent?
    var writable: Bool
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Profile Accent")
                .font(.headline)
            Text("This is how your public Profile identifies itself. It does not change how visitors see Modula’s tab bar or Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if writable {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(ProfileAccent.allCases) { accent in
                            Button {
                                selection = accent
                                HapticEngine.shared.play(.selection)
                            } label: {
                                Circle()
                                    .fill(accent.color)
                                    .frame(width: 36, height: 36)
                                    .overlay {
                                        if selection == accent {
                                            Image(systemName: "checkmark")
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(.white)
                                        }
                                    }
                                    .overlay(Circle().stroke(Color.primary.opacity(0.15)))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(accent.title)
                            .accessibilityAddTraits(selection == accent ? [.isSelected, .isButton] : .isButton)
                        }
                    }
                }
            } else if let selection {
                HStack {
                    Circle().fill(selection.color).frame(width: 22, height: 22)
                    Text(selection.title)
                    Text("Not writable on Greenfield yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No public accent is stored yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("profile.accent.picker")
    }
}

struct ProfileLinksEditor: View {
    let links: [ProfileLink]
    var writable: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Links")
                .font(.headline)
            if links.isEmpty {
                Text("No public links yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(links) { link in
                    HStack {
                        Image(systemName: "line.3.horizontal")
                            .foregroundStyle(.tertiary)
                            .opacity(writable ? 1 : 0)
                        VStack(alignment: .leading) {
                            Text(link.label).font(.subheadline.weight(.semibold))
                            Text(link.domain ?? link.url?.host ?? "")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(link.visibility.displayTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(minHeight: 44)
                }
            }
            if !writable {
                Text("Link add, remove, and reorder wait on a Greenfield write contract.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .accessibilityIdentifier("profile.links.editor")
    }
}

struct FeaturedModulesEditor: View {
    let featuredIDs: [String]
    let available: [CatalogueProduct]
    var writable: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Modules")
                .font(.headline)
            if featuredIDs.isEmpty && available.isEmpty {
                Text("No featured modules yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("Featured")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(featuredIDs, id: \.self) { id in
                    HStack {
                        Image(systemName: "line.3.horizontal")
                            .opacity(writable ? 1 : 0)
                        Text(available.first { $0.moduleId == id }?.name ?? id)
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(minHeight: 44)
                }
                let unused = available.filter { !featuredIDs.contains($0.moduleId) }
                if !unused.isEmpty {
                    Text("Available")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(unused) { product in
                        HStack {
                            Image(systemName: "plus")
                            Text(product.name)
                        }
                        .foregroundStyle(.secondary)
                        .frame(minHeight: 44)
                    }
                }
            }
            if !writable {
                Text("Featured module order is read-only until Greenfield can persist it.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .accessibilityIdentifier("profile.modules.editor")
    }
}

struct ProfileVisitorPreviewBanner: View {
    var onExit: () -> Void

    var body: some View {
        HStack {
            Text("Preview as visitor — public fields only. The server remains the privacy authority.")
                .font(.caption)
            Spacer()
            Button("Exit", action: onExit)
                .font(.caption.weight(.semibold))
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityIdentifier("profile.visitor.preview")
    }
}
