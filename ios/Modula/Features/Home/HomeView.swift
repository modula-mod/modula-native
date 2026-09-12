import SwiftUI

struct HomeView: View {
    @Environment(AppEnvironment.self) private var app
    var body: some View {
        List {
            Section {
                Text("Your space, built for iPhone.").font(.title2.bold())
                Text("Modula’s native foundation. Your modules open inside this app.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Button("Product Hub", systemImage: "square.grid.2x2") { app.navigation.open(.productHub) }
                Button("Profile", systemImage: "person.crop.circle") { app.navigation.open(.profile("me")) }
                Button("Settings", systemImage: "gearshape") { app.navigation.open(.settings) }
            }
        }
        .navigationTitle("Modula")
        .accessibilityIdentifier("native.home")
    }
}
