import AVFoundation
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct PreparedImage: Sendable, Equatable {
    var data: Data
    var width: Int
    var height: Int
    var mimeType: String
}

enum MediaPreparationError: Error, Equatable {
    case empty
    case unsupported
    /// The image could not be brought under the requested byte budget, even at the
    /// smallest permitted size and quality.
    case exceedsByteBudget
}

enum MediaPreparation {
    /// Re-encodes on a background executor. Bitmap round-trip strips EXIF/GPS/camera metadata.
    static func jpegStrippingMetadata(_ data: Data, maxPixel: CGFloat = 2048, quality: CGFloat = 0.86) async throws -> PreparedImage {
        try await Task.detached(priority: .userInitiated) {
            try jpegStrippingMetadataSync(data, maxPixel: maxPixel, quality: quality)
        }.value
    }

    nonisolated static func jpegStrippingMetadataSync(_ data: Data, maxPixel: CGFloat, quality: CGFloat) throws -> PreparedImage {
        guard !data.isEmpty else { throw MediaPreparationError.empty }
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw MediaPreparationError.unsupported
        }
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let longest = max(width, height)
        let scale = longest > maxPixel ? maxPixel / longest : 1
        let targetWidth = max(1, Int((width * scale).rounded()))
        let targetHeight = max(1, Int((height * scale).rounded()))
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw MediaPreparationError.unsupported
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        guard let scaled = context.makeImage() else { throw MediaPreparationError.unsupported }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw MediaPreparationError.unsupported
        }
        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(destination, scaled, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw MediaPreparationError.unsupported }
        return PreparedImage(data: output as Data, width: targetWidth, height: targetHeight, mimeType: "image/jpeg")
    }

    /// Re-encodes `data` as a metadata-free JPEG whose encoded size is at most `maxBytes`.
    /// Quality is stepped down first (0.9 → 0.72) at the largest allowed size; only then
    /// is the long edge reduced (×0.84 per step) toward `minPixel`. At `minPixel` the
    /// ladder extends to 0.6, and only a pathological image falls back below `minPixel`
    /// (to a 1440px last resort). Never upscales; applies EXIF orientation.
    static func jpegFitting(
        _ data: Data,
        maxBytes: Int,
        maxPixel: CGFloat = 3072,
        minPixel: CGFloat = 2048
    ) async throws -> PreparedImage {
        try await Task.detached(priority: .userInitiated) {
            try jpegFittingSync(data, maxBytes: maxBytes, maxPixel: maxPixel, minPixel: minPixel)
        }.value
    }

    nonisolated static let fittingQualityLadder: [CGFloat] = [0.9, 0.86, 0.82, 0.78, 0.75, 0.72]
    nonisolated static let floorQualityLadder: [CGFloat] = [0.68, 0.64, 0.6]
    nonisolated static let lastResortLongEdge: CGFloat = 1440

    nonisolated static func jpegFittingSync(
        _ data: Data,
        maxBytes: Int,
        maxPixel: CGFloat = 3072,
        minPixel: CGFloat = 2048
    ) throws -> PreparedImage {
        guard !data.isEmpty, maxBytes > 0 else { throw MediaPreparationError.empty }
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let sourceWidth = properties[kCGImagePropertyPixelWidth] as? Int,
              let sourceHeight = properties[kCGImagePropertyPixelHeight] as? Int else {
            throw MediaPreparationError.unsupported
        }
        let longest = CGFloat(max(sourceWidth, sourceHeight))
        let start = min(maxPixel, longest)
        let floor = min(minPixel, start)
        var sizes: [CGFloat] = [start]
        while let last = sizes.last, last > floor {
            sizes.append(max(floor, (last * 0.84).rounded()))
        }
        func attempt(_ pixel: CGFloat, _ ladder: [CGFloat]) throws -> PreparedImage? {
            // Thumbnail decode downsamples efficiently, applies EXIF orientation and never upscales.
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: Int(pixel.rounded()),
                kCGImageSourceShouldCacheImmediately: true
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                throw MediaPreparationError.unsupported
            }
            for quality in ladder {
                let encoded = try encodeJPEG(image, quality: quality)
                if encoded.count <= maxBytes {
                    return PreparedImage(data: encoded, width: image.width, height: image.height, mimeType: "image/jpeg")
                }
            }
            return nil
        }
        for (index, pixel) in sizes.enumerated() {
            let atFloor = index == sizes.count - 1
            if let fitted = try attempt(pixel, atFloor ? fittingQualityLadder + floorQualityLadder : fittingQualityLadder) {
                return fitted
            }
        }
        if floor > lastResortLongEdge, let fitted = try attempt(lastResortLongEdge, fittingQualityLadder + floorQualityLadder) {
            return fitted
        }
        throw MediaPreparationError.exceedsByteBudget
    }

    nonisolated private static func encodeJPEG(_ image: CGImage, quality: CGFloat) throws -> Data {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw MediaPreparationError.unsupported
        }
        // Only the bitmap is written: no EXIF/GPS/camera metadata survives.
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw MediaPreparationError.unsupported }
        return output as Data
    }

    static func cropJPEG(
        _ data: Data,
        normalizedRect: CGRect,
        maxPixel: CGFloat,
        quality: CGFloat = 0.84
    ) async throws -> PreparedImage {
        try await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                throw MediaPreparationError.unsupported
            }
            let imageRect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
            let crop = CGRect(
                x: normalizedRect.origin.x * imageRect.width,
                y: normalizedRect.origin.y * imageRect.height,
                width: normalizedRect.width * imageRect.width,
                height: normalizedRect.height * imageRect.height
            ).integral.intersection(imageRect)
            guard crop.width >= 8, crop.height >= 8, let cropped = image.cropping(to: crop) else {
                throw MediaPreparationError.unsupported
            }
            let longest = max(CGFloat(cropped.width), CGFloat(cropped.height))
            let scale = longest > maxPixel ? maxPixel / longest : 1
            let targetWidth = max(1, Int((CGFloat(cropped.width) * scale).rounded()))
            let targetHeight = max(1, Int((CGFloat(cropped.height) * scale).rounded()))
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            guard let context = CGContext(
                data: nil,
                width: targetWidth,
                height: targetHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                throw MediaPreparationError.unsupported
            }
            context.interpolationQuality = .high
            context.draw(cropped, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
            guard let scaled = context.makeImage() else { throw MediaPreparationError.unsupported }
            let output = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
                throw MediaPreparationError.unsupported
            }
            CGImageDestinationAddImage(destination, scaled, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { throw MediaPreparationError.unsupported }
            return PreparedImage(data: output as Data, width: targetWidth, height: targetHeight, mimeType: "image/jpeg")
        }.value
    }

    static func rotatedJPEG(_ data: Data, quarterTurns: Int) async throws -> PreparedImage {
        try await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                throw MediaPreparationError.unsupported
            }
            let turns = ((quarterTurns % 4) + 4) % 4
            let ci = CIImage(cgImage: image)
            let rotated: CIImage
            switch turns {
            case 1: rotated = ci.oriented(.right)
            case 2: rotated = ci.oriented(.down)
            case 3: rotated = ci.oriented(.left)
            default: rotated = ci
            }
            let context = CIContext(options: [.useSoftwareRenderer: false])
            guard let cg = context.createCGImage(rotated, from: rotated.extent) else {
                throw MediaPreparationError.unsupported
            }
            let output = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
                throw MediaPreparationError.unsupported
            }
            CGImageDestinationAddImage(destination, cg, [kCGImageDestinationLossyCompressionQuality: 0.86] as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { throw MediaPreparationError.unsupported }
            return PreparedImage(data: output as Data, width: cg.width, height: cg.height, mimeType: "image/jpeg")
        }.value
    }

    /// Inspect only — no silent transcode. Publishing remains capability-gated.
    static func inspectVideo(at url: URL) async throws -> VideoInspection {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let size: CGSize
        if let track = tracks.first {
            size = try await track.load(.naturalSize)
        } else {
            size = .zero
        }
        let bytes = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
        return VideoInspection(
            duration: duration.seconds,
            width: Int(size.width),
            height: Int(size.height),
            byteCount: bytes
        )
    }
}

struct VideoInspection: Sendable, Equatable {
    var duration: TimeInterval
    var width: Int
    var height: Int
    var byteCount: Int?
}
