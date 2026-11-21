import SwiftUI
import Observation
import SteadyCore

/// Keeps open meal drafts while switching between the Food and Today tabs.
@Observable
final class FoodDraftNavigation {
    struct Meal: Hashable, Identifiable {
        let slot: MealSlot
        let day: Date
        var id: Self { self }

        init(slot: MealSlot, day: Date = .now) {
            self.slot = slot
            self.day = Calendar.current.startOfDay(for: day)
        }
    }

    struct Request: Identifiable {
        let id = UUID()
        let meal: Meal
        var scan = false
    }

    var request: Request?
    private(set) var latest: Meal?
    private var meals: [Meal: [FoodDiaryDraft]] = [:]
    private var order: [Meal] = []

    func draft(for meal: Meal) -> Binding<[FoodDiaryDraft]> {
        Binding(get: { self.meals[meal] ?? [] }, set: { lines in
            self.order.removeAll { $0 == meal }
            if lines.isEmpty {
                self.meals.removeValue(forKey: meal)
            } else {
                self.meals[meal] = lines
                self.order.append(meal)
            }
            self.latest = self.order.last
        })
    }
}
