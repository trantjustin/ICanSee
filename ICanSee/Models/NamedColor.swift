import SwiftUI

/// A named sRGB color in the compact palette used for colorblind disambiguation.
///
/// The palette is intentionally small (~30 names): every entry must be a
/// color a non-colorblind speaker would name unprompted. Adding obscure
/// names (papayawhip, gainsboro) makes nearest-neighbor matching *worse*
/// for the people this app is for — they see "ochre" and learn nothing.
struct NamedColor: Hashable {
    let name: String
    let red: Double    // 0...1, sRGB
    let green: Double
    let blue: Double

    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: 1)
    }

    var hex: String {
        String(format: "#%02X%02X%02X",
               Int((red * 255).rounded()),
               Int((green * 255).rounded()),
               Int((blue * 255).rounded()))
    }
}

extension NamedColor {
    /// Compact palette curated for red/green and blue/purple disambiguation —
    /// the two confusion axes that affect ~99% of colorblind users.
    static let palette: [NamedColor] = [
        // Neutrals
        .init(name: "Black",       red: 0.00, green: 0.00, blue: 0.00),
        .init(name: "Dark Gray",   red: 0.25, green: 0.25, blue: 0.25),
        .init(name: "Gray",        red: 0.50, green: 0.50, blue: 0.50),
        .init(name: "Light Gray",  red: 0.75, green: 0.75, blue: 0.75),
        .init(name: "White",       red: 1.00, green: 1.00, blue: 1.00),

        // Reds / pinks
        .init(name: "Maroon",      red: 0.50, green: 0.00, blue: 0.00),
        .init(name: "Red",         red: 0.86, green: 0.08, blue: 0.10),
        .init(name: "Crimson",     red: 0.86, green: 0.08, blue: 0.24),
        .init(name: "Salmon",      red: 0.98, green: 0.50, blue: 0.45),
        .init(name: "Pink",        red: 1.00, green: 0.71, blue: 0.76),
        .init(name: "Hot Pink",    red: 1.00, green: 0.41, blue: 0.71),

        // Oranges / browns
        .init(name: "Orange",      red: 1.00, green: 0.55, blue: 0.00),
        .init(name: "Peach",       red: 1.00, green: 0.80, blue: 0.65),
        .init(name: "Brown",       red: 0.55, green: 0.27, blue: 0.07),
        .init(name: "Tan",         red: 0.82, green: 0.71, blue: 0.55),

        // Yellows
        .init(name: "Yellow",      red: 1.00, green: 0.92, blue: 0.00),
        .init(name: "Gold",        red: 1.00, green: 0.84, blue: 0.00),
        .init(name: "Olive",       red: 0.50, green: 0.50, blue: 0.00),

        // Greens
        .init(name: "Lime",        red: 0.50, green: 1.00, blue: 0.00),
        .init(name: "Green",       red: 0.13, green: 0.70, blue: 0.20),
        .init(name: "Forest Green",red: 0.13, green: 0.40, blue: 0.13),
        .init(name: "Mint",        red: 0.60, green: 1.00, blue: 0.75),
        .init(name: "Teal",        red: 0.00, green: 0.50, blue: 0.50),

        // Blues
        .init(name: "Cyan",        red: 0.00, green: 0.85, blue: 1.00),
        .init(name: "Sky Blue",    red: 0.53, green: 0.81, blue: 0.92),
        .init(name: "Blue",        red: 0.10, green: 0.30, blue: 0.90),
        .init(name: "Navy",        red: 0.00, green: 0.00, blue: 0.45),

        // Purples
        .init(name: "Purple",      red: 0.50, green: 0.00, blue: 0.50),
        .init(name: "Violet",      red: 0.55, green: 0.20, blue: 0.85),
        .init(name: "Lavender",    red: 0.80, green: 0.75, blue: 0.95),
        .init(name: "Magenta",     red: 0.90, green: 0.10, blue: 0.85)
    ]
}
