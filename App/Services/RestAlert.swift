import Foundation
import UserNotifications

/// A local notification when a rest timer ends, so the phone can be locked between sets.
/// Only scheduled when the person has switched it on in Settings; nothing leaves the phone.
enum RestAlert {
    /// Deliberately outside the "steady." prefix so rescheduling the weekly reminders never removes it.
    static let id = "rest.end"

    static func schedule(at end: Date) async {
        let seconds = end.timeIntervalSinceNow
        guard seconds >= 1 else { return }
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = "Rest over"
        content.body = "Time for your next set."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        // Adding a request with the same identifier replaces the earlier one.
        try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }
}
