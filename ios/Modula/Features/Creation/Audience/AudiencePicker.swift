import SwiftUI

struct AudiencePicker: View {
    @Binding var selection: AudienceSelection
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        Menu {
            ForEach(AudienceSelection.allCases, id: \.self) { option in
                Button {
                    selection = option
                } label: {
                    VStack(alignment: .leading) {
                        Text(option.title)
                        Text(option.explanation)
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: audienceSymbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(app.appearance.accent.color)
                Text(selection.title)
                    .font(.subheadline.weight(.semibold))
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .modulaGlass(
                in: Capsule(),
                interactive: true,
                tint: app.appearance.accent.color.opacity(0.22),
                specular: true
            )
        }
        .accessibilityLabel("Audience")
        .accessibilityValue(selection.title)
        .accessibilityHint(selection.explanation)
        .accessibilityIdentifier("compose.audience")
        .fontDesign(.default)
    }

    private var audienceSymbol: String {
        switch selection {
        case .everyone: "globe"
        case .followers: "person.2.fill"
        case .onlyMe: "lock.fill"
        }
    }
}
