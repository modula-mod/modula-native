# Navigation architecture

`NavigationCoordinator` stores a typed root and typed path for every `AppTab`. Selecting a contextual rail item replaces that destination's contextual root; it does not push a screen. Opening Module Detail pushes from Product Hub, and opening its bundled module pushes `ModuleHost` above the detail. Closing the host pops back to the detail.

Global path strings are parsed only by `RouteParser`. Module requests continue through the N1 allowlist in `ModulaBridge`; a module cannot replace shell chrome, mutate Appearance, or submit arbitrary paths. Module-local paths are delivered as initial module context and stay owned by the module.

Unknown or malformed paths are rejected. Route round-trip tests cover defaults, nested Settings, IDs, Product Hub details, deep-link origins, and module-local state.
