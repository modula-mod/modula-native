import Foundation

/// Universal create actions. Command Center consumes this registry; modules may join later
/// only when manifests declare authorized actions.
struct CreateAction: Identifiable, Sendable, Hashable {
    enum Source: String, Sendable, Hashable {
        case native
        case module
    }

    let id: String
    let title: String
    let subtitle: String?
    let icon: SemanticIcon
    let source: Source
    let availability: CommandAvailability
    let action: CommandAction
    let moduleID: String?

    init(
        id: String,
        title: String,
        subtitle: String? = nil,
        icon: SemanticIcon,
        source: Source = .native,
        availability: CommandAvailability = .available,
        action: CommandAction,
        moduleID: String? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.source = source
        self.availability = availability
        self.action = action
        self.moduleID = moduleID
    }
}

enum CreateActionRegistry {
    static func actions(capabilities: CommandCapabilitySnapshot) -> [CreateAction] {
        var items: [CreateAction] = []
        if capabilities.postCompose {
            items.append(.init(
                id: "post",
                title: "Post",
                subtitle: "Share an update",
                icon: .init("square.and.pencil"),
                availability: capabilities.signedIn ? .available : .requiresSignIn,
                action: .composeStart(.post)
            ))
        }
        if capabilities.photoCompose {
            items.append(.init(
                id: "photo",
                title: "Photo",
                subtitle: "Share a photo",
                icon: .init("photo"),
                availability: capabilities.signedIn ? .available : .requiresSignIn,
                action: .composeStart(.photo)
            ))
        }
        if capabilities.pollCompose {
            items.append(.init(
                id: "poll",
                title: "Poll",
                icon: .init("chart.bar.doc.horizontal"),
                availability: capabilities.signedIn ? .available : .requiresSignIn,
                action: .composeStart(.poll)
            ))
        }
        if capabilities.storyCreate {
            items.append(.init(
                id: "story",
                title: "Story",
                icon: .init("circle.dashed"),
                availability: capabilities.signedIn ? .available : .requiresSignIn,
                action: .routeOpen(.stories(.create))
            ))
        } else {
            // Keep architecture aware without leading users into dead screens.
            items.append(.init(
                id: "story",
                title: "Story",
                subtitle: "Unavailable",
                icon: .init("circle.dashed"),
                availability: .unavailable,
                action: .routeOpen(.stories(.create))
            ))
        }
        items.append(.init(
            id: "in-mail",
            title: "In-Mail",
            icon: .init("envelope"),
            availability: capabilities.inMailCompose
                ? (capabilities.signedIn ? .available : .requiresSignIn)
                : .unavailable,
            action: .routeOpen(.messages(.inMail(.compose)))
        ))
        items.append(.init(
            id: "message",
            title: "Message",
            icon: .init("bubble.left.and.bubble.right"),
            availability: capabilities.messagingSend
                ? (capabilities.signedIn ? .available : .requiresSignIn)
                : .unavailable,
            action: .routeOpen(.messages(.new))
        ))
        // Module-declared create actions intentionally empty until manifest authorization is clean.
        return items.filter { $0.availability != .unavailable || capabilities.developerMode }
    }

    static func available(capabilities: CommandCapabilitySnapshot) -> [CreateAction] {
        actions(capabilities: capabilities).filter {
            $0.availability == .available || ($0.availability == .requiresSignIn && !capabilities.signedIn)
        }.filter { $0.availability != .unavailable }
    }
}
