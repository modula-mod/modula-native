import SwiftUI

struct ProductHubView: View {
    var body: some View {
        ContentUnavailableView("Product Hub", systemImage: "square.grid.2x2", description: Text("Your Modula modules will appear here."))
            .navigationTitle("Product Hub")
    }
}
