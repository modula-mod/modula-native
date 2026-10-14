# Architecture
Blender source (.blend, procedural bpy) → USDZ (Y-up, metres, UsdPreviewSurface, baked base colour, BlendShapes)
→ app bundle (`Resources/Moliboo3D`) + `moliboo_manifest.json` (schema 1)
→ `MolibooManifest`/`MolibooCharacterDescriptor` → `MolibooAssetLoader` (async Entity) → `MolibooSceneController`
(@MainActor @Observable: expressions, idle blink, wobble/bounce/react, equipment at named anchors)
→ `Moliboo3DPreview` (RealityView, virtual camera, drag-rotate, tap) ← entry `Moliboo3DEntryButton` in Mascot Studio (flag + Pebble only).
Persistence reuses `MascotWardrobeStore` (`composer.mascot.outfit`). No backend, no migration. Generic: a new character = new manifest entry + USDZ.
