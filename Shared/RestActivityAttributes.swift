import ActivityKit
import Foundation

/// The rest timer shown on the lock screen and in the Dynamic Island. Shared by the app and the widget extension.
struct RestActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// When this rest started and ends; the system counts down between them, even while the app is asleep.
        var start: Date
        var end: Date
        /// What comes after the rest, for example "Next: set 2 of 3".
        var next: String?
    }

    var workoutName: String
}
