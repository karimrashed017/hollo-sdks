import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Photos are shrunk on the device before upload (F-17): the long edge to at
// most 1600 px, saved as JPEG. That also turns HEIC, which the server can't
// read, into JPEG, and leaves the EXIF block (with the location) behind.
// ImageIO only, no UIKit, so it can be unit-tested.

enum HolloPhotos {
    static let maxPerMessage = 5
    static let maxEdge = 1600
    /** The server refuses photos over 4 MB. */
    static let maxBytes = 4 * 1024 * 1024

    /** A JPEG of any image ImageIO can read, under `maxBytes`; nil if it can't. */
    static func jpeg(from data: Data, maxEdge: Int = maxEdge, quality: Double = 0.7) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0
        else { return nil }
        // Never upscale a photo that's already small.
        var edge = min(maxEdge, longEdge(of: source) ?? maxEdge)
        var quality = quality
        // A 1600 px photo at 0.7 is far under 4 MB; this only guards odd ones.
        for _ in 0..<4 {
            guard let image = downscaled(source, to: edge).flatMap(opaque),
                  let jpeg = encode(image, quality: quality)
            else { return nil }
            if jpeg.count <= maxBytes { return jpeg }
            edge = edge * 3 / 4
            quality = max(0.4, quality - 0.1)
        }
        return nil
    }

    /** A small copy for previews, upright. */
    static func thumbnail(_ data: Data, maxEdge: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0
        else { return nil }
        return downscaled(source, to: maxEdge)
    }

    private static func longEdge(of source: CGImageSource) -> Int? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0
        else { return nil }
        return max(width, height)
    }

    private static func downscaled(_ source: CGImageSource, to edge: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            // Applies the EXIF orientation, so the photo isn't sideways.
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, edge),
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /** JPEG has no transparency: put see-through pixels on white, not black. */
    private static func opaque(_ image: CGImage) -> CGImage? {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast:
            return image
        default:
            break
        }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: image.width, height: image.height,
                  bitsPerComponent: 8, bytesPerRow: 0, space: space,
                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              )
        else { return image }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(rect)
        context.draw(image, in: rect)
        return context.makeImage() ?? image
    }

    private static func encode(_ image: CGImage, quality: Double) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }
        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
