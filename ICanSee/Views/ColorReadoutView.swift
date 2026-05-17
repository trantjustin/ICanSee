import SwiftUI

/// Bottom card that names the sampled color. Large, high-contrast text —
/// this is the whole point of the app for the user.
struct ColorReadoutView: View {
    let match: ColorMatcher.Match?
    let sampledColor: Color
    let isFrozen: Bool

    var body: some View {
        HStack(spacing: 14) {
            swatch

            VStack(alignment: .leading, spacing: 4) {
                Text(match?.name ?? String(localized: "Point at a color"))
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)

                HStack(spacing: 8) {
                    if let match {
                        Text(match.composition)
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                    } else {
                        Text("Aim the crosshair at something")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    if isFrozen {
                        Text("FROZEN")
                            .font(.caption2.bold())
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(.white.opacity(0.22), in: Capsule())
                            .foregroundStyle(.white)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var swatch: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(match == nil ? AnyShapeStyle(.white.opacity(0.08)) : AnyShapeStyle(sampledColor))
            .frame(width: 44, height: 44)
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.white.opacity(match == nil ? 0.25 : 0.4), lineWidth: 1)
            }
            .overlay {
                if match == nil {
                    Image(systemName: "scope")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
    }
}
