import SwiftUI

struct FirstRunGuideView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "eye.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(LinearGradient(
                    colors: [
                        Color(red: 0.88, green: 0.22, blue: 0.30), // red
                        Color(red: 0.98, green: 0.55, blue: 0.18), // orange
                        Color(red: 0.95, green: 0.82, blue: 0.22), // yellow
                        Color(red: 0.32, green: 0.72, blue: 0.36), // green
                        Color(red: 0.22, green: 0.45, blue: 0.88), // blue
                        Color(red: 0.55, green: 0.25, blue: 0.78)  // purple
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))

            Text("I Can See!")
                .font(.system(.largeTitle, design: .rounded, weight: .heavy))

            Text("Point your camera at anything. The crosshair in the middle tells you what color it is — useful when red and green, or blue and purple, look the same to you.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)

            VStack(alignment: .leading, spacing: 16) {
                tip(icon: "scope", title: "Aim the crosshair", body: "The center reticle is what gets sampled.")
                tip(icon: "hand.tap", title: "Tap to freeze", body: "Hold a reading in place so you can read it.")
                tip(icon: "sun.max", title: "Use even light", body: "Harsh shadows or screens shift the answer — step into daylight when you can.")
            }
            .padding(.horizontal, 32)
            .padding(.top, 8)

            Spacer()

            Button("Get started") { dismiss() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.bottom, 24)
        }
        .padding(.top, 48)
    }

    private func tip(icon: String, title: LocalizedStringKey, body: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(body)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview { FirstRunGuideView() }
