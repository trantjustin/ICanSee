import Foundation
import OSLog
import TelemetryDeck

/// Thin wrapper around TelemetryDeck so callsites stay vendor-agnostic
/// and we have one place to enforce "no PII" hygiene.
///
/// **Privacy contract:**
/// - Never pass raw pixel values, hex codes, or per-sample readings.
/// - Only counts and enum-like buckets are eligible parameters.
enum Analytics {
    private static var started = false
    private static let log = Logger(subsystem: "com.jtrant.i-can-see", category: "analytics")

    static func start() {
        guard !started else { return }
        guard let appID = Bundle.main.object(forInfoDictionaryKey: "TelemetryDeckAppID") as? String,
              !appID.trimmingCharacters(in: .whitespaces).isEmpty,
              !appID.hasPrefix("REPLACE") else {
            log.notice("TelemetryDeckAppID missing or placeholder; analytics disabled.")
            return
        }
        let config = TelemetryDeck.Config(appID: appID)
        if let namespace = Bundle.main.object(forInfoDictionaryKey: "TelemetryDeckNamespace") as? String,
           !namespace.isEmpty {
            config.defaultSignalPrefix = "\(namespace)."
        }
        TelemetryDeck.initialize(config: config)
        started = true
        log.info("TelemetryDeck initialized.")
    }

    static func signal(_ name: String, parameters: [String: String] = [:]) {
        guard started else { return }
        TelemetryDeck.signal(name, parameters: parameters)
    }

    enum Event {
        static let appLaunch = "App.launch"
        static let cameraAuthorized = "Camera.authorized"
        static let cameraDenied = "Camera.denied"
        static let readingCorrected = "Reading.corrected"
        static let readingCorrectionCleared = "Reading.correctionCleared"
        static let readingFrozen = "Reading.frozen"
        static let readingResumed = "Reading.resumed"
        static let calibrationCompleted = "Calibration.completed"
        static let calibrationReset = "Calibration.reset"
        static let calibrationSkipped = "Calibration.skipped"
        static let complementaryExpanded = "Complementary.expanded"
    }

    /// Source surface for a reading correction. Low-cardinality so it
    /// works as a TelemetryDeck group-by dimension.
    enum ReadingMode: String {
        case live
        case photo
    }

    /// Map a normalized RGB triple to a coarse hue bucket. Returns a small
    /// fixed set of strings so the dashboard can group by it without
    /// leaking raw color data.
    static func hueBucket(red: Double, green: Double, blue: Double) -> String {
        let maxC = max(red, max(green, blue))
        let minC = min(red, min(green, blue))
        let delta = maxC - minC

        if maxC < 0.12 { return "black" }
        if minC > 0.88 { return "white" }
        if delta < 0.08 {
            return maxC < 0.45 ? "darkGray" : "gray"
        }

        var hue: Double = 0
        if maxC == red {
            hue = 60 * ((green - blue) / delta).truncatingRemainder(dividingBy: 6)
        } else if maxC == green {
            hue = 60 * ((blue - red) / delta + 2)
        } else {
            hue = 60 * ((red - green) / delta + 4)
        }
        if hue < 0 { hue += 360 }

        switch hue {
        case 0..<15, 345..<360: return "red"
        case 15..<45: return "orange"
        case 45..<70: return "yellow"
        case 70..<165: return "green"
        case 165..<200: return "teal"
        case 200..<250: return "blue"
        case 250..<290: return "purple"
        case 290..<345: return "pink"
        default: return "unknown"
        }
    }
}
