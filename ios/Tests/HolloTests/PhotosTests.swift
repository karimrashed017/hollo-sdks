import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Hollo

final class PhotosTests: XCTestCase {
    /** A plain image of the given size, encoded as `type`. */
    private func image(width: Int, height: Int, type: UTType = .png, alpha: Bool = false) throws -> Data {
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let info = alpha ? CGImageAlphaInfo.premultipliedLast : CGImageAlphaInfo.noneSkipLast
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: info.rawValue
        ))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.6, alpha: alpha ? 0.5 : 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let cgImage = try XCTUnwrap(context.makeImage())
        let data = NSMutableData()
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithData(data as CFMutableData, type.identifier as CFString, 1, nil)
        )
        CGImageDestinationAddImage(destination, cgImage, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func pixelSize(_ data: Data) throws -> (width: Int, height: Int) {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        let width = try XCTUnwrap(properties[kCGImagePropertyPixelWidth] as? Int)
        let height = try XCTUnwrap(properties[kCGImagePropertyPixelHeight] as? Int)
        return (width, height)
    }

    private func isJPEG(_ data: Data) -> Bool {
        data.starts(with: [0xFF, 0xD8, 0xFF])
    }

    func testShrinksALargePhotoToA1600PixelJPEG() throws {
        let jpeg = try XCTUnwrap(HolloPhotos.jpeg(from: try image(width: 3200, height: 2000)))
        XCTAssertTrue(isJPEG(jpeg))
        let size = try pixelSize(jpeg)
        XCTAssertEqual(size.width, 1600)
        XCTAssertEqual(size.height, 1000)
        XCTAssertLessThanOrEqual(jpeg.count, HolloPhotos.maxBytes)
    }

    func testKeepsASmallPhotoItsOwnSize() throws {
        let jpeg = try XCTUnwrap(HolloPhotos.jpeg(from: try image(width: 400, height: 300)))
        XCTAssertTrue(isJPEG(jpeg))
        let size = try pixelSize(jpeg)
        XCTAssertEqual(size.width, 400)
        XCTAssertEqual(size.height, 300)
    }

    func testTurnsATransparentPNGIntoAJPEG() throws {
        let jpeg = try XCTUnwrap(HolloPhotos.jpeg(from: try image(width: 800, height: 600, alpha: true)))
        XCTAssertTrue(isJPEG(jpeg))
    }

    func testRefusesDataThatIsNotAnImage() {
        XCTAssertNil(HolloPhotos.jpeg(from: Data("not a photo".utf8)))
        XCTAssertNil(HolloPhotos.jpeg(from: Data()))
    }

    func testMakesSmallThumbnails() throws {
        let thumbnail = try XCTUnwrap(HolloPhotos.thumbnail(try image(width: 1600, height: 800), maxEdge: 240))
        XCTAssertEqual(thumbnail.width, 240)
        XCTAssertEqual(thumbnail.height, 120)
    }
}
