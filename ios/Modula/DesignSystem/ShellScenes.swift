import SwiftUI
import UIKit

/// Display-size scene art. The multi-megabyte source files are not in the app.
/// Greenfield has no catalogue route for these pictures, so they are not fetched.
/// A chosen cover is uploaded with the existing profile media flow.
enum ShellScene: String, CaseIterable, Identifiable, Sendable {
    case meadow
    case studio
    case mountainLake
    case library
    case moonLake
    case unitLake
    case sunrise
    case misty
    case storageCloud

    var id: String { rawValue }

    var title: String {
        switch self {
        case .meadow: "Meadow"
        case .studio: "Studio"
        case .mountainLake: "Mountain lake"
        case .library: "Library"
        case .moonLake: "Moon lake"
        case .unitLake: "Unit lake"
        case .sunrise: "Sunrise lake"
        case .misty: "Misty mountains"
        case .storageCloud: "Storage"
        }
    }

    var assetName: String {
        switch self {
        case .meadow: "SceneMeadow"
        case .studio: "SceneStudio"
        case .mountainLake: "SceneMountainLake"
        case .library: "SceneLibrary"
        case .moonLake: "SceneMoonLake"
        case .unitLake: "SceneUnitLake"
        case .sunrise: "SceneSunrise"
        case .misty: "SceneMisty"
        case .storageCloud: "SceneStorageCloud"
        }
    }

    /// Opaque landscapes offered as a profile cover. The banner and the cloud stay local headers.
    static var coverChoices: [ShellScene] {
        [.meadow, .studio, .mountainLake, .library, .moonLake, .unitLake, .sunrise]
    }

    /// JPEG for `POST /v1/attachments/uploads` and then `POST /v1/profiles/me/cover`.
    func coverJPEG() -> Data? {
        guard Self.coverChoices.contains(self),
              let image = UIImage(named: assetName),
              let data = image.jpegData(compressionQuality: 0.86),
              !data.isEmpty else { return nil }
        return data
    }
}

struct ShellSceneImage: View {
    var scene: ShellScene

    var body: some View {
        Image(scene.assetName)
            .resizable()
            .interpolation(.high)
    }
}

/// Seven cover choices. One labelled grid, not a second settings tree (Hick’s law).
struct ShellSceneCoverPicker: View {
    var onPick: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(ShellScene.coverChoices) { scene in
                        Button {
                            guard let data = scene.coverJPEG() else { return }
                            onPick(data)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                ShellSceneImage(scene: scene)
                                    .scaledToFill()
                                    .frame(height: 108)
                                    .frame(maxWidth: .infinity)
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                Text(scene.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                            }
                        }
                        .buttonStyle(.plain)
                        .frame(minHeight: 44)
                        .accessibilityLabel(scene.title)
                        .accessibilityIdentifier("profile.cover.scene.\(scene.rawValue)")
                    }
                }
                .padding(16)
            }
            .navigationTitle("Modula scenes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .accessibilityIdentifier("profile.cover.scenes")
    }
}
