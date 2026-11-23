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
                SettingsAPIFootnote(text: "Used by the composer camera (Camera in the post tool bar). Camera access is managed in iOS Settings.")
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
                .tint(app.appearance.liveAccent)
                SettingsAPIFootnote(text: "Shows the access you’ve given Modula in iOS Settings.")
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
                SettingsToggleCard {
                    Toggle("Edge swipe to go back", isOn: $edgeBack)
                    Toggle("Double-tap to like", isOn: $doubleTapLike)
                    Toggle("Swipe to reply in chats", isOn: $swipeReply)
                    Toggle("Shake to undo compose", isOn: $shakeUndo)
                }
                SettingsAPIFootnote(text: "Double-tap likes posts with photos or video. Swipe right on a chat bubble to quote it in your reply. Shake to undo works in Modula’s text fields. Edge Picker options are in Appearance.")
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
    @AppStorage("settings.finder.includeModules") private var includeModules = true
    @AppStorage("settings.finder.peopleFirst") private var peopleFirst = false

    var body: some View {
        switch route {
        case .root:
            SettingsScrollCanvas {
                SettingsHeroBanner(title: "Search", subtitle: "How lookup behaves on this device.", symbol: "magnifyingglass")
                SettingsSceneGraphic(style: .constellation)
                // Search doesn't keep a recent-searches history yet, so the
                // "Save recent searches" toggle and "Clear" row were removed
                // rather than shown as controls that do nothing.
                SettingsToggleCard {
                    Toggle("Include modules in results", isOn: $includeModules)
                    Toggle("Prefer people first", isOn: $peopleFirst)
                }
                SettingsAPIFootnote(text: "Applies to the All results in Search. The Modules tab always shows modules.")
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
                SharingFlowGraphic(preferSheet: preferNative, copyAsLink: copyAsLink)
                SettingsToggleCard {
                    Toggle("Include @handle in share text", isOn: $includeHandle)
                        .settingsAnchor("sharing.handle")
                    Toggle("Prefer system share sheet", isOn: $preferNative)
                        .settingsAnchor("sharing.sheet")
                    Toggle("Copy link instead of opening sheet", isOn: $copyAsLink)
                        .settingsAnchor("sharing.link")
                }
                SettingsAPIFootnote(text: "Used when you share a post from Home or a post page. Copy link wins over the share sheet.")
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
                apiNote: "Location access is managed in iOS Settings."
            )
        case .map:
            SettingsScrollCanvas {
                SettingsHeroBanner(title: "Map posts", subtitle: "Place attachments on posts.", symbol: "map")
                SettingsSceneGraphic(style: .constellation)
                ContentUnavailableView("Adding places isn’t available yet", systemImage: "map", description: Text("You’ll be able to add a location to posts in a future update."))
                    .frame(minHeight: 160)
                SettingsAPIFootnote(text: "Nearby places will appear here when location features are available.")
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
                SettingsAPIFootnote(text: "Previews of Modula widgets.")
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
                apiNote: "Widgets aren’t available yet."
            )
        }
    }

    private func widgetPreview(_ title: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.tint)
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
                SproutIllustrationView(illustration: .science, height: 148)
                SettingsToggleCard {
                    Toggle("Experimental bottom chrome", isOn: $experimentalChrome)
                    Toggle("Debug overlay", isOn: $debugOverlays)
                    Toggle("Verbose network logging", isOn: $verboseLogging)
                }
                SettingsAPIFootnote(text: "Experimental bottom chrome swaps the system tab bar for Modula’s floating bar. The debug overlay shows route, network, power and motion state. Verbose logging writes request method, path, status and timing (never headers or content) to the device log.")
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
                SettingsToggleCard {
                    Toggle("Save Stories you post to Photos", isOn: $autoSaveStories)
                    Toggle("Explain photo access in the composer", isOn: $limitedHint)
                }
                Button("Open iOS Photos access") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
                SettingsAPIFootnote(text: "Modula picks photos through the iOS picker, so it never needs your whole library. Saving Stories asks for add-only access the first time.")
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
                    SettingsStatChip(label: "Server", value: "Modula", symbol: "server.rack")
                    SettingsStatChip(label: "Preload", value: preload ? "On" : "Off", symbol: "arrow.down.circle")
                }
                SettingsToggleCard {
                    Toggle("Prefer Wi‑Fi for large uploads", isOn: $preferWiFi)
                    Toggle("Preload media on Wi‑Fi", isOn: $preload)
                }
                Text("Uploads over 25 MB wait for Wi‑Fi on cellular or Low Data Mode. With preload on, videos in your feed download ahead of time on Wi‑Fi only.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                SettingsGroup(title: "Related") {
                    VStack(spacing: 0) {
                        SettingsNavigationRow(title: "Battery & Data", subtitle: "Data saver", symbol: "battery.100.bolt") {
                            app.navigation.open(.settings(.battery(.root)))
                        }
                    }
                }
                SettingsAPIFootnote(text: "Saved on this device.")
            }
            .navigationTitle("Network")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Reminders / Digests (designed)

struct DigestsSettingsHost: View {
    let route: DigestsSettingsRoute

    var body: some View {
        switch route {
        case .root:
            DigestsSettingsView()
        }
    }
}
