import Foundation

/// What the home and lock screen widgets show. The app writes it to the shared app-group container whenever
/// Today changes; the widget only reads it. It never leaves the phone.
struct WidgetSnapshot: Codable, Equatable {
    var updated: Date
    var nextSession: String?
    var weekLabel: String?
    var sessionMinutes: Int?
    var kcalTarget: Int
    var kcalEaten: Int
    var proteinTarget: Int
    var proteinEaten: Int
    var waterMl: Int
    var waterGoalMl: Int
    var sleepHours: Double?
    var streakWeeks: Int

    static let appGroup = "group.au.com.rwfitness.steadystrength"
    private static let fileName = "widget-snapshot.json"

    private static var url: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?.appendingPathComponent(fileName)
    }

    static func load() -> WidgetSnapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    /// Returns true if the stored snapshot changed.
    @discardableResult
    func save() -> Bool {
        guard let url = Self.url else { return false }
        if var old = Self.load() {
            old.updated = updated
            if old == self { return false }
        }
        guard let data = try? JSONEncoder().encode(self) else { return false }
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return true
    }

    static let sample = WidgetSnapshot(updated: .now, nextSession: "Workout A (Monday)", weekLabel: "Week 1 of 12", sessionMinutes: 24,
                                       kcalTarget: 2000, kcalEaten: 1240, proteinTarget: 140, proteinEaten: 96,
                                       waterMl: 1500, waterGoalMl: 2500, sleepHours: 7.4, streakWeeks: 3)
}
