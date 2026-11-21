import Foundation
import SteadyCore
import SwiftData

/// An entry under review. It only becomes part of the diary when the whole meal is saved.
struct FoodDiaryDraft: Identifiable {
    let id = UUID()
    let entry: FoodEntry
    var food: FoodItem?
    var favourite: Bool?
    var recipe: Recipe?
    var savedMeal: SavedMeal?
}

@MainActor
enum FoodDiary {
    static func save(_ draft: [FoodDiaryDraft], in context: ModelContext) throws -> [FoodEntry] {
        var foods: [String: SavedFood] = [:]
        var entries: [FoodEntry] = []
        for line in draft {
            let entry = FoodEntry(copying: line.entry, eatenAt: line.entry.eatenAt, meal: line.entry.meal)
            context.insert(entry)
            entries.append(entry)
            line.recipe?.lastUsed = .now
            line.savedMeal?.lastUsed = .now
            guard let food = line.food else { continue }
            let record: SavedFood
            if let cached = foods[food.id] {
                record = cached
            } else {
                do {
                    if let existing = try savedFood(food.id, in: context) {
                        record = existing
                    } else {
                        record = SavedFood(item: food, isCustom: entry.source == .manual)
                        context.insert(record)
                    }
                } catch {
                    context.rollback()
                    throw error
                }
                foods[id] = record
            }
            record.lastUsed = .now
            record.useCount += 1
            if let favourite = line.favourite { record.isFavourite = favourite }
        }
        try commit(in: context)
        return entries
    }

    static func savedFood(_ id: String, in context: ModelContext) throws -> SavedFood? {
        var request = FetchDescriptor<SavedFood>(predicate: #Predicate { $0.foodId == id })
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    static func lastAmount(for item: FoodItem, in context: ModelContext) throws -> Double? {
        let id = item.id
        let request = FetchDescriptor<FoodEntry>(predicate: #Predicate { $0.foodId == id },
                                                 sortBy: [SortDescriptor(\.loggedAt, order: .reverse)])
        return try context.fetch(request).first {
            $0.grams > 0 && $0.grams <= 100_000 && $0.portionUnit == item.portionUnit
        }?.grams
    }

    static func delete(_ entries: [FoodEntry], in context: ModelContext) throws {
        for entry in entries { context.delete(entry) }
        try commit(in: context)
    }

    static func restore(_ snapshot: FoodEntry, in context: ModelContext) throws {
        let restored = copyForUndo(snapshot)
        context.insert(restored)
        try commit(in: context)
    }

    static func copyForUndo(_ entry: FoodEntry) -> FoodEntry {
        let copy = FoodEntry(copying: entry, eatenAt: entry.eatenAt, meal: entry.meal)
        copy.loggedAt = entry.loggedAt
        return copy
    }

    static func commit(in context: ModelContext) throws {
        do { try context.save() }
        catch {
            context.rollback()
            throw error
        }
    }
}
