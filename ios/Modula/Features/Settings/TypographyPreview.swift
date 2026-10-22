import SwiftUI

enum FontSampleKind: String, CaseIterable, Identifiable, EdgeLoopItem {
    case letters
    case numbers
    case body
    case symbols

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .letters: "textformat"
        case .numbers: "number"
        case .body: "text.alignleft"
        case .symbols: "asterisk"
        }
    }

    var label: String {
        switch self {
        case .letters: "Letters"
        case .numbers: "Numbers"
        case .body: "Body"
        case .symbols: "Symbols"
        }
    }

    var accessibilityLabel: String { label }
}

struct TypographyPreviewCard: View {
    var family: AppearanceStore.FontFamily
    @State private var sample: FontSampleKind = .letters
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 10) {
                Text(sampleTitle)
                    .font(.system(size: 42, weight: .bold, design: design))
                    .foregroundStyle(.primary)
                    .minimumScaleFactor(0.6)
                    .lineLimit(2)
                    .accessibilityIdentifier("typography.sample.hero")
                Text(sampleBody)
                    .font(.system(size: 17, weight: .regular, design: design))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(family.rawValue.replacingOccurrences(of: "-", with: " ").capitalized)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 8)

            ContainedLoopPicker(
                items: Array(FontSampleKind.allCases),
                selection: Binding(
                    get: { sample.id },
                    set: { sample = FontSampleKind(rawValue: $0) ?? .letters }
                ),
                behavior: .bounded
            )
            .frame(width: 52, height: 168)
        }
        // Grow with the sample instead of clipping the last line at larger text sizes.
        .frame(minHeight: 176)
        .fixedSize(horizontal: false, vertical: true)
        .padding(16)
        .modulaMaterial(.content, in: RoundedRectangle(cornerRadius: app.appearance.interfaceShape.radius(for: .contentCard), style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("typography.preview")
    }

    private var design: Font.Design {
        switch family {
        case .rounded, .geometric: .rounded
        case .editorial: .serif
        case .mono: .monospaced
        default: .default
        }
    }

    private var sampleTitle: String {
        switch sample {
        case .letters: "Aa"
        case .numbers: "0123456789"
        case .body: "Headline"
        case .symbols: "* & ¶ @"
        }
    }

    private var sampleBody: String {
        switch sample {
        case .letters:
            "The quick brown fox jumps over the lazy dog."
        case .numbers:
            "0123456789  24.6K  1,280"
        case .body:
            "Your digital world, your way. Clear type, deliberate rhythm, comfortable reading."
        case .symbols:
            "#modula  @handle  —  ★  ✓  →"
        }
    }
}
