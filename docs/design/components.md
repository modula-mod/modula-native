# Component reference

Future agents must inspect the interactive `/developer/components` catalog before adding a Modula-wide component. The catalog covers typography, controls, identity, forms, rows, states, Product Hub components, the floating tab bar and attached accessory, the looping contextual rail, and live Appearance variants.

The polished Product Hub reference uses `ProductArtwork`, `ProductBackdrop`, `ProductHero`, `ProductShelf`, and `ProductCard`. Artwork is deterministic native vector composition, not a fabricated screenshot or catalogue claim. Approved publisher assets can replace that rendering later without changing catalogue truth or product-state logic.

`ModulaBottomChrome` composes two separate semantics: `ModulaTabBar` contains exactly the five frozen top-level destinations, while `ModulaTabAccessory` presents the current area plus Search and a More menu. The accessory must not become a second Home/Activity/Profile mode selector; those modes belong only to `ModulaContextRail`.

Component readiness is judged in Light, Standard Dark, Dim, and OLED; curated accents and fonts; compact and comfortable density; large Dynamic Type; Reduce Motion; increased contrast; and reduced transparency where relevant. SwiftUI previews may supplement the catalog but never replace simulator acceptance.
