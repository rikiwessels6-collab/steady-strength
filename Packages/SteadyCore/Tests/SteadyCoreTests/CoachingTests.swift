import XCTest
@testable import SteadyCore

final class CoachingTests: XCTestCase {
    private func day(_ n: Int) -> Date { Date(timeIntervalSince1970: 1_700_000_000 + Double(n) * 86_400) }

    func testRecordNeedsSomethingToBeat() {
        let first = [StatSet(date: day(0), weight: 60, reps: 8)]
        XCTAssertFalse(ExerciseStats.isRecord(before: [], during: first))
        XCTAssertTrue(ExerciseStats.isRecord(before: first, during: [StatSet(date: day(7), weight: 62.5, reps: 8)]))
        XCTAssertTrue(ExerciseStats.isRecord(before: first, during: [StatSet(date: day(7), weight: 60, reps: 10)]))   // better est. 1RM
        XCTAssertFalse(ExerciseStats.isRecord(before: first, during: [StatSet(date: day(7), weight: 60, reps: 8)]))
        XCTAssertFalse(ExerciseStats.isRecord(before: first, during: [StatSet(date: day(7), weight: 0, reps: 20)]))   // bodyweight
    }

    func testWeekStreak() {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 12))!      // a Thursday
        func d(_ day: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: 11, day: day))! }
        // Last week (2-8 Nov): 3 sessions. The week before (26 Oct-1 Nov): 3. This week so far: 1.
        let dates = [d(2), d(4), d(6), cal.date(from: DateComponents(year: 2026, month: 10, day: 27))!,
                     cal.date(from: DateComponents(year: 2026, month: 10, day: 29))!,
                     cal.date(from: DateComponents(year: 2026, month: 10, day: 31))!, d(9)]
        XCTAssertEqual(Consistency.weekStreak(sessionDates: dates, planned: 3, now: now, calendar: cal), 2)
        // Once this week reaches the plan it counts too.
        XCTAssertEqual(Consistency.weekStreak(sessionDates: dates + [d(10), d(11)], planned: 3, now: now, calendar: cal), 3)
        // A missed week ends it.
        XCTAssertEqual(Consistency.weekStreak(sessionDates: [d(9)], planned: 3, now: now, calendar: cal), 0)
        XCTAssertEqual(Consistency.weekStreak(sessionDates: dates, planned: 0, now: now, calendar: cal), 0)
    }

    private func advise(goal: Goal, rate: Double?, calories: Int = 2000, floor: Int = 1500, span: Double = 21,
                        logged: Int = 10, intake: Double? = 2000, easing: Bool = false, since: Double? = nil) -> CalorieAdvice {
        CalorieCoach.advise(goal: goal, currentCalories: calories, floor: floor, bodyWeightKg: 80, weeklyChangeKg: rate,
                            spanDays: span, loggedDays: logged, averageIntake: intake, easingIn: easing, daysSinceLastChange: since)
    }

    func testFatLossStallSuggestsASmallCut() {
        let a = advise(goal: .fatLoss, rate: 0.0)
        XCTAssertEqual(a.kind, .adjust)
        XCTAssertEqual(a.delta, -100)
        XCTAssertEqual(a.newCalories, 1900)
    }

    func testOnTrackHolds() {
        XCTAssertEqual(advise(goal: .fatLoss, rate: -0.5).kind, .hold)      // 0.6% a week
        XCTAssertEqual(advise(goal: .buildMuscle, rate: 0.2).kind, .hold)
        XCTAssertEqual(advise(goal: .maintain, rate: 0.1).kind, .hold)
    }

    func testTooFastGoesTheOtherWay() {
        XCTAssertEqual(advise(goal: .fatLoss, rate: -1.0).delta, 100)       // 1.25% a week
        XCTAssertEqual(advise(goal: .buildMuscle, rate: 0.6).delta, -100)
        XCTAssertEqual(advise(goal: .buildMuscle, rate: 0.0).delta, 100)
    }

    func testNeverSuggestsBelowTheFloor() {
        let a = advise(goal: .fatLoss, rate: 0.0, calories: 1550, floor: 1500)
        XCTAssertEqual(a.kind, .hold)
        XCTAssertEqual(a.newCalories, 1550)
    }

    func testNeedsDataAndAdherenceFirst() {
        XCTAssertEqual(advise(goal: .fatLoss, rate: nil).kind, .needMoreData)
        XCTAssertEqual(advise(goal: .fatLoss, rate: 0, span: 7).kind, .needMoreData)
        XCTAssertEqual(advise(goal: .fatLoss, rate: 0, logged: 3).kind, .needMoreData)
        XCTAssertEqual(advise(goal: .fatLoss, rate: 0, intake: 2400).kind, .hold)      // eating over target: don't cut the target
        XCTAssertEqual(advise(goal: .fatLoss, rate: 0, easing: true).kind, .hold)
        XCTAssertEqual(advise(goal: .fatLoss, rate: 0, since: 5).kind, .hold)
        XCTAssertEqual(advise(goal: .fatLoss, rate: 0, since: 20).kind, .adjust)
    }
}
