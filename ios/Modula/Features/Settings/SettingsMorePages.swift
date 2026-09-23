import SwiftUI
import UIKit

// MARK: - Camera

struct CameraSettingsHost: View {
    let route: CameraSettingsRoute
    @Environment(AppEnvironment.self) private var app
    @AppStorage("settings.camera.grid") private var grid = true
    @AppStorage("settings.camera.mirrorFront") private var mirrorFront = true
    @AppStorage("settings.camera.saveCapture") private var saveCapture = true
    @AppStorage("settings.camera.format") private var format = "heic"

    var body: some View {
        switch route {
        case .root:
            SettingsScrollCanvas {
                SettingsHeroBanner(title: "Camera", subtitle: "Capture framing and save behaviour.", symbol: "camera")
                SettingsSceneGraphic(style: .filmstrip)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    SettingsStatChip(label: "Grid", value: grid ? "On" : "Off", symbol: "grid")
                    SettingsStatChip(label: "Format", value: format.uppercased(), symbol: "photo")
                }
                SettingsGroup(title: "Open") {
                    VStack(spacing: 0) {
                        SettingsNavigationRow(title: "Capture", subtitle: "Grid, mirror, format", symbol: "viewfinder") {
                            app.navigation.open(.settings(.camera(.capture)))
                        }
                        SettingsDivider()
                        SettingsNavigationRow(title: "Permissions", subtitle: "Camera & mic access", symbol: "hand.raised.square") {
                            app.navigation.open(.settings(.camera(.permissions)))
                        }
                    }
                }
                SettingsAPIFootnote(text: "Capture prefs are local. Permission state is owned by iOS Settings — Modula does not invent a camera API matrix.")
            }
            .navigationTitle("Camera")
            .navigationBarTitleDisplayMode(.inline)
        case .capture:
            Form {
                Toggle("Show grid", isOn: $grid)
                Toggle("Mirror front camera", isOn: $mirrorFront)
                Toggle("Save to Photos", isOn: $saveCapture)
                Picker("Format", selection: $format) {
                    Text("HEIC").tag("heic")
                    Text("JPEG").tag("jpeg")
                }
            }
            .modulaSoftScrollEdge()
            .navigationTitle("Capture")
            .navigationBarTitleDisplayMode(.inline)
        case .permissions:
            SettingsScrollCanvas {
                SettingsHeroBanner(title: "Permissions", subtitle: "Camera and microphone.", symbol: "hand.raised.square")
                SettingsSceneGraphic(style: .rings)
                SettingsGroup(title: "System access") {
                    VStack(spacing: 0) {
                        SettingsPreviewRow(title: "Camera", subtitle: "Managed in iOS Settings", symbol: "camera", trailing: "System")
                        SettingsDivider()
                        SettingsPreviewRow(title: "Microphone", subtitle: "Managed in iOS Settings", symbol: "mic", trailing: "System")
                    }
                }
                Button("Open iOS Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(app.appearance.accent.color)
                SettingsAPIFootnote(text: "Native reads authorization through system APIs only; no fabricated grant state.")
            }
            .navigationTitle("Permissions")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Gestures

struct GesturesSettingsHost: View {
    let route: GesturesSettingsRoute
    @AppStorage("settings.gestures.edgeBack") private var edgeBack = true
    @AppStorage("settings.gestures.doubleTapLike") private var doubleTapLike = true
    @AppStorage("settings.gestures.swipeReply") private var swipeReply = true
    @AppStorage("settings.gestures.shakeUndo") private var shakeUndo = false

    var body: some View {
        switch route {
        case .root:
            SettingsScrollCanvas {
                SettingsHeroBanner(title: "Gestures", subtitle: "Touch shortcuts for browsing and chat.", symbol: "hand.draw")
                SettingsSceneGraphic(style: .orbit)
                Form {
                    Toggle("Edge swipe to go back", isOn: $edgeBack)
                    Toggle("Double-tap to like", isOn: $doubleTapLike)
                    Toggle("Swipe to reply in chats", isOn: $swipeReply)
                    Toggle("Shake to undo compose", isOn: $shakeUndo)
                }
                .scrollDisabled(true)
                .frame(minHeight: 220)
                SettingsAPIFootnote(text: "Local interaction prefs. Does not change Edge Picker geometry — that stays under Appearance → Edge Picker.")
            }
            .navigationTitle("Gestures")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Finder (search prefs — not Discover)

struct FinderSettingsHost: View {
    let route: FinderSettingsRoute
    @Environment(AppEnvironment.self) private var app
    @AppStorage("settings.finder.saveHistory") private var saveHistory = true
    @AppStorage("settings.finder.includeModules") private var includeModules = true
    @AppStorage("settings.finder.peopleFirst") private var peopleFirst = false

    var body: some View {
        switch route {
        case .root:
            SettingsScrollCanvas {
                SettingsHeroBanner(title: "Search", subtitle: "How lookup behaves on this device.", symbol: "magnifyingglass")
                SettingsSceneGraphic(style: .constellation)
                Form {
                    Toggle("Save recent searches", isOn: $saveHistory)
                    Toggle("Include modules in results", isOn: $includeModules)
                    Toggle("Prefer people first", isOn: $peopleFirst)
                }
                .scrollDisabled(true)
                .frame(minHeight: 160)
                SettingsGroup(title: "History") {
                    VStack(spacing: 0) {
                        SettingsNavigationRow(title: "Clear recent searches", subtitle: "Removes local history", symbol: "trash") {
                            UserDefaults.standard.removeObject(forKey: "settings.finder.history.cache")
                            HapticEngine.shared.play(.confirmation)
                        }
                    }
                }
                SettingsAPIFootnote(text: "History is device-local. Discover scope chips remain on Discover — this page does not open Appearance or Discover routes.")
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("settings.finder")
        }
    }
}

// MARK: - Sharing

struct SharingSettingsHost: View {
    let route: SharingSettingsRoute
    @AppStorage("settings.sharing.includeHandle") private var includeHandle = true
    @AppStorage("settings.sharing.preferNativeSheet") private var preferNative = true
    @AppStorage("settings.sharing.copyAsLink") private var copyAsLink = false

    var body: some View {
        switch route {
        case .root:
            SettingsScrollCanvas {
                SettingsHeroBanner(title: "Sharing", subtitle: "Defaults for the share sheet.", symbol: "square.and.arrow.up")
                SettingsSceneGraphic(style: .grid)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    SettingsFeatureTile(title: "Link", detail: "Canonical URLs", symbol: "link", tint: Color.accentColor)
                    SettingsFeatureTile(title: "Sheet", detail: "System share", symbol: "square.and.arrow.up.on.square", tint: Color.accentColor)
                }
                Form {
                    Toggle("Include @handle in share text", isOn: $includeHandle)
                    Toggle("Prefer system share sheet", isOn: $preferNative)
                    Toggle("Copy link instead of opening sheet", isOn: $copyAsLink)
                }
                .scrollDisabled(true)
                .frame(minHeight: 160)
                SettingsAPIFootnote(text: "Local share defaults. Universal-link entitlements remain infrastructure work; no invented share analytics.")
            }
            .navigationTitle("Sharing")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Location

struct LocationSettingsHost: View {
    let route: LocationSettingsRoute
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        switch route {
        case .root:
            SettingsDesignedUnavailableCanvas(
                title: "Location",
                subtitle: "Precise and approximate access for modules that ask.",
                symbol: "location",
                tiles: [
                    ("While using", "Foreground only", "location"),
                    ("Precise", "Exact coordinates", "scope"),
                    ("Approximate", "City-level", "mappin.and.ellipse"),
                    ("Modules", "Per-module grants", "shippingbox")
                ],
                previewRows: [
                    ("Map posts", "Attach place", "map"),
                    ("Nearby", "Local discovery", "binoculars"),
                    ("Clear history", "Forget places", "trash")
                ],
                apiNote: "No verified location-preference contract in native settings this run. Open iOS Settings for system authorization. UI is designed ahead of wiring."
            )
        case .map:
            SettingsScrollCanvas {
                SettingsHeroBanner(title: "Map posts", subtitle: "Place attachments on posts.", symbol: "map")
                SettingsSceneGraphic(style: .constellation)
                ContentUnavailableView("Map attach unavailable", systemImage: "map", description: Text("Place pickers stay off until a verified location attach contract exists."))
                    .frame(minHeight: 160)
                SettingsAPIFootnote(text: "No fabricated nearby places or coordinates.")
            }
            .navigationTitle("Map posts")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Widgets

struct WidgetsSettingsHost: View {
    let route: WidgetsSettingsRoute

    var body: some View {
        switch route {
        case .root:
            SettingsScrollCanvas {
                SettingsHeroBanner(title: "Widgets", subtitle: "Home Screen and Lock Screen surfaces.", symbol: "rectangle.on.rectangle.angled")
                SettingsSceneGraphic(style: .grid)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    widgetPreview("Following", "person.2")
                    widgetPreview("Activity", "bell")
                    widgetPreview("Module", "shippingbox")
                    widgetPreview("Compose", "plus")
                }
                SettingsAPIFootnote(text: "WidgetKit targets are not shipping in this build. Previews are illustrative — not installable widgets.")
            }
            .navigationTitle("Widgets")
            .navigationBarTitleDisplayMode(.inline)
        case .gallery:
            SettingsDesignedUnavailableCanvas(
                title: "Widget gallery",
                subtitle: "Pick sizes and timelines.",
                symbol: "square.grid.3x3",
                tiles: [
                    ("Small", "2×2", "square"),
                    ("Medium", "4×2", "rectangle"),
                    ("Large", "4×4", "rectangle.portrait"),
                    ("Lock", "Inline", "lock.rectangle")
                ],
                previewRows: [
                    ("Following stack", "Latest posts", "person.2"),
                    ("Unread activity", "Counts", "bell.badge")
                ],
                apiNote: "Gallery is design-only until Widget extensions land."
            )
        }
    }

    private func widgetPreview(_ title: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(Color.accentColor)
            Text(title)
                .font(.subheadline.weight(.semibold))
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.06))
                .frame(height: 36)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

// MARK: - Labs

struct LabsSettingsHost: View {
    let route: LabsSettingsRoute
    @AppStorage("settings.labs.experimentalChrome") private var experimentalChrome = false
    @AppStorage("settings.labs.debugOverlays") private var debugOverlays = false
    @AppStorage("settings.labs.verboseLogging") private var verboseLogging = false

    var body: some View {
        switch route {
        case .root:
            SettingsScrollCanvas {
                SettingsHeroBanner(title: "Labs", subtitle: "Optional experiments on this device — not the Features registry.", symbol: "flask")
                SettingsSceneGraphic(style: .pulse)
                Form {
                    Toggle("Experimental chrome sketches", isOn: $experimentalChrome)
                    Toggle("Debug overlays", isOn: $debugOverlays)
                    Toggle("Verbose local logging", isOn: $verboseLogging)
                }
                .scrollDisabled(true)
                .frame(minHeight: 160)
                SettingsAPIFootnote(text: "Labs toggles are local only. Typed FeatureFlagRegistry remains under Features. Developer diagnostics stay under Developer.")
            }
            .navigationTitle("Labs")
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("settings.labs")
        }
    }
}

// MARK: - Photos library prefs

struct PhotosSettingsHost: View {
    let route: PhotosSettingsRoute
    @AppStorage("settings.photos.autoSaveStories") private var autoSaveStories = false
    @AppStorage("settings.photos.limitedLibraryHint") private var limitedHint = true

    var body: some View {
        switch route {
        case .root:
            SettingsScrollCanvas {
                SettingsHeroBanner(title: "Photos", subtitle: "Library access and save behaviour.", symbol: "photo.on.rectangle")
                SettingsSceneGraphic(style: .filmstrip)
                Form {
                    Toggle("Offer to save Stories to Photos", isOn: $autoSaveStories)
                    Toggle("Explain Limited Library", isOn: $limitedHint)
                }
                .scrollDisabled(true)
                .frame(minHeight: 120)
                Button("Open iOS Photos access") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
                SettingsAPIFootnote(text: "Authorization is system-owned. These toggles only affect Modula prompts on this device.")
            }
            .navigationTitle("Photos")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Network diagnostics feel (distinct from Battery)

struct NetworkSettingsHost: View {
    let route: NetworkSettingsRoute
    @Environment(AppEnvironment.self) private var app
    @AppStorage("settings.network.preferWiFiUploads") private var preferWiFi = true
    @AppStorage("settings.network.preloadMedia") private var preload = true

    var body: some View {
        switch route {
        case .root:
            SettingsScrollCanvas {
                SettingsHeroBanner(title: "Network", subtitle: "Upload and preload behaviour on this device.", symbol: "network")
                SettingsSceneGraphic(style: .meter)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    SettingsStatChip(label: "API host", value: "Greenfield", symbol: "server.rack")
                    SettingsStatChip(label: "Preload", value: preload ? "On" : "Off", symbol: "arrow.down.circle")
                }
                Form {
                    Toggle("Prefer Wi‑Fi for large uploads", isOn: $preferWiFi)
                    Toggle("Preload media on Wi‑Fi", isOn: $preload)
                }
                .scrollDisabled(true)
                .frame(minHeight: 120)
                SettingsGroup(title: "Related") {
                    VStack(spacing: 0) {
                        SettingsNavigationRow(title: "Battery & Data", subtitle: "Data saver", symbol: "battery.100.bolt") {
                            app.navigation.open(.settings(.battery(.root)))
                        }
                    }
                }
                SettingsAPIFootnote(text: "Does not print secrets or raw base URLs. Developer → Network remains the diagnostics surface.")
            }
            .navigationTitle("Network")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Reminders / Digests (designed)

struct DigestsSettingsHost: View {
    let route: DigestsSettingsRoute
    @AppStorage("settings.digests.weekly") private var weekly = false
    @AppStorage("settings.digests.morning") private var morning = false

    var body: some View {
        switch route {
        case .root:
            SettingsScrollCanvas {
                SettingsHeroBanner(title: "Digests", subtitle: "Email and push summaries when delivery exists.", symbol: "envelope.open")
                SettingsSceneGraphic(style: .waves)
                Form {
                    Toggle("Weekly recap (when available)", isOn: $weekly)
                    Toggle("Morning brief (when available)", isOn: $morning)
                }
                .scrollDisabled(true)
                .frame(minHeight: 120)
                SettingsAPIFootnote(text: "Toggles are stored locally as intent. No digest dispatcher is claimed — delivery stays off until Greenfield verifies it.")
            }
            .navigationTitle("Digests")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
