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
                title: saved ? "Unsave" : "Add to Collection",
                systemImage: "bookmark"
            ))
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
