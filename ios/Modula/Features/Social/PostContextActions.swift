import Foundation

/// Ownership-aware post context actions built on ModulaContextAction primitives.
enum PostContextActions {
    static func menu(
        isOwn: Bool,
        saved: Bool,
        capabilities: PostBackendCapabilities = .production
    ) -> [ModulaContextAction] {
        if isOwn {
            var items: [ModulaContextAction] = []
            if capabilities.editOwnPost {
                items.append(.init(id: "edit-post", title: "Edit Post", systemImage: "pencil"))
            }
            if capabilities.save {
                items.append(.init(
                    id: "save",
                    title: saved ? "Unsave" : "Save",
                    systemImage: saved ? "bookmark.fill" : "bookmark"
                ))
                items.append(.init(
                    id: "save-collection",
                    title: "Save to Collection…",
                    systemImage: "rectangle.stack.badge.plus"
                ))
            }
            items.append(.init(id: "copy-link", title: "Copy Link", systemImage: "link"))
            items.append(.init(id: "share", title: "Share", systemImage: "square.and.arrow.up"))
            if capabilities.deleteOwnPost {
                items.append(.init(
                    id: "delete",
                    title: "Delete Post",
                    systemImage: "trash",
                    role: .destructive,
                    accessibilityLabel: "Delete post"
                ))
            }
            return items
        }

        var items: [ModulaContextAction] = []
        if capabilities.save {
            items.append(.init(
                id: "save",
                title: saved ? "Unsave" : "Save",
                systemImage: saved ? "bookmark.fill" : "bookmark"
            ))
            items.append(.init(
                id: "save-collection",
                title: "Save to Collection…",
                systemImage: "rectangle.stack.badge.plus"
            ))
        }
        items.append(.init(id: "copy-link", title: "Copy Link", systemImage: "link"))
        items.append(.init(id: "share", title: "Share", systemImage: "square.and.arrow.up"))
        if capabilities.notInterested {
            items.append(.init(id: "not-interested", title: "Not Interested", systemImage: "eye.slash"))
        } else if capabilities.hideLocally {
            items.append(.init(id: "hide", title: "Hide this post", systemImage: "eye.slash"))
        }
        if capabilities.muteAuthor {
            items.append(.init(id: "mute-author", title: "Mute Author", systemImage: "speaker.slash"))
        }
        if capabilities.reportPost {
            items.append(.init(
                id: "report",
                title: "Report",
                systemImage: "exclamationmark.bubble",
                role: .destructive,
                accessibilityLabel: "Report post"
            ))
        }
        return items
    }

    /// Glass panel opened by swiping down on the immersive rail (or "…").
    static func immersivePanel(
        isOwn: Bool,
        saved: Bool,
        capabilities: PostBackendCapabilities = .production
    ) -> [ModulaContextAction] {
        var items: [ModulaContextAction] = [
            .init(id: "share", title: "Share post", systemImage: "square.and.arrow.up"),
            .init(id: "copy-link", title: "Copy link", systemImage: "link")
        ]
        if capabilities.save {
            items.append(.init(id: "save-collection", title: "Add to collection", systemImage: "rectangle.stack.badge.plus"))
        }
        if isOwn {
            if capabilities.editOwnPost { items.append(.init(id: "edit-post", title: "Edit post", systemImage: "pencil")) }
            if capabilities.deleteOwnPost {
                items.append(.init(id: "delete", title: "Delete post", systemImage: "trash", role: .destructive, accessibilityLabel: "Delete post"))
            }
            return items
        }
        items.append(.init(id: "notify", title: "Turn on notifications", systemImage: "bell"))
        items.append(.init(id: "not-interested", title: "Not interested", systemImage: "eye.slash"))
        items.append(.init(id: "report", title: "Report", systemImage: "exclamationmark.bubble", role: .destructive, accessibilityLabel: "Report post"))
        return items
    }

    /// X-style author section (@handle: Follow, Add to lists, Mute, Block).
    static func authorActions(capabilities: PostBackendCapabilities = .production) -> [ModulaContextAction] {
        var items: [ModulaContextAction] = [
            .init(id: "follow-author", title: "Follow", systemImage: "person.badge.plus"),
            .init(id: "lists-author", title: "Add to lists", systemImage: "list.bullet.rectangle")
        ]
        if capabilities.muteAuthor {
            items.append(.init(id: "mute-author", title: "Mute", systemImage: "speaker.slash"))
        }
        items.append(.init(id: "block-author", title: "Block", systemImage: "hand.raised", role: .destructive, accessibilityLabel: "Block author"))
        return items
    }

    static func railContextActions(
        saved: Bool,
        capabilities: PostBackendCapabilities = .production
    ) -> [ModulaContextAction] {
        var items: [ModulaContextAction] = [
            .init(id: "share", title: "Share Post", systemImage: "square.and.arrow.up"),
            .init(id: "copy-link", title: "Copy Link", systemImage: "link")
        ]
        if capabilities.save {
            items.append(.init(
                id: "save",
                title: saved ? "Unsave" : "Save",
                systemImage: "bookmark"
            ))
            items.append(.init(id: "save-collection", title: "Add to Collection", systemImage: "rectangle.stack.badge.plus"))
        }
        if capabilities.notInterested {
            items.append(.init(id: "not-interested", title: "Not Interested", systemImage: "eye.slash"))
        } else if capabilities.hideLocally {
            items.append(.init(id: "hide", title: "Hide this post", systemImage: "eye.slash"))
        }
        return items
    }

    static func commentMenu(
        isOwn: Bool,
        capabilities: PostBackendCapabilities = .production
    ) -> [ModulaContextAction] {
        if isOwn {
            var items: [ModulaContextAction] = [
                .init(id: "copy", title: "Copy", systemImage: "doc.on.doc")
            ]
            if capabilities.commentsDelete {
                items.append(.init(id: "delete", title: "Delete", systemImage: "trash", role: .destructive))
            }
            return items
        }
        var items: [ModulaContextAction] = [
            .init(id: "copy", title: "Copy", systemImage: "doc.on.doc")
        ]
        if capabilities.muteAuthor {
            items.append(.init(id: "mute-author", title: "Mute Author", systemImage: "speaker.slash"))
        }
        if capabilities.reportComment {
            items.append(.init(id: "report", title: "Report", systemImage: "exclamationmark.bubble", role: .destructive))
        }
        return items
    }
}
