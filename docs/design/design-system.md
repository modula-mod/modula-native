# Modula Design System v1

The native design system contains semantic colour, typography, spacing, density, radius, icon, motion, haptic, elevation/material, and layout decisions. It supplies text, icon, button, icon button, avatar, badge, card, list row, section, search, metric, picker, chip, toolbar, top bar, tab bar, tab accessory, context rail, sheet, menu, empty/loading/error, hero, metadata, and Product Hub components.

Use a shared component when the semantic role recurs across Modula. Keep feature-specific layout local. Native and module components are cousins: they share roles and environment values but retain appropriate SwiftUI and React Native implementations.

Neutral values live in `packages/design-contracts/tokens/design-contract.json`. `npm run generate:design` produces Swift and TypeScript artifacts; `npm run verify:design` fails when they drift. The contract version is independent of the app marketing version.

Material is reserved for shell chrome and presentations. Content cards use stable surfaces. Teal marks selection, focus, primary action, progress, and links where appropriate; it is not a blanket recolouring rule.

On iOS 26 and later, convex floating tab and accessory capsules adopt native Liquid Glass. Reduced Transparency and the iOS 18 fallback use opaque or standard material surfaces. Nonconvex rail geometry uses clipped native material because visual testing showed that applying custom Liquid Glass to the edge-loop path can refract outside the intended footprint. Dim resolves to a deliberate blue-charcoal canvas and OLED resolves to true black.

Accessibility-sized page content remains fully scalable and scrollable. Compact shell labels retain the system Large visual size, matching the stable footprint of a system tab bar; their complete names remain exposed through accessibility labels and the controls preserve at least 44-point targets.
