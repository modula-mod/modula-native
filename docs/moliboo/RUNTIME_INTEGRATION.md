# Runtime integration (iOS 18+, Swift 6, strict concurrency complete)
Files: Features/Moliboo3D/{MolibooFeatureFlags, MolibooCosmetics, MolibooCharacterDescriptor, MolibooAssetLoader, MolibooSceneController, Moliboo3DPreview, MOL01DebugHarness}.swift; Resources/Moliboo3D/*.
Edits to existing files (anchor-based, idempotent): MascotWardrobe.swift (one new catalog line), MascotStudioViews.swift (entry button), ModulaApp.swift (DEBUG-only `.modifier(MOL01DebugCover())`).
Flag: UserDefaults `dev.moliboo.native3D` (default false).
Expressions: idle/blink/happy/excited/surprised/sleepy/sad, transform-driven on face parts (eye/iris/shine/mouth). Baked clips played via `playClip` (AnimationView trim of the USD timeline) with procedural fallback for wobble/tap. Clip playback in RealityKit: PENDING.
Accessory orientation: both USDZs carry root −90°X; accessory gets +90°X local correction under the anchor (covered by test).
Box verification: `swiftc -parse` all files OK; Swift 6 typecheck of non-UI files against RealityKit-shaped stubs OK. Real Xcode build: PENDING (needs Mac/Xcode/simulator).

Expressions now play baked blend-shape hold clips (`expr_<name>`, looped) — giving ^-arc happy eyes and the open excited mouth — with the transform fallback if clips are unavailable. Manifest schema 2 (cosmetics + per-character attachments).
