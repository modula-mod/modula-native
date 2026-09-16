import CoreSpotlight
import Foundation
import UniformTypeIdentifiers

/// Spotlight preparation for safe entities only. Never indexes drafts, messages, or In-Mail.
enum SpotlightIndexPreparation {
    static let domainModules = "digital.modula.spotlight.modules"
    static let domainSettings = "digital.modula.spotlight.settings"

    static func moduleItems(installed: [(id: String, name: String)]) -> [CSSearchableItem] {
        installed.map { module in
            let attributes = CSSearchableItemAttributeSet(contentType: .content)
            attributes.title = module.name
            attributes.contentDescription = "Installed Modula module"
            attributes.keywords = ["modula", "module", module.name]
            return CSSearchableItem(
                uniqueIdentifier: "module:\(module.id)",
                domainIdentifier: domainModules,
                attributeSet: attributes
            )
        }
    }

    static func settingsItems() -> [CSSearchableItem] {
        let destinations: [(id: String, title: String, keywords: [String])] = [
            ("settings", "Settings", ["settings", "preferences"]),
            ("appearance", "Appearance", ["theme", "dark mode", "font", "accent"]),
            ("notifications", "Notifications", ["alerts", "push"]),
            ("privacy", "Privacy & Security", ["privacy", "security", "lock"]),
            ("accessibility", "Accessibility", ["accessibility", "contrast", "motion"])
        ]
        return destinations.map { item in
            let attributes = CSSearchableItemAttributeSet(contentType: .content)
            attributes.title = item.title
            attributes.contentDescription = "Modula settings"
            attributes.keywords = item.keywords
            return CSSearchableItem(
                uniqueIdentifier: "settings:\(item.id)",
                domainIdentifier: domainSettings,
                attributeSet: attributes
            )
        }
    }

    static func refresh(installedModules: [(id: String, name: String)]) {
        let index = CSSearchableIndex.default()
        index.deleteSearchableItems(withDomainIdentifiers: [domainModules, domainSettings]) { _ in
            let items = moduleItems(installed: installedModules) + settingsItems()
            index.indexSearchableItems(items) { _ in }
        }
    }
}
