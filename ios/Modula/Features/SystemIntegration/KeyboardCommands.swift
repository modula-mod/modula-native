import SwiftUI

/// Hardware keyboard enhancements. On-screen Command entry remains primary.
struct ModulaKeyboardCommands: Commands {
    var openCommandCenter: () -> Void
    var openCreate: () -> Void
    var openSearch: () -> Void

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Command Center") { openCommandCenter() }
                .keyboardShortcut("k", modifiers: [.command])
            Button("Create") { openCreate() }
                .keyboardShortcut("n", modifiers: [.command])
            Button("Search Modula") { openSearch() }
                .keyboardShortcut("f", modifiers: [.command])
        }
    }
}

/// View-level key handlers for environments without a Commands scene builder.
struct CommandKeyboardModifier: ViewModifier {
    var onCommandK: () -> Void
    var onCommandN: () -> Void
    var onCommandF: () -> Void

    func body(content: Content) -> some View {
        content
            .onKeyPress(keys: [.init("k")], phases: .down) { press in
                guard press.modifiers.contains(.command) else { return .ignored }
                onCommandK()
                return .handled
            }
            .onKeyPress(keys: [.init("n")], phases: .down) { press in
                guard press.modifiers.contains(.command) else { return .ignored }
                onCommandN()
                return .handled
            }
            .onKeyPress(keys: [.init("f")], phases: .down) { press in
                guard press.modifiers.contains(.command) else { return .ignored }
                onCommandF()
                return .handled
            }
    }
}

extension View {
    func modulaCommandKeyboard(
        onCommandK: @escaping () -> Void,
        onCommandN: @escaping () -> Void,
        onCommandF: @escaping () -> Void
    ) -> some View {
        modifier(CommandKeyboardModifier(
            onCommandK: onCommandK,
            onCommandN: onCommandN,
            onCommandF: onCommandF
        ))
    }
}
