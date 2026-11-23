#if DEBUG
import SwiftUI
import UIKit

// MOL-03B developer fitting lab — Debug builds only, never reachable from the public Studio.
// Live-tunes the Signature Cap fit for data-driven families (scale / max width / head-top lift go through the same
// spec path a signed package `fit` uses), shows still + animated phases side by side, and exports a
// `modula.moliboo.fits.1` profile. X / Y / rotation / layer / anchor / occlusion are recorded for the export;
// only scale, width and lift are previewed live because the 2D rig positions the cap from those.

struct MolibooFitLabView: View {
    @State private var kind: ModulaMascotKind = .somna
    @State private var hatScale = 1.0
    @State private var maxWidth = 0.6
    @State private var lift = 0.0
    @State private var offsetX = 0.0
    @State private var offsetY = 0.0
    @State private var rotation = 0.0
    @State private var layer = "front"
    @State private var occlusion = "head-top props hide while a hat is worn"
    @State private var exported: String?
    @State private var revision = MolibooPackageRevision.shared

    private var cap: MascotWardrobeItem? { MascotWardrobeCatalog.item(id: "cap.moliboo.signature") }
    private var wearable: [ModulaMascotKind] { ModulaMascotKind.allCases.filter(\.supportsWardrobe) }
    private var liveTunable: Bool { kind.builtInSpec != nil }

    var body: some View {
        let _ = revision.value
        Form {
            Section("Character") {
                Picker("Moliboo", selection: $kind) {
                    ForEach(wearable, id: \.self) { k in Text("#\(String(format: "%03d", k.number)) \(k.registryEntry?.name ?? k.rawValue)").tag(k) }
                }
                if let p = MolibooFitProfiles.bundled?.profiles["fit/\(kind.rawValue)"] {
                    LabeledContent("Committed fit", value: String(format: "y %.3f · w %.3f · sink %.3f", p.anchor.y, p.width, p.sink))
                }
            }
            Section {
                HStack(spacing: 8) {
                    if let cap {
                        ModulaMascotFigure(kind: kind, pose: .still(), size: 56, outfit: .solo(cap)).frame(width: 112, height: 108)
                        ForEach([0.7, 1.9], id: \.self) { t in
                            ModulaMascotFigure(kind: kind, pose: MascotPose(t: t, amp: 1), size: 40, outfit: .solo(cap)).frame(width: 80, height: 78)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            } header: { Text("Preview (still, t=0.7, t=1.9)") }
            Section(liveTunable ? "Live (spec families)" : "Read-only (Originals use the hand-drawn rig)") {
                slider("Scale", $hatScale, 0.4...1.4)
                slider("Max width", $maxWidth, 0.2...0.9)
                slider("Head-top lift", $lift, 0...0.3)
            }
            .disabled(!liveTunable)
            Section("Recorded for export") {
                slider("X", $offsetX, -0.3...0.3)
                slider("Y", $offsetY, -0.3...0.3)
                slider("Rotation°", $rotation, -30...30)
                Picker("Layer", selection: $layer) { ForEach(["back", "body", "front"], id: \.self) { Text($0) } }
                TextField("Occlusion", text: $occlusion)
            }
            Section {
                Button("Reset to built-in") { reset() }
                Button("Export profile") { export() }
                if let exported { Text(exported).font(.caption.monospaced()).textSelection(.enabled) }
            }
        }
        .navigationTitle("Fit lab")
        .onAppear(perform: reset)
        .onChange(of: kind) { reset() }
        .onChange(of: hatScale) { apply() }
        .onChange(of: maxWidth) { apply() }
        .onChange(of: lift) { apply() }
        .onDisappear {
            for k in ModulaMascotKind.allCases { MolibooPackageRuntime.shared.setDebugFit(nil, for: k) }
            revision.bump()
        }
    }

    private func slider(_ title: String, _ v: Binding<Double>, _ r: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading) {
            HStack { Text(title); Spacer(); Text(String(format: "%.3f", v.wrappedValue)).monospacedDigit().foregroundStyle(.secondary) }
            Slider(value: v, in: r)
        }
    }

    private func reset() {
        let spec = kind.builtInSpec
        hatScale = Double(spec?.hatScale ?? 1)
        maxWidth = Double(spec?.hatMaxWidth ?? 0.6)
        lift = Double(spec?.headTopExtra ?? 0)
        offsetX = 0; offsetY = 0; rotation = 0; layer = "front"
        MolibooPackageRuntime.shared.setDebugFit(nil, for: kind)
        revision.bump()
    }

    private func apply() {
        guard liveTunable else { return }
        MolibooPackageRuntime.shared.setDebugFit(.init(hatScale: hatScale, hatMaxWidth: maxWidth, headTopExtra: lift), for: kind)
        revision.bump()
    }

    private func export() {
        let rig = MascotRig.stock(kind)
        let profile: [String: Any] = [
            "characterId": kind.registryID, "accessoryId": "cap.moliboo.signature",
            "anchor": ["x": offsetX, "y": Double(rig.headTop) + offsetY], "scale": hatScale, "width": Double(rig.hatWidth),
            "maxWidth": maxWidth, "headTopExtra": lift, "rotation": rotation, "zIndex": 30, "layer": layer,
            "occlusion": occlusion, "followHeadMotion": true, "sink": Double(rig.hatSink), "validated": false,
        ]
        let file: [String: Any] = ["schemaVersion": MolibooFitFile.schemaVersion, "accessoryId": "cap.moliboo.signature",
                                   "coordinateConvention": MolibooFitProfiles.convention, "profiles": ["fit/\(kind.rawValue)": profile]]
        guard let data = try? JSONSerialization.data(withJSONObject: file, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return }
        UIPasteboard.general.string = text
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("mol03-fit-\(kind.rawValue).json")
        try? data.write(to: url, options: .atomic)
        exported = "Copied and saved \(url.lastPathComponent) (validated=false until the acceptance suite re-measures it)\n" + text
    }
}
#endif
