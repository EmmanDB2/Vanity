import AppKit
import CoreImage

struct CapturedShot: Identifiable {
    let id = UUID()
    var angle: String
    let image: NSImage
    let jpeg: Data
}

/// Turns the frame on screen into a photo, with the same mirror/rotation the tile shows.
enum Snapshotter {
    private static let context = CIContext()

    static func capture(_ feed: Feed) -> CapturedShot? {
        guard let buffer = feed.router.currentFrame else { return nil }

        var image = CIImage(cvPixelBuffer: buffer)
        if feed.settings.mirrored {
            image = image.transformed(by: CGAffineTransform(scaleX: -1, y: 1))
        }
        if feed.settings.quarterTurns % 4 != 0 {
            image = image.transformed(by: CGAffineTransform(rotationAngle: -CGFloat(feed.settings.quarterTurns) * .pi / 2))
        }
        let extent = image.extent.integral
        image = image.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))

        guard let cgImage = context.createCGImage(image, from: CGRect(origin: .zero, size: extent.size)),
              let jpeg = NSBitmapImageRep(cgImage: cgImage).representation(using: .jpeg, properties: [.compressionFactor: 0.88])
        else { return nil }

        return CapturedShot(angle: feed.settings.label, image: NSImage(cgImage: cgImage, size: .zero), jpeg: jpeg)
    }
}
