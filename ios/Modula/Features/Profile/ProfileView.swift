import SwiftUI

struct ProfileView: View {
    let userID: String?
    let section: ProfileSection
    @Environment(AppEnvironment.self) private var app
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    LinearGradient(colors: [app.appearance.accent.color.opacity(0.8), .indigo.opacity(0.42), .black.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing).frame(height: 220)
                    ModulaAvatar(initials: userID == nil ? "M" : "P", size: 92).overlay(Circle().stroke(.background, lineWidth: 5)).offset(y: 42).padding(.leading, 20)
                }
                VStack(alignment: .leading, spacing: 8) {
                    ModulaText(text: userID == nil ? "Your profile" : "Modula member", role: .title)
                    Text(userID == nil ? "Current authenticated profile" : "@\(userID!)").foregroundStyle(.secondary)
                    Text("Profile data and social content arrive in N3. The native route and contextual rail are ready.")
                    ModulaMetadataRail(values: [("—", "Posts"), ("—", "Followers"), ("—", "Following")])
                    ModulaCard { ModulaEmptyState(title: section.rawValue.capitalized, message: "This profile section is ready for N3.", symbol: "person.crop.rectangle.stack") }
                }.padding(.horizontal, 18).padding(.top, 54)
            }
        }.navigationTitle("Profile").navigationBarTitleDisplayMode(.inline).accessibilityIdentifier("profile.\(section.rawValue)")
    }
}
