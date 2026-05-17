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
    @Published var isFrozen: Bool = false {
        didSet {
            let new = isFrozen
            frozenFlag.withLock { $0 = new }
            if isFrozen {
                Analytics.signal(Analytics.Event.readingFrozen)
            } else if oldValue {
                Analytics.signal(Analytics.Event.readingResumed)
            }
        }
    }

    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.jtrant.i-can-see.session")
    private let frameQueue = DispatchQueue(label: "com.jtrant.i-can-see.frames")
    private let videoOutput = AVCaptureVideoDataOutput()
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    /// Accessed only on `sessionQueue`.
    private var configured = false
    /// Read by the frame queue; written from main when `isFrozen` toggles.
    private let frozenFlag = OSAllocatedUnfairLock<Bool>(initialState: false)

    /// Pixel side-length of the square sampled at the center of the frame.
    /// 24 px averages out sensor noise without smearing across edges in
    /// typical handheld framing.
    private let sampleSize: CGFloat = 24

    func requestAccessAndStart() {
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
    }

    func stop() {
        sessionQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

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

        if frozenFlag.withLock({ $0 }) { return }

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
        let r = Double(rSum) / Double(pixelCount) / 255.0
        let g = Double(gSum) / Double(pixelCount) / 255.0
        let b = Double(bSum) / Double(pixelCount) / 255.0

        let match = ColorMatcher.match(red: r, green: g, blue: b)

        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isFrozen else { return }
            self.sampledRed = r
            self.sampledGreen = g
            self.sampledBlue = b
            self.currentMatch = match
        }
    }
}
