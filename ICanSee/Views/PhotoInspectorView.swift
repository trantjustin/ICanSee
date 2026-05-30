import SwiftUI

/// Loads a photo and lets the user drag a dropper to identify a specific
/// pixel's color. Pinch to zoom in on a region; the dropper shrinks with
/// zoom so it doesn't occlude the pixel you're trying to inspect.
///
/// Coordinate model: the canonical dropper position lives in **image-pixel
/// space** (`dropperImagePoint`) so it survives zoom changes without
/// drifting. View coordinates are derived through the same affine each
/// frame, and gestures are converted back via the inverse.
struct PhotoInspectorView: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss

    @State private var dropperImagePoint: CGPoint = .zero
    @State private var hasPlacedDropper = false
    @State private var match: ColorMatcher.Match?
    @State private var sampledColor: Color = .gray

    /// Motion settling for photo inspector (delay color match when dragging)
    private let smoothingAlpha: Double = 0.2
    private let motionThreshold: Double = 0.05
    private let settlingFrames: Int = 6
    @State private var settlingCounter: Int = 0
    @State private var smoothedR: Double = 0
    @State private var smoothedG: Double = 0
    @State private var smoothedB: Double = 0
    @State private var prevSmoothedR: Double = 0
    @State private var prevSmoothedG: Double = 0
    @State private var prevSmoothedB: Double = 0

    /// Zoom is anchored on the dropper, so the pixel under the dropper
    /// stays put while pinching. 1...8 keeps things usable on small phones.
    @State private var zoom: CGFloat = 1
    @State private var pinchBase: CGFloat = 1
    @State private var showCalibrationSheet = false
    @State private var showSettingsSheet = false

    private let minZoom: CGFloat = 1
    private let maxZoom: CGFloat = 8
    private let baseLoupeSize: CGFloat = 64
    @AppStorage("isDiagnosticModeEnabled") private var isDiagnosticModeEnabled = false
    @AppStorage("redGain") private var redGain: Double = 1.0
    @AppStorage("greenGain") private var greenGain: Double = 1.0
    @AppStorage("blueGain") private var blueGain: Double = 1.0

    /// Reads the actual screen safe-area inset from UIKit. Inside a
    /// `fullScreenCover`, SwiftUI's `GeometryReader.safeAreaInsets` and
    /// `.safeAreaInset(...)` both reported zero on this device — going
    /// straight to the key window's `safeAreaInsets` is the only thing
    /// that returns the real status-bar height here.
    private var systemSafeAreaInsets: UIEdgeInsets {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })
        return window?.safeAreaInsets ?? .zero
    }

    var body: some View {
        let insets = systemSafeAreaInsets
        content(safeTop: insets.top, safeBottom: insets.bottom)
            .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func content(safeTop: CGFloat, safeBottom: CGFloat) -> some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            GeometryReader { proxy in
                let displayRect = PhotoInspectorGeometry.aspectFitRect(imageSize: image.size, in: proxy.size)
                let anchor = dropperUnitPoint(container: proxy.size, displayRect: displayRect)
                let dropperScreenPoint = imageToScreen(dropperImagePoint,
                                                       displayRect: displayRect,
                                                       container: proxy.size,
                                                       anchor: anchor,
                                                       zoom: zoom)
                let loupeSize = max(28, baseLoupeSize / zoom)

                ZStack {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .scaleEffect(zoom, anchor: anchor)
                        .animation(.interactiveSpring(response: 0.2, dampingFraction: 0.9), value: zoom)
                        .contentShape(Rectangle())

                    Loupe(color: sampledColor)
                        .frame(width: loupeSize, height: loupeSize)
                        .position(dropperScreenPoint)
                        .allowsHitTesting(false)
                }
                .gesture(
                    SimultaneousGesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                handleDrag(value.location,
                                           container: proxy.size,
                                           displayRect: displayRect,
                                           anchor: anchor)
                            },
                        MagnificationGesture()
                            .onChanged { scale in
                                let next = min(max(pinchBase * scale, minZoom), maxZoom)
                                zoom = next
                            }
                            .onEnded { _ in
                                pinchBase = zoom
                            }
                    )
                )
                .onAppear {
                    if !hasPlacedDropper {
                        dropperImagePoint = CGPoint(x: image.size.width / 2, y: image.size.height / 2)
                        sample(force: true)
                    }
                }
            }

            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().strokeBorder(.white.opacity(0.15), lineWidth: 1))
                        .environment(\.colorScheme, .dark)
                }
                .accessibilityLabel(Text("Close"))
                Spacer()
                if zoom > 1.05 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            zoom = 1
                            pinchBase = 1
                        }
                    } label: {
                        Text(String(format: "%.1f×", zoom))
                            .font(.system(.footnote, design: .rounded).weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .frame(height: 36)
                            .background(.ultraThinMaterial, in: Capsule())
                            .overlay(Capsule().strokeBorder(.white.opacity(0.15), lineWidth: 1))
                            .environment(\.colorScheme, .dark)
                    }
                    .transition(.opacity.combined(with: .scale))
                    .accessibilityLabel(Text("Reset zoom"))
                }

                // Settings button. Uses a sheet rather than a `Menu` to
                // avoid the SwiftUI bug where a Menu child Button's state
                // mutation is dropped before the downstream sheet binds.
                Button {
                    showSettingsSheet = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().strokeBorder(.white.opacity(0.15), lineWidth: 1))
                        .environment(\.colorScheme, .dark)
                }
                .accessibilityLabel(Text("Settings"))
            }
            .padding(.horizontal, 12)
            .padding(.top, safeTop + 6)

            VStack {
                Spacer()
                ColorReadoutView(match: match, sampledColor: sampledColor, mode: .photo)
                    .padding(.bottom, safeBottom + 8)
            }
        }
        .ignoresSafeArea()
        .sheet(isPresented: $showCalibrationSheet) {
            PhotoCalibrationView(
                redGain: $redGain,
                greenGain: $greenGain,
                blueGain: $blueGain,
                currentRed: smoothedR,
                currentGreen: smoothedG,
                currentBlue: smoothedB
            )
        }
        .sheet(isPresented: $showSettingsSheet) {
            PhotoSettingsSheet(
                isDiagnosticModeEnabled: $isDiagnosticModeEnabled,
                onCalibrate: {
                    showSettingsSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        showCalibrationSheet = true
                    }
                }
            )
        }
    }

    // MARK: - Gestures
    private func handleDrag(_ location: CGPoint,
                            container: CGSize,
                            displayRect: CGRect,
                            anchor: UnitPoint) {
        let imagePoint = screenToImage(location,
                                       displayRect: displayRect,
                                       container: container,
                                       anchor: anchor,
                                       zoom: zoom)
        let clamped = CGPoint(
            x: min(max(imagePoint.x, 0), image.size.width),
            y: min(max(imagePoint.y, 0), image.size.height)
        )

        // Detect significant movement to reset smoothing
        let moveDistance = hypot(clamped.x - dropperImagePoint.x, clamped.y - dropperImagePoint.y)
        let wasFirstPlacement = !hasPlacedDropper

        dropperImagePoint = clamped
        hasPlacedDropper = true

        // Reset smoothing on significant move or first placement
        if wasFirstPlacement || moveDistance > 20 {
            smoothedR = 0
            smoothedG = 0
            smoothedB = 0
            settlingCounter = 0
        }

        sample()
    }

    private func sample(force: Bool = false) {
        // 3×3 average at zoom 1, down to a single pixel at high zoom. The
        // dropper's center dot promises a point sample; a larger radius
        // pulls in surrounding colors (e.g. yellow petal centre reads as
        // the surrounding magenta), which is what the user reported.
        let radius = max(1, Int((2 / zoom).rounded()))
        guard let avg = ImageSampler.averageColor(in: image, at: dropperImagePoint, radius: radius) else { return }

        // Initialize smoothed values on first sample or after reset
        let wasReset = smoothedR == 0 && smoothedG == 0 && smoothedB == 0
        if !hasPlacedDropper || wasReset {
            smoothedR = avg.r
            smoothedG = avg.g
            smoothedB = avg.b
        } else {
            // Temporal smoothing
            smoothedR = (smoothingAlpha * avg.r) + ((1.0 - smoothingAlpha) * smoothedR)
            smoothedG = (smoothingAlpha * avg.g) + ((1.0 - smoothingAlpha) * smoothedG)
            smoothedB = (smoothingAlpha * avg.b) + ((1.0 - smoothingAlpha) * smoothedB)
        }

        // Update display color and match immediately. Unlike live camera
        // (which samples every frame and benefits from settling), the photo
        // inspector only samples on user interaction, so each sample reflects
        // the user's intent and should update the readout directly.
        sampledColor = Color(.sRGB, red: smoothedR, green: smoothedG, blue: smoothedB, opacity: 1)
        match = ColorMatcher.match(red: smoothedR, green: smoothedG, blue: smoothedB)
    }

    // MARK: - Coordinate transforms

    /// Where (in unit-point form) the image's scaleEffect should anchor.
    /// We pin the anchor to the dropper's *unzoomed* screen position, so
    /// pinching never drags the inspected pixel out from under the loupe.
    private func dropperUnitPoint(container: CGSize, displayRect: CGRect) -> UnitPoint {
        PhotoInspectorGeometry.dropperUnitPoint(
            dropperImagePoint: dropperImagePoint,
            imageSize: image.size,
            container: container,
            displayRect: displayRect
        )
    }

    private func imageToScreen(_ p: CGPoint,
                               displayRect: CGRect,
                               container: CGSize,
                               anchor: UnitPoint,
                               zoom: CGFloat) -> CGPoint {
        PhotoInspectorGeometry.imageToScreen(
            p,
            imageSize: image.size,
            displayRect: displayRect,
            container: container,
            anchor: anchor,
            zoom: zoom
        )
    }

    private func screenToImage(_ p: CGPoint,
                               displayRect: CGRect,
                               container: CGSize,
                               anchor: UnitPoint,
                               zoom: CGFloat) -> CGPoint {
        PhotoInspectorGeometry.screenToImage(
            p,
            imageSize: image.size,
            displayRect: displayRect,
            container: container,
            anchor: anchor,
            zoom: zoom
        )
    }
}

enum PhotoInspectorGeometry {
    static func aspectFitRect(imageSize: CGSize, in container: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        let w = imageSize.width * scale
        let h = imageSize.height * scale
        return CGRect(x: (container.width - w) / 2,
                      y: (container.height - h) / 2,
                      width: w, height: h)
    }

    static func dropperUnitPoint(
        dropperImagePoint: CGPoint,
        imageSize: CGSize,
        container: CGSize,
        displayRect: CGRect
    ) -> UnitPoint {
        guard container.width > 0, container.height > 0,
              imageSize.width > 0, imageSize.height > 0 else { return .center }
        let nx = dropperImagePoint.x / imageSize.width
        let ny = dropperImagePoint.y / imageSize.height
        let sx = displayRect.minX + nx * displayRect.width
        let sy = displayRect.minY + ny * displayRect.height
        return UnitPoint(x: sx / container.width, y: sy / container.height)
    }

    static func imageToScreen(
        _ point: CGPoint,
        imageSize: CGSize,
        displayRect: CGRect,
        container: CGSize,
        anchor: UnitPoint,
        zoom: CGFloat
    ) -> CGPoint {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let nx = point.x / imageSize.width
        let ny = point.y / imageSize.height
        let unscaledX = displayRect.minX + nx * displayRect.width
        let unscaledY = displayRect.minY + ny * displayRect.height
        let ax = anchor.x * container.width
        let ay = anchor.y * container.height
        return CGPoint(x: (unscaledX - ax) * zoom + ax,
                       y: (unscaledY - ay) * zoom + ay)
    }

    static func screenToImage(
        _ point: CGPoint,
        imageSize: CGSize,
        displayRect: CGRect,
        container: CGSize,
        anchor: UnitPoint,
        zoom: CGFloat
    ) -> CGPoint {
        let ax = anchor.x * container.width
        let ay = anchor.y * container.height
        let unscaled = CGPoint(x: (point.x - ax) / zoom + ax,
                               y: (point.y - ay) / zoom + ay)
        guard displayRect.width > 0, displayRect.height > 0 else { return .zero }
        let nx = (unscaled.x - displayRect.minX) / displayRect.width
        let ny = (unscaled.y - displayRect.minY) / displayRect.height
        return CGPoint(x: nx * imageSize.width, y: ny * imageSize.height)
    }
}

private struct PhotoCalibrationView: View {
    @Binding var redGain: Double
    @Binding var greenGain: Double
    @Binding var blueGain: Double
    let currentRed: Double
    let currentGreen: Double
    let currentBlue: Double
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Text("Photo calibration uses the same gains as live camera. Changes apply to both.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .padding(.top, 8)

                    VStack(spacing: 10) {
                        Text("Current Photo Reading")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(.sRGB, red: currentRed, green: currentGreen, blue: currentBlue, opacity: 1))
                            .frame(width: 140, height: 140)
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.2), lineWidth: 1))

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

                    VStack(spacing: 12) {
                        Text("Calibration Gains")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 24) {
                            gainLabel("R", value: redGain, color: .red)
                            gainLabel("G", value: greenGain, color: .green)
                            gainLabel("B", value: blueGain, color: .blue)
                        }
                    }

                    Button {
                        redGain = 1.0
                        greenGain = 1.0
                        blueGain = 1.0
                    } label: {
                        Text("Reset to Default")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.secondary)
                    .controlSize(.large)
                    .padding(.top, 8)
                }
                .padding()
            }
            .navigationTitle("Color Calibration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
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

/// Lightweight settings sheet for the photo inspector. Replaces the
/// previous `Menu`-based settings to avoid the SwiftUI bug where a
/// Menu's child Button dismisses before its state mutation propagates.
private struct PhotoSettingsSheet: View {
    @Binding var isDiagnosticModeEnabled: Bool
    let onCalibrate: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        onCalibrate()
                    } label: {
                        Label("Calibrate Colors", systemImage: "eyedropper.halffull")
                    }
                }

                Section {
                    Toggle(isOn: $isDiagnosticModeEnabled) {
                        Label("Diagnostic Mode", systemImage: "ladybug")
                    }
                } footer: {
                    Text("Shows the DIAG indicator, RGB values, and the color-correction picker on the readout.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

/// Apple-style loupe: a swatch of the sampled color ringed in white/black
/// so it stays visible against any photo background. Size is driven by
/// the inspector view so it can shrink at higher zoom levels.
private struct Loupe: View {
    let color: Color

    var body: some View {
        ZStack {
            // Semi-transparent fill so you can still see the pixel you're
            // sampling through the loupe — keeps the picker honest.
            Circle().fill(color.opacity(0.45))
            Circle().strokeBorder(.white, lineWidth: 3)
            Circle().strokeBorder(.black.opacity(0.6), lineWidth: 1).padding(3)
            Circle().fill(.white).frame(width: 3, height: 3)
            Circle().fill(.black).frame(width: 1.5, height: 1.5)
        }
        .shadow(color: .black.opacity(0.35), radius: 5, y: 2)
    }
}
