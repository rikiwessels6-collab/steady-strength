import AppIntents
import SwiftData
import SteadyCore

/// The meals Siri and Shortcuts can name.
enum MealChoice: String, AppEnum {
    case breakfast, lunch, dinner, snacks

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Meal"
    static var caseDisplayRepresentations: [MealChoice: DisplayRepresentation] = [
        .breakfast: "Breakfast", .lunch: "Lunch", .dinner: "Dinner", .snacks: "Snacks",
    ]

    var slot: MealSlot { MealSlot(rawValue: rawValue) ?? .snacks }
}

/// "Log my usual lunch in Steady Strength": copies the last time that meal was logged onto today.
struct LogUsualMealIntent: AppIntents.AppIntent {
    static var title: LocalizedStringResource = "Log my usual meal"
    static var description = IntentDescription("Copies the last day you logged this meal onto today, with the same foods and amounts.")
    /// Food data is behind Face ID in the app, so a locked phone has to be unlocked first.
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Meal") var meal: MealChoice

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = Persistence.shared.mainContext
        let message = try FoodLogging.repeatLast(meal.slot, on: .now, context: context)
        await MealReminderService.refresh(context)
        return .result(dialog: "\(message)")
    }
}

/// "Add lunch in Steady Strength": opens the app on Add for that meal (search, barcode or plate photo).
struct AddFoodIntent: AppIntents.AppIntent {
    static var title: LocalizedStringResource = "Add food"
    static var description = IntentDescription("Opens Steady Strength ready to add food to a meal.")
    static var openAppWhenRun = true

    @Parameter(title: "Meal") var meal: MealChoice?

    @MainActor
    func perform() async throws -> some IntentResult {
        NotificationRouter.shared.openMeal = meal?.slot ?? MealSlot.suggested(for: .now)
        return .result()
    }
}

struct SteadyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: LogUsualMealIntent(), phrases: [
            "Log my usual \(\.$meal) in \(.applicationName)",
            "Log my usual \(\.$meal) with \(.applicationName)",
            "Repeat my \(\.$meal) in \(.applicationName)",
        ], shortTitle: "Log usual meal", systemImageName: "arrow.counterclockwise")
        AppShortcut(intent: AddFoodIntent(), phrases: [
            "Add \(\.$meal) in \(.applicationName)",
            "Log \(\.$meal) in \(.applicationName)",
            "Add food in \(.applicationName)",
        ], shortTitle: "Add food", systemImageName: "fork.knife")
    }
}

@MainActor
enum FoodLogging {
    /// Copies the most recent earlier day's entries for `meal` onto `day`, at the same times of day.
    /// Returns a sentence saying what happened, for Siri to read out.
    static func repeatLast(_ meal: MealSlot, on day: Date, context: ModelContext) throws -> String {
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        let raw = meal.rawValue
        let name = meal.label.lowercased()
        let (todayStart, todayEnd) = cal.dayRange(day)
        let already = try context.fetchCount(FetchDescriptor<FoodEntry>(predicate: #Predicate {
            $0.mealRaw == raw && $0.eatenAt >= todayStart && $0.eatenAt < todayEnd }))
        if already > 0 { return "Your \(name) already has food logged today, so nothing was added." }

        var recent = FetchDescriptor<FoodEntry>(predicate: #Predicate { $0.mealRaw == raw && $0.eatenAt < start },
                                                sortBy: [SortDescriptor(\.eatenAt, order: .reverse)])
        recent.fetchLimit = 60
        let earlier = try context.fetch(recent)
        guard let latest = earlier.first?.eatenAt else { return "There's no earlier \(name) to copy yet. Log it once in the app first." }
        let (s, e) = cal.dayRange(latest)
        let items = earlier.filter { $0.eatenAt >= s && $0.eatenAt < e }
        for item in items {
            context.insert(FoodEntry(copying: item, eatenAt: FoodRepeat.time(of: item.eatenAt, on: day, now: .now), meal: meal))
        }
        try context.save()
        let kcal = Int(items.reduce(0.0) { $0 + $1.kcal }.rounded())
        let when = cal.isDateInYesterday(latest) ? "yesterday" : latest.formatted(.dateTime.weekday(.wide))
        let count = items.count == 1 ? "1 food" : "\(items.count) foods"
        return "Added \(name) from \(when): \(count), \(kcal) calories."
    }
}
