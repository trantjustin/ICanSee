import XCTest
import UIKit
@testable import ICanSee

final class ImageSamplerTests: XCTestCase {
    func testAverageColorAtCenterOfSolidImage() {
        let image = makeSolidImage(color: UIColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1), size: CGSize(width: 30, height: 30))
        let point = CGPoint(x: 15, y: 15)

        let sampled = ImageSampler.averageColor(in: image, at: point, radius: 2)
        XCTAssertNotNil(sampled)
        XCTAssertEqual(sampled?.r ?? 0, 0.2, accuracy: 0.03)
        XCTAssertEqual(sampled?.g ?? 0, 0.4, accuracy: 0.03)
        XCTAssertEqual(sampled?.b ?? 0, 0.6, accuracy: 0.03)
    }

    func testAverageColorAtImageEdgeClampsSafely() {
        let image = makeSolidImage(color: UIColor(red: 0.9, green: 0.1, blue: 0.2, alpha: 1), size: CGSize(width: 24, height: 24))
        let point = CGPoint(x: 0, y: 0)

        let sampled = ImageSampler.averageColor(in: image, at: point, radius: 6)
        XCTAssertNotNil(sampled)
        XCTAssertEqual(sampled?.r ?? 0, 0.9, accuracy: 0.03)
        XCTAssertEqual(sampled?.g ?? 0, 0.1, accuracy: 0.03)
        XCTAssertEqual(sampled?.b ?? 0, 0.2, accuracy: 0.03)
    }

    private func makeSolidImage(color: UIColor, size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}
