import XCTest
@testable import ICanSee

final class ColorMatcherTests: XCTestCase {
    func testPureRedMatchesRed() {
        let m = ColorMatcher.match(red: 1, green: 0, blue: 0)
        XCTAssertEqual(m.name, "Red")
    }

    func testPureGreenMatchesGreen() {
        let m = ColorMatcher.match(red: 0, green: 1, blue: 0)
        XCTAssertEqual(m.name, "Lime")
    }

    func testPureBlueMatchesBlue() {
        let m = ColorMatcher.match(red: 0, green: 0, blue: 1)
        XCTAssertEqual(m.name, "Blue")
    }

    func testBlackAndWhite() {
        XCTAssertEqual(ColorMatcher.match(red: 0, green: 0, blue: 0).name, "Black")
        XCTAssertEqual(ColorMatcher.match(red: 1, green: 1, blue: 1).name, "White")
    }

    func testCompositionForOrange() {
        let m = ColorMatcher.match(red: 1, green: 0.5, blue: 0)
        XCTAssertEqual(m.name, "Orange")
        XCTAssertEqual(m.composition, "Red + Yellow")
    }

    func testChromaticBlueIsNotCalledGray() {
        // Washed-out blue that previously matched "Gray" because Lab
        // distance favored neutrals. Chroma penalty should keep us blue.
        let m = ColorMatcher.match(red: 0.30, green: 0.40, blue: 0.60)
        XCTAssertFalse(m.name.contains("Gray"))
        XCTAssertFalse(m.name == "Black")
        XCTAssertFalse(m.name == "White")
    }

    func testUnderExposedYellowStaysYellow() {
        // Camera-captured "bright yellow" comes in 10-20 L* low under
        // most indoor lighting. Without the L*-weight + primary bonus
        // this used to slip to Olive.
        let m = ColorMatcher.match(red: 0.70, green: 0.60, blue: 0.10)
        XCTAssertEqual(m.name, "Yellow")
    }

    func testUnderExposedRedStaysRed() {
        // "One level darker" regression — Red was being reported as Maroon
        // for moderate-brightness red samples.
        let m = ColorMatcher.match(red: 0.70, green: 0.10, blue: 0.10)
        XCTAssertEqual(m.name, "Red")
    }

    func testWarmGraySpeakerStaysGray() {
        // Bose speaker in a slightly warm-tinted room. Sample is barely
        // off-neutral; matcher must not snap it to Tan because of a tiny
        // a*/b* offset. (Real-world camera capture: roughly mid-gray with
        // ~5% warmth.)
        let m = ColorMatcher.match(red: 0.55, green: 0.50, blue: 0.45)
        XCTAssertTrue(m.name.contains("Gray"), "Got \(m.name)")
    }

    func testTanFabricIsNotCalledPink() {
        // Khaki / tan jacket. Sample is mid-light warm. Pink's high a*
        // used to win via primary bonus despite a 50°+ hue mismatch.
        let m = ColorMatcher.match(red: 0.55, green: 0.45, blue: 0.38)
        XCTAssertNotEqual(m.name, "Pink")
    }

    func testDimNavyIsNotCalledGray() {
        // Low-light Navy fabric — camera under-exposes a chromatic surface,
        // sample comes out barely-chromatic. Used to land on Black or
        // Dark Gray; chroma penalty + non-primary neutrals keep it blue.
        let m = ColorMatcher.match(red: 0.10, green: 0.10, blue: 0.20)
        XCTAssertFalse(m.name.contains("Gray"))
        XCTAssertNotEqual(m.name, "Black")
    }

    func testDimBrownIsNotCalledGray() {
        let m = ColorMatcher.match(red: 0.30, green: 0.15, blue: 0.05)
        XCTAssertFalse(m.name.contains("Gray"))
        XCTAssertNotEqual(m.name, "Black")
    }

    func testGenuineMaroonIsStillMaroon() {
        // The primary bonus must not be so strong that an actually-dark
        // red gets re-labelled "Red". (0.4, 0.05, 0.05) is well into
        // Maroon territory.
        let m = ColorMatcher.match(red: 0.40, green: 0.05, blue: 0.05)
        XCTAssertEqual(m.name, "Maroon")
    }

    func testRedGreenDisambiguation() {
        // Classic deuteranopia confusion pair — the app must NOT call
        // these the same thing or it has no value to the user.
        let red = ColorMatcher.match(red: 0.80, green: 0.15, blue: 0.15)
        let green = ColorMatcher.match(red: 0.15, green: 0.60, blue: 0.20)
        XCTAssertNotEqual(red.name, green.name)
    }

    func testMatcherBenchmarkProbe() {
        let samples: [(Double, Double, Double)] = [
            (1, 0, 0), (0, 1, 0), (0, 0, 1),
            (0.2, 0.3, 0.8), (0.8, 0.6, 0.1), (0.55, 0.5, 0.45)
        ]

        let started = CFAbsoluteTimeGetCurrent()
        var checksum = 0
        for i in 0..<10_000 {
            let s = samples[i % samples.count]
            let m = ColorMatcher.match(red: s.0, green: s.1, blue: s.2)
            checksum += m.name.count
        }
        let elapsedMs = (CFAbsoluteTimeGetCurrent() - started) * 1000.0

        XCTAssertGreaterThan(checksum, 0)
        XCTAssertGreaterThan(elapsedMs, 0)
    }
}
