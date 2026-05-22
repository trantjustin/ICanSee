import SwiftUI
import UIKit
import PhotosUI
import UniformTypeIdentifiers

struct RootView: View {
    @StateObject private var camera = CameraService()
    @AppStorage("hasSeenFirstRunGuide") private var hasSeenFirstRunGuide = false
    @AppStorage("hasSeenCalibrationPrompt") private var hasSeenCalibrationPrompt = false
    @AppStorage("lastSeenVersion") private var lastSeenVersion: String = ""
    @AppStorage("isDiagnosticModeEnabled") private var isDiagnosticModeEnabled = false
    @AppStorage("redGain") private var redGain: Double = 1.0
    @AppStorage("greenGain") private var greenGain: Double = 1.0
    @AppStorage("blueGain") private var blueGain: Double = 1.0
    @State private var showGuide = false
    @State private var showWhatsNew = false
    @State private var showCalibrationSheet = false

    @State private var photoPickerItem: PhotosPickerItem?
    @State private var showFileImporter = false
    @State private var showPhotosPicker = false
    @State private var showLoadOptions = false
    @State private var inspectorImage: InspectorImage?
    /// Zoom factor at the start of the current pinch gesture. The
    /// MagnificationGesture's `scale` is multiplicative against this so
    /// release-and-re-pinch keeps cumulative zoom.
    @State private var liveZoomBase: CGFloat = 1

    var body: some View {
        ZStack {
            backdrop

            switch camera.authState {
            case .authorized:
                liveView
            case .denied:
                fallbackView(reason: .denied)
            case .unavailable:
                fallbackView(reason: .noCamera)
            case .unknown:
                ProgressView().tint(.white)
            }
        }
        .preferredColorScheme(.dark)
        .task {
            camera.redGain = redGain
            camera.greenGain = greenGain
            camera.blueGain = blueGain
            camera.requestAccessAndStart()
            // Show guide for new users, or existing users who haven't seen calibration
            if !hasSeenFirstRunGuide || !hasSeenCalibrationPrompt {
                showGuide = true
            } else if isNewVersion {
                // Show what's new for updating users who've already seen the guide
                showWhatsNew = true
            }
        }
        .onChange(of: camera.authState) { _, state in
            // Keep the screen awake while the camera is live — locking
            // mid-reading is the most common interruption for the kind of
            // tasks this app gets used for (matching paint, picking
            // produce, sorting clothes).
            UIApplication.shared.isIdleTimerDisabled = (state == .authorized)
        }
        .onChange(of: redGain) { _, newValue in camera.redGain = newValue }
        .onChange(of: greenGain) { _, newValue in camera.greenGain = newValue }
        .onChange(of: blueGain) { _, newValue in camera.blueGain = newValue }
        .onDisappear {
            camera.stop()
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .confirmationDialog("Load a photo", isPresented: $showLoadOptions, titleVisibility: .visible) {
            // confirmationDialog handles "set state → present sheet" more
            // reliably than `Menu { Button {...} }`, which on some iOS
            // builds dismisses before the picker has bound to the new
            // state and ends up doing nothing.
            Button("Choose from Photos") { showPhotosPicker = true }
            Button("Choose from Files") { showFileImporter = true }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showGuide, onDismiss: {
            hasSeenFirstRunGuide = true
            hasSeenCalibrationPrompt = true
        }) {
            FirstRunGuideView()
        }
        .fullScreenCover(item: $inspectorImage) { wrapper in
            PhotoInspectorView(image: wrapper.image)
        }
        .sheet(isPresented: $showCalibrationSheet) {
            RootCalibrationView(
                redGain: $redGain,
                greenGain: $greenGain,
                blueGain: $blueGain,
                currentRed: Double(camera.sampledRed),
                currentGreen: Double(camera.sampledGreen),
                currentBlue: Double(camera.sampledBlue)
            )
        }
        .fullScreenCover(isPresented: $showWhatsNew) {
            WhatsNewView()
        }
        .photosPicker(isPresented: $showPhotosPicker, selection: $photoPickerItem, matching: .images)
        .onChange(of: photoPickerItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let ui = UIImage(data: data) {
                    inspectorImage = InspectorImage(image: ui)
                }
                photoPickerItem = nil
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                let didStart = url.startAccessingSecurityScopedResource()
                defer { if didStart { url.stopAccessingSecurityScopedResource() } }
                if let data = try? Data(contentsOf: url), let ui = UIImage(data: data) {
                    inspectorImage = InspectorImage(image: ui)
                }
            }
        }
    }

    // MARK: - Backdrop
    /// A soft gradient so the screen never reads as pure black when the
    /// camera preview is empty (simulator, denied, briefly during startup).
    /// Pure black + a tiny reticle made the original UI feel broken.
    private var backdrop: some View {
        LinearGradient(
            colors: [
                Color(red: 0.10, green: 0.10, blue: 0.14),
                Color(red: 0.04, green: 0.04, blue: 0.06)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    // MARK: - Live camera
    private var liveView: some View {
        ZStack {
            CameraPreviewView(session: camera.session)
                .ignoresSafeArea()
                .gesture(
                    MagnificationGesture()
                        .onChanged { scale in
                            camera.setZoom(liveZoomBase * scale)
                        }
                        .onEnded { _ in
                            liveZoomBase = camera.zoomFactor
                        }
                )

            // Reticle shrinks with zoom so the target stays a target rather
            // than swallowing the thing you're trying to identify. Matches
            // the photo-inspector loupe's behaviour. Floor at 36 pt so it
            // stays visible at the 5× cap.
            Reticle()
                .frame(width: max(36, 84 / camera.zoomFactor),
                       height: max(36, 84 / camera.zoomFactor))
                .allowsHitTesting(false)
                .shadow(color: .black.opacity(0.5), radius: 6)

            VStack(spacing: 0) {
                topBar
                Spacer()
                ColorReadoutView(
                    match: camera.currentMatch,
                    sampledColor: Color(.sRGB,
                                        red: camera.sampledRed,
                                        green: camera.sampledGreen,
                                        blue: camera.sampledBlue,
                                        opacity: 1)
                )
                .padding(.bottom, 28)
            }
        }
    }

    // MARK: - Version check
    private var isNewVersion: Bool {
        let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return lastSeenVersion != current && !lastSeenVersion.isEmpty
    }

    // MARK: - Top bar
    private var topBar: some View {
        HStack(spacing: 10) {
            if camera.zoomFactor > 1.05 {
                Button {
                    liveZoomBase = 1
                    camera.setZoom(1)
                } label: {
                    Text(String(format: "%.1f×", camera.zoomFactor))
                        .font(.system(.footnote, design: .rounded).weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .frame(height: 40)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(Capsule().strokeBorder(.white.opacity(0.15), lineWidth: 1))
                        .environment(\.colorScheme, .dark)
                }
                .transition(.opacity.combined(with: .scale))
                .accessibilityLabel(Text("Reset zoom"))
            }
            Spacer()
            loadMenu
            settingsMenu
            iconButton(systemName: "questionmark") {
                showGuide = true
            }
            .accessibilityLabel(Text("Help"))
        }
        .animation(.easeInOut(duration: 0.2), value: camera.zoomFactor > 1.05)
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }

    private var loadMenu: some View {
        Button {
            showLoadOptions = true
        } label: {
            iconButtonLabel(systemName: "photo.on.rectangle.angled")
        }
        .accessibilityLabel(Text("Load a photo"))
    }

    private var settingsMenu: some View {
        Menu {
            Button {
                showCalibrationSheet = true
            } label: {
                Label("Calibrate Colors", systemImage: "eyedropper.halffull")
            }

            Toggle("Diagnostic Mode", isOn: $isDiagnosticModeEnabled)
        } label: {
            iconButtonLabel(systemName: "gearshape")
        }
        .accessibilityLabel(Text("Settings"))
    }

    private func iconButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            iconButtonLabel(systemName: systemName)
        }
    }

    private func iconButtonLabel(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 40, height: 40)
            .background(.ultraThinMaterial, in: Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.15), lineWidth: 1))
            .environment(\.colorScheme, .dark)
    }

    // MARK: - Fallback (no camera available, or denied)
    private enum FallbackReason { case denied, noCamera }

    @ViewBuilder
    private func fallbackView(reason: FallbackReason) -> some View {
        VStack(spacing: 28) {
            Spacer()

            VStack(spacing: 14) {
                Image(systemName: reason == .denied ? "camera.metering.unknown" : "camera.on.rectangle")
                    .font(.system(size: 52))
                    .foregroundStyle(.white.opacity(0.85))
                Text(reason == .denied ? "Camera access needed" : "No camera available")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                Text(reason == .denied
                     ? String(localized: "I Can See! needs camera access to identify colors. You can also load a photo to inspect.")
                     : String(localized: "This device doesn't have a usable camera, but you can still load a photo to inspect."))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 32)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 12) {
                Button {
                    showPhotosPicker = true
                } label: {
                    Label("Choose from Photos", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    showFileImporter = true
                } label: {
                    Label("Choose from Files", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(.white)

                if reason == .denied {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .font(.footnote)
                    .tint(.white.opacity(0.7))
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 32)

            Spacer()

            Button {
                showGuide = true
            } label: {
                Label("How it works", systemImage: "questionmark.circle")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(.bottom, 24)
        }
    }
}

private struct RootCalibrationView: View {
    @Binding var redGain: Double
    @Binding var greenGain: Double
    @Binding var blueGain: Double
    let currentRed: Double
    let currentGreen: Double
    let currentBlue: Double
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Point at something white or neutral gray, then tap Calibrate to baseline the colors.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                // Current reading swatch
                VStack(spacing: 8) {
                    Text("Current Reading")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.sRGB, red: currentRed, green: currentGreen, blue: currentBlue, opacity: 1))
                        .frame(width: 80, height: 80)
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.2), lineWidth: 1))

                    HStack(spacing: 12) {
                        Text("R: \(Int(currentRed * 255))")
                            .font(.caption.monospaced())
                            .foregroundStyle(.red)
                        Text("G: \(Int(currentGreen * 255))")
                            .font(.caption.monospaced())
                            .foregroundStyle(.green)
                        Text("B: \(Int(currentBlue * 255))")
                            .font(.caption.monospaced())
                            .foregroundStyle(.blue)
                    }
                }

                Divider()

                // Current gains
                VStack(spacing: 12) {
                    Text("Calibration Gains")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 20) {
                        gainLabel("R", value: redGain, color: .red)
                        gainLabel("G", value: greenGain, color: .green)
                        gainLabel("B", value: blueGain, color: .blue)
                    }
                }

                Spacer()

                Button("Calibrate to White") {
                    // Calculate gains so current reading becomes ~0.9 (near white but not clipped)
                    let target: Double = 0.9
                    if currentRed > 0.01 { redGain = target / currentRed }
                    if currentGreen > 0.01 { greenGain = target / currentGreen }
                    if currentBlue > 0.01 { blueGain = target / currentBlue }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("Reset to Default") {
                    redGain = 1.0
                    greenGain = 1.0
                    blueGain = 1.0
                }
                .buttonStyle(.bordered)
                .tint(.secondary)
            }
            .padding()
            .navigationTitle("Color Calibration")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func gainLabel(_ label: String, value: Double, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption.bold())
                .foregroundStyle(color)
            Text(String(format: "%.2f", value))
                .font(.caption.monospaced())
        }
    }
}

/// Crosshair drawn over the camera preview. Two-tone (black halo + white
/// core) so it stays visible against any background.
private struct Reticle: View {
    var body: some View {
        ZStack {
            Circle().strokeBorder(.black.opacity(0.7), lineWidth: 5)
            Circle().strokeBorder(.white, lineWidth: 2.5)
            Rectangle().fill(.white).frame(width: 1.5, height: 22)
            Rectangle().fill(.white).frame(width: 22, height: 1.5)
            Rectangle().fill(.black.opacity(0.6)).frame(width: 0.5, height: 22)
            Rectangle().fill(.black.opacity(0.6)).frame(width: 22, height: 0.5)
        }
    }
}

/// Wraps a `UIImage` so it can drive `.fullScreenCover(item:)` without
/// retroactively conforming `UIImage` itself to `Identifiable` — UIKit may
/// add that conformance in a future SDK and a retroactive one would clash.
private struct InspectorImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

#Preview { RootView() }
