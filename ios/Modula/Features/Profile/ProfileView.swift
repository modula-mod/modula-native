import SwiftUI

struct ProfileView: View {
    let userID: String
    var body: some View {
        ContentUnavailableView("Profile", systemImage: "person.crop.circle", description: Text("Your native profile is coming in a later phase."))
            .navigationTitle("Profile")
    }
}
