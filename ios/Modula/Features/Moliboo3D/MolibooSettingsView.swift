import SwiftUI

/// Settings → Moliboo. Its own home for everything Moliboo: choose, wardrobe/Studio, 3D, motion, sounds/haptics,
/// Home companion, and a preview of the Originals collection. Storage keys are the existing mascot keys (unchanged),
/// so saved choices, outfits and entitlements carry over.
enum MolibooSettings {
    static let animationsKey = "moliboo.playfulAnimations"
    static let hapticsKey = "moliboo.haptics"
    static let onboardedKey = "moliboo.onboarded.v1"
}

struct MolibooSettingsView: View {
    @AppStorage(ModulaMascotSettings.kindKey) private var kindRaw = ModulaMascotKind.pip.rawValue
    @AppStorage(MolibooFeatureFlags.native3DKey) private var native3D = MolibooFeatureFlags.native3DDefault
    @AppStorage(MolibooSettings.animationsKey) private var playful = true
    @AppStorage(MolibooSettings.hapticsKey) private var haptics = true
    @AppStorage(MolibooSettings.onboardedKey) private var onboarded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hop = false
    @State private var cheer = 0
    @State private var showOnboarding = false
    private var wardrobe = MascotWardrobeStore.shared

    private var kind: ModulaMascotKind? { ModulaMascotKind(rawValue: kindRaw) }
    private var motionOn: Bool { playful && !reduceMotion }

    var body: some View {
        Form {
            Section { hero.listRowInsets(EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14)) }

            // Choose, show-on surfaces, Studio and wardrobe, Profile and sounds (shared with Composer settings).
            ComposerMascotSettingsSection()

            Section {
                Toggle(isOn: $native3D) { Label("3D Moliboos", systemImage: "cube.transparent") }
                    .accessibilityIdentifier("moliboo.settings.3d")
                if native3D, let d = MolibooRegistry.descriptor(for: kindRaw) {
                    NavigationLink { MolibooLivingStudioView(characterID: d.id) } label: { Label("Open \(d.displayName)'s Studio", systemImage: "sparkles") }
                        .accessibilityIdentifier("moliboo.settings.studio")
                }
                if native3D {
                    NavigationLink { MolibooCollectionView() } label: { Label("Collection", systemImage: "square.grid.3x3.fill") }
                        .accessibilityIdentifier("moliboo.settings.collection")
                }
            } header: { Text("3D") } footer: {
                Text(native3D ? "3D is ready for \(MolibooRegistry.available3D.map(\.displayName).formatted(.list(type: .and))). More Moliboos are on the way." : "Moliboos use the classic 2D look everywhere.")
            }

            Section {
                Toggle(isOn: $playful) { Label("Playful animations", systemImage: "figure.dance") }
                Toggle(isOn: $haptics) { Label("Haptics", systemImage: "hand.tap") }
            } header: { Text("Motion & feel") } footer: {
                Text(reduceMotion ? "Reduce Motion is on in iOS, so Moliboos keep their movements calm." : "Hops, wiggles and little celebrations. Turn this off for a calmer Moliboo.")
            }

            Section {
                collection
            } header: { Text("The Originals") } footer: {
                Text("25 founding Moliboos. Collect them as they arrive.")
            }

            Section {
                Button { showOnboarding = true } label: { Label("Replay the welcome", systemImage: "party.popper") }
            }
        }
        .navigationTitle("Moliboo")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("settings.moliboo")
        .sensoryFeedback(.impact(flexibility: .soft), trigger: cheer) { _, _ in haptics }
        .sheet(isPresented: $showOnboarding) { MolibooWelcomeSheet { onboarded = true; showOnboarding = false } }
        .onAppear { if !onboarded { showOnboarding = true } }
    }

    private var hero: some View {
        VStack(spacing: 12) {
            Image("MoliboosLogo")   // official wordmark, exact vector asset
                .resizable().scaledToFit().frame(height: 30)
                .accessibilityLabel("Moliboos")
            ZStack {
                Circle().fill(.tint.opacity(0.12)).frame(width: 150, height: 150)
                    .scaleEffect(hop && motionOn ? 1.08 : 1)
                if let kind {
                    ModulaMascotFigure(kind: kind, pose: .still(), size: 62, outfit: wardrobe.outfit)
                        .offset(y: hop && motionOn ? -14 : 0)
                        .rotationEffect(.degrees(hop && motionOn ? -6 : 0))
                        .transition(.scale.combined(with: .opacity))
                        .id(kind)
                } else {
                    Image(systemName: "moon.zzz").font(.largeTitle).foregroundStyle(.secondary)
                }
            }
            .frame(height: 160)
            .contentShape(Rectangle())
            .onTapGesture { boop() }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(kind.map { "\($0.name). Tap to say hi." } ?? "No Moliboo chosen")
            Text(kind.map { "Hi, I’m \($0.name)!" } ?? "Choose a Moliboo below")
                .font(.headline)
            if let kind { Text(kind.personality).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center) }
        }
        .frame(maxWidth: .infinity)
        .animation(motionOn ? .spring(response: 0.32, dampingFraction: 0.5) : nil, value: hop)
        .animation(motionOn ? .snappy : nil, value: kindRaw)
        .onChange(of: kindRaw) { _, _ in boop() }
    }

    private func boop() {
        cheer += 1
        guard motionOn else { return }
        hop = true
        Task { try? await Task.sleep(for: .milliseconds(260)); hop = false }
    }

    private var collection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Array(MolibooCosmetics.originals.enumerated()), id: \.offset) { i, id in
                    let k = ModulaMascotKind(rawValue: id)
                    VStack(spacing: 4) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.quaternary.opacity(0.5))
                            if native3D, let img = MolibooPortrait.image(for: id) {
                                Image(uiImage: img).resizable().scaledToFit().padding(4)
                            } else if let k {
                                ModulaMascotFigure(kind: k, pose: .still(), size: 22)
                            } else {
                                Image(systemName: "questionmark").font(.title3.weight(.bold)).foregroundStyle(.tertiary)
                            }
                        }
                        .frame(width: 64, height: 64)
                        Text(String(format: "%03d", i + 1)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        Text(k != nil ? id.prefix(1).uppercased() + id.dropFirst() : "Soon").font(.caption2.weight(.semibold))
                    }
                    .onTapGesture { if k != nil { kindRaw = id } }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.vertical, 4)
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
    }
}

/// One-time welcome moment (also replayable from Settings → Moliboo).
struct MolibooWelcomeSheet: View {
    var done: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(MolibooSettings.animationsKey) private var playful = true
    @State private var appear = false
    private let trio: [ModulaMascotKind] = [.pip, .pebble, .moss]

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            Image("MoliboosLogo").resizable().scaledToFit().frame(height: 44).accessibilityLabel("Moliboos")
            HStack(spacing: 18) {
                ForEach(Array(trio.enumerated()), id: \.offset) { i, k in
                    ModulaMascotFigure(kind: k, pose: .still(), size: 40)
                        .offset(y: appear ? 0 : 40)
                        .opacity(appear ? 1 : 0)
                        .animation(playful && !reduceMotion ? .spring(response: 0.5, dampingFraction: 0.6).delay(Double(i) * 0.12) : nil, value: appear)
                }
            }
            Text("Little friends, big feelings.").font(.title2.weight(.bold)).multilineTextAlignment(.center)
            Text("Pick your Moliboo, dress it up in the Studio and it’ll keep you company across Modula.")
                .font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 24)
            Spacer()
            Button(action: done) { Text("Let’s go").frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent).controlSize(.large).padding(.horizontal, 24)
                .accessibilityIdentifier("moliboo.welcome.go")
        }
        .padding(.bottom, 24)
        .presentationDetents([.large])
        .onAppear { appear = true }
        .sensoryFeedback(.success, trigger: appear)
    }
}
