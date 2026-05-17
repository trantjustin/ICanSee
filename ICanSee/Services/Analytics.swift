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
        static let readingFrozen = "Reading.frozen"
        static let readingResumed = "Reading.resumed"
    }
}
