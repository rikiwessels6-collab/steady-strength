import Foundation
import SwiftData
import UserNotifications
import SteadyCore

/// Local reminders only: scheduled on this phone, no server involved.
/// Permission is asked for only when the person turns reminders on.
enum ReminderService {
    static func enable() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        case .notDetermined: return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        default: return false
        }
    }

    /// Replaces all Steady Strength reminders with the given slots (an empty list switches them off).
    static func schedule(_ slots: [ReminderSlot]) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter { $0.hasPrefix(Reminders.idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ours)
        for slot in slots {
            let content = UNMutableNotificationContent()
            content.title = slot.title
            content.body = slot.body
            content.sound = .default
            var parts = DateComponents()
            parts.weekday = slot.weekday; parts.hour = slot.hour; parts.minute = slot.minute
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: true)
            try? await center.add(UNNotificationRequest(identifier: slot.id, content: content, trigger: trigger))
        }
    }
}

/// "Log lunch?" nudges. One-off notifications for the coming week, rebuilt whenever the app opens or food
/// is logged, so a meal already logged today is never nagged about.
enum MealReminderService {
    @MainActor
    static func refresh(_ context: ModelContext) async {
        let center = UNUserNotificationCenter.current()
        let settings = try? context.fetch(FetchDescriptor<AppSettings>()).first
        var times: [MealSlot: Int] = [:]
        for (key, minutes) in settings?.mealReminderMinutes ?? [:] {
            if let meal = MealSlot(rawValue: key) { times[meal] = minutes }
        }
        let (start, end) = Calendar.current.dayRange(.now)
        let today = (try? context.fetch(FetchDescriptor<FoodEntry>(predicate: #Predicate { $0.eatenAt >= start && $0.eatenAt < end }))) ?? []
        let logged = Set(today.map(\.meal))
        let plan = times.isEmpty ? [] : MealReminders.plan(times: times, loggedToday: logged)

        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(MealReminders.idPrefix) })
        // Clear a nudge still sitting on the lock screen once that meal is logged.
        let delivered = await center.deliveredNotifications()
        center.removeDeliveredNotifications(withIdentifiers: delivered.map(\.request.identifier).filter {
            guard let meal = MealReminders.meal(fromId: $0) else { return false }
            return logged.contains(meal)
        })
        guard !plan.isEmpty else { return }
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional || status == .ephemeral else { return }
        for p in plan {
            let content = UNMutableNotificationContent()
            content.title = p.title
            content.body = p.body
            content.sound = .default
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: p.date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: p.id, content: content, trigger: trigger))
        }
    }
}

/// Where a tapped notification should take you. Tapping a meal nudge opens Food with Add for that meal.
@Observable
final class NotificationRouter {
    static let shared = NotificationRouter()
    var openMeal: MealSlot?
}

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let meal = MealReminders.meal(fromId: response.notification.request.identifier)
        DispatchQueue.main.async {
            if let meal { NotificationRouter.shared.openMeal = meal }
            completionHandler()
        }
    }

    /// Meal nudges still show while the app is open; other alerts (like the rest timer) stay quiet as before.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let isMeal = notification.request.identifier.hasPrefix(MealReminders.idPrefix)
        completionHandler(isMeal ? [.banner, .list, .sound] : [])
    }
}
