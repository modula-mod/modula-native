import SwiftUI

enum FontSampleKind: String, CaseIterable, Identifiable, Hashable {
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
        VStack(alignment: .leading, spacing: ModulaSpacing.sm) {
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

            // Standard segmented control (replaces the retired ContainedLoopPicker / EdgeLoop reel).
            Picker("Sample", selection: $sample) {
                ForEach(FontSampleKind.allCases) { kind in
                    Label(kind.label, systemImage: kind.icon)
                        .labelStyle(.titleOnly)
                        .tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("typography.sample.picker")
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
