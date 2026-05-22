import SwiftUI

struct FirstRunGuideView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("isDiagnosticModeEnabled") private var isDiagnosticModeEnabled = false
    @AppStorage("hasCalibrated") private var hasCalibrated = false
    @AppStorage("hasSeenCalibrationPrompt") private var hasSeenCalibrationPrompt = false
    @AppStorage("redGain") private var redGain: Double = 1.0
    @AppStorage("greenGain") private var greenGain: Double = 1.0
    @AppStorage("blueGain") private var blueGain: Double = 1.0
    @State private var diagnosticTapCount = 0
    @State private var showCalibration = false

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
                .onTapGesture {
                    diagnosticTapCount += 1
                    if diagnosticTapCount >= 3 {
                        diagnosticTapCount = 0
                        isDiagnosticModeEnabled.toggle()
                    }
                }

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

            Toggle("Diagnostic mode", isOn: $isDiagnosticModeEnabled)
                .padding(.horizontal, 32)

            Spacer()

            VStack(spacing: 12) {
                // Show calibration prompt to new users and users updating from older versions
                if !hasSeenCalibrationPrompt || !hasCalibrated {
                    Button {
                        showCalibration = true
                    } label: {
                        Label(hasCalibrated ? "Calibration complete" : "Calibrate colors (recommended)",
                              systemImage: hasCalibrated ? "checkmark.circle.fill" : "eyedropper.halffull")
                    }
                    .buttonStyle(.bordered)
                    .tint(hasCalibrated ? .green : .accentColor)
                    .controlSize(.large)
                }

                Button("Get started") {
                    hasSeenCalibrationPrompt = true
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(.bottom, 24)
        }
        .padding(.top, 48)
        .fullScreenCover(isPresented: $showCalibration) {
            FirstRunCalibrationView(
                redGain: $redGain,
                greenGain: $greenGain,
                blueGain: $blueGain,
                hasCalibrated: $hasCalibrated
            )
        }
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

struct FirstRunCalibrationView: View {
    @Binding var redGain: Double
    @Binding var greenGain: Double
    @Binding var blueGain: Double
    @Binding var hasCalibrated: Bool
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

                // Current gains display
                VStack(spacing: 8) {
                    Text("Current calibration")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 16) {
                        gainText("R", redGain, .red)
                        gainText("G", greenGain, .green)
                        gainText("B", blueGain, .blue)
                    }
                }

                VStack(spacing: 12) {
                    Button("Calibrate to White") {
                        // Will be set from camera readings - placeholder for now
                        hasCalibrated = true
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button("Skip for now") {
                        dismiss()
                    }
                    .buttonStyle(.bordered)
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

    private func gainText(_ label: String, _ value: Double, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption.bold())
                .foregroundStyle(color)
            Text(String(format: "%.2f", value))
                .font(.caption.monospaced())
        }
    }
}
