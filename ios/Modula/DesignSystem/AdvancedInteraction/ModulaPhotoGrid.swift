import Photos
import SwiftUI
import UIKit

// MARK: - In-app photo library grid (PhotoKit) — Instagram / X style

struct ModulaPhotoAlbum: Identifiable, Hashable {
    let id: String
    let title: String
    let count: Int
    let collection: PHAssetCollection?
}

@MainActor
final class ModulaPhotoLibraryModel: ObservableObject {
    @Published private(set) var status: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @Published private(set) var assets: PHFetchResult<PHAsset> = PHFetchResult()
    @Published private(set) var albums: [ModulaPhotoAlbum] = []
    @Published var album: ModulaPhotoAlbum?
    let imageManager = PHCachingImageManager()
    var includeVideos: Bool
    private var registered = false
    private lazy var observer = ModulaPhotoChangeObserver { [weak self] in
        Task { @MainActor in
            guard let self else { return }
            self.status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            self.reload()
        }
    }

    init(includeVideos: Bool) {
        self.includeVideos = includeVideos
    }

    var hasAccess: Bool { status == .authorized || status == .limited }

    func prepare() async {
        if status == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        } else {
            status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        }
        guard hasAccess else { return }
        if !registered {
            PHPhotoLibrary.shared().register(observer)
            registered = true
        }
        reload()
    }

    func unregister() {
        if registered { PHPhotoLibrary.shared().unregisterChangeObserver(observer); registered = false }
    }

    private var options: PHFetchOptions {
        let o = PHFetchOptions()
        o.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        o.predicate = includeVideos
            ? NSPredicate(format: "mediaType == %d || mediaType == %d", PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue)
            : NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        return o
    }

    func reload() {
        if let collection = album?.collection {
            assets = PHAsset.fetchAssets(in: collection, options: options)
        } else {
            assets = PHAsset.fetchAssets(with: options)
        }
        var list: [ModulaPhotoAlbum] = [ModulaPhotoAlbum(id: "recents", title: "Recents", count: PHAsset.fetchAssets(with: options).count, collection: nil)]
        var smart: [PHAssetCollectionSubtype] = [.smartAlbumFavorites, .smartAlbumSelfPortraits, .smartAlbumScreenshots, .smartAlbumPanoramas, .smartAlbumLivePhotos]
        if includeVideos { smart.insert(.smartAlbumVideos, at: 1) }
        for subtype in smart {
            PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: subtype, options: nil).enumerateObjects { c, _, _ in
                let n = PHAsset.fetchAssets(in: c, options: self.options).count
                if n > 0 { list.append(ModulaPhotoAlbum(id: c.localIdentifier, title: c.localizedTitle ?? "Album", count: n, collection: c)) }
            }
        }
        PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil).enumerateObjects { c, _, _ in
            let n = PHAsset.fetchAssets(in: c, options: self.options).count
            if n > 0 { list.append(ModulaPhotoAlbum(id: c.localIdentifier, title: c.localizedTitle ?? "Album", count: n, collection: c)) }
        }
        albums = list
        if album == nil { album = list.first }
    }


    /// Loads a display-sized, upright UIImage for attaching (re-encoded later, which strips metadata).
    func fullImage(_ asset: PHAsset, maxPixel: CGFloat = 2560) async -> UIImage? {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.resizeMode = .exact
        let scale = min(1, maxPixel / CGFloat(max(asset.pixelWidth, asset.pixelHeight, 1)))
        let size = CGSize(width: CGFloat(asset.pixelWidth) * scale, height: CGFloat(asset.pixelHeight) * scale)
        return await withCheckedContinuation { cont in
            PHImageManager.default().requestImage(for: asset, targetSize: size, contentMode: .aspectFit, options: options) { image, info in
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if !degraded { cont.resume(returning: image.map(Self.upright)) }
            }
        }
    }

    /// Bakes EXIF orientation into the pixels so re-encoding (which strips metadata) keeps the photo upright.
    nonisolated static func upright(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    /// Exports a video asset to a temporary file.
    func videoFile(_ asset: PHAsset) async -> URL? {
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        let avAsset: AVAsset? = await withCheckedContinuation { cont in
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { a, _, _ in
                nonisolated(unsafe) let a = a
                cont.resume(returning: a)
            }
        }
        guard let url = (avAsset as? AVURLAsset)?.url else { return nil }
        let out = FileManager.default.temporaryDirectory.appending(path: "library-\(UUID().uuidString).\(url.pathExtension.isEmpty ? "mov" : url.pathExtension)")
        do { try FileManager.default.copyItem(at: url, to: out); return out } catch { return nil }
    }
}

private final class ModulaPhotoChangeObserver: NSObject, PHPhotoLibraryChangeObserver, @unchecked Sendable {
    let onChange: @Sendable () -> Void
    init(_ onChange: @escaping @Sendable () -> Void) { self.onChange = onChange }
    func photoLibraryDidChange(_ changeInstance: PHChange) { onChange() }
}

/// Grid of the user's photos: camera tile first, recents, album switcher, numbered multi-select.
struct ModulaPhotoGrid: View {
    @ObservedObject var model: ModulaPhotoLibraryModel
    @Binding var selection: [String]
    var maxSelection: Int
    var accent: Color
    var columns: Int = 4
    var showsCameraTile = true
    var onCamera: (() -> Void)? = nil
    var onExpand: (() -> Void)? = nil
    /// Videos are listed (with durations) but only selectable when the destination supports them.
    var allowsVideo = true
    var onVideoBlocked: (() -> Void)? = nil
    var onAdd: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 8) {
            if model.hasAccess {
                toolbar
                if model.status == .limited { limitedBanner }
                grid
            } else if model.status == .notDetermined {
                ProgressView().frame(maxWidth: .infinity, minHeight: 160)
            } else {
                deniedCard
            }
        }
        .task { await model.prepare() }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(model.albums) { album in
                    Button {
                        model.album = album
                        model.reload()
                        HapticEngine.shared.play(.selection)
                    } label: {
                        Label("\(album.title) (\(album.count))", systemImage: album.id == model.album?.id ? "checkmark" : "photo.on.rectangle")
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(model.album?.title ?? "Recents").font(.subheadline.weight(.semibold))
                    Image(systemName: "chevron.down").font(.caption.weight(.bold))
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 12).frame(height: 34)
                .modulaGlass(in: Capsule(), interactive: true)
            }
            .accessibilityLabel("Album")
            Spacer(minLength: 0)
            if let onExpand {
                Button { onExpand() } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.primary)
                        .frame(width: 34, height: 34)
                        .modulaGlass(in: Circle(), interactive: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Expand library")
            }
            Button {
                onAdd()
            } label: {
                Text(selection.isEmpty ? "Add" : "Add \(selection.count)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(selection.isEmpty ? Color.primary.opacity(0.75) : .white)
                    .padding(.horizontal, 14).frame(height: 34)
                    .background { if !selection.isEmpty { Capsule().fill(accent) } }
                    .modulaGlass(in: Capsule(), interactive: !selection.isEmpty, tint: selection.isEmpty ? nil : accent, prominent: !selection.isEmpty)
            }
            .buttonStyle(.plain)
            .disabled(selection.isEmpty)
            .accessibilityIdentifier("photogrid.add")
        }
    }

    private var limitedBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "photo.badge.exclamationmark").foregroundStyle(accent)
            Text("Modula can see only some of your photos.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 0)
            Menu("Manage") {
                Button("Select more photos") { Self.presentLimitedPicker() }
                Button("Allow all photos in Settings") { Self.openSettings() }
            }
            .font(.footnote.weight(.semibold))
        }
        .padding(10)
        .background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var deniedCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "photo.on.rectangle.angled").font(.title2).foregroundStyle(accent)
            Text("Allow photo access to pick from your library.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Open Settings") { Self.openSettings() }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 16).frame(height: 38)
                .modulaGlass(in: Capsule(), interactive: true, tint: accent)
                .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
    }

    private var grid: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 2
            let side = (geo.size.width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(side), spacing: spacing), count: columns), spacing: spacing) {
                    if showsCameraTile, let onCamera {
                        Button(action: onCamera) {
                            ZStack {
                                Rectangle().fill(Color.primary.opacity(0.08))
                                Image(systemName: "camera.fill").font(.title2).foregroundStyle(accent)
                            }
                            .frame(width: side, height: side)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Take photo")
                    }
                    ForEach(0..<model.assets.count, id: \.self) { index in
                        let asset = model.assets.object(at: index)
                        ModulaPhotoGridCell(
                            asset: asset,
                            manager: model.imageManager,
                            side: side,
                            order: selection.firstIndex(of: asset.localIdentifier).map { $0 + 1 },
                            accent: accent,
                            reduceMotion: reduceMotion
                        ) { toggle(asset) }
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private func toggle(_ asset: PHAsset) {
        let id = asset.localIdentifier
        if asset.mediaType == .video, !allowsVideo {
            HapticEngine.shared.play(.warning)
            onVideoBlocked?()
            return
        }
        if let i = selection.firstIndex(of: id) {
            selection.remove(at: i)
        } else if selection.count < maxSelection {
            if maxSelection == 1 { selection = [id] } else { selection.append(id) }
        } else {
            HapticEngine.shared.play(.warning)
            return
        }
        HapticEngine.shared.play(.selection)
    }

    static func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }

    static func presentLimitedPicker() {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
              var top = scene.keyWindow?.rootViewController else { return }
        while let next = top.presentedViewController { top = next }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: top)
    }
}

private struct ModulaPhotoGridCell: View {
    let asset: PHAsset
    let manager: PHCachingImageManager
    let side: CGFloat
    var order: Int?
    var accent: Color
    var reduceMotion: Bool
    var onTap: () -> Void
    @State private var image: UIImage?
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let image {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else {
                        Rectangle().fill(Color.primary.opacity(0.06))
                    }
                }
                .frame(width: side, height: side)
                .clipped()
                .overlay { if order != nil { Color.white.opacity(0.22) } }

                ZStack {
                    Circle().fill(order != nil ? accent : Color.black.opacity(0.25))
                    Circle().strokeBorder(.white, lineWidth: 1.5)
                    if let order {
                        Text("\(order)").font(.caption2.weight(.bold)).foregroundStyle(.white)
                    }
                }
                .frame(width: 22, height: 22)
                .padding(5)
                .scaleEffect(order != nil && !reduceMotion ? 1.08 : 1)
                .animation(.snappy(duration: 0.18), value: order)

                if asset.mediaType == .video {
                    Text(Duration.seconds(asset.duration).formatted(.time(pattern: .minuteSecond)))
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.6), radius: 2)
                        .padding(5)
                        .frame(width: side, height: side, alignment: .bottomTrailing)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(asset.mediaType == .video ? "Video" : "Photo")
        .accessibilityValue(order.map { "Selected, \($0)" } ?? "")
        .accessibilityAddTraits(order != nil ? .isSelected : [])
        .task(id: asset.localIdentifier) {
            let px = side * displayScale
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.isNetworkAccessAllowed = true
            options.resizeMode = .fast
            let stream = AsyncStream<UIImage> { continuation in
                let id = manager.requestImage(for: asset, targetSize: CGSize(width: px, height: px), contentMode: .aspectFill, options: options) { image, info in
                    if let image { continuation.yield(image) }
                    let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                    if !degraded { continuation.finish() }
                }
                continuation.onTermination = { _ in manager.cancelImageRequest(id) }
            }
            for await next in stream { image = next }
        }
    }
}
