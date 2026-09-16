import SwiftUI

struct AudiencePicker: View {
    @Binding var selection: AudienceSelection

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
            HStack(spacing: 4) {
                Text(selection.title)
                    .font(.subheadline.weight(.semibold))
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.thinMaterial, in: Capsule())
        }
        .accessibilityLabel("Audience")
        .accessibilityValue(selection.title)
        .accessibilityHint(selection.explanation)
        .accessibilityIdentifier("compose.audience")
        .fontDesign(.default)
    }
}
