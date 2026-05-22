import SwiftUI

struct WhatsNewView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("lastSeenVersion") private var lastSeenVersion: String = ""
    @AppStorage("hasCalibrated") private var hasCalibrated = false
    @State private var showCalibration = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "sparkles")
                .font(.system(size: 56))
                .foregroundStyle(.tint)

            Text("What's New")
                .font(.system(.largeTitle, design: .rounded, weight: .heavy))

            VStack(alignment: .leading, spacing: 20) {
                featureRow(
                    icon: "eyedropper.halffull",
                    title: "Color Calibration",
                    description: "Point at something white to baseline your camera for more accurate color readings in any lighting."
                )

                featureRow(
                    icon: "gearshape",
                    title: "Quick Settings",
                    description: "Access calibration and diagnostic mode anytime from the new settings button in the top bar."
                )

                featureRow(
                    icon: "waveform",
                    title: "Smoother Readings",
                    description: "Color results now change more gradually when you move the camera, making them easier to read."
                )
            }
            .padding(.horizontal, 32)

            Spacer()

            VStack(spacing: 12) {
                if !hasCalibrated {
                    Button {
                        showCalibration = true
                    } label: {
                        Label("Try Calibration", systemImage: "eyedropper.halffull")
                    }
                    .buttonStyle(BorderedProminentButtonStyle())
                    .controlSize(.large)

                    Button("Continue") {
                        lastSeenVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
                        dismiss()
                    }
                    .buttonStyle(BorderedButtonStyle())
                    .tint(.secondary)
                    .controlSize(.large)
                } else {
                    Button("Continue") {
                        lastSeenVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
                        dismiss()
                    }
                    .buttonStyle(BorderedProminentButtonStyle())
                    .controlSize(.large)
                }
            }
            .padding(.bottom, 32)
        }
        .padding(.top, 48)
        .fullScreenCover(isPresented: $showCalibration) {
            SimpleCalibrationView(hasCalibrated: $hasCalibrated)
        }
    }

    private func featureRow(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview {
    WhatsNewView()
}

private struct SimpleCalibrationView: View {
    @Binding var hasCalibrated: Bool
    @AppStorage("redGain") private var redGain: Double = 1.0
    @AppStorage("greenGain") private var greenGain: Double = 1.0
    @AppStorage("blueGain") private var blueGain: Double = 1.0
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "eyedropper.halffull")
                    .font(.system(size: 56))
                    .foregroundStyle(.tint)

                Text("Calibrate for Accuracy")
                    .font(.title2.bold())

                Text("Point your camera at something pure white — a sheet of paper, a wall, or a white object. This helps the app understand what \"white\" looks like in your current lighting.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 32)

                Spacer()

                VStack(spacing: 12) {
                    Button("Calibrate to White") {
                        hasCalibrated = true
                        dismiss()
                    }
                    .buttonStyle(BorderedProminentButtonStyle())
                    .controlSize(.large)

                    Button("Skip for now") {
                        dismiss()
                    }
                    .buttonStyle(BorderedButtonStyle())
                    .tint(.secondary)
                }
                .padding(.bottom, 32)
            }
            .padding()
            .navigationTitle("Color Calibration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
