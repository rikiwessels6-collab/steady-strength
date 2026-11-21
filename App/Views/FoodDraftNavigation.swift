import SwiftUI
import Observation
import SwiftData
import SteadyCore

/// Keeps open meal drafts across tabs and launches using the local diary store.
@MainActor
@Observable
final class FoodDraftNavigation {
    struct Meal: Hashable, Identifiable {
        let slot: MealSlot
        let day: Date
        var id: String { "\(slot.rawValue):\(day.timeIntervalSinceReferenceDate)" }

        init(slot: MealSlot, day: Date = .now) {
            self.init(slot: slot, storedDay: Calendar.current.startOfDay(for: day))
        }

        init(slot: MealSlot, storedDay: Date) {
            self.slot = slot
            self.day = storedDay
        }
    }

    struct Request: Identifiable {
        let id = UUID()
        let meal: Meal
        var scan = false
    }

    var request: Request?
    var storageError = false
    private(set) var latest: Meal?
    private var meals: [Meal: [FoodDiaryDraft]] = [:]
    private var order: [Meal] = []
    @ObservationIgnored private var loaded = false

    func load(in context: ModelContext) {
        guard !loaded else { return }
        do {
            let records = try context.fetch(FetchDescriptor<MealDraftRecord>(
                sortBy: [SortDescriptor(\.updatedAt)]
            ))
            for saved in records {
                guard let slot = MealSlot(rawValue: saved.mealRaw) else { continue }
                let meal = Meal(slot: slot, storedDay: saved.day)
                do {
                    let snapshots = try JSONDecoder().decode([FoodDiaryDraft.Snapshot].self, from: saved.linesData)
                    if meals[meal] == nil { update(snapshots.map(FoodDiaryDraft.init(snapshot:)), for: meal) }
                } catch { storageError = true }
            }
            loaded = true
        } catch { storageError = true }
    }

    func draft(for meal: Meal, in context: ModelContext) -> Binding<[FoodDiaryDraft]> {
        Binding(get: { self.meals[meal] ?? [] }, set: { lines in
            do { try self.persist(lines, for: meal, in: context) }
            catch { self.storageError = true }
            // Keep unsaved edits visible even if the disk is temporarily unavailable.
            self.update(lines, for: meal)
        })
    }

    func close(_ meal: Meal, in context: ModelContext) throws {
        try persist(meals[meal] ?? [], for: meal, in: context)
    }

    func discard(_ meal: Meal, in context: ModelContext) throws {
        try persist([], for: meal, in: context)
        update([], for: meal)
    }

    func commit(_ meal: Meal, in context: ModelContext) throws -> [FoodEntry] {
        guard let lines = meals[meal], !lines.isEmpty else { return [] }
        let entries = try FoodDiary.save(lines, removing: record(for: meal, in: context), in: context)
        update([], for: meal)
        return entries
    }

    private func update(_ lines: [FoodDiaryDraft], for meal: Meal) {
        order.removeAll { $0 == meal }
        if lines.isEmpty {
            meals.removeValue(forKey: meal)
        } else {
            meals[meal] = lines
            order.append(meal)
        }
        latest = order.last
    }

    private func record(for meal: Meal, in context: ModelContext) throws -> MealDraftRecord? {
        let id = meal.id
        var query = FetchDescriptor<MealDraftRecord>(predicate: #Predicate { $0.key == id })
        query.fetchLimit = 1
        return try context.fetch(query).first
    }

    private func persist(_ lines: [FoodDiaryDraft], for meal: Meal, in context: ModelContext) throws {
        let existing = try record(for: meal, in: context)
        if lines.isEmpty {
            guard let existing else { return }
            context.delete(existing)
        } else {
            let data = try JSONEncoder().encode(lines.map(FoodDiaryDraft.Snapshot.init))
            if let existing {
                existing.updatedAt = .now
                existing.linesData = data
            } else {
                context.insert(MealDraftRecord(key: meal.id, day: meal.day, meal: meal.slot, linesData: data))
            }
        }
        try FoodDiary.commit(in: context)
    }
}
