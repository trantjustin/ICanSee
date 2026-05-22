import SwiftUI

/// A named sRGB color in the compact palette used for colorblind disambiguation.
///
/// The palette is intentionally small (~30 names): every entry must be a
/// color a non-colorblind speaker would name unprompted. Adding obscure
/// names (papayawhip, gainsboro) makes nearest-neighbor matching *worse*
/// for the people this app is for — they see "ochre" and learn nothing.
///
/// Each entry also carries a `composition` — the primaries/neutrals you'd
/// mix on a colour wheel to get that hue. This is what the app shows in
/// place of the hex code: "Red + Yellow" reads as a useful answer to
/// "what colour is this?" for someone who can't tell on their own.
struct NamedColor: Hashable {
    let name: String
    let red: Double    // 0...1, sRGB
    let green: Double
    let blue: Double
    let composition: String
    /// "Primary" here means *common everyday English colour names* — what
    /// a non-colour-specialist will reach for first. Primaries get a
    /// distance bonus from the matcher so a slightly off-bright red
    /// reads "Red" instead of being snapped to the (technically closer
    /// but less useful) "Maroon", and pale yellow doesn't slip into
    /// "Lavender"/"Violet" when the camera under-exposes it.
    let isPrimary: Bool

    init(name: String, red: Double, green: Double, blue: Double, composition: String, isPrimary: Bool = false) {
        self.name = name
        self.red = red
        self.green = green
        self.blue = blue
        self.composition = composition
        self.isPrimary = isPrimary
    }
}

extension NamedColor {
    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: 1)
    }
}

extension NamedColor {
    /// Compact palette curated for red/green and blue/purple disambiguation —
    /// the two confusion axes that affect ~99% of colorblind users.
    static let palette: [NamedColor] = [
        // Neutrals — deliberately *not* primary. A primary bonus on
        // neutrals lets them outscore mid-chroma colours under low light
        // (e.g. a dim Navy sample comes in slightly chromatic, but Gray
        // ends up closer once the bonus is subtracted). True neutrals
        // win on Lab distance alone — they don't need the bonus.
        .init(name: "Black",        red: 0.00, green: 0.00, blue: 0.00, composition: "Black"),
        .init(name: "Dark Gray",    red: 0.25, green: 0.25, blue: 0.25, composition: "Black + White"),
        .init(name: "Gray",         red: 0.50, green: 0.50, blue: 0.50, composition: "Black + White"),
        .init(name: "Light Gray",   red: 0.75, green: 0.75, blue: 0.75, composition: "White + a little Black"),
        .init(name: "White",        red: 1.00, green: 1.00, blue: 1.00, composition: "White"),

        // Reds / pinks
        .init(name: "Maroon",       red: 0.50, green: 0.00, blue: 0.00, composition: "Red + Black"),
        .init(name: "Red",          red: 0.86, green: 0.08, blue: 0.10, composition: "Red",                         isPrimary: true),
        .init(name: "Crimson",      red: 0.86, green: 0.08, blue: 0.24, composition: "Red + a touch of Purple"),
        .init(name: "Salmon",       red: 0.98, green: 0.50, blue: 0.45, composition: "Red + Orange + White"),
        // Pink intentionally *not* primary: its high a* (red-ward) with a
        // small b* sits next to Tan/Salmon in Lab, and a primary bonus
        // was pulling tan/khaki samples into "Pink" across a 50°+ hue
        // gap. A genuine pink wins on Lab distance alone, no bonus needed.
        .init(name: "Pink",         red: 1.00, green: 0.71, blue: 0.76, composition: "Red + White"),
        .init(name: "Hot Pink",     red: 1.00, green: 0.41, blue: 0.71, composition: "Red + Pink"),

        // Oranges / browns
        .init(name: "Orange",       red: 1.00, green: 0.55, blue: 0.00, composition: "Red + Yellow",                isPrimary: true),
        .init(name: "Peach",        red: 1.00, green: 0.80, blue: 0.65, composition: "Orange + White"),
        // Brown is intentionally *not* primary: with a primary bonus it
        // started winning against Maroon for very dark reds, which is
        // less useful than "Maroon" for the user.
        .init(name: "Brown",        red: 0.55, green: 0.27, blue: 0.07, composition: "Red + Yellow + Black"),
        .init(name: "Tan",          red: 0.82, green: 0.71, blue: 0.55, composition: "Brown + White"),

        // Yellows
        .init(name: "Yellow",       red: 1.00, green: 0.92, blue: 0.00, composition: "Yellow",                      isPrimary: true),
        .init(name: "Gold",         red: 1.00, green: 0.84, blue: 0.00, composition: "Yellow + a little Orange"),
        .init(name: "Olive",        red: 0.50, green: 0.50, blue: 0.00, composition: "Yellow + Green + Black"),

        // Greens
        .init(name: "Lime",         red: 0.50, green: 1.00, blue: 0.00, composition: "Yellow + Green"),
        .init(name: "Green",        red: 0.13, green: 0.70, blue: 0.20, composition: "Yellow + Blue",               isPrimary: true),
        .init(name: "Forest Green", red: 0.13, green: 0.40, blue: 0.13, composition: "Green + Black"),
        .init(name: "Mint",         red: 0.60, green: 1.00, blue: 0.75, composition: "Green + White"),
        .init(name: "Teal",         red: 0.00, green: 0.50, blue: 0.50, composition: "Green + Blue"),

        // Blues
        .init(name: "Cyan",         red: 0.00, green: 0.85, blue: 1.00, composition: "Blue + Green + White"),
        .init(name: "Sky Blue",     red: 0.53, green: 0.81, blue: 0.92, composition: "Blue + White"),
        .init(name: "Blue",         red: 0.10, green: 0.30, blue: 0.90, composition: "Blue",                        isPrimary: true),
        .init(name: "Navy",         red: 0.00, green: 0.00, blue: 0.45, composition: "Blue + Black"),

        // Purples
        .init(name: "Purple",       red: 0.50, green: 0.00, blue: 0.50, composition: "Red + Blue",                  isPrimary: true),
        .init(name: "Violet",       red: 0.55, green: 0.20, blue: 0.85, composition: "Blue + a little Red"),
        .init(name: "Lavender",     red: 0.80, green: 0.75, blue: 0.95, composition: "Purple + White"),
        .init(name: "Magenta",      red: 0.90, green: 0.10, blue: 0.85, composition: "Red + Purple")
    ]
}
