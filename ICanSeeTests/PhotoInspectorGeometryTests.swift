import XCTest
import SwiftUI
@testable import ICanSee

final class PhotoInspectorGeometryTests: XCTestCase {
    func testImageScreenRoundTripPreservesPoint() {
        let imageSize = CGSize(width: 1200, height: 800)
        let container = CGSize(width: 390, height: 844)
        let displayRect = PhotoInspectorGeometry.aspectFitRect(imageSize: imageSize, in: container)
        let original = CGPoint(x: 700, y: 500)
        let anchor = PhotoInspectorGeometry.dropperUnitPoint(
            dropperImagePoint: original,
            imageSize: imageSize,
            container: container,
            displayRect: displayRect
        )

        let screenPoint = PhotoInspectorGeometry.imageToScreen(
            original,
            imageSize: imageSize,
            displayRect: displayRect,
            container: container,
            anchor: anchor,
            zoom: 3.25
        )
        let roundTrip = PhotoInspectorGeometry.screenToImage(
            screenPoint,
            imageSize: imageSize,
            displayRect: displayRect,
            container: container,
            anchor: anchor,
            zoom: 3.25
        )

        XCTAssertEqual(roundTrip.x, original.x, accuracy: 0.001)
        XCTAssertEqual(roundTrip.y, original.y, accuracy: 0.001)
    }
}
