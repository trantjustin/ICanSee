import UIKit
import CoreGraphics

/// Samples a small region around a point in a `UIImage` and averages the
/// pixels into an sRGB triple. Used by the photo-dropper.
enum ImageSampler {
    /// `point` is in image-pixel coordinates with origin top-left.
    /// `radius` is half the side of the square sampled around the point.
    static func averageColor(in image: UIImage, at point: CGPoint, radius: Int = 4) -> (r: Double, g: Double, b: Double)? {
        guard let cg = image.cgImage else { return nil }

        // Re-orient if needed: CGImage ignores UIImage.imageOrientation, so a
        // photo from the library can be sideways. Bake the orientation in.
        let oriented = image.imageOrientation == .up ? cg : redraw(cg, orientation: image.imageOrientation, size: image.size)
        guard let source = oriented else { return nil }

        let w = source.width
        let h = source.height
        let cx = Int(point.x.rounded())
        let cy = Int(point.y.rounded())
        let x0 = max(0, cx - radius)
        let y0 = max(0, cy - radius)
        let x1 = min(w, cx + radius)
        let y1 = min(h, cy + radius)
        let sw = x1 - x0
        let sh = y1 - y0
        guard sw > 0, sh > 0 else { return nil }

        var bytes = [UInt8](repeating: 0, count: sw * sh * 4)
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &bytes,
            width: sw,
            height: sh,
            bitsPerComponent: 8,
            bytesPerRow: sw * 4,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // Draw the full image translated so that (x0,y0) of the image lines
        // up with (0,0) of our small bitmap. CG origin is bottom-left, so we
        // flip y to match the top-left convention `point` uses.
        ctx.translateBy(x: CGFloat(-x0), y: CGFloat(-(h - y1)))
        ctx.draw(source, in: CGRect(x: 0, y: 0, width: w, height: h))

        var rSum = 0, gSum = 0, bSum = 0
        let count = sw * sh
        for i in 0..<count {
            rSum += Int(bytes[i * 4 + 0])
            gSum += Int(bytes[i * 4 + 1])
            bSum += Int(bytes[i * 4 + 2])
        }
        // Our bitmap is top-left origin (we flipped y), but rows in the buffer
        // come out bottom-up because CG draws bottom-up. That doesn't change
        // the average — order is irrelevant when summing.
        return (Double(rSum) / Double(count) / 255.0,
                Double(gSum) / Double(count) / 255.0,
                Double(bSum) / Double(count) / 255.0)
    }

    private static func redraw(_ cg: CGImage, orientation: UIImage.Orientation, size: CGSize) -> CGImage? {
        // Force scale=1, otherwise UIGraphicsImageRenderer defaults to the
        // main screen's scale (typically 3×) and the resulting CGImage is
        // 3× larger than `size`. Subsequent sampling code treats the input
        // point as pixel coordinates in a `size`-sized image, so a scaled
        // result puts the sample at ~1/3 the intended (x, y) — far from
        // the dropper's visible center.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let ui = renderer.image { _ in
            UIImage(cgImage: cg, scale: 1, orientation: orientation).draw(in: CGRect(origin: .zero, size: size))
        }
        return ui.cgImage
    }
}
