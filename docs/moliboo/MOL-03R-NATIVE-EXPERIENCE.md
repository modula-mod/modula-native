# MOL-03R — Native Experience, Hierarchy & Metal Shader Polish

## 1. Visual & Information Hierarchy
- **Primary Focal Point**: Across **Moliboos Home (`MolibooWorldView`)** and **Living Studio (`MolibooLivingStudioView`)**, the active Moliboo sits on a dedicated 300pt+ stage framed by a volumetric Metal aura (`molibooStageAura`) and caustic moss pedestal (`molibooCaustics`).
- **Secondary Controls & Care Actions**:
  - **World Home**: Single Liquid Glass section bar (`Home`, `Studio`, `Wardrobe`, `Stickers`, `Care`) with specular rim (`molibooSpecularRim`), three high-contrast stat chips (`Mood`, `Energy`, `Bond`), and one-tap care pills (`Say hi`, `Play`, `Give treat`, `Take photo`, `Cards`).
  - **Studio**: Floating 5-item action rail (`Style`, `Wardrobe`, `Play`, `Faces`, `More`) + `Photo`. Opening any panel presents a non-blocking Liquid Glass sheet (Compact `250pt` for `Faces`/`Play`, `300pt` for `Style`, Medium / `76%` Expanded for `Wardrobe`/`More`) while shifting the 3D camera so the Moliboo stays centered in the upper viewport.
- **Tertiary Metadata & Progressive Disclosure**:
  - Extended collection browsing, search, and filters live in the 2-column `MolibooCollectionView`.
  - Coins, daily chest, achievements, custom Moliboos, and keyword assistant live in Studio's `More` stacked sections (`MascotStudioView(embedded: true)`).

## 2. Typography & Contrast Discipline
- **Display & Titles**: `.system(.title2, design: .rounded).weight(.heavy)` for character greetings and screen headers.
- **Body & Controls**: Native `.subheadline`, `.footnote`, and `.caption` with explicit dark-on-pastel contrast (`Color.black.opacity(0.88)` on light character palette cards) and white-on-dark contrast for night scenes and trading cards.
- **Monospaced Discipline**: Reserved strictly for numeric/catalogue badges (`#001`–`#025`, `Lv. 1`, `79%`, `195 items`).

## 3. Metal Shader Kit (`MolibooShaders.metal` & `MolibooShaderKit.swift`)
All shaders are single-pass, branch-light, capped via `MolibooShaderClock` (15–30 fps for ambient, 60 fps for 1.4s interactive bursts), paused off-screen or in background, and render a still frame under Reduce Motion:
1. **`molibooHoloFoil`**: Prismatic rainbow bands + micro-diamond facet sparkles driven by live `tilt` (`CGSize`) and time.
2. **`molibooStageAura`**: Breathing radial aura + concentric harmonic ring behind the active Moliboo on World and Studio stages.
3. **`molibooSunbeams`**: Volumetric daylight god-rays and warm motes for Morning, Afternoon, Meadow, and Cozy Room scenes.
4. **`molibooNebula`**: Dual dancing aurora ribbons in Modula Teal and violet over layered FBM night clouds.
5. **`molibooJoyPulse`**: Expanding chromatic/teal energy ring triggered on stage taps, `Say hi`, `Play`, `Give treat`, and Studio expressions/play actions.
6. **`molibooSpecularRim`**: Travelling liquid-glass rim sheen on active navigation bars, environment pills, and Studio chrome.
7. **`molibooCaustics` / `molibooRipple` / `molibooShimmer` / `molibooPackReveal`**: Pedestal caustics, tap distortion ripple, rarity shimmer sweep, and pack-tear dissolve.
