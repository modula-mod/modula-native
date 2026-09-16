import Foundation

/// Ownership- and capability-aware Profile menus. Only Greenfield-backed actions appear.
enum ProfileContextActions {
    struct Capabilities: Sendable, Equatable {
        var canMute = true
        var canBlock = true
        var canReport = true
        var canEdit = true
        var canShare = true
        var canCopyLink = true
        var canShowModulaCode = true
        var canPreviewAsVisitor = true
        var canOpenSettings = true
        /// Avatar/cover change & remove require upload contracts that are not deployed.
        var canChangeMedia = false
        var canRemoveMedia = false
        var canRepositionCover = false
    }

    static let production = Capabilities()

    static func moreMenu(
        isOwn: Bool,
        capabilities: Capabilities = Capabilities()
    ) -> [ModulaContextAction] {
        if isOwn {
            var items: [ModulaContextAction] = []
            if capabilities.canShare {
                items.append(.init(id: "share", title: "Share Profile", systemImage: "square.and.arrow.up"))
            }
            if capabilities.canCopyLink {
                items.append(.init(id: "copy-link", title: "Copy Profile Link", systemImage: "link"))
            }
            if capabilities.canShowModulaCode {
                items.append(.init(id: "modula-code", title: "My Modula Code", systemImage: "qrcode"))
            }
            if capabilities.canPreviewAsVisitor {
                items.append(.init(id: "preview-visitor", title: "Preview as Visitor", systemImage: "eye"))
            }
            if capabilities.canOpenSettings {
                items.append(.init(id: "settings", title: "Profile Settings", systemImage: "gearshape"))
            }
            if capabilities.canEdit {
                items.append(.init(id: "edit", title: "Edit Profile", systemImage: "pencil"))
            }
            return items
        }

        var items: [ModulaContextAction] = []
        if capabilities.canShare {
            items.append(.init(id: "share", title: "Share Profile", systemImage: "square.and.arrow.up"))
        }
        if capabilities.canCopyLink {
            items.append(.init(id: "copy-link", title: "Copy Profile Link", systemImage: "link"))
        }
        if capabilities.canMute {
            items.append(.init(id: "mute", title: "Mute", systemImage: "speaker.slash"))
        }
        if capabilities.canBlock {
            items.append(.init(
                id: "block",
                title: "Block",
                systemImage: "hand.raised",
                role: .destructive,
                accessibilityLabel: "Block profile"
            ))
        }
        if capabilities.canReport {
            items.append(.init(
                id: "report",
                title: "Report",
                systemImage: "exclamationmark.bubble",
                role: .destructive,
                accessibilityLabel: "Report profile"
            ))
        }
        return items
    }

    static func avatarMenu(
        isOwn: Bool,
        hasPhoto: Bool,
        capabilities: Capabilities = Capabilities()
    ) -> [ModulaContextAction] {
        var items: [ModulaContextAction] = []
        if hasPhoto {
            items.append(.init(id: "view-photo", title: "View Photo", systemImage: "photo"))
        }
        if isOwn {
            if capabilities.canChangeMedia {
                items.append(.init(id: "change-photo", title: "Change Photo", systemImage: "camera"))
            }
            if capabilities.canRemoveMedia, hasPhoto {
                items.append(.init(id: "remove-photo", title: "Remove Photo", systemImage: "trash", role: .destructive))
            }
        } else {
            items.append(.init(id: "share", title: "Share Profile", systemImage: "square.and.arrow.up"))
            items.append(.init(id: "copy-link", title: "Copy Profile Link", systemImage: "link"))
        }
        return items
    }

    static func coverMenu(
        isOwn: Bool,
        hasCover: Bool,
        capabilities: Capabilities = Capabilities()
    ) -> [ModulaContextAction] {
        var items: [ModulaContextAction] = []
        if hasCover {
            items.append(.init(id: "view-cover", title: "View Cover", systemImage: "photo"))
        }
        if isOwn {
            if capabilities.canChangeMedia {
                items.append(.init(id: "change-cover", title: "Change Cover", systemImage: "camera"))
            }
            if capabilities.canRepositionCover, hasCover {
                items.append(.init(id: "reposition-cover", title: "Reposition Cover", systemImage: "arrow.up.and.down.and.arrow.left.and.right"))
            }
            if capabilities.canRemoveMedia, hasCover {
                items.append(.init(id: "remove-cover", title: "Remove Cover", systemImage: "trash", role: .destructive))
            }
        } else {
            items.append(.init(id: "share", title: "Share Profile", systemImage: "square.and.arrow.up"))
        }
        return items
    }

    static func postMenu(isOwn: Bool) -> [ModulaContextAction] {
        if isOwn {
            return [
                .init(id: "edit-post", title: "Edit Post", systemImage: "pencil", role: .disabled),
                .init(id: "save", title: "Save", systemImage: "bookmark"),
                .init(id: "copy-link", title: "Copy Link", systemImage: "link"),
                .init(id: "share", title: "Share", systemImage: "square.and.arrow.up"),
                .init(id: "delete", title: "Delete", systemImage: "trash", role: .disabled)
            ]
        }
        return [
            .init(id: "save", title: "Save", systemImage: "bookmark"),
            .init(id: "copy-link", title: "Copy Link", systemImage: "link"),
            .init(id: "share", title: "Share", systemImage: "square.and.arrow.up"),
            .init(id: "not-interested", title: "Not Interested", systemImage: "eye.slash", role: .disabled),
            .init(id: "mute-author", title: "Mute Author", systemImage: "speaker.slash"),
            .init(id: "report", title: "Report", systemImage: "exclamationmark.bubble", role: .destructive)
        ]
    }
}
