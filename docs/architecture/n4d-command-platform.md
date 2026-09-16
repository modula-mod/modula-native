# N4D — Command platform architecture

Modula’s Social OS layer: Command Center, Universal Create, Saved, Collections, Drafts, Universal Share, and system integration.

## Principles

- **Search ≠ Command.** Search finds content; Command Center does something.
- **No sixth root tab.** `/command` is a transient sheet/overlay.
- **Typed actions only.** Registered capabilities + parameters — never downloaded closures.
- **Capability-honest.** Unavailable create/send actions stay gated.
- **Additive.** Prefer new directories under `Core/Commands`, `Core/Sharing`, `Features/CommandCenter`, `Saved`, `Collections`, `Drafts`, `UniversalShare`, `SystemIntegration`.

## Flow

```text
Shell More / ⌘K / Quick Action / App Intent
        ↓
  Command Center (local registry + matcher)
        ↓
  CommandExecutor → NavigationCoordinator / presentations
        ↓
  Module open → ModuleHost (N1) — Hermes only then
```

## Key types

- `ModulaCommand`, `CommandAction`, `CommandRegistry`, `CommandMatcher`, `CommandRecentsStore`
- `CreateActionRegistry` + `CreateActionPicker`
- `SavedStore` / `SavedRepository` (list OPEN — VPS)
- `CollectionStore` with `CollectionStorage.local` | `.greenfield`
- `DraftStore` via `PrivateFileStore` (Application Support + data protection)
- `SharePayload` / `ShareCoordinator` / `ModulaShareSheet` / `PeoplePicker`
- `QuickActionMapper`, App Intents foundation, Spotlight preparation

## Privacy

- Recents: no message bodies, draft text, or free-form search terms
- Drafts: never Spotlight, never analytics bodies
- Collections metadata: app-private persistence
- Saved: server remains authority for visibility/deletion when list exists

See `docs/migration/command-platform-backend.md` and `docs/environment/n4d-remote-staging.md`.
