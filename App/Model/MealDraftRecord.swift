import Foundation
import SteadyCore
import SwiftData

/// Only draft values are stored here. The food diary contains committed meals.
@Model
final class MealDraftRecord {
    @Attribute(.unique) var key: String
    var day: Date
    var mealRaw: String
    var updatedAt: Date
    var linesData: Data

    init(key: String, day: Date, meal: MealSlot, linesData: Data) {
        self.key = key
        self.day = day
        self.mealRaw = meal.rawValue
        self.updatedAt = .now
        self.linesData = linesData
    }
}
