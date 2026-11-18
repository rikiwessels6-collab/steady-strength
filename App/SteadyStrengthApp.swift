import SwiftUI
import SwiftData
import UserNotifications

@main
struct SteadyStrengthApp: App {
    let container = Persistence.shared

    init() {
        // Set before launch finishes so a tapped notification that opened the app is handled.
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}
