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

enum MediaPreparationError: Error {
    case empty
    case unsupported
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
