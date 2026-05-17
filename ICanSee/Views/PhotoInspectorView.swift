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

    /// Zoom is anchored on the dropper, so the pixel under the dropper
    /// stays put while pinching. 1...8 keeps things usable on small phones.
    @State private var zoom: CGFloat = 1
    @State private var pinchBase: CGFloat = 1

    private let minZoom: CGFloat = 1
    private let maxZoom: CGFloat = 8
    private let baseLoupeSize: CGFloat = 64

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
                let displayRect = aspectFitRect(imageSize: image.size, in: proxy.size)
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
                        sample()
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
            }
            .padding(.horizontal, 12)
            .padding(.top, safeTop + 6)

            VStack {
                Spacer()
                ColorReadoutView(match: match, sampledColor: sampledColor, isFrozen: false)
                    .padding(.bottom, safeBottom + 8)
            }
        }
        .ignoresSafeArea()
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
        dropperImagePoint = clamped
        hasPlacedDropper = true
        sample()
    }

    private func sample() {
        // 3×3 average at zoom 1, down to a single pixel at high zoom. The
        // dropper's center dot promises a point sample; a larger radius
        // pulls in surrounding colors (e.g. yellow petal centre reads as
        // the surrounding magenta), which is what the user reported.
        let radius = max(1, Int((2 / zoom).rounded()))
        guard let avg = ImageSampler.averageColor(in: image, at: dropperImagePoint, radius: radius) else { return }
        sampledColor = Color(.sRGB, red: avg.r, green: avg.g, blue: avg.b, opacity: 1)
        match = ColorMatcher.match(red: avg.r, green: avg.g, blue: avg.b)
    }

    // MARK: - Coordinate transforms

    private func aspectFitRect(imageSize: CGSize, in container: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        let w = imageSize.width * scale
        let h = imageSize.height * scale
        return CGRect(x: (container.width - w) / 2,
                      y: (container.height - h) / 2,
                      width: w, height: h)
    }

    /// Where (in unit-point form) the image's scaleEffect should anchor.
    /// We pin the anchor to the dropper's *unzoomed* screen position, so
    /// pinching never drags the inspected pixel out from under the loupe.
    private func dropperUnitPoint(container: CGSize, displayRect: CGRect) -> UnitPoint {
        guard container.width > 0, container.height > 0,
              image.size.width > 0, image.size.height > 0 else { return .center }
        let nx = dropperImagePoint.x / image.size.width
        let ny = dropperImagePoint.y / image.size.height
        let sx = displayRect.minX + nx * displayRect.width
        let sy = displayRect.minY + ny * displayRect.height
        return UnitPoint(x: sx / container.width, y: sy / container.height)
    }

    private func imageToScreen(_ p: CGPoint,
                               displayRect: CGRect,
                               container: CGSize,
                               anchor: UnitPoint,
                               zoom: CGFloat) -> CGPoint {
        guard image.size.width > 0, image.size.height > 0 else { return .zero }
        let nx = p.x / image.size.width
        let ny = p.y / image.size.height
        let unscaledX = displayRect.minX + nx * displayRect.width
        let unscaledY = displayRect.minY + ny * displayRect.height
        let ax = anchor.x * container.width
        let ay = anchor.y * container.height
        return CGPoint(x: (unscaledX - ax) * zoom + ax,
                       y: (unscaledY - ay) * zoom + ay)
    }

    private func screenToImage(_ p: CGPoint,
                               displayRect: CGRect,
                               container: CGSize,
                               anchor: UnitPoint,
                               zoom: CGFloat) -> CGPoint {
        let ax = anchor.x * container.width
        let ay = anchor.y * container.height
        let unscaled = CGPoint(x: (p.x - ax) / zoom + ax,
                               y: (p.y - ay) / zoom + ay)
        guard displayRect.width > 0, displayRect.height > 0 else { return .zero }
        let nx = (unscaled.x - displayRect.minX) / displayRect.width
        let ny = (unscaled.y - displayRect.minY) / displayRect.height
        return CGPoint(x: nx * image.size.width, y: ny * image.size.height)
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
