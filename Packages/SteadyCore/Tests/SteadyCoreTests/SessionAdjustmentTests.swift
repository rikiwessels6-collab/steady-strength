import Foundation
import XCTest
@testable import SteadyCore

final class SessionAdjustmentTests: XCTestCase {
    func testMovingOneOccurrenceKeepsOtherTrainingDays() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Australia/Brisbane"))
        let monday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 23)))
        let tuesday = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: monday))
        let nextMonday = try XCTUnwrap(calendar.date(byAdding: .day, value: 7, to: monday))
        var adjustment = SessionAdjustment(programID: "a", planStart: monday, sessionIndex: 3)
        adjustment.movedFrom = monday
        adjustment.movedTo = tuesday
        adjustment.version = .express
        adjustment.swaps[4] = "dumbbell-press"

        XCTAssertFalse(adjustment.isTrainingDay(monday, weekdays: [2], calendar: calendar))
        XCTAssertTrue(adjustment.isTrainingDay(tuesday, weekdays: [2], calendar: calendar))
        XCTAssertTrue(adjustment.isTrainingDay(nextMonday, weekdays: [2], calendar: calendar))
        XCTAssertEqual(SessionAdjustment.preferredDay(onOrAfter: tuesday, weekdays: [2], calendar: calendar), nextMonday)

        let restored = try JSONDecoder().decode(SessionAdjustment.self, from: JSONEncoder().encode(adjustment))
        XCTAssertEqual(restored, adjustment)
        XCTAssertTrue(restored.applies(programID: "a", planStart: monday, sessionIndex: 3))
        XCTAssertFalse(restored.applies(programID: "a", planStart: monday, sessionIndex: 4))
    }

    func testNextSetAlternatesSupersetPartnersAndFillsMissingSets() {
        var first = PlannedExercise(moduleExerciseId: "a", name: "A", id: 1, sets: 2,
                                    repMin: 8, repMax: 10, restSeconds: 60)
        var second = PlannedExercise(moduleExerciseId: "b", name: "B", id: 2, sets: 2,
                                     repMin: 8, repMax: 10, restSeconds: 60)
        first.supersetGroup = "pair"
        second.supersetGroup = "pair"
        let plan = [first, second]

        XCTAssertEqual(WorkoutSetOrder.next(in: plan, completed: [1: [0]], extraSets: [:])?.exerciseIndex, 1)
        XCTAssertEqual(WorkoutSetOrder.next(in: plan, completed: [1: [0], 2: [0]], extraSets: [:])?.exerciseIndex, 0)
        XCTAssertEqual(WorkoutSetOrder.next(in: plan, completed: [1: [1], 2: [0]], extraSets: [:])?.setIndex, 0)
        XCTAssertNil(WorkoutSetOrder.next(in: plan, completed: [1: [0, 1], 2: [0, 1]], extraSets: [:]))
        XCTAssertEqual(WorkoutSetOrder.next(in: plan, completed: [1: [0, 1], 2: [0, 1]], extraSets: [1: 1])?.setIndex, 2)
    }
}
