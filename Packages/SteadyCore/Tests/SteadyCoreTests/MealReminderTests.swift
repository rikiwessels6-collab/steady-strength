import XCTest
@testable import SteadyCore

final class MealReminderTests: XCTestCase {
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Australia/Sydney")!
        return c
    }
    private func date(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }

    func testSkipsPastTimesAndMealsAlreadyLogged() {
        let now = date("2026-11-18T01:00:00Z")   // 12 pm in Sydney
        let plan = MealReminders.plan(times: MealReminders.defaultTimes, loggedToday: [.lunch], now: now, days: 2, calendar: cal)
        // Today: breakfast is past, lunch is logged, so only dinner. Tomorrow: all three.
        XCTAssertEqual(plan.map(\.id), ["meal.dinner.2026-11-18", "meal.breakfast.2026-11-19",
                                        "meal.lunch.2026-11-19", "meal.dinner.2026-11-19"])
        XCTAssertEqual(plan[0].date, date("2026-11-18T08:30:00Z"))   // 7:30 pm
        XCTAssertEqual(plan[2].meal, .lunch)
    }

    func testOnlyChosenMeals() {
        let now = date("2026-11-17T13:00:00Z")   // midnight in Sydney
        let plan = MealReminders.plan(times: [.lunch: 810], loggedToday: [], now: now, days: 7, calendar: cal)
        XCTAssertEqual(plan.count, 7)
        XCTAssertTrue(plan.allSatisfy { $0.meal == .lunch })
        XCTAssertTrue(MealReminders.plan(times: [:], loggedToday: [], now: now, calendar: cal).isEmpty)
    }

    func testMealFromId() {
        XCTAssertEqual(MealReminders.meal(fromId: "meal.lunch.2026-11-18"), .lunch)
        XCTAssertNil(MealReminders.meal(fromId: "steady.session.2"))
    }
}
