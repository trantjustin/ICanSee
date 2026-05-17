import Foundation
import simd

/// Maps an sRGB sample to the nearest entry in `NamedColor.palette` using
/// CIE Lab distance with a chroma penalty.
///
/// Plain Euclidean Lab distance (CIEDE76) gets the broad strokes right
/// but has one failure mode that bites users: a mildly chromatic sample
/// (say, a faded blue under warm lighting) can sit closer to neutral
/// "Gray" than to any chromatic candidate, so the answer becomes "Gray"
/// even though the user is clearly pointing at something blue. We add a
/// **chroma penalty**: if the sample has appreciable chroma, candidates
/// whose own chroma is much lower take a distance penalty proportional
/// to the gap. Pure grays get pushed out of the running for chromatic
/// samples without affecting genuinely grey samples.
enum ColorMatcher {
    struct Match {
        let name: String
        /// e.g. "Red + Yellow" — what primaries/neutrals mix to make this.
        let composition: String
        let confidence: Double  // 0...1, 1 = exact, 0 = on a boundary
    }

    /// `red`, `green`, `blue` are sRGB in 0...1.
    static func match(red: Double, green: Double, blue: Double) -> Match {
        let sampleLab = labFromSRGB(r: red, g: green, b: blue)
        let sampleChroma = sqrt(sampleLab.y * sampleLab.y + sampleLab.z * sampleLab.z)

        var bestIndex = 0
        var bestDistance = Double.infinity
        var secondDistance = Double.infinity

        for (i, candidate) in NamedColor.palette.enumerated() {
            let candidateLab = labFromSRGB(r: candidate.red, g: candidate.green, b: candidate.blue)
            let candidateChroma = sqrt(candidateLab.y * candidateLab.y + candidateLab.z * candidateLab.z)
            let d = simd_distance(sampleLab, candidateLab) + chromaPenalty(sample: sampleChroma, candidate: candidateChroma)
            if d < bestDistance {
                secondDistance = bestDistance
                bestDistance = d
                bestIndex = i
            } else if d < secondDistance {
                secondDistance = d
            }
        }

        let best = NamedColor.palette[bestIndex]
        let margin = max(0, secondDistance - bestDistance)
        let confidence = min(1.0, margin / 25.0)
        return Match(name: best.name, composition: best.composition, confidence: confidence)
    }

    /// Penalty added to a candidate when the sample has more chroma than
    /// the candidate does — i.e. a chromatic sample paired with a gray
    /// candidate. The 0.6 coefficient was chosen so a sample chroma of
    /// ~10 (a fairly washed-out blue) makes Gray (chroma 0) lose by a
    /// margin comparable to the chromatic-blue alternatives, without
    /// being so harsh that a true near-gray gets misnamed.
    private static func chromaPenalty(sample: Double, candidate: Double) -> Double {
        let gap = sample - candidate
        guard gap > 0 else { return 0 }
        return gap * 0.6
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
