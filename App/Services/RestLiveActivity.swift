import ActivityKit
import Foundation

/// Starts, updates and ends the lock-screen rest timer. Does nothing if Live Activities are switched off
/// for the app in the iPhone's Settings.
@MainActor
enum RestLiveActivity {
    static func show(workout: String, start: Date, end: Date, next: String?) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled, end > start else { return }
        let state = RestActivityAttributes.ContentState(start: start, end: end, next: next)
        let content = ActivityContent(state: state, staleDate: end)
        if let current = Activity<RestActivityAttributes>.activities.first {
            await current.update(content)
        } else {
            _ = try? Activity.request(attributes: RestActivityAttributes(workoutName: workout), content: content, pushType: nil)
        }
    }

    static func end() async {
        for activity in Activity<RestActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
