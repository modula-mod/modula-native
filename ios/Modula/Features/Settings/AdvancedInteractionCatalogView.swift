import SwiftUI

enum AdvancedInteractionCatalogRoute: String, CaseIterable, Identifiable {
    case context
    case reactions
    case overlays
    case sheets
    case tabs
    case spaces
    case selection
    case media
    case sharing
    case indicators
    case composer

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .context: "rectangle.and.hand.point.up.left"
        case .reactions: "face.smiling"
        case .overlays: "square.stack.3d.up"
        case .sheets: "rectangle.bottomhalf.inset.filled"
        case .tabs: "rectangle.3.group"
        case .spaces: "square.grid.2x2"
        case .selection: "checkmark.circle"
        case .media: "photo.on.rectangle.angled"
        case .sharing: "square.and.arrow.up"
        case .indicators: "circlebadge.2"
        case .composer: "text.bubble"
        }
    }
}

struct AdvancedInteractionCatalogView: View {
    var body: some View {
        List {
            Section {
                Text("Production components with interactive state labs. All examples use the live Modula appearance, motion, and haptic systems.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Families") {
                ForEach(AdvancedInteractionCatalogRoute.allCases) { route in
                    NavigationLink {
                        destination(route)
                    } label: {
                        Label(route.title, systemImage: route.symbol)
                    }
                    .accessibilityIdentifier("catalog.advanced.\(route.rawValue)")
                }
            }
        }
        .navigationTitle("Advanced Interaction")
        .accessibilityIdentifier("catalog.advanced")
    }

    @ViewBuilder private func destination(_ route: AdvancedInteractionCatalogRoute) -> some View {
        switch route {
        case .context: ContextCatalogPage()
        case .reactions: ReactionsCatalogPage()
        case .overlays: OverlaysCatalogPage()
        case .sheets: SheetsCatalogPage()
        case .tabs: TabsCatalogPage()
        case .spaces: SpacesCatalogPage()
        case .selection: SelectionCatalogPage()
        case .media: MediaCatalogPage()
        case .sharing: SharingCatalogPage()
        case .indicators: IndicatorsCatalogPage()
        case .composer: ComposerCatalogPage()
        }
    }
}

struct CatalogLabSection<Content: View>: View {
    let title: String
    var note: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: ModulaSpacing.sm) {
            Text(title).font(.headline)
            if let note { Text(note).font(.caption).foregroundStyle(.secondary) }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ModulaSpacing.md)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: ModulaRadius.medium, style: .continuous))
    }
}
