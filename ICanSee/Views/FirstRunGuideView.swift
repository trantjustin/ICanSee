import SwiftUI

struct FirstRunGuideView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("hasCalibrated") private var hasCalibrated = false
    @AppStorage("hasSeenCalibrationPrompt") private var hasSeenCalibrationPrompt = false
    @AppStorage("redGain") private var redGain: Double = 1.0
    @AppStorage("greenGain") private var greenGain: Double = 1.0
    @AppStorage("blueGain") private var blueGain: Double = 1.0
    @State private var showCalibration = false

    /// Optional so #Preview without a session still compiles. In-app this is
    /// always supplied by RootView so the calibration sheet can show a live
    /// viewfinder and use the real sampled RGB for white-balance.
    var camera: CameraService? = nil

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
                tip(icon: "hand.tap", title: "Tap to freeze", body: "Tap anywhere on the camera view to lock in the current image. Tap again to resume.")
                tip(icon: "sun.max", title: "Use even light", body: "Harsh shadows or screens shift the answer — step into daylight when you can.")
            }
            .padding(.horizontal, 32)
            .padding(.top, 8)

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
            if let camera {
                FirstRunCalibrationView(
                    redGain: $redGain,
                    greenGain: $greenGain,
                    blueGain: $blueGain,
                    hasCalibrated: $hasCalibrated,
                    camera: camera
                )
            } else {
                // #Preview path only: no live session available.
                Text("Camera unavailable")
                    .foregroundStyle(.secondary)
            }
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
    @ObservedObject var camera: CameraService
    @Environment(\.dismiss) private var dismiss
    @State private var showDoneAlert = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Point your camera at something pure white — a sheet of paper, a wall, or a white object — and keep the crosshair centered on it.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)

                // Live viewfinder
                viewfinder
                    .frame(maxWidth: .infinity)
                    .frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(.white.opacity(0.15), lineWidth: 1)
                    )
                    .padding(.horizontal, 20)

                // Current reading swatch
                VStack(spacing: 8) {
                    Text("Current reading")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(.sRGB,
                                    red: currentRed,
                                    green: currentGreen,
                                    blue: currentBlue,
                                    opacity: 1))
                        .frame(width: 120, height: 120)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(.white.opacity(0.2), lineWidth: 1)
                        )
                    HStack(spacing: 10) {
                        Text("R \(Int(currentRed * 255))").foregroundStyle(.red)
                        Text("G \(Int(currentGreen * 255))").foregroundStyle(.green)
                        Text("B \(Int(currentBlue * 255))").foregroundStyle(.blue)
                    }
                    .font(.caption.monospaced())
                }

                // Current gains display
                VStack(spacing: 6) {
                    Text("Current calibration")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 16) {
                        gainText("R", redGain, .red)
                        gainText("G", greenGain, .green)
                        gainText("B", blueGain, .blue)
                    }
                }

                Spacer(minLength: 0)

                VStack(spacing: 12) {
                    Button("Calibrate to White") {
                        calibrate()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button("Skip for now") {
                        Analytics.signal(Analytics.Event.calibrationSkipped, parameters: ["source": "firstRun"])
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                    .tint(.secondary)
                }
                .padding(.bottom, 24)
            }
            .padding(.top, 4)
            .navigationTitle("Color Calibration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Calibration Complete", isPresented: $showDoneAlert) {
                Button("Done") { dismiss() }
            } message: {
                Text("Your camera is now calibrated to your current lighting. You can recalibrate anytime from Settings.")
            }
        }
    }

    @ViewBuilder
    private var viewfinder: some View {
        ZStack {
            #if targetEnvironment(simulator)
            Color(.sRGB,
                  red: Double(camera.sampledRed),
                  green: Double(camera.sampledGreen),
                  blue: Double(camera.sampledBlue),
                  opacity: 1)
                .overlay(alignment: .top) {
                    Text("SIMULATOR")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.4), in: Capsule())
                        .padding(.top, 8)
                }
            #else
            CameraPreviewView(session: camera.session)
            #endif
            Reticle()
                .frame(width: 64, height: 64)
                .allowsHitTesting(false)
                .shadow(color: .black.opacity(0.5), radius: 6)
        }
    }

    private var currentRed: Double { Double(camera.sampledRed) }
    private var currentGreen: Double { Double(camera.sampledGreen) }
    private var currentBlue: Double { Double(camera.sampledBlue) }

    private func calibrate() {
        // The sampledR/G/B values already have the *previous* gains baked in,
        // so divide back out to recover the raw sensor reading before solving
        // for the new gain that maps it to the near-white target.
        let target: Double = 0.9
        let rawR = currentRed / max(redGain, 0.0001)
        let rawG = currentGreen / max(greenGain, 0.0001)
        let rawB = currentBlue / max(blueGain, 0.0001)
        if rawR > 0.01 { redGain = target / rawR }
        if rawG > 0.01 { greenGain = target / rawG }
        if rawB > 0.01 { blueGain = target / rawB }
        hasCalibrated = true
        Analytics.signal(Analytics.Event.calibrationCompleted, parameters: ["source": "firstRun"])
        showDoneAlert = true
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
