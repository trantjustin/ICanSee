import SwiftUI

@main
struct ICanSeeApp: App {
    init() {
        Analytics.start()
        Analytics.signal(Analytics.Event.appLaunch)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
