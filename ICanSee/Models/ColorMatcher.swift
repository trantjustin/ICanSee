import Foundation
import simd

/// Maps an sRGB sample to the nearest entry in `NamedColor.palette` using
/// hue-weighted Lab distance, a chroma penalty, and a primary-name bonus.
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
/// - **Lightness weight 0.6** down-weights ΔL*, so hue dominates.
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
        let confidence: Double  // 0...1, 1 = exact, 0 = on a boundary
    }

    /// How much an L* difference contributes to the Euclidean sum, relative
    /// to a/b. 1.0 = standard CIEDE76. Less than 1.0 = hue dominates.
    private static let lightnessWeight: Double = 0.6
    /// Distance discount applied to palette entries flagged as everyday
    /// colour names. 18 was chosen empirically: enough to overcome the
    /// ~5-15 L* gap that auto-exposure tends to introduce, not so much
    /// that genuinely-darker samples (a true Maroon, a real Olive) lose
    /// to their primary cousins.
    private static let primaryBonus: Double = 18
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
        var bestDistance = Double.infinity
        var secondDistance = Double.infinity

        for (i, candidate) in paletteVectors.enumerated() {
            let dL = (sampleLab.x - candidate.lab.x) * lightnessWeight
            let da = sampleLab.y - candidate.lab.y
            let db = sampleLab.z - candidate.lab.z
            let labDistance = sqrt(dL * dL + da * da + db * db)
            let bonus = candidate.color.isPrimary ? primaryBonus : 0
            let d = labDistance + chromaPenalty(sample: sampleChroma, candidate: candidate.chroma) - bonus
            if d < bestDistance {
                secondDistance = bestDistance
                bestDistance = d
                bestIndex = i
            } else if d < secondDistance {
                secondDistance = d
            }
        }

        let best = paletteVectors[bestIndex].color
        let margin = max(0, secondDistance - bestDistance)
        let confidence = min(1.0, margin / 25.0)
        return Match(name: best.name, composition: best.composition, confidence: confidence)
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
