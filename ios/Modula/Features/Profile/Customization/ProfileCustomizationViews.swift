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
    var showsTitle = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsTitle {
                Text("Profile Accent")
                    .font(.headline)
            }
            if writable {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(ProfileAccent.allCases) { accent in
                            Button {
                                selection = accent
                                HapticEngine.shared.play(.selection)
                            } label: {
                                Circle()
                                    .fill(accent.color)
                                    .frame(width: 34, height: 34)
                                    .overlay {
                                        if selection == accent {
                                            Image(systemName: "checkmark")
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(.white)
                                        }
                                    }
                                    .padding(3)
                                    .overlay(Circle().strokeBorder(selection == accent ? accent.color : Color.primary.opacity(0.12), lineWidth: 2))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(accent.title)
                            .accessibilityAddTraits(selection == accent ? [.isSelected, .isButton] : .isButton)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } else if let selection {
                HStack(spacing: 10) {
                    Circle().fill(selection.color).frame(width: 22, height: 22)
                    Text(selection.title)
                }
            }
        }
        .accessibilityIdentifier("profile.accent.picker")
    }
}

struct ProfileLinksEditor: View {
    let links: [ProfileLink]
    var writable: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if links.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "link")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .background(Color.primary.opacity(0.06), in: Circle())
                    Text("No links on your profile")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(minHeight: 44)
            } else {
                ForEach(Array(links.enumerated()), id: \.element.id) { index, link in
                    if index > 0 { Divider().padding(.leading, 44) }
                    HStack(spacing: 12) {
                        Image(systemName: "link")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                            .background(Color.primary.opacity(0.06), in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
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
                    .frame(minHeight: 48)
                }
            }
        }
        .accessibilityIdentifier("profile.links.editor")
    }
}

/// Compact chip picker of the modules you have installed. Tap a chip to feature or
/// un-feature it; drag a chip onto the Featured row (or onto another featured chip) to
/// feature/reorder it.
struct FeaturedModulesEditor: View {
    @Binding var featuredIDs: [String]
    /// Installed modules only.
    let installed: [CatalogueProduct]
    var writable: Bool
    var accent: Color = .accentColor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var featured: [CatalogueProduct] {
        featuredIDs.compactMap { id in installed.first { $0.moduleId == id } }
    }
    private var others: [CatalogueProduct] {
        installed.filter { !featuredIDs.contains($0.moduleId) }
    }
    private var spring: Animation? { reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.8) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if installed.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "square.grid.2x2")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No modules yet").font(.subheadline.weight(.semibold))
                        Text("Install modules to feature them on your profile.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
            } else {
                row(title: "Featured", items: featured, isFeatured: true)
                    .dropDestination(for: String.self) { ids, _ in
                        guard writable, let id = ids.first else { return false }
                        withAnimation(spring) {
                            featuredIDs.removeAll { $0 == id }
                            featuredIDs.append(id)
                        }
                        HapticEngine.shared.play(.success)
                        return true
                    }
                if !others.isEmpty {
                    row(title: "Installed", items: others, isFeatured: false)
                }
            }
        }
        .accessibilityIdentifier("profile.modules.editor")
    }

    private func row(title: String, items: [CatalogueProduct], isFeatured: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if items.isEmpty && isFeatured {
                        Label(writable ? "Tap or drag a module here" : "None featured", systemImage: "plus.circle")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14)
                            .frame(height: 36)
                            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                    }
                    ForEach(items) { product in
                        chip(product, isFeatured: isFeatured)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func chip(_ product: CatalogueProduct, isFeatured: Bool) -> some View {
        Button {
            guard writable else { return }
            withAnimation(spring) {
                if isFeatured {
                    featuredIDs.removeAll { $0 == product.moduleId }
                } else {
                    featuredIDs.append(product.moduleId)
                }
            }
            HapticEngine.shared.play(.selection)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isFeatured ? "star.fill" : "plus")
                    .font(.caption.weight(.bold))
                Text(product.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(isFeatured ? Color.white : Color.primary)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(isFeatured ? AnyShapeStyle(accent) : AnyShapeStyle(Color.primary.opacity(0.07)), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!writable)
        .draggable(product.moduleId)
        .dropDestination(for: String.self) { ids, _ in
            guard writable, isFeatured, let id = ids.first, id != product.moduleId else { return false }
            withAnimation(spring) {
                featuredIDs.removeAll { $0 == id }
                let target = featuredIDs.firstIndex(of: product.moduleId) ?? featuredIDs.endIndex
                featuredIDs.insert(id, at: target)
            }
            HapticEngine.shared.play(.success)
            return true
        }
        .accessibilityLabel(product.name)
        .accessibilityHint(isFeatured ? "Remove from featured" : "Feature on your profile")
        .accessibilityAddTraits(isFeatured ? .isSelected : [])
    }
}

struct ProfileVisitorPreviewBanner: View {
    var onExit: () -> Void

    var body: some View {
        HStack {
            Text("Previewing your profile as a visitor.")
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
