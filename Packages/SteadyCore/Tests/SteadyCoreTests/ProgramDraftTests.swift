import XCTest
@testable import SteadyCore

final class ProgramDraftTests: XCTestCase {
    private func draft() -> ProgramDraft {
        ProgramDraft(id: "mine-test", name: "  My Split ", weeks: 6, notes: "Keep form strict.", workouts: [
            WorkoutDraft(name: "Upper", slots: [
                SlotDraft(exerciseId: "bench_press", exerciseName: "Bench press", sets: 4, repMin: 6, repMax: 8, rirMin: 1, rirMax: 2, restSeconds: 150),
                SlotDraft(exerciseId: "db_curl", exerciseName: "Dumbbell biceps curl", sets: 3, repMin: 12, repMax: 12, rirMin: nil, rirMax: nil, restSeconds: 60),
            ]),
            WorkoutDraft(name: "Lower", slots: [
                SlotDraft(exerciseId: "split_squat", exerciseName: "Split squat", sets: 3, repMin: 10, repMax: 12, restSeconds: 90, perSide: true),
            ]),
        ])
    }

    func testMakesARunnableProgram() throws {
        let p = try draft().makeProgram(mainLiftIds: ["bench_press"])
        XCTAssertEqual(p.id, "mine-test")
        XCTAssertEqual(p.name, "My Split")
        XCTAssertEqual(p.weeks.count, 6)
        XCTAssertEqual(p.weeks[5].workouts.map(\.name), ["Upper", "Lower"])
        XCTAssertEqual(p.catalogue, "mine")
        XCTAssertFalse(p.isDraft)
        let bench = p.weeks[0].workouts[0].slots[0]
        XCTAssertEqual(bench.sets.count, 4)
        XCTAssertEqual(bench.reps.scheme, .range(6, 8))
        XCTAssertEqual(bench.effort?.min, 1)
        XCTAssertEqual(bench.rest?.maxSec, 150)
        XCTAssertEqual(bench.isMainLift, true)
        let curl = p.weeks[0].workouts[0].slots[1]
        XCTAssertEqual(curl.reps.scheme, .fixed(12))
        XCTAssertNil(curl.effort)
        XCTAssertEqual(p.weeks[0].workouts[1].slots[0].reps.perSide, true)
        // 12 sessions over 6 weeks, then the program is complete.
        XCTAssertNotNil(p.session(at: 11))
        XCTAssertNil(p.session(at: 12))
    }

    func testEstimatedMinutes() {
        // Upper: 4 x (40 + 150) + 3 x (40 + 60) = 1060 s, about 18 min, plus 12.
        XCTAssertEqual(draft().workouts[0].estimatedMinutes, 30)
    }

    func testCompleteness() {
        XCTAssertTrue(draft().isComplete)
        XCTAssertFalse(ProgramDraft(name: "", workouts: draft().workouts).isComplete)
        XCTAssertFalse(ProgramDraft(name: "X", workouts: [WorkoutDraft(name: "Empty")]).isComplete)
        XCTAssertFalse(ProgramDraft(name: "X").isComplete)
    }

    func testCopyRoundTrip() throws {
        let original = try draft().makeProgram()
        let copy = ProgramDraft.copy(of: original, name: "Copy")
        XCTAssertEqual(copy.weeks, 6)
        XCTAssertEqual(copy.workouts.count, 2)
        XCTAssertEqual(copy.workouts[0].slots[0].repMin, 6)
        XCTAssertEqual(copy.workouts[0].slots[0].repMax, 8)
        XCTAssertEqual(copy.workouts[0].slots[0].rirMax, 2)
        XCTAssertEqual(copy.workouts[0].slots[1].rirMin, nil)
        XCTAssertNotEqual(copy.id, "mine-test")
    }

    func testSummary() {
        XCTAssertEqual(draft().workouts[0].slots[0].summary, "4 × 6-8 · 1-2 RIR · 2.5 min rest")
        XCTAssertEqual(draft().workouts[0].slots[1].summary, "3 × 12 · 1 min rest")
    }

    func testDraftsSurviveEncoding() throws {
        let data = try JSONEncoder().encode(draft())
        XCTAssertEqual(try JSONDecoder().decode(ProgramDraft.self, from: data), draft())
    }
}
