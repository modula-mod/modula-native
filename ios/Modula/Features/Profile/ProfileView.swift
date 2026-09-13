import SwiftUI

private struct ProfileBackdrop: View {
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color(hex: "#071C20")
                Circle()
                    .fill(app.appearance.accent.color.opacity(0.22))
                    .frame(width: proxy.size.width * 0.76)
                    .offset(x: proxy.size.width * 0.34, y: -proxy.size.height * 0.15)
                Circle()
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
                    .frame(width: proxy.size.width * 0.51)
                    .offset(x: proxy.size.width * 0.34, y: -proxy.size.height * 0.15)
                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { index in
                        Capsule().fill(Color.white.opacity(0.11 + Double(index) * 0.08)).frame(width: 48, height: 7)
                    }
                }
                .rotationEffect(.degrees(-17))
                .offset(x: -proxy.size.width * 0.26, y: proxy.size.height * 0.26)
            }
        }
        .accessibilityHidden(true)
    }
}

struct ProfileView: View {
    let userID: String?
    let section: ProfileSection
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    ProfileBackdrop().frame(height: 230)
                    ModulaAvatar(initials: userID == nil ? "M" : "P", size: 96)
                        .overlay(Circle().stroke(.background, lineWidth: 5))
                        .offset(y: 46)
                        .padding(.leading, 20)
                }
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        ModulaText(text: userID == nil ? "Your profile" : "Modula member", role: .title)
                        Text(userID == nil ? "Current authenticated profile" : "@\(userID!)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Text("Profile data and social content arrive in N3. The native route and contextual rail are ready.")
                        .foregroundStyle(.secondary)
                    ModulaCard {
                        ModulaMetadataRail(values: [("—", "Posts"), ("—", "Followers"), ("—", "Following")])
                    }
                    ModulaSection(title: display(section.rawValue)) {
                        ModulaCard {
                            ModulaEmptyState(title: display(section.rawValue), message: "This profile section is ready for N3.", symbol: "person.crop.rectangle.stack")
                        }
                    }
                }
                .padding(.horizontal, ModulaLayout.contentInset)
                .padding(.top, 62)
                .padding(.bottom, 28)
            }
        }
        .modulaCanvas()
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("profile.\(section.rawValue)")
    }

    private func display(_ value: String) -> String {
        value.replacingOccurrences(of: "-", with: " ").capitalized
    }
}
