@preconcurrency import AVFoundation
import CoreImage
import Combine
import UIKit
import os

/// Runs the back camera, samples a small region around the center of each
/// frame, averages it, and publishes a color match. One foreground user,
/// no background mode, no recording.
///
/// Threading: AVCaptureSession is configured and toggled on `sessionQueue`,
/// frames arrive on a dedicated frame queue, and only `@Published` writes
/// hop back to the main actor. The class is *not* `@MainActor` because the
/// capture pipeline genuinely lives on background queues; making the class
/// main-isolated would force every interaction into Sendable closures and
/// produce the warnings Xcode just flagged.
final class CameraService: NSObject, ObservableObject {
    enum AuthState { case unknown, authorized, denied, unavailable }

    @Published private(set) var authState: AuthState = .unknown
    @Published private(set) var currentMatch: ColorMatcher.Match?
    @Published private(set) var sampledRed: Double = 0
    @Published private(set) var sampledGreen: Double = 0
    @Published private(set) var sampledBlue: Double = 0
    @Published private(set) var zoomFactor: CGFloat = 1

    /// When true, sampling is paused and `frozenSnapshot` holds the last
    /// captured frame so the UI can render a static image in place of the
    /// live preview. Toggled via `toggleFreeze()`.
    @Published private(set) var isFrozen: Bool = false
    /// A UIImage rendered from the frame that was live when freeze was
    /// requested. Nil while not frozen.
    @Published private(set) var frozenSnapshot: UIImage?

    /// Calibration gains to correct for lighting/sensor differences.
    /// Applied to raw sensor values before color matching. Defaults to 1.0 (no change).
    @Published var redGain: Double = 1.0
    @Published var greenGain: Double = 1.0
    @Published var blueGain: Double = 1.0
    /// Upper bound for pinch zoom, set once the device is configured.
    /// Cap at 5× — beyond that the wide-angle's digital crop visibly
    /// destroys the color we're trying to sample.
    @Published private(set) var maxZoomFactor: CGFloat = 5

    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.jtrant.i-can-see.session")
    private let frameQueue = DispatchQueue(label: "com.jtrant.i-can-see.frames")
    private let videoOutput = AVCaptureVideoDataOutput()
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    /// Accessed only on `sessionQueue`.
    private var configured = false
    /// Held on `sessionQueue` so zoom changes can `lockForConfiguration`
    /// the same device that's already wired into the session.
    private var device: AVCaptureDevice?

    /// Shared freeze state. Read by the frame queue every frame; written
    /// from main when the user toggles freeze. An unfair lock is the right
    /// primitive here — contention is essentially zero (one taps, frames
    /// arrive at 30Hz) and the critical section is two boolean reads.
    private struct FreezeState {
        var frozen: Bool = false
        /// Set true when the user requests freeze. The next captured frame
        /// will be rendered into `frozenSnapshot`, then `frozen` flips true
        /// and this clears.
        var pendingCapture: Bool = false
    }
    private let freezeLock = OSAllocatedUnfairLock(initialState: FreezeState())
    /// Result of consulting the freeze state on a frame queue tick.
    private enum FreezeAction { case live, skip, capture }

    /// Pixel side-length of the square sampled at the center of the frame.
    /// 24 px averages out sensor noise without smearing across edges in
    /// typical handheld framing.
    private let sampleSize: CGFloat = 24

    /// Smoothing factor for color transitions (0...1). Higher = more smoothing.
    private let smoothingAlpha: Double = 0.15
    /// Smoothed RGB values for temporal stability.
    private var smoothedR: Double = 0
    private var smoothedG: Double = 0
    private var smoothedB: Double = 0

    /// Motion settling: only update color match after frames are stable.
    /// Threshold for detecting significant motion (in 0-1 RGB space).
    private let motionThreshold: Double = 0.05
    /// Frames required to settle before updating match.
    private let settlingFrames: Int = 8
    /// Current settling counter (0 when motion detected, increments when stable).
    private var settlingCounter: Int = 0
    /// Previous smoothed values to detect motion.
    private var prevSmoothedR: Double = 0
    private var prevSmoothedG: Double = 0
    private var prevSmoothedB: Double = 0
    /// Stabilized color match (only updates when settled).
    private var settledMatch: ColorMatcher.Match?

    func requestAccessAndStart() {
        #if targetEnvironment(simulator)
        // The simulator has no camera. Drive a synthetic RGB feed instead so
        // the live view, smoothing, calibration, and analytics pipeline are
        // all exercisable end-to-end without a device.
        publish { $0.authState = .authorized }
        Analytics.signal(Analytics.Event.cameraAuthorized)
        startSimulatorFeed()
        return
        #else
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            publish { $0.authState = .authorized }
            Analytics.signal(Analytics.Event.cameraAuthorized)
            configureAndStart()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else { return }
                self.publish { $0.authState = granted ? .authorized : .denied }
                Analytics.signal(granted ? Analytics.Event.cameraAuthorized : Analytics.Event.cameraDenied)
                if granted { self.configureAndStart() }
            }
        default:
            publish { $0.authState = .denied }
            Analytics.signal(Analytics.Event.cameraDenied)
        }
        #endif
    }

    func stop() {
        #if targetEnvironment(simulator)
        stopSimulatorFeed()
        #else
        sessionQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
        #endif
    }

    #if targetEnvironment(simulator)
    /// Hue cycle phase, in degrees [0, 360). Advances once per timer tick.
    private var simulatorHue: Double = 0
    private var simulatorTimer: Timer?

    /// Starts the synthetic RGB feed. Sweeps the hue circle slowly so the
    /// readout, smoothing, motion-settling, and matcher all see realistic
    /// transitions. Pauses every full revolution at the cardinal hues so
    /// motion-settling actually fires and the match label settles.
    private func startSimulatorFeed() {
        publish { $0.maxZoomFactor = 5 }
        stopSimulatorFeed()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // 30 Hz update keeps it visually smooth without overwhelming
            // the smoothing filter.
            let timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
                self?.tickSimulatorFeed()
            }
            self.simulatorTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func stopSimulatorFeed() {
        DispatchQueue.main.async { [weak self] in
            self?.simulatorTimer?.invalidate()
            self?.simulatorTimer = nil
        }
    }

    private func tickSimulatorFeed() {
        // Honour freeze state — stop updating when frozen, just like
        // the real camera's frame queue returns early on .skip/.capture.
        let frozen = freezeLock.withLock { $0.frozen }
        if frozen { return }

        // Pause at each 45° "named" hue for ~30 frames (1s) so the
        // settling logic can lock in a match before sweeping on. This
        // gives you a believable demo loop in the simulator.
        let stationaryMask = sin(simulatorHue * .pi / 90.0) > 0.97
        if !stationaryMask {
            simulatorHue = (simulatorHue + 0.6).truncatingRemainder(dividingBy: 360)
        }

        let (r, g, b) = Self.rgbFromHue(simulatorHue, saturation: 0.85, brightness: 0.9)

        // Reuse the same calibration + smoothing path as the real camera.
        let calibratedR = min(1.0, max(0.0, r * redGain))
        let calibratedG = min(1.0, max(0.0, g * greenGain))
        let calibratedB = min(1.0, max(0.0, b * blueGain))

        smoothedR = (smoothingAlpha * calibratedR) + ((1.0 - smoothingAlpha) * smoothedR)
        smoothedG = (smoothingAlpha * calibratedG) + ((1.0 - smoothingAlpha) * smoothedG)
        smoothedB = (smoothingAlpha * calibratedB) + ((1.0 - smoothingAlpha) * smoothedB)

        let deltaR = abs(smoothedR - prevSmoothedR)
        let deltaG = abs(smoothedG - prevSmoothedG)
        let deltaB = abs(smoothedB - prevSmoothedB)
        let maxDelta = max(deltaR, max(deltaG, deltaB))

        if maxDelta > motionThreshold {
            settlingCounter = 0
        } else {
            settlingCounter = min(settlingCounter + 1, settlingFrames)
        }
        if settlingCounter >= settlingFrames {
            settledMatch = ColorMatcher.match(red: smoothedR, green: smoothedG, blue: smoothedB)
        }

        prevSmoothedR = smoothedR
        prevSmoothedG = smoothedG
        prevSmoothedB = smoothedB

        // Already on main queue (Timer fires there); set directly.
        sampledRed = smoothedR
        sampledGreen = smoothedG
        sampledBlue = smoothedB
        currentMatch = settledMatch
    }

    /// HSB → RGB conversion. Local helper to avoid pulling in UIColor for
    /// what amounts to three lines of arithmetic.
    private static func rgbFromHue(_ hue: Double, saturation s: Double, brightness v: Double) -> (Double, Double, Double) {
        let h = hue / 60.0
        let c = v * s
        let x = c * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1))
        let m = v - c
        let (r1, g1, b1): (Double, Double, Double)
        switch h {
        case 0..<1: (r1, g1, b1) = (c, x, 0)
        case 1..<2: (r1, g1, b1) = (x, c, 0)
        case 2..<3: (r1, g1, b1) = (0, c, x)
        case 3..<4: (r1, g1, b1) = (0, x, c)
        case 4..<5: (r1, g1, b1) = (x, 0, c)
        default:    (r1, g1, b1) = (c, 0, x)
        }
        return (r1 + m, g1 + m, b1 + m)
    }
    #endif

    /// Apply a pinch-gesture-driven zoom. Clamped to `[1, maxZoomFactor]`
    /// on the session queue (the only thread that may lock the device
    /// for configuration).
    func setZoom(_ factor: CGFloat) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.device else { return }
            let cap = min(CGFloat(5), device.activeFormat.videoMaxZoomFactor)
            let clamped = min(max(factor, 1.0), cap)
            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = clamped
                device.unlockForConfiguration()
                self.publish { $0.zoomFactor = clamped }
            } catch {
                // Lock failure is non-fatal — the zoom just won't update.
            }
        }
    }

    /// Toggle between a live preview and a static snapshot of whatever
    /// was on-screen at the moment of the tap. Freezing also pauses
    /// sampling so the readout stays locked on the frozen color.
    ///
    /// Freezing is a two-phase operation: we set `pendingCapture` here,
    /// then the next frame on the frame queue renders itself into a
    /// `UIImage` and flips `frozen`. That avoids allocating a UIImage
    /// per frame just so we have a snapshot ready in the rare case the
    /// user wants one.
    func toggleFreeze() {
        let wasFrozen = freezeLock.withLock { state -> Bool in
            let was = state.frozen
            if was {
                state.frozen = false
                state.pendingCapture = false
            } else {
                state.pendingCapture = true
            }
            return was
        }
        if wasFrozen {
            // Resume live preview immediately; the frame queue will
            // start updating sampledRGB again on its next frame.
            publish {
                $0.isFrozen = false
                $0.frozenSnapshot = nil
            }
            Analytics.signal(Analytics.Event.readingResumed)

            #if targetEnvironment(simulator)
            // No frame queue in the simulator — just clear state.
            #endif
        } else {
            Analytics.signal(Analytics.Event.readingFrozen)

            #if targetEnvironment(simulator)
            // Synthesize a snapshot from the current sampled color so
            // the simulator preview can show "FROZEN" over a solid swatch
            // matching what the readout was reading.
            let r = sampledRed
            let g = sampledGreen
            let b = sampledBlue
            let image = Self.solidColorImage(red: r, green: g, blue: b)
            freezeLock.withLock { state in
                state.frozen = true
                state.pendingCapture = false
            }
            publish {
                $0.frozenSnapshot = image
                $0.isFrozen = true
            }
            #endif
        }
    }

    #if targetEnvironment(simulator)
    /// 64×64 solid color image used as a stand-in snapshot in the
    /// simulator (where there's no real camera frame to capture).
    private static func solidColorImage(red: Double, green: Double, blue: Double) -> UIImage {
        let size = CGSize(width: 64, height: 64)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            UIColor(red: CGFloat(red), green: CGFloat(green), blue: CGFloat(blue), alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }
    #endif

    /// All `@Published` writes go through here so they're never made
    /// during a SwiftUI render pass. `DispatchQueue.main.async` is *not*
    /// enough — its block can still land in the middle of an in-flight
    /// view update on the same runloop tick. A `Task { @MainActor }` hop
    /// is scheduled by Swift concurrency, not the runloop, and reliably
    /// resumes after the current update completes.
    private func publish(_ update: @escaping @Sendable (CameraService) -> Void) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            update(self)
        }
    }

    private func configureAndStart() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !self.configured {
                let ok = self.configureSession()
                self.configured = true
                if !ok {
                    // No usable camera (simulator, iPad without rear cam).
                    // Photo-inspector mode still works, so surface this
                    // distinctly from "user denied permission".
                    self.publish { $0.authState = .unavailable }
                    return
                }
            }
            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }

    /// Returns true if at least one usable input was wired up.
    private func configureSession() -> Bool {
        session.beginConfiguration()
        session.sessionPreset = .high

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            return false
        }
        session.addInput(input)
        self.device = device
        let cap = min(CGFloat(5), device.activeFormat.videoMaxZoomFactor)
        publish { $0.maxZoomFactor = cap }

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoOutput.setSampleBufferDelegate(self, queue: frameQueue)
        if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }

        if let conn = videoOutput.connection(with: .video) {
            // `videoOrientation` was deprecated in iOS 17 in favour of
            // `videoRotationAngle` (in degrees clockwise from the natural
            // sensor orientation). 90° == portrait for back cameras.
            if conn.isVideoRotationAngleSupported(90) {
                conn.videoRotationAngle = 90
            }
        }

        // Try to lock to continuous auto-focus / exposure for stable readings.
        if let _ = try? device.lockForConfiguration() {
            if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
            if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                device.whiteBalanceMode = .continuousAutoWhiteBalance
            }
            device.unlockForConfiguration()
        }

        session.commitConfiguration()
        return true
    }
}

extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // Honour freeze state. Capture this frame as the static snapshot
        // if a freeze was requested, then early-return for all subsequent
        // frames until the user resumes.
        let freezeAction: FreezeAction = freezeLock.withLock { state in
            if state.pendingCapture {
                state.pendingCapture = false
                state.frozen = true
                return .capture
            } else if state.frozen {
                return .skip
            } else {
                return .live
            }
        }
        switch freezeAction {
        case .capture:
            let ci = CIImage(cvPixelBuffer: pixelBuffer)
            if let cg = ciContext.createCGImage(ci, from: ci.extent) {
                let ui = UIImage(cgImage: cg)
                publish {
                    $0.frozenSnapshot = ui
                    $0.isFrozen = true
                }
            } else {
                // Couldn't render — roll back so the user isn't stuck in
                // a frozen state with no image to show.
                freezeLock.withLock { state in
                    state.frozen = false
                }
            }
            return
        case .skip:
            return
        case .live:
            break
        }

        let w = CVPixelBufferGetWidth(pixelBuffer)
        let h = CVPixelBufferGetHeight(pixelBuffer)
        let side = Int(sampleSize)
        let x = max(0, (w - side) / 2)
        let y = max(0, (h - side) / 2)
        let rect = CGRect(x: x, y: y, width: side, height: side)

        let ci = CIImage(cvPixelBuffer: pixelBuffer).cropped(to: rect)

        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        let cs = CGColorSpaceCreateDeviceRGB()
        bytes.withUnsafeMutableBytes { ptr in
            guard let base = ptr.baseAddress else { return }
            ciContext.render(ci,
                             toBitmap: base,
                             rowBytes: side * 4,
                             bounds: CGRect(x: x, y: y, width: side, height: side),
                             format: .RGBA8,
                             colorSpace: cs)
        }

        var rSum = 0, gSum = 0, bSum = 0
        let pixelCount = side * side
        for i in 0..<pixelCount {
            rSum += Int(bytes[i * 4 + 0])
            gSum += Int(bytes[i * 4 + 1])
            bSum += Int(bytes[i * 4 + 2])
        }
        let rawR = Double(rSum) / Double(pixelCount) / 255.0
        let rawG = Double(gSum) / Double(pixelCount) / 255.0
        let rawB = Double(bSum) / Double(pixelCount) / 255.0

        // Apply calibration gains
        let calibratedR = min(1.0, max(0.0, rawR * redGain))
        let calibratedG = min(1.0, max(0.0, rawG * greenGain))
        let calibratedB = min(1.0, max(0.0, rawB * blueGain))

        // Temporal smoothing to slow down rapid color changes
        smoothedR = (smoothingAlpha * calibratedR) + ((1.0 - smoothingAlpha) * smoothedR)
        smoothedG = (smoothingAlpha * calibratedG) + ((1.0 - smoothingAlpha) * smoothedG)
        smoothedB = (smoothingAlpha * calibratedB) + ((1.0 - smoothingAlpha) * smoothedB)

        // Detect motion by comparing to previous frame
        let deltaR = abs(smoothedR - prevSmoothedR)
        let deltaG = abs(smoothedG - prevSmoothedG)
        let deltaB = abs(smoothedB - prevSmoothedB)
        let maxDelta = max(deltaR, max(deltaG, deltaB))

        if maxDelta > motionThreshold {
            // Motion detected — reset settling counter
            settlingCounter = 0
        } else {
            // Stable — increment counter up to settling threshold
            settlingCounter = min(settlingCounter + 1, settlingFrames)
        }

        // Update settled match only when camera has been stable long enough
        if settlingCounter >= settlingFrames {
            settledMatch = ColorMatcher.match(red: smoothedR, green: smoothedG, blue: smoothedB)
        }

        // Store previous values for next frame
        prevSmoothedR = smoothedR
        prevSmoothedG = smoothedG
        prevSmoothedB = smoothedB

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.sampledRed = smoothedR
            self.sampledGreen = smoothedG
            self.sampledBlue = smoothedB
            self.currentMatch = self.settledMatch
        }
    }
}
