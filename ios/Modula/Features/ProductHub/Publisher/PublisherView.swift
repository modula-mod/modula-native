import SwiftUI

struct PublisherView: View {
    let publisherID: String
    @Environment(AppEnvironment.self) private var app

    private var products: [CatalogueProduct] {
        app.catalogue.products.filter { $0.publisherId == publisherID }
    }

    private var publisherName: String {
        products.first?.publisherName ?? publisherID
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 14) {
                    Circle()
                        .fill(app.appearance.liveAccent.opacity(0.2))
                        .frame(width: 64, height: 64)
                        .overlay {
                            Text(String(publisherName.prefix(1)).uppercased())
                                .font(.title.bold())
                        }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(publisherName).font(.largeTitle.bold())
                        Text("Product publisher")
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Publisher \(publisherName)")

                Text("This is the publisher’s page for their modules. It’s separate from their social profile.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if products.isEmpty {
                    Text("No catalogue modules are published under this publisher in the current response.")
                        .foregroundStyle(.secondary)
                } else {
                    ProductShelf(
                        title: "Modules",
                        products: products,
                        installedIDs: app.catalogue.installedIDs
                    ) { product in
                        app.navigation.open(.productHub(.module(product.id, .overview)))
                    }
                }
            }
            .padding(ModulaLayout.contentInset)
        }
        .modulaSoftScrollEdge()
        .modulaCanvas()
        .navigationTitle(publisherName)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("publisher.\(publisherID)")
    }
}
