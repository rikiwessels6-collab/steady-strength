import XCTest
@testable import SteadyCore

final class AutoPilotTests: XCTestCase {
    func testInRangeKeepsTheWeight() {
        let a = SetAdvisor.next(lastWeight: 60, lastReps: 9, minReps: 8, topReps: 12, step: 2.5)
        XCTAssertEqual(a.kind, .keep)
        XCTAssertEqual(a.weight, 60)
    }

    func testJustShortDropsALittle() {
        let a = SetAdvisor.next(lastWeight: 60, lastReps: 7, minReps: 8, topReps: 12, step: 2.5)
        XCTAssertEqual(a.kind, .lighter)
        XCTAssertEqual(a.weight, 55)            // 5% off 60 is 57, rounded down to a 2.5 kg step
        XCTAssertNotNil(a.note)
    }

    func testWellShortDropsMore() {
        let a = SetAdvisor.next(lastWeight: 100, lastReps: 4, minReps: 8, topReps: 12, step: 2.5)
        XCTAssertEqual(a.kind, .lighter)
        XCTAssertEqual(a.weight, 90)
    }

    func testLightWeightsStillDropAtLeastOneStep() {
        let a = SetAdvisor.next(lastWeight: 10, lastReps: 7, minReps: 8, topReps: 12, step: 2.5)
        XCTAssertEqual(a.weight, 7.5)
        XCTAssertEqual(SetAdvisor.next(lastWeight: 2.5, lastReps: 3, minReps: 8, topReps: 12, step: 2.5).kind, .keep)
    }

    func testFarAboveTheRangeOffersMore() {
        let a = SetAdvisor.next(lastWeight: 40, lastReps: 15, minReps: 8, topReps: 12, step: 2.5)
        XCTAssertEqual(a.kind, .heavier)
        XCTAssertEqual(a.weight, 42.5)
        XCTAssertEqual(SetAdvisor.next(lastWeight: 40, lastReps: 13, minReps: 8, topReps: 12, step: 2.5).kind, .keep)
    }

    func testBodyweightAndUnknownTargetsAreLeftAlone() {
        XCTAssertEqual(SetAdvisor.next(lastWeight: 0, lastReps: 3, minReps: 8, topReps: 12, step: 2.5).kind, .keep)
        XCTAssertEqual(SetAdvisor.next(lastWeight: 60, lastReps: 3, minReps: nil, topReps: nil, step: 2.5).kind, .keep)
    }

    func testNextUp() {
        let plan: [(name: String, done: Int, total: Int)] = [("Leg press", 2, 3), ("Row", 0, 3), ("Curl", 0, 2)]
        XCTAssertEqual(NextUp.text(remaining: plan, current: 0), "Next: set 3 of 3")
        let after: [(name: String, done: Int, total: Int)] = [("Leg press", 3, 3), ("Row", 0, 3), ("Curl", 0, 2)]
        XCTAssertEqual(NextUp.text(remaining: after, current: 0), "Next: Row")
        let skipped: [(name: String, done: Int, total: Int)] = [("Leg press", 1, 3), ("Row", 3, 3), ("Curl", 2, 2)]
        XCTAssertEqual(NextUp.text(remaining: skipped, current: 2), "Next: Leg press")
        let done: [(name: String, done: Int, total: Int)] = [("Leg press", 3, 3)]
        XCTAssertEqual(NextUp.text(remaining: done, current: 0), "That was your last set")
    }

    func testUsualFoods() {
        func e(_ id: String, _ grams: Double, _ day: Double) -> FoodHabits.Eaten {
            FoodHabits.Eaten(foodId: id, name: id.capitalized, grams: grams, date: Date(timeIntervalSince1970: day * 86_400))
        }
        let history = [e("oats", 40, 1), e("oats", 50, 2), e("oats", 60, 3), e("eggs", 100, 1), e("eggs", 120, 4), e("jam", 20, 5)]
        let usual = FoodHabits.usual(history)
        XCTAssertEqual(usual.map(\.foodId), ["oats", "eggs"])          // jam was only eaten once
        XCTAssertEqual(usual.first?.grams, 60)                          // the most recent amount
        XCTAssertEqual(FoodHabits.usual(history, excluding: ["oats"]).map(\.foodId), ["eggs"])
        XCTAssertEqual(FoodHabits.usual(history, limit: 1).count, 1)
    }
}
