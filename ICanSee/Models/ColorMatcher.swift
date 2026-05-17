import Foundation
import simd

/// Maps an sRGB sample to the nearest entry in `NamedColor.palette` using
/// CIE Lab distance. Lab is roughly perceptually uniform — Euclidean distance
/// in RGB would call dark navy "black" and pale yellow "white" because RGB
/// distance is dominated by lightness, not hue.
enum ColorMatcher {
    /// Result of a single match.
    struct Match {
        let name: String
        let hex: String
        let confidence: Double  // 0...1, 1 = exact, 0 = far across the palette
    }

    /// `red`, `green`, `blue` are sRGB in 0...1.
    static func match(red: Double, green: Double, blue: Double) -> Match {
        let sampleLab = labFromSRGB(r: red, g: green, b: blue)
        var bestIndex = 0
        var bestDistance = Double.infinity
        var secondDistance = Double.infinity

        for (i, candidate) in NamedColor.palette.enumerated() {
            let candidateLab = labFromSRGB(r: candidate.red, g: candidate.green, b: candidate.blue)
            let d = simd_distance(sampleLab, candidateLab)
            if d < bestDistance {
                secondDistance = bestDistance
                bestDistance = d
                bestIndex = i
            } else if d < secondDistance {
                secondDistance = d
            }
        }

        let best = NamedColor.palette[bestIndex]
        // Confidence = how much closer the winner is than the runner-up.
        // Two near-equidistant matches → low confidence (the sample is on a
        // boundary, e.g. red/orange). Lone winner → high confidence.
        let margin = max(0, secondDistance - bestDistance)
        let confidence = min(1.0, margin / 25.0)
        let hex = String(format: "#%02X%02X%02X",
                         Int((red * 255).rounded()),
                         Int((green * 255).rounded()),
                         Int((blue * 255).rounded()))
        return Match(name: best.name, hex: hex, confidence: confidence)
    }

    // MARK: - sRGB → Lab

    private static func labFromSRGB(r: Double, g: Double, b: Double) -> SIMD3<Double> {
        let lr = linearize(r)
        let lg = linearize(g)
        let lb = linearize(b)

        // sRGB → XYZ (D65), per IEC 61966-2-1.
        let x = lr * 0.4124564 + lg * 0.3575761 + lb * 0.1804375
        let y = lr * 0.2126729 + lg * 0.7151522 + lb * 0.0721750
        let z = lr * 0.0193339 + lg * 0.1191920 + lb * 0.9503041

        // D65 reference white.
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
