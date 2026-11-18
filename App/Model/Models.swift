import Foundation
import SwiftData
import SteadyCore

// One person per phone: each of these is a single row, created at the end of
// onboarding. Enums are stored as raw strings so the schema stays simple.

@Model
final class UserProfile {
    var name: String
    var birthYear: Int
    var sexRaw: String
    var heightCm: Double
    var weightKg: Double
    var bodyFatRange: String?
    var goalRaw: String
    var experienceRaw: String
    var activityRaw: String
    var injuries: String
    /// Turns on the perimenopause-aware defaults (protein, optional daily check-ins).
    var perimenopause: Bool
    var createdAt: Date
    /// When the goal was last changed in Settings. Nil if it never has been.
    var goalChangedAt: Date? = nil

    init(name: String, birthYear: Int, sex: Sex, heightCm: Double, weightKg: Double, bodyFatRange: String?,
         goal: Goal, experience: Experience, activity: ActivityLevel, injuries: String, perimenopause: Bool) {
        self.name = name
        self.birthYear = birthYear
        self.sexRaw = sex.rawValue
        self.heightCm = heightCm
        self.weightKg = weightKg
        self.bodyFatRange = bodyFatRange
        self.goalRaw = goal.rawValue
        self.experienceRaw = experience.rawValue
        self.activityRaw = activity.rawValue
        self.injuries = injuries
        self.perimenopause = perimenopause
        self.createdAt = .now
    }

    var sex: Sex { Sex(rawValue: sexRaw) ?? .female }
    var goal: Goal { Goal(rawValue: goalRaw) ?? .generalHealth }
    var experience: Experience { Experience(rawValue: experienceRaw) ?? .new }
    var activity: ActivityLevel { ActivityLevel(rawValue: activityRaw) ?? .light }
    var age: Int { Calendar.current.component(.year, from: .now) - birthYear }
    var stats: BodyStats { BodyStats(weightKg: weightKg, heightCm: heightCm, age: age, sex: sex) }
}

struct FixedCommitment: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    /// Calendar weekday, 1 = Sunday ... 7 = Saturday.
    var weekday: Int
    var minutes: Int
    var countsAsActivity: Bool = true
}

@Model
final class TrainingPlan {
    var programId: String
    var startDate: Date
    var daysPerWeek: Int
    /// Preferred training weekdays (1 = Sunday ... 7 = Saturday).
    var preferredWeekdays: [Int]
    var sessionMinutes: Int
    var fixedCommitments: [FixedCommitment]
    var avoidHeavyLegsNextToCommitments: Bool
    var equipmentProfileId: String
    /// Equipment actually available (starts as the profile's list; the user can toggle items).
    var equipment: [String]
    /// Estimated 1RMs in kg by lift id (squat, bench, deadlift, ohp). Empty if not entered.
    var oneRepMaxes: [String: Double]
    /// Rotation position: index of the next session across the whole program.
    var nextSessionIndex: Int
    /// Smallest weight steps the app suggests when you hit the top of the rep range (kg). Editable in Settings.
    var upperIncrement: Double = 2.5
    var lowerIncrement: Double = 5

    init(programId: String, startDate: Date, daysPerWeek: Int, preferredWeekdays: [Int], sessionMinutes: Int,
         fixedCommitments: [FixedCommitment], avoidHeavyLegsNextToCommitments: Bool, equipmentProfileId: String,
         equipment: [String], oneRepMaxes: [String: Double]) {
        self.programId = programId
        self.startDate = startDate
        self.daysPerWeek = daysPerWeek
        self.preferredWeekdays = preferredWeekdays
        self.sessionMinutes = sessionMinutes
        self.fixedCommitments = fixedCommitments
        self.avoidHeavyLegsNextToCommitments = avoidHeavyLegsNextToCommitments
        self.equipmentProfileId = equipmentProfileId
        self.equipment = equipment
        self.oneRepMaxes = oneRepMaxes
        self.nextSessionIndex = 0
    }
}

@Model
final class NutritionPlan {
    var calories: Int
    var protein: Int
    var carbs: Int
    var fat: Int
    var fibre: Int
    var maintenance: Int
    var presetName: String
    var proteinPerKg: Double
    /// Follow the workbook advice: two weeks at maintenance before a deficit or surplus.
    var startAtMaintenance: Bool
    var createdAt: Date
    /// While set, the targets are at maintenance and switch to the goal's targets on this date.
    var easeInUntil: Date? = nil
    /// When a calorie suggestion from the weekly summary was last applied.
    var lastCoachAdjustAt: Date? = nil

    init(calories: Int, protein: Int, carbs: Int, fat: Int, fibre: Int, maintenance: Int,
         presetName: String, proteinPerKg: Double, startAtMaintenance: Bool) {
        self.calories = calories; self.protein = protein; self.carbs = carbs; self.fat = fat
        self.fibre = fibre; self.maintenance = maintenance
        self.presetName = presetName; self.proteinPerKg = proteinPerKg
        self.startAtMaintenance = startAtMaintenance
        self.createdAt = .now
    }

    init(targets: Nutrition.Targets, presetName: String, proteinPerKg: Double, startAtMaintenance: Bool) {
        self.calories = targets.calories
        self.protein = targets.protein
        self.carbs = targets.carbs
        self.fat = targets.fat
        self.fibre = targets.fibre
        self.maintenance = targets.maintenance
        self.presetName = presetName
        self.proteinPerKg = proteinPerKg
        self.startAtMaintenance = startAtMaintenance
        self.createdAt = .now
    }
}

@Model
final class CheckInSettings {
    /// Calendar weekday, 1 = Sunday ... 7 = Saturday.
    var weekday: Int
    var sleepGoalHours: Double
    var stepsGoal: Int
    /// Daily water goal in millilitres.
    var waterGoalMl: Int = 2500
    var metrics: [String]
    var dailyCheckIns: Bool

    init(weekday: Int, sleepGoalHours: Double, stepsGoal: Int, metrics: [String], dailyCheckIns: Bool) {
        self.weekday = weekday
        self.sleepGoalHours = sleepGoalHours
        self.stepsGoal = stepsGoal
        self.metrics = metrics
        self.dailyCheckIns = dailyCheckIns
    }
}

@Model
final class AppSettings {
    var onboardingComplete: Bool
    var lockEnabled: Bool
    var lockTimeoutSeconds: Int
    var disclaimerAcceptedAt: Date?
    /// Consent per data type (DataType.rawValue -> when it was given). Missing = not given.
    var consents: [String: Date]
    /// Opt-in local reminders (training days and the weekly check-in).
    var remindersEnabled: Bool = false
    var reminderHour: Int = 7
    var reminderMinute: Int = 0
    /// Your bar and plates, used by the plate calculator and warm-up sets. Plate keys are weights in kg; values are pairs owned.
    var barWeightKg: Double = 20
    var plateStock: [String: Int] = ["25": 4, "20": 2, "15": 2, "10": 4, "5": 4, "2.5": 4, "1.25": 2]
    var warmupStyleRaw: String = "percent"
    /// Optional YouTube channel to prefer in technique searches (empty = any channel).
    var videoChannel: String = ""
    /// When "Export my data" last made a backup file.
    var lastBackupAt: Date? = nil
    /// Send a notification when a rest timer ends (needs notification permission).
    var restAlerts: Bool = false
    /// Save finished workouts to Apple Health as strength training (start and end time only).
    var saveWorkoutsToHealth: Bool = false
    /// Extra calories (as carbs) on days marked as hard training days; 0 turns it off.
    var hardDayExtraKcal: Int = 200
    /// Days marked as hard training days, as "yyyy-MM-dd".
    var hardDays: [String] = []
    /// Share (%) of active calories from Apple Health workouts that day added to the calorie target; 0 = off.
    var healthAddBackPercent: Int = 50

    init() {
        onboardingComplete = false
        lockEnabled = true
        lockTimeoutSeconds = 60
        consents = [:]
    }
}

/// The kinds of personal data the app keeps, each with its own consent.
enum DataType: String, CaseIterable, Identifiable {
    case profile, training, nutrition, checkIns, photos, plateAnalysis, appleHealth
    var id: String { rawValue }

    var title: String {
        switch self {
        case .profile: return "Profile and body measurements"
        case .training: return "Workouts and training history"
        case .nutrition: return "Food log and nutrition targets"
        case .checkIns: return "Check-ins, sleep, energy and symptoms"
        case .photos: return "Progress photos"
        case .plateAnalysis: return "Plate photo estimates"
        case .appleHealth: return "Apple Health"
        }
    }

    var detail: String {
        switch self {
        case .profile: return "Age, sex, height, weight and goals, used to set your plan and targets."
        case .training: return "Sets, reps and weights, used to progress your program."
        case .nutrition: return "What you eat and your targets. Barcode lookups send only the barcode to Open Food Facts."
        case .checkIns: return "Weekly check-ins and optional daily notes. Private to this phone."
        case .photos: return "Front, side and rear photos, kept in the app, behind Face ID, never analysed."
        case .plateAnalysis: return "Off by default. When on, a plate photo you choose to analyse is sent once to estimate its food and macros, then discarded. Nothing is stored or linked to you."
        case .appleHealth: return "Reads your steps, workouts, sleep and body weight to fill in check-ins. Saves your finished workouts to Health only if you switch that on. Turn it on in Settings > Apple Health."
        }
    }

    /// The app can't work without these two.
    var required: Bool { self == .profile || self == .training }
}

// MARK: - Workout logs

@Model
final class WorkoutLog {
    var programId: String
    var weekNumber: Int
    var workoutPosition: Int
    var workoutName: String
    var versionRaw: String
    /// Exercises swapped for this session: slot order -> exercise id.
    var swaps: [Int: String]
    var startedAt: Date
    var finishedAt: Date?
    var notes: String
    /// Multiplier on suggested weights for this session (0.9 when "lower the load" was chosen at the readiness check).
    var loadFactor: Double = 1.0
    /// Readiness choice and reason code, kept on the phone only.
    var readinessChoiceRaw: String = ""
    var readinessCode: String = ""
    /// Exercise ids where the user accepted or declined a suggested increase or deload today.
    var acceptedSuggestions: [String] = []
    var declinedSuggestions: [String] = []
    /// An open workout (no program): the exercises added so far, in order.
    var isFreestyle: Bool = false
    /// Exercises you added yourself, in order: all of an open workout, or extras added to a program session.
    var freeExerciseIds: [String] = []
    /// Sets added beyond the program's prescription: slot order -> how many extra.
    var extraSets: [Int: Int] = [:]
    /// True once this workout has been saved to Apple Health, so it is never saved twice.
    var savedToHealth: Bool = false
    @Relationship(deleteRule: .cascade, inverse: \SetLog.workout) var sets: [SetLog] = []

    init(programId: String, weekNumber: Int, workoutPosition: Int, workoutName: String, version: SessionVersion, swaps: [Int: String]) {
        self.programId = programId
        self.weekNumber = weekNumber
        self.workoutPosition = workoutPosition
        self.workoutName = workoutName
        self.versionRaw = version.rawValue
        self.swaps = swaps
        self.startedAt = .now
        self.notes = ""
    }

    var version: SessionVersion { SessionVersion(rawValue: versionRaw) ?? .standard }
}

@Model
final class SetLog {
    var exerciseId: String
    var slotOrder: Int
    var setIndex: Int
    var weight: Double
    var reps: Int
    var rpe: Double?
    var completedAt: Date
    // What was asked for, so progression can judge this set later.
    var targetSets: Int
    var targetReps: Int?
    var minReps: Int?
    var maxRPE: Double?
    var workout: WorkoutLog?

    init(exerciseId: String, slotOrder: Int, setIndex: Int, weight: Double, reps: Int, rpe: Double?,
         targetSets: Int, targetReps: Int?, minReps: Int?, maxRPE: Double?) {
        self.exerciseId = exerciseId
        self.slotOrder = slotOrder
        self.setIndex = setIndex
        self.weight = weight
        self.reps = reps
        self.rpe = rpe
        self.completedAt = .now
        self.targetSets = targetSets
        self.targetReps = targetReps
        self.minReps = minReps
        self.maxRPE = maxRPE
    }
}

// MARK: - Food

/// One thing eaten. Every entry is time-stamped twice: when it was logged and
/// when it was eaten (defaults to now, editable), plus how it was entered.
@Model
final class FoodEntry {
    var loggedAt: Date
    var eatenAt: Date
    var mealRaw: String
    var sourceRaw: String
    var name: String
    var brand: String?
    var barcode: String?
    var foodId: String
    var grams: Double
    var kcal: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var fibre: Double
    /// Photo estimates: "high", "medium" or "low". Nil for exact sources.
    var confidence: String?
    /// Detail, when the food listed it: sugars and saturated fat in grams, sodium in milligrams.
    var sugar: Double? = nil
    var satFat: Double? = nil
    var sodiumMg: Double? = nil

    init(item: FoodItem, grams: Double, meal: MealSlot, source: FoodSource, eatenAt: Date) {
        let m = item.macros(grams: grams)
        self.loggedAt = .now
        self.eatenAt = eatenAt
        self.mealRaw = meal.rawValue
        self.sourceRaw = source.rawValue
        self.name = item.name
        self.brand = item.brand
        self.barcode = item.barcode
        self.foodId = item.id
        self.grams = grams
        self.kcal = m.kcal
        self.protein = m.protein
        self.carbs = m.carbs
        self.fat = m.fat
        self.fibre = m.fibre
        self.sugar = m.sugar
        self.satFat = m.satFat
        self.sodiumMg = m.sodium
    }

    /// A copy of another entry, for repeating a meal on another day. Keeps the exact amounts.
    init(copying e: FoodEntry, eatenAt: Date, meal: MealSlot) {
        self.loggedAt = .now
        self.eatenAt = eatenAt
        self.mealRaw = meal.rawValue
        self.sourceRaw = e.sourceRaw
        self.name = e.name
        self.brand = e.brand
        self.barcode = e.barcode
        self.foodId = e.foodId
        self.grams = e.grams
        self.kcal = e.kcal
        self.protein = e.protein
        self.carbs = e.carbs
        self.fat = e.fat
        self.fibre = e.fibre
        self.confidence = e.confidence
        self.sugar = e.sugar
        self.satFat = e.satFat
        self.sodiumMg = e.sodiumMg
    }

    /// An entry from a saved meal's item, with the amounts it was saved with.
    init(mealItem i: MealItem, eatenAt: Date, meal: MealSlot) {
        self.loggedAt = .now
        self.eatenAt = eatenAt
        self.mealRaw = meal.rawValue
        self.sourceRaw = i.sourceRaw
        self.name = i.name
        self.brand = i.brand
        self.barcode = i.barcode
        self.foodId = i.foodId
        self.grams = i.grams
        self.kcal = i.kcal
        self.protein = i.protein
        self.carbs = i.carbs
        self.fat = i.fat
        self.fibre = i.fibre
        self.sugar = i.sugar
        self.satFat = i.satFat
        self.sodiumMg = i.sodiumMg
    }

    var meal: MealSlot { MealSlot(rawValue: mealRaw) ?? .snacks }
    var source: FoodSource { FoodSource(rawValue: sourceRaw) ?? .manual }
    var macros: Macros {
        Macros(kcal: kcal, protein: protein, carbs: carbs, fat: fat, fibre: fibre, sugar: sugar, satFat: satFat, sodium: sodiumMg)
    }
}

/// Foods kept for quick logging: everything scanned or searched is cached here
/// (so it works offline next time), and custom foods live here too.
@Model
final class SavedFood {
    @Attribute(.unique) var foodId: String
    var itemData: Data
    var isFavourite: Bool
    var isCustom: Bool
    var lastUsed: Date
    var useCount: Int

    init(item: FoodItem, isCustom: Bool = false) {
        self.foodId = item.id
        self.itemData = (try? JSONEncoder().encode(item)) ?? Data()
        self.isFavourite = false
        self.isCustom = isCustom
        self.lastUsed = .now
        self.useCount = 0
    }

    var item: FoodItem? { try? JSONDecoder().decode(FoodItem.self, from: itemData) }
}


// MARK: - Weekly check-ins

/// One weekly check-in: weight, sleep, steps, your own 1-10 ratings, tape measurements and a note.
/// Everything is optional so a quick check-in can be just a weight. Stays on this phone.
@Model
final class CheckInEntry {
    var date: Date
    var weightKg: Double?
    var sleepHours: Double?
    var steps: Int?
    var ratings: [String: Int] = [:]
    var measurements: [String: Double] = [:]
    var note: String = ""
    /// From Apple Health when you tap Fill from Apple Health: minutes of recorded workouts and how many, in the last 7 days.
    var activeMinutes: Int? = nil
    var healthWorkoutCount: Int? = nil

    init(date: Date, weightKg: Double?, sleepHours: Double?, steps: Int?,
         ratings: [String: Int], measurements: [String: Double], note: String) {
        self.date = date; self.weightKg = weightKg; self.sleepHours = sleepHours; self.steps = steps
        self.ratings = ratings; self.measurements = measurements; self.note = note
    }
}


// MARK: - Exercise notes

/// A note you keep on an exercise, for example a pin hole or a cue. Shown during the workout.
@Model
final class ExerciseNote {
    @Attribute(.unique) var exerciseId: String
    var text: String

    init(exerciseId: String, text: String) {
        self.exerciseId = exerciseId
        self.text = text
    }
}


// MARK: - Progress photos

enum PhotoAngle: String, CaseIterable, Identifiable {
    case front, side, rear
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

/// Where a progress photo is and when it was taken. The picture itself is a file inside the app (see PhotoStore).
@Model
final class ProgressPhoto {
    var date: Date
    var angleRaw: String
    var fileName: String

    init(date: Date, angle: PhotoAngle, fileName: String) {
        self.date = date
        self.angleRaw = angle.rawValue
        self.fileName = fileName
    }

    var angle: PhotoAngle { PhotoAngle(rawValue: angleRaw) ?? .front }
}


// MARK: - Your own exercises

/// An exercise you added yourself. It is merged into the exercise list at launch (see ContentStore).
@Model
final class CustomExercise {
    @Attribute(.unique) var exerciseId: String
    var name: String
    var primaryMuscle: String
    var secondaryMuscle: String?
    /// One of CustomExercise.kinds.
    var kind: String
    var loadable: Bool
    var unilateral: Bool
    var timed: Bool
    var createdAt: Date

    init(name: String, primaryMuscle: String, secondaryMuscle: String?, kind: String, loadable: Bool, unilateral: Bool, timed: Bool) {
        self.exerciseId = "custom-" + UUID().uuidString.prefix(8).lowercased()
        self.name = name
        self.primaryMuscle = primaryMuscle
        self.secondaryMuscle = secondaryMuscle
        self.kind = kind
        self.loadable = loadable
        self.unilateral = unilateral
        self.timed = timed
        self.createdAt = .now
    }

    /// What it is done with: label and the equipment ids stored on the exercise.
    static let kinds: [(id: String, label: String, equipment: [String])] = [
        ("barbell", "Barbell", ["barbell"]),
        ("dumbbells", "Dumbbells", ["dumbbells"]),
        ("cable", "Cable", ["cable"]),
        ("machine", "Machine", ["machine"]),
        ("bodyweight", "Bodyweight", []),
        ("other", "Something else", []),
    ]

    var asExercise: SteadyCore.Exercise {
        SteadyCore.Exercise.custom(id: exerciseId, name: name, primaryMuscle: primaryMuscle, secondaryMuscle: secondaryMuscle,
                                   equipment: Self.kinds.first { $0.id == kind }?.equipment ?? [],
                                   loadable: loadable, unilateral: unilateral, timed: timed)
    }
}


// MARK: - Saved meals

/// One food inside a saved meal, with the amount it was saved with.
struct MealItem: Codable, Hashable {
    var name: String
    var brand: String?
    var barcode: String?
    var foodId: String
    var grams: Double
    var kcal: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var fibre: Double
    var sourceRaw: String
    var sugar: Double? = nil
    var satFat: Double? = nil
    var sodiumMg: Double? = nil

    init(_ e: FoodEntry) {
        name = e.name; brand = e.brand; barcode = e.barcode; foodId = e.foodId; grams = e.grams
        kcal = e.kcal; protein = e.protein; carbs = e.carbs; fat = e.fat; fibre = e.fibre; sourceRaw = e.sourceRaw
        sugar = e.sugar; satFat = e.satFat; sodiumMg = e.sodiumMg
    }
}

/// A named group of foods you eat together, added to a meal in one tap.
@Model
final class SavedMeal {
    var name: String
    var itemsData: Data
    var createdAt: Date
    var lastUsed: Date

    init(name: String, items: [MealItem]) {
        self.name = name
        self.itemsData = (try? JSONEncoder().encode(items)) ?? Data()
        self.createdAt = .now
        self.lastUsed = .now
    }

    var items: [MealItem] { (try? JSONDecoder().decode([MealItem].self, from: itemsData)) ?? [] }
    var kcal: Double { items.reduce(0) { $0 + $1.kcal } }
}


// MARK: - Recipes

/// A home-cooked dish: its raw ingredients, how many servings it makes, and (optionally) its cooked weight.
@Model
final class Recipe {
    var name: String
    var ingredientsData: Data
    var servings: Double
    var cookedWeightGrams: Double?
    var createdAt: Date
    var lastUsed: Date

    init(name: String, ingredients: [RecipeIngredient], servings: Double, cookedWeightGrams: Double?) {
        self.name = name
        self.ingredientsData = (try? JSONEncoder().encode(ingredients)) ?? Data()
        self.servings = servings
        self.cookedWeightGrams = cookedWeightGrams
        self.createdAt = .now
        self.lastUsed = .now
    }

    var ingredients: [RecipeIngredient] {
        get { (try? JSONDecoder().decode([RecipeIngredient].self, from: ingredientsData)) ?? [] }
        set { ingredientsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }
    var totalWeight: Double { RecipeMath.totalWeight(ingredients, cookedWeight: cookedWeightGrams) }
    var kcalPerServing: Double { servings > 0 ? RecipeMath.totals(ingredients).kcal / servings : 0 }

    /// The dish as a food you can log by the gram.
    var asFood: FoodItem {
        let perServing = servings > 0 ? totalWeight / servings : nil
        return FoodItem(id: "recipe-\(createdAt.timeIntervalSince1970)", name: name, brand: "Recipe", barcode: nil,
                        per100: RecipeMath.per100(ingredients, cookedWeight: cookedWeightGrams),
                        servingGrams: perServing, servingLabel: "1 serving")
    }
}


// MARK: - Your own programs

/// A program built in the app. The draft is stored as JSON and turned into a full program at launch (see ContentStore).
@Model
final class CustomProgram {
    @Attribute(.unique) var programId: String
    var draftData: Data
    var createdAt: Date
    var updatedAt: Date

    init(draft: ProgramDraft) {
        self.programId = draft.id
        self.draftData = (try? JSONEncoder().encode(draft)) ?? Data()
        self.createdAt = .now
        self.updatedAt = .now
    }

    var draft: ProgramDraft? { try? JSONDecoder().decode(ProgramDraft.self, from: draftData) }

    func update(_ d: ProgramDraft) {
        draftData = (try? JSONEncoder().encode(d)) ?? draftData
        updatedAt = .now
    }
}


// MARK: - Water and cardio

/// One drink of water, logged with a tap on Today.
@Model
final class WaterEntry {
    var date: Date
    var ml: Int
    init(date: Date = .now, ml: Int) { self.date = date; self.ml = ml }
}

/// A cardio or conditioning session logged in the app.
@Model
final class CardioSession {
    var date: Date
    var kindRaw: String
    var minutes: Int
    var distanceKm: Double?
    var kcal: Int?
    var notes: String
    var savedToHealth: Bool = false

    init(date: Date, kind: CardioKind, minutes: Int, distanceKm: Double?, kcal: Int?, notes: String) {
        self.date = date; self.kindRaw = kind.rawValue; self.minutes = minutes
        self.distanceKm = distanceKm; self.kcal = kcal; self.notes = notes
    }

    var kind: CardioKind { CardioKind(rawValue: kindRaw) ?? .other }
}
