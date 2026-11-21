import Foundation
import SteadyCore
import SwiftData

/// An entry under review. It only becomes part of the diary when the whole meal is saved.
struct FoodDiaryDraft: Identifiable {
    let id: UUID
    let entry: FoodEntry
    var food: FoodItem?
    var favourite: Bool?
    var recipeDate: Date?
    var savedMealDate: Date?

    init(entry: FoodEntry, food: FoodItem? = nil, favourite: Bool? = nil,
         recipe: Recipe? = nil, savedMeal: SavedMeal? = nil) {
        id = UUID()
        self.entry = entry
        self.food = food
        self.favourite = favourite
        recipeDate = recipe?.createdAt
        savedMealDate = savedMeal?.createdAt
    }

    struct Snapshot: Codable {
        let id: UUID
        let item: MealItem
        let meal: MealSlot
        let loggedAt: Date
        let eatenAt: Date
        let confidence: String?
        let food: FoodItem?
        let favourite: Bool?
        let recipeDate: Date?
        let savedMealDate: Date?

        init(_ draft: FoodDiaryDraft) {
            id = draft.id
            item = MealItem(draft.entry)
            meal = draft.entry.meal
            loggedAt = draft.entry.loggedAt
            eatenAt = draft.entry.eatenAt
            confidence = draft.entry.confidence
            food = draft.food
            favourite = draft.favourite
            recipeDate = draft.recipeDate
            savedMealDate = draft.savedMealDate
        }
    }

    init(snapshot: Snapshot) {
        id = snapshot.id
        entry = FoodEntry(mealItem: snapshot.item, eatenAt: snapshot.eatenAt, meal: snapshot.meal)
        entry.loggedAt = snapshot.loggedAt
        entry.confidence = snapshot.confidence
        food = snapshot.food
        favourite = snapshot.favourite
        recipeDate = snapshot.recipeDate
        savedMealDate = snapshot.savedMealDate
    }
}

@MainActor
enum FoodDiary {
    static func save(_ draft: [FoodDiaryDraft], removing record: MealDraftRecord? = nil,
                     in context: ModelContext) throws -> [FoodEntry] {
        do { return try commitMeal(draft, removing: record, in: context) }
        catch { context.rollback(); throw error }
    }

    private static func commitMeal(_ draft: [FoodDiaryDraft], removing record: MealDraftRecord?,
                                   in context: ModelContext) throws -> [FoodEntry] {
        var foods: [String: SavedFood] = [:]
        var entries: [FoodEntry] = []
        for line in draft {
            let entry = FoodEntry(copying: line.entry, eatenAt: line.entry.eatenAt, meal: line.entry.meal)
            context.insert(entry)
            entries.append(entry)
            if let date = line.recipeDate {
                let recipes = try context.fetch(FetchDescriptor<Recipe>(predicate: #Predicate { $0.createdAt == date }))
                recipes.first?.lastUsed = .now
            }
            if let date = line.savedMealDate {
                let meals = try context.fetch(FetchDescriptor<SavedMeal>(predicate: #Predicate { $0.createdAt == date }))
                meals.first?.lastUsed = .now
            }
            guard let food = line.food else { continue }
            let record: SavedFood
            if let cached = foods[food.id] {
                record = cached
            } else {
                if let existing = try savedFood(food.id, in: context) {
                    record = existing
                } else {
                    record = SavedFood(item: food, isCustom: entry.source == .manual)
                    context.insert(record)
                }
                foods[food.id] = record
            }
            record.lastUsed = .now
            record.useCount += 1
            if let favourite = line.favourite { record.isFavourite = favourite }
        }
        if let record { context.delete(record) }
        try context.save()
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
