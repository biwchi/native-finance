import Foundation
import ImageIO
import UniformTypeIdentifiers

struct ReceiptPhoto: Sendable {
    let jpegData: Data

    var dataURL: String { "data:image/jpeg;base64," + jpegData.base64EncodedString() }

    init(data: Data) throws {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 2048,
                kCGImageSourceShouldCacheImmediately: true,
              ] as CFDictionary) else {
            throw LocalDataError(message: "This photo couldn't be opened. Choose another photo.")
        }

        // Re-encode the oriented thumbnail without the source's location or EXIF metadata.
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw LocalDataError(message: "This photo couldn't be prepared. Try another photo.")
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination), output.length <= 4 * 1024 * 1024 else {
            throw LocalDataError(message: "This photo is too large. Try a smaller photo.")
        }
        jpegData = output as Data
    }
}
