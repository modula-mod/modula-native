import SwiftUI

struct DiscoverDashboardView: View {
    let dashboard: DiscoverDashboard
    let previewPosts: [DiscoverPost]
    let featuredProducts: [CatalogueProduct]
    let installedIDs: Set<String>
    var followBusyID: String?
    var onTopic: (DiscoverTopic) -> Void
    var onPerson: (DiscoverPerson) -> Void
    var onFollow: (DiscoverPerson) -> Void
    var onSeePeople: () -> Void
    var onPost: (DiscoverPost) -> Void
    var onModule: (CatalogueProduct) -> Void
    var onSeeModules: () -> Void

    private var shelfPeople: [DiscoverPerson] {
        Array(dashboard.people.sorted { $0.usefulness > $1.usefulness }.prefix(8))
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 28) {
            if !dashboard.topics.isEmpty {
                DiscoverTopicShelf(topics: dashboard.topics, onOpen: onTopic)
            }
            if !shelfPeople.isEmpty {
                DiscoverPeopleShelf(
                    people: shelfPeople,
                    followBusyID: followBusyID,
                    onSeeAll: onSeePeople,
                    onOpen: onPerson,
                    onFollow: onFollow
                )
            }
            if !previewPosts.isEmpty {
                DiscoverPostShelf(posts: Array(previewPosts.prefix(2)), onOpen: onPost)
            } else if !dashboard.media.isEmpty {
                mediaStrip
            }
            if !featuredProducts.isEmpty {
                DiscoverModuleShelf(
                    products: Array(featuredProducts.prefix(4)),
                    installedIDs: installedIDs,
                    onSeeAll: onSeeModules,
                    onOpen: onModule
                )
            }
        }
    }

    private var mediaStrip: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Visuals").font(.title3.bold())
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(dashboard.media.prefix(6).enumerated()), id: \.offset) { item in
                        DiscoverMediaPreview(media: item.element)
                            .frame(width: 180)
                    }
                }
            }
        }
    }
}
