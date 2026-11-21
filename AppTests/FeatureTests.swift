import XCTest
import SwiftData
import SteadyCore
@testable import SteadyStrength

@MainActor
final class FeatureTests: XCTestCase {
    private func container() throws -> ModelContainer {
        try ModelContainer(for: Persistence.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    private func profile(goal: Goal = .generalHealth) -> UserProfile {
        UserProfile(name: "Sam", birthYear: 1985, sex: .female, heightCm: 168, weightKg: 70, bodyFatRange: nil,
                    goal: goal, experience: .intermediate, activity: .moderate, injuries: "", perimenopause: false)
    }

    private func nutrition(for p: UserProfile) -> NutritionPlan {
        let t = Nutrition.targets(p.stats, activity: p.activity, goal: .maintain)
        return NutritionPlan(targets: t, presetName: "Balanced", proteinPerKg: 1.8, startAtMaintenance: true)
    }

    func testMealDraftSurvivesAStoreReopenAndClearsWhenSaved() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("diary.store")
        func openStore() throws -> ModelContainer {
            try ModelContainer(for: Persistence.schema, configurations: ModelConfiguration(schema: Persistence.schema, url: url))
        }

        let meal = FoodDraftNavigation.Meal(slot: .lunch, day: Date(timeIntervalSince1970: 1_700_000_000))
        let food = FoodItem(id: "milk", name: "Milk", brand: nil, barcode: "9300123456789",
                            per100: Per100(kcal: 60, protein: 4, carbs: 5, fat: 3, sugar: 5, sodium: 20),
                            servingGrams: 250, servingLabel: nil, amountUnit: "mL")
        let time = meal.day.addingTimeInterval(11 * 60 * 60)
        do {
            let oldSchema = Schema([UserProfile.self, TrainingPlan.self, NutritionPlan.self, CheckInSettings.self,
                                    AppSettings.self, WorkoutLog.self, SetLog.self, FoodEntry.self, SavedFood.self,
                                    CheckInEntry.self, ExerciseNote.self, ProgressPhoto.self, CustomExercise.self,
                                    SavedMeal.self, Recipe.self, CustomProgram.self, WaterEntry.self, CardioSession.self])
            let old = try ModelContainer(for: oldSchema, configurations: ModelConfiguration(schema: oldSchema, url: url))
            old.mainContext.insert(FoodEntry(item: food, grams: 100, meal: .breakfast, source: .manual, eatenAt: time))
            try old.mainContext.save()
        }
        do {
            let store = try openStore()
            let context = store.mainContext
            let first = FoodDraftNavigation()
            first.load(in: context)
            let entry = FoodEntry(item: food, grams: 200, meal: .lunch, source: .photo, eatenAt: time)
            entry.confidence = "medium"
            first.draft(for: meal, in: context).wrappedValue = [FoodDiaryDraft(entry: entry, food: food, favourite: true)]
            XCTAssertFalse(first.storageError)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<FoodEntry>()), 1)
        }
        do {
            let store = try openStore()
            let context = store.mainContext
            let second = FoodDraftNavigation()
            second.load(in: context)
            XCTAssertEqual(second.latest, meal)
            let draft = try XCTUnwrap(second.draft(for: meal, in: context).wrappedValue.first)
            XCTAssertEqual(draft.entry.eatenAt, time)
            XCTAssertEqual(draft.entry.confidence, "medium")
            XCTAssertEqual(draft.entry.sugar, 10)
            XCTAssertEqual(draft.entry.portionUnit, "mL")
            XCTAssertEqual(draft.food, food)
            let saved = try second.commit(meal, in: context)
            XCTAssertEqual(saved.count, 1)
            XCTAssertNil(second.latest)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<MealDraftRecord>()), 0)
            XCTAssertEqual(try FoodDiary.savedFood(food.id, in: context)?.isFavourite, true)
        }
        let reopened = try openStore()
        let context = reopened.mainContext
        let entries = try context.fetch(FetchDescriptor<FoodEntry>())
        XCTAssertEqual(entries.map(\.grams).sorted(), [100, 200])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MealDraftRecord>()), 0)
    }

    func testMealDraftCommitsTogetherAndUndoRemovesOnlyItsEntries() throws {
        let store = try container()
        let context = ModelContext(store)
        let food = FoodItem(id: "sausage", name: "Sausage", brand: nil, barcode: nil,
                            per100: Per100(kcal: 240, protein: 13, carbs: 2, fat: 20),
                            servingGrams: 89, servingLabel: "1 sausage")
        let existing = FoodEntry(item: food, grams: 89, meal: .breakfast, source: .search, eatenAt: .now)
        context.insert(existing)
        try context.save()
        let draft = [178.0, 76.0].map { amount in
            FoodDiaryDraft(entry: FoodEntry(item: food, grams: amount, meal: .dinner, source: .search, eatenAt: .now),
                           food: food, favourite: true)
        }

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<FoodEntry>()), 1)
        let added = try FoodDiary.save(draft, in: context)
        XCTAssertEqual(added.map(\.grams), [178, 76])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<FoodEntry>()), 3)
        XCTAssertEqual(try FoodDiary.savedFood(food.id, in: context)?.useCount, 2)
        XCTAssertEqual(try FoodDiary.lastAmount(for: food, in: context), 76)

        try FoodDiary.delete(added, in: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<FoodEntry>()), 1)
        XCTAssertEqual(try FoodDiary.lastAmount(for: food, in: context), 89)
    }

    func testRestoreDeletedDiaryEntryPreservesNutritionAndTimestamps() throws {
        let store = try container()
        let context = ModelContext(store)
        let food = FoodItem(id: "milk", name: "Milk", brand: nil, barcode: nil,
                            per100: Per100(kcal: 60, protein: 4, carbs: 5, fat: 3, sugar: 5, sodium: 20),
                            servingGrams: 250, servingLabel: nil, amountUnit: "mL")
        let entry = FoodEntry(item: food, grams: 250, meal: .lunch, source: .photo, eatenAt: Date(timeIntervalSince1970: 500))
        entry.loggedAt = Date(timeIntervalSince1970: 600)
        entry.confidence = "medium"
        context.insert(entry)
        try context.save()
        let snapshot = FoodDiary.copyForUndo(entry)

        try FoodDiary.delete([entry], in: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<FoodEntry>()), 0)
        try FoodDiary.restore(snapshot, in: context)
        let restored = try XCTUnwrap(context.fetch(FetchDescriptor<FoodEntry>()).first)
        XCTAssertEqual(restored.macros, snapshot.macros)
        XCTAssertEqual(restored.loggedAt, snapshot.loggedAt)
        XCTAssertEqual(restored.eatenAt, snapshot.eatenAt)
        XCTAssertEqual(restored.meal, .lunch)
        XCTAssertEqual(restored.portionUnit, "mL")
        XCTAssertEqual(restored.confidence, "medium")
    }

    func testReviewedProductCanBeReadFromTheLocalStoreAndRepeated() throws {
        let container = try container()
        let item = FoodItem(id: "9300633603224", name: "Test drink", brand: nil, barcode: "9300633603224",
                            per100: Per100(kcal: 40, protein: 3, carbs: 5, fat: 1, fibre: 1, sugar: 4, sodium: 50),
                            servingGrams: 250, servingLabel: nil, amountUnit: "mL")
        let context = ModelContext(container)
        context.insert(SavedFood(item: item, isCustom: true))
        try context.save()

        let freshContext = ModelContext(container)
        let record = try XCTUnwrap(freshContext.fetch(FetchDescriptor<SavedFood>()).first)
        let saved = try XCTUnwrap(record.item)
        XCTAssertEqual(saved, item)
        let entry = FoodEntry(item: saved, grams: 250, meal: .breakfast, source: .barcode, eatenAt: .now)
        let repeated = FoodEntry(mealItem: MealItem(entry), eatenAt: .now, meal: .lunch)
        XCTAssertEqual(repeated.portionUnit, "mL")
        XCTAssertEqual(repeated.macros.sodium, 125)
        XCTAssertEqual(repeated.macros.sugar, 10)
        XCTAssertEqual(repeated.macros.kcal, 100)
    }

    func testGoalChangeRecomputesTargets() {
        let p = profile()
        let n = nutrition(for: p)
        let before = n.calories
        GoalSwitch.apply(.fatLoss, profile: p, nutrition: n, today: Date(timeIntervalSince1970: 1_000_000))
        XCTAssertEqual(p.goal, .fatLoss)
        XCTAssertNotNil(p.goalChangedAt)
        XCTAssertLessThan(n.calories, before)
        XCTAssertFalse(n.startAtMaintenance)
        GoalSwitch.apply(.buildMuscle, profile: p, nutrition: n)
        XCTAssertGreaterThan(n.calories, before)
        XCTAssertEqual(n.protein, Int((1.8 * 70).rounded()))
    }

    func testEaseInHoldsMaintenanceThenStepsUp() {
        let p = profile()
        let n = nutrition(for: p)
        let maintenance = n.calories
        let day0 = Date(timeIntervalSince1970: 1_700_000_000)
        GoalSwitch.apply(.fatLoss, profile: p, nutrition: n, easeIn: true, today: day0)
        XCTAssertEqual(n.calories, maintenance)
        XCTAssertTrue(n.startAtMaintenance)
        XCTAssertNotNil(n.easeInUntil)
        XCTAssertFalse(GoalSwitch.finishEaseInIfDue(profile: p, nutrition: n, now: day0.addingTimeInterval(13 * 86_400)))
        XCTAssertEqual(n.calories, maintenance)
        XCTAssertTrue(GoalSwitch.finishEaseInIfDue(profile: p, nutrition: n, now: day0.addingTimeInterval(15 * 86_400)))
        XCTAssertLessThan(n.calories, maintenance)
        XCTAssertFalse(n.startAtMaintenance)
        XCTAssertNil(n.easeInUntil)
    }

    func testOnboardingMaintenanceStartEndsAfterTwoWeeks() {
        let p = profile(goal: .buildMuscle)
        let n = nutrition(for: p)          // startAtMaintenance = true, no end date, created now
        XCTAssertFalse(GoalSwitch.finishEaseInIfDue(profile: p, nutrition: n, now: .now))
        XCTAssertTrue(GoalSwitch.finishEaseInIfDue(profile: p, nutrition: n, now: .now.addingTimeInterval(15 * 86_400)))
        XCTAssertGreaterThan(n.calories, n.maintenance)
    }

    func testEaseInIgnoredForMaintainAndLatestWeightIsUsed() {
        let p = profile()
        let n = nutrition(for: p)
        GoalSwitch.apply(.maintain, profile: p, nutrition: n, easeIn: true, weightKg: 80)
        XCTAssertNil(n.easeInUntil)
        XCTAssertFalse(n.startAtMaintenance)
        XCTAssertEqual(p.weightKg, 80)
        GoalSwitch.apply(.maintain, profile: p, nutrition: n, weightKg: 5)    // out of range, ignored
        XCTAssertEqual(p.weightKg, 80)
    }

    func testGoalChangeWithoutNutritionPlanStillSavesGoal() {
        let p = profile()
        GoalSwitch.apply(.maintain, profile: p, nutrition: nil)
        XCTAssertEqual(p.goal, .maintain)
    }

    func testRemovingAnOpenWorkoutExerciseKeepsLaterSetsInPlace() throws {
        let c = try container()
        let log = WorkoutLog(programId: "open", weekNumber: 0, workoutPosition: 0, workoutName: "Open workout",
                             version: .standard, swaps: [:])
        log.isFreestyle = true
        log.freeExerciseIds = ["a", "b", "c"]
        c.mainContext.insert(log)
        let second = SetLog(exerciseId: "c", slotOrder: 2, setIndex: 0, weight: 50, reps: 8, rpe: nil,
                            targetSets: 3, targetReps: 12, minReps: 8, maxRPE: nil)
        c.mainContext.insert(second)
        second.workout = log
        FreeWorkout.remove(at: 1, from: log)
        XCTAssertEqual(log.freeExerciseIds, ["a", "c"])
        XCTAssertEqual(second.slotOrder, 1)
        // An exercise with sets can't be removed.
        FreeWorkout.remove(at: 1, from: log)
        XCTAssertEqual(log.freeExerciseIds, ["a", "c"])
    }

    func testBackupRoundTrip() throws {
        let c = try container()
        let ctx = c.mainContext
        let p = profile(goal: .buildMuscle)
        p.goalChangedAt = Date(timeIntervalSince1970: 1_700_000_000)
        ctx.insert(p)
        ctx.insert(nutrition(for: p))
        ctx.insert(TrainingPlan(programId: "ss-strength-foundations", startDate: .now, daysPerWeek: 3, preferredWeekdays: [2, 4, 6],
                                sessionMinutes: 60, fixedCommitments: [], avoidHeavyLegsNextToCommitments: false,
                                equipmentProfileId: "full_gym", equipment: ["barbell"], oneRepMaxes: ["squat": 100]))
        let custom = CustomExercise(name: "Cable crunch", primaryMuscle: "abs", secondaryMuscle: nil, kind: "cable",
                                    loadable: true, unilateral: false, timed: false)
        ctx.insert(custom)
        let log = WorkoutLog(programId: "open", weekNumber: 0, workoutPosition: 0, workoutName: "Open workout",
                             version: .standard, swaps: [3: "swapped-id"])
        log.isFreestyle = true
        log.freeExerciseIds = [custom.exerciseId]
        log.finishedAt = .now
        ctx.insert(log)
        let set = SetLog(exerciseId: custom.exerciseId, slotOrder: 0, setIndex: 0, weight: 40, reps: 10, rpe: 8,
                         targetSets: 3, targetReps: 12, minReps: 8, maxRPE: nil)
        ctx.insert(set)
        set.workout = log
        try ctx.save()

        let url = try DataExport.write(ctx)
        defer { try? FileManager.default.removeItem(at: url) }

        // Restore into a different, empty store.
        let other = try container()
        let summary = try DataImport.restore(from: url, into: other.mainContext)
        XCTAssertEqual(summary.workouts, 1)
        let profiles = try other.mainContext.fetch(FetchDescriptor<UserProfile>())
        XCTAssertEqual(profiles.first?.goal, .buildMuscle)
        XCTAssertNotNil(profiles.first?.goalChangedAt)
        let logs = try other.mainContext.fetch(FetchDescriptor<WorkoutLog>())
        XCTAssertEqual(logs.first?.isFreestyle, true)
        XCTAssertEqual(logs.first?.swaps[3], "swapped-id")
        XCTAssertEqual(logs.first?.sets.first?.targetSets, 3)
        XCTAssertEqual(logs.first?.sets.first?.rpe, 8)
        let customs = try other.mainContext.fetch(FetchDescriptor<CustomExercise>())
        XCTAssertEqual(customs.first?.exerciseId, custom.exerciseId)
        let settings = try other.mainContext.fetch(FetchDescriptor<AppSettings>())
        XCTAssertEqual(settings.first?.onboardingComplete, true)
        // Restoring twice doesn't double anything up.
        _ = try DataImport.restore(from: url, into: other.mainContext)
        XCTAssertEqual(try other.mainContext.fetch(FetchDescriptor<WorkoutLog>()).count, 1)
    }

    func testSwitchingProgramClosesSessionsLeftOpenFromTheOldOne() throws {
        let c = try container()
        let ctx = c.mainContext
        let withSets = WorkoutLog(programId: "old", weekNumber: 1, workoutPosition: 1, workoutName: "Upper A", version: .standard, swaps: [:])
        let empty = WorkoutLog(programId: "old", weekNumber: 1, workoutPosition: 2, workoutName: "Lower A", version: .standard, swaps: [:])
        let current = WorkoutLog(programId: "new", weekNumber: 1, workoutPosition: 1, workoutName: "Full Body", version: .standard, swaps: [:])
        let open = WorkoutLog(programId: "open", weekNumber: 0, workoutPosition: 0, workoutName: "Open workout", version: .standard, swaps: [:])
        open.isFreestyle = true
        for l in [withSets, empty, current, open] { ctx.insert(l) }
        let set = SetLog(exerciseId: "x", slotOrder: 0, setIndex: 0, weight: 50, reps: 8, rpe: nil,
                         targetSets: 3, targetReps: 10, minReps: 8, maxRPE: nil)
        ctx.insert(set)
        set.workout = withSets
        try ctx.save()

        ProgramSwitch.closeStaleSessions(in: ctx, currentProgramId: "new")
        let logs = try ctx.fetch(FetchDescriptor<WorkoutLog>())
        XCTAssertEqual(logs.count, 3)                                  // the empty old session is gone
        XCTAssertNotNil(logs.first { $0.workoutName == "Upper A" }?.finishedAt)   // kept, with its set
        XCTAssertNil(logs.first { $0.workoutName == "Full Body" }?.finishedAt)    // current program untouched
        XCTAssertNil(logs.first { $0.isFreestyle }?.finishedAt)                   // open workout untouched
    }

    func testCalorieSuggestionAppliesAndKeepsProtein() {
        let p = profile(goal: .fatLoss)
        let n = nutrition(for: p)
        let protein = n.protein
        GoalSwitch.applyCalories(n.calories - 100, profile: p, nutrition: n)
        XCTAssertEqual(n.protein, protein)
        XCTAssertNotNil(n.lastCoachAdjustAt)
        XCTAssertLessThan(n.calories, n.maintenance)
    }

    func testSavedMealRoundTripsThroughBackup() throws {
        let c = try container()
        let ctx = c.mainContext
        ctx.insert(profile())
        let item = FoodItem(id: "oats", name: "Oats", brand: nil, barcode: nil,
                            per100: Per100(kcal: 380, protein: 13, carbs: 60, fat: 7), servingGrams: nil, servingLabel: nil)
        let entry = FoodEntry(item: item, grams: 50, meal: .breakfast, source: .manual, eatenAt: .now)
        ctx.insert(entry)
        ctx.insert(SavedMeal(name: "Usual breakfast", items: [MealItem(entry)]))
        try ctx.save()
        let url = try DataExport.write(ctx)
        defer { try? FileManager.default.removeItem(at: url) }
        let other = try container()
        _ = try DataImport.restore(from: url, into: other.mainContext)
        let meals = try other.mainContext.fetch(FetchDescriptor<SavedMeal>())
        XCTAssertEqual(meals.first?.name, "Usual breakfast")
        XCTAssertEqual(meals.first?.items.first?.kcal ?? 0, 190, accuracy: 0.01)
        // Adding it back gives the same numbers.
        let again = FoodEntry(mealItem: try XCTUnwrap(meals.first?.items.first), eatenAt: .now, meal: .lunch)
        XCTAssertEqual(again.kcal, 190, accuracy: 0.01)
        XCTAssertEqual(again.meal, .lunch)
    }

    func testFoodTimingUsesNowForTodayAndMiddayOtherwise() {
        let cal = Calendar.current
        let now = Date.now
        XCTAssertEqual(FoodTiming.defaultEatenAt(for: now, now: now), now)
        let yesterday = cal.date(byAdding: .day, value: -1, to: now)!
        XCTAssertEqual(cal.component(.hour, from: FoodTiming.defaultEatenAt(for: yesterday, now: now)), 12)
    }

    func testExtrasAddedToAProgramSessionKeepTheirOwnSlots() throws {
        let c = try container()
        let log = WorkoutLog(programId: "p", weekNumber: 1, workoutPosition: 1, workoutName: "Full Body A",
                             version: .standard, swaps: [:])
        log.freeExerciseIds = ["curl", "pushdown", "raise"]
        c.mainContext.insert(log)
        // A program set (slot 2) and a set on the third extra exercise.
        let programSet = SetLog(exerciseId: "x", slotOrder: 2, setIndex: 0, weight: 50, reps: 8, rpe: nil,
                                targetSets: 1, targetReps: 12, minReps: 8, maxRPE: nil)
        let extraSet = SetLog(exerciseId: "raise", slotOrder: FreeWorkout.extraBase + 2, setIndex: 0, weight: 6, reps: 12, rpe: nil,
                              targetSets: 3, targetReps: 12, minReps: 8, maxRPE: nil)
        for s in [programSet, extraSet] { c.mainContext.insert(s); s.workout = log }
        FreeWorkout.remove(at: 1, from: log, base: FreeWorkout.extraBase)
        XCTAssertEqual(log.freeExerciseIds, ["curl", "raise"])
        XCTAssertEqual(extraSet.slotOrder, FreeWorkout.extraBase + 1)
        XCTAssertEqual(programSet.slotOrder, 2)                // program slots never move
    }

    func testExtraSetsSurviveABackup() throws {
        let c = try container()
        let ctx = c.mainContext
        ctx.insert(profile())
        let log = WorkoutLog(programId: "p", weekNumber: 1, workoutPosition: 1, workoutName: "A", version: .standard, swaps: [:])
        log.extraSets = [1: 2]
        log.freeExerciseIds = ["curl"]
        log.finishedAt = .now
        ctx.insert(log)
        try ctx.save()
        let url = try DataExport.write(ctx)
        defer { try? FileManager.default.removeItem(at: url) }
        let other = try container()
        _ = try DataImport.restore(from: url, into: other.mainContext)
        let restored = try XCTUnwrap(other.mainContext.fetch(FetchDescriptor<WorkoutLog>()).first)
        XCTAssertEqual(restored.extraSets[1], 2)
        XCTAssertEqual(restored.freeExerciseIds, ["curl"])
    }

    func testRecipeLogsAPortionAndSurvivesABackup() throws {
        let c = try container()
        let ctx = c.mainContext
        ctx.insert(profile())
        let recipe = Recipe(name: "Bolognese",
                            ingredients: [RecipeIngredient(name: "Mince", grams: 500, kcal: 1250, protein: 100, carbs: 0, fat: 90),
                                          RecipeIngredient(name: "Pasta", grams: 400, kcal: 1400, protein: 50, carbs: 280, fat: 6)],
                            servings: 4, cookedWeightGrams: 1200)
        ctx.insert(recipe)
        try ctx.save()
        // One serving is a quarter of the dish.
        let grams = RecipeMath.grams(servings: 1, servingsInRecipe: recipe.servings, totalWeight: recipe.totalWeight)
        XCTAssertEqual(grams, 300)
        XCTAssertEqual(recipe.asFood.macros(grams: grams).kcal, 662.5, accuracy: 0.01)
        XCTAssertEqual(recipe.kcalPerServing, 662.5, accuracy: 0.01)

        let url = try DataExport.write(ctx)
        defer { try? FileManager.default.removeItem(at: url) }
        let other = try container()
        _ = try DataImport.restore(from: url, into: other.mainContext)
        let restored = try XCTUnwrap(other.mainContext.fetch(FetchDescriptor<Recipe>()).first)
        XCTAssertEqual(restored.name, "Bolognese")
        XCTAssertEqual(restored.ingredients.count, 2)
        XCTAssertEqual(restored.cookedWeightGrams, 1200)
    }

    func testCustomProgramSurvivesABackup() throws {
        let c = try container()
        let ctx = c.mainContext
        ctx.insert(profile())
        let draft = ProgramDraft(id: "mine-abc", name: "My Split", weeks: 4, workouts: [
            WorkoutDraft(name: "Upper", slots: [SlotDraft(exerciseId: "bench_press", exerciseName: "Bench press")]),
        ])
        ctx.insert(CustomProgram(draft: draft))
        try ctx.save()
        let url = try DataExport.write(ctx)
        defer { try? FileManager.default.removeItem(at: url) }
        let other = try container()
        _ = try DataImport.restore(from: url, into: other.mainContext)
        let restored = try XCTUnwrap(other.mainContext.fetch(FetchDescriptor<CustomProgram>()).first)
        XCTAssertEqual(restored.draft, draft)
        XCTAssertEqual(try restored.draft?.makeProgram().weeks.count, 4)
    }

    func testCustomProgramJoinsTheCatalogue() throws {
        let bundle = Bundle(for: AppLock.self)
        func data(_ name: String) throws -> Data {
            let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: "json") ?? Bundle.main.url(forResource: name, withExtension: "json"))
            return try Data(contentsOf: url)
        }
        let content = try BundledContent(programs: data("programs"), library: data("exercise_library"),
                                         equipment: data("equipment"), checkIn: data("checkin_defaults"))
        let p = try ProgramDraft(id: "mine-xyz", name: "Mine", weeks: 2, workouts: [
            WorkoutDraft(name: "A", slots: [SlotDraft(exerciseId: "goblet_squat", exerciseName: "Goblet squat")]),
        ]).makeProgram()
        let merged = content.adding([], programs: [p])
        XCTAssertNotNil(merged.program("mine-xyz"))
        XCTAssertTrue(merged.catalogue(showDraft: false).contains { $0.id == "mine-xyz" })
        XCTAssertEqual(merged.programs.count, content.programs.count + 1)
    }

    func testWaterCardioAndFoodDetailSurviveABackup() throws {
        let c = try container()
        let ctx = c.mainContext
        ctx.insert(profile())
        ctx.insert(WaterEntry(ml: 500))
        ctx.insert(CardioSession(date: .now, kind: .rower, minutes: 20, distanceKm: 4.2, kcal: 180, notes: "Steady"))
        let bar = FoodItem(id: "bar", name: "Muesli bar", brand: nil, barcode: nil,
                           per100: Per100(kcal: 420, protein: 7, carbs: 60, fat: 15, sugar: 28, satFat: 6, sodium: 200),
                           servingGrams: 50, servingLabel: nil)
        let entry = FoodEntry(item: bar, grams: 50, meal: .snacks, source: .barcode, eatenAt: .now)
        XCTAssertEqual(entry.sugar ?? 0, 14, accuracy: 0.01)
        ctx.insert(entry)
        try ctx.save()
        let url = try DataExport.write(ctx)
        defer { try? FileManager.default.removeItem(at: url) }
        let other = try container()
        _ = try DataImport.restore(from: url, into: other.mainContext)
        XCTAssertEqual(try other.mainContext.fetch(FetchDescriptor<WaterEntry>()).first?.ml, 500)
        let cardio = try XCTUnwrap(other.mainContext.fetch(FetchDescriptor<CardioSession>()).first)
        XCTAssertEqual(cardio.kind, .rower)
        XCTAssertEqual(cardio.distanceKm, 4.2)
        let food = try XCTUnwrap(other.mainContext.fetch(FetchDescriptor<FoodEntry>()).first)
        XCTAssertEqual(food.sodiumMg ?? 0, 100, accuracy: 0.01)
        XCTAssertEqual(food.macros.satFat ?? 0, 3, accuracy: 0.01)
    }

    func testNotABackupIsRejected() {
        XCTAssertThrowsError(try DataImport.decode(Data("{\"hello\": 1}".utf8)))
    }
}
