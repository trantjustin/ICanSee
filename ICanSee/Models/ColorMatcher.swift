import Foundation
import simd

/// Maps an sRGB sample to the nearest entry in `NamedColor.palette` using
/// CIEDE2000 distance, plus domain-specific penalties/bonuses.
///
/// Plain Euclidean Lab distance (CIEDE76) has three failure modes that
/// hurt the people this app is for:
///
/// 1. **Lightness dominates hue.** A slightly underexposed bright red
///    sits closer in raw Lab to Maroon than to Red even though a typical
///    speaker would call it "red". Auto-exposure routinely knocks
///    10-20 L* off a saturated surface.
/// 2. **Neutrals win against mildly chromatic samples.** A faded blue
///    under warm lighting can sit closer to Gray than to any blue.
/// 3. **Off-axis darker variants win against canonical names.** Even
///    after L* weighting, a mid-saturation yellow can land closer in a/b
///    to Olive than to Yellow, because Yellow's b* is unusually high.
///    The user's mental model is "yellow", not "olive".
///
/// Fixes:
/// - **CIEDE2000** better aligns with human perception than plain CIE76.
/// - **Linear chroma penalty** keeps neutrals from sneaking in.
/// - **Primary bonus** (`-primaryBonus` distance for entries flagged
///   `isPrimary` in the palette) tips ties toward everyday colour names
///   like Red / Yellow / Blue instead of Maroon / Olive / Navy.
enum ColorMatcher {
    private struct PaletteVector {
        let color: NamedColor
        let lab: SIMD3<Double>
        let chroma: Double
    }

    struct Match {
        let name: String
        /// e.g. "Red + Yellow" — what primaries/neutrals mix to make this.
        let composition: String
        /// Second-closest name when decision boundary is tight.
        let alternateName: String?
        let confidence: Double  // 0...1, 1 = exact, 0 = on a boundary
    }

    /// Distance discount applied to palette entries flagged as everyday
    /// colour names. Tuned for CIEDE2000 scale: enough to favor common
    /// names near boundaries, but not so large that true darker variants
    /// (Maroon/Olive) lose to primary counterparts.
    private static let primaryBonus: Double = 10
    /// Olive is a darker, muted yellow-green. With lightness deliberately
    /// down-weighted for the general matcher, bright yellows can sometimes
    /// drift toward Olive on a/b proximity alone. Apply a targeted penalty
    /// so high-L* yellow tones stay "Yellow".
    private static let oliveBrightPenalty: Double = 12
    private static let oliveBrightLThreshold: Double = 58
    private static let yellowAxisThreshold: Double = 28
    private static let paletteVectors: [PaletteVector] = {
        NamedColor.palette.map { candidate in
            let lab = labFromSRGB(r: candidate.red, g: candidate.green, b: candidate.blue)
            let chroma = sqrt(lab.y * lab.y + lab.z * lab.z)
            return PaletteVector(color: candidate, lab: lab, chroma: chroma)
        }
    }()

    /// `red`, `green`, `blue` are sRGB in 0...1.
    static func match(red: Double, green: Double, blue: Double) -> Match {
        let sampleLab = labFromSRGB(r: red, g: green, b: blue)
        let sampleChroma = sqrt(sampleLab.y * sampleLab.y + sampleLab.z * sampleLab.z)

        var bestIndex = 0
        var secondIndex = 0
        var bestDistance = Double.infinity
        var secondDistance = Double.infinity

        for (i, candidate) in paletteVectors.enumerated() {
            let perceptualDistance = deltaE2000(sampleLab, candidate.lab)
            let bonus = candidate.color.isPrimary ? primaryBonus : 0
            let d = perceptualDistance
                + chromaPenalty(sample: sampleChroma, candidate: candidate.chroma)
                + olivePenalty(sampleLab: sampleLab, candidateName: candidate.color.name)
                - bonus
            if d < bestDistance {
                secondIndex = bestIndex
                secondDistance = bestDistance
                bestDistance = d
                bestIndex = i
            } else if d < secondDistance {
                secondDistance = d
                secondIndex = i
            }
        }

        let best = paletteVectors[bestIndex].color
        let second = paletteVectors[secondIndex].color
        let margin = max(0, secondDistance - bestDistance)
        let confidence = min(1.0, margin / 8.0)
        let alternateName = (secondIndex != bestIndex) ? second.name : nil
        return Match(name: best.name, composition: best.composition, alternateName: alternateName, confidence: confidence)
    }

    /// Penalty added to a candidate when the sample has more chroma than
    /// the candidate does.
    ///
    /// Two regimes:
    /// - **Sample chroma < `neutralThreshold`**: light penalty (×0.5).
    ///   Samples in this band are *near-neutral with a hint of warmth or
    ///   coolness* — a slight-warm-gray speaker, a slightly-blue shadow.
    ///   A heavy penalty here pushes neutrals out and the matcher
    ///   incorrectly snaps to Tan / Pink / Sky Blue. A light touch keeps
    ///   "Gray" available while still preferring chromatic candidates
    ///   when they're genuinely closer.
    /// - **Sample chroma ≥ `neutralThreshold`**: heavy penalty (×2.0).
    ///   The sample is clearly chromatic; neutrals must not win on Lab
    ///   distance alone (e.g. dim Navy or dim Brown landing on Black).
    private static let neutralThreshold: Double = 10

    private static func chromaPenalty(sample: Double, candidate: Double) -> Double {
        let gap = sample - candidate
        guard gap > 0 else { return 0 }
        return sample < neutralThreshold ? gap * 0.5 : gap * 2.0
    }

    private static func olivePenalty(sampleLab: SIMD3<Double>, candidateName: String) -> Double {
        guard candidateName == "Olive" else { return 0 }
        // b* is yellow-blue axis. High positive b* + high L* is a bright
        // yellow-ish sample, not olive.
        if sampleLab.x >= oliveBrightLThreshold && sampleLab.z >= yellowAxisThreshold {
            return oliveBrightPenalty
        }
        return 0
    }

    // MARK: - Lab distance

    /// CIEDE2000 color-difference formula.
    private static func deltaE2000(_ l1: SIMD3<Double>, _ l2: SIMD3<Double>) -> Double {
        let (L1, a1, b1) = (l1.x, l1.y, l1.z)
        let (L2, a2, b2) = (l2.x, l2.y, l2.z)

        let c1 = hypot(a1, b1)
        let c2 = hypot(a2, b2)
        let cBar = (c1 + c2) / 2
        let cBar7 = pow(cBar, 7)
        let g = 0.5 * (1 - sqrt(cBar7 / (cBar7 + pow(25.0, 7))))

        let a1Prime = (1 + g) * a1
        let a2Prime = (1 + g) * a2
        let c1Prime = hypot(a1Prime, b1)
        let c2Prime = hypot(a2Prime, b2)

        let h1Prime = hueAngleDegrees(b: b1, aPrime: a1Prime)
        let h2Prime = hueAngleDegrees(b: b2, aPrime: a2Prime)

        let deltaLPrime = L2 - L1
        let deltaCPrime = c2Prime - c1Prime
        let deltaHPrimeAngle = hueDelta(c1Prime: c1Prime, c2Prime: c2Prime, h1Prime: h1Prime, h2Prime: h2Prime)
        let deltaHPrime = 2 * sqrt(c1Prime * c2Prime) * sin(deg2rad(deltaHPrimeAngle / 2))

        let lBarPrime = (L1 + L2) / 2
        let cBarPrime = (c1Prime + c2Prime) / 2
        let hBarPrime = hueAverage(c1Prime: c1Prime, c2Prime: c2Prime, h1Prime: h1Prime, h2Prime: h2Prime)

        let t = 1
            - 0.17 * cos(deg2rad(hBarPrime - 30))
            + 0.24 * cos(deg2rad(2 * hBarPrime))
            + 0.32 * cos(deg2rad(3 * hBarPrime + 6))
            - 0.20 * cos(deg2rad(4 * hBarPrime - 63))

        let deltaTheta = 30 * exp(-pow((hBarPrime - 275) / 25, 2))
        let cBarPrime7 = pow(cBarPrime, 7)
        let rC = 2 * sqrt(cBarPrime7 / (cBarPrime7 + pow(25.0, 7)))

        let sL = 1 + (0.015 * pow(lBarPrime - 50, 2)) / sqrt(20 + pow(lBarPrime - 50, 2))
        let sC = 1 + 0.045 * cBarPrime
        let sH = 1 + 0.015 * cBarPrime * t
        let rT = -sin(deg2rad(2 * deltaTheta)) * rC

        let dL = deltaLPrime / sL
        let dC = deltaCPrime / sC
        let dH = deltaHPrime / sH
        return sqrt(dL * dL + dC * dC + dH * dH + rT * dC * dH)
    }

    private static func hueAngleDegrees(b: Double, aPrime: Double) -> Double {
        var angle = rad2deg(atan2(b, aPrime))
        if angle < 0 { angle += 360 }
        return angle
    }

    private static func hueDelta(c1Prime: Double, c2Prime: Double, h1Prime: Double, h2Prime: Double) -> Double {
        guard c1Prime * c2Prime != 0 else { return 0 }
        let diff = h2Prime - h1Prime
        if abs(diff) <= 180 { return diff }
        return diff > 180 ? diff - 360 : diff + 360
    }

    private static func hueAverage(c1Prime: Double, c2Prime: Double, h1Prime: Double, h2Prime: Double) -> Double {
        guard c1Prime * c2Prime != 0 else { return h1Prime + h2Prime }
        if abs(h1Prime - h2Prime) <= 180 {
            return (h1Prime + h2Prime) / 2
        }
        let sum = h1Prime + h2Prime
        return sum < 360 ? (sum + 360) / 2 : (sum - 360) / 2
    }

    private static func deg2rad(_ degrees: Double) -> Double {
        degrees * .pi / 180
    }

    private static func rad2deg(_ radians: Double) -> Double {
        radians * 180 / .pi
    }

    // MARK: - sRGB → Lab

    private static func labFromSRGB(r: Double, g: Double, b: Double) -> SIMD3<Double> {
        let lr = linearize(r)
        let lg = linearize(g)
        let lb = linearize(b)

        let x = lr * 0.4124564 + lg * 0.3575761 + lb * 0.1804375
        let y = lr * 0.2126729 + lg * 0.7151522 + lb * 0.0721750
        let z = lr * 0.0193339 + lg * 0.1191920 + lb * 0.9503041

        let fx = labF(x / 0.95047)
        let fy = labF(y / 1.00000)
        let fz = labF(z / 1.08883)

        let L = 116 * fy - 16
        let a = 500 * (fx - fy)
        let bb = 200 * (fy - fz)
        return SIMD3<Double>(L, a, bb)
    }

    private static func linearize(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    private static func labF(_ t: Double) -> Double {
        let epsilon = 216.0 / 24389.0
        let kappa = 24389.0 / 27.0
        return t > epsilon ? pow(t, 1.0 / 3.0) : (kappa * t + 16) / 116
    }
}

// MARK: - Color Harmony

/// Computes color harmony suggestions (complementary, split-complementary)
/// from a detected `NamedColor`, returning results mapped back to the app's
/// existing palette so every suggestion has a familiar name.
///
/// All hue math happens in HSB space derived from the palette entry's sRGB
/// values. Results are snapped to the nearest `NamedColor.palette` entry via
/// `ColorMatcher` so the user always sees names they recognise.
enum ColorHarmony {

    struct Suggestion: Identifiable {
        let id = UUID()
        let namedColor: NamedColor
    }

    /// Returns up to 3 harmony suggestions for the given color:
    /// 1. Complementary (180° opposite)
    /// 2. Split-complementary left (150°)
    /// 3. Split-complementary right (210°)
    ///
    /// Neutrals (Black, White, Grays) return an empty array — there's no
    /// meaningful "complementary" for achromatic colors.
    static func suggestions(for color: NamedColor) -> [Suggestion] {
        let hsb = hsbFromRGB(r: color.red, g: color.green, b: color.blue)

        // Skip neutrals — saturation too low for meaningful harmony
        guard hsb.s > 0.08 else { return [] }

        let complementary = rgbFromHSB(h: rotateHue(hsb.h, by: 180), s: hsb.s, b: hsb.b)
        let splitLeft = rgbFromHSB(h: rotateHue(hsb.h, by: 150), s: hsb.s, b: hsb.b)
        let splitRight = rgbFromHSB(h: rotateHue(hsb.h, by: 210), s: hsb.s, b: hsb.b)

        var results: [Suggestion] = []

        let comp = matchToPalette(r: complementary.r, g: complementary.g, b: complementary.b)
        results.append(Suggestion(namedColor: comp))

        let left = matchToPalette(r: splitLeft.r, g: splitLeft.g, b: splitLeft.b)
        if left.name != comp.name {
            results.append(Suggestion(namedColor: left))
        }

        let right = matchToPalette(r: splitRight.r, g: splitRight.g, b: splitRight.b)
        if right.name != comp.name && right.name != left.name {
            results.append(Suggestion(namedColor: right))
        }

        // Remove duplicates of the source color itself
        return results.filter { $0.namedColor.name != color.name }
    }

    // MARK: - Palette lookup

    private static func matchToPalette(r: Double, g: Double, b: Double) -> NamedColor {
        let match = ColorMatcher.match(red: r, green: g, blue: b)
        return NamedColor.palette.first { $0.name == match.name }
            ?? NamedColor.palette[0]
    }

    // MARK: - HSB ↔ RGB

    private static func hsbFromRGB(r: Double, g: Double, b: Double) -> (h: Double, s: Double, b: Double) {
        let maxC = max(r, max(g, b))
        let minC = min(r, min(g, b))
        let delta = maxC - minC

        let brightness = maxC
        let saturation = maxC > 0 ? delta / maxC : 0

        var hue: Double = 0
        if delta > 0 {
            if maxC == r {
                hue = 60 * ((g - b) / delta).truncatingRemainder(dividingBy: 6)
            } else if maxC == g {
                hue = 60 * ((b - r) / delta + 2)
            } else {
                hue = 60 * ((r - g) / delta + 4)
            }
            if hue < 0 { hue += 360 }
        }

        return (hue, saturation, brightness)
    }

    private static func rgbFromHSB(h: Double, s: Double, b: Double) -> (r: Double, g: Double, b: Double) {
        let c = b * s
        let x = c * (1 - abs((h / 60).truncatingRemainder(dividingBy: 2) - 1))
        let m = b - c

        let (r1, g1, b1): (Double, Double, Double)
        switch h {
        case 0..<60:    (r1, g1, b1) = (c, x, 0)
        case 60..<120:  (r1, g1, b1) = (x, c, 0)
        case 120..<180: (r1, g1, b1) = (0, c, x)
        case 180..<240: (r1, g1, b1) = (0, x, c)
        case 240..<300: (r1, g1, b1) = (x, 0, c)
        default:        (r1, g1, b1) = (c, 0, x)
        }

        return (r1 + m, g1 + m, b1 + m)
    }

    private static func rotateHue(_ hue: Double, by degrees: Double) -> Double {
        var result = (hue + degrees).truncatingRemainder(dividingBy: 360)
        if result < 0 { result += 360 }
        return result
    }
}
