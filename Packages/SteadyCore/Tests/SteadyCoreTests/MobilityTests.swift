import XCTest
@testable import SteadyCore

final class MobilityTests: XCTestCase {
    func testRoutinesAreShortAndComplete() {
        XCTAssertEqual(Mobility.routines.count, 3)
        for r in Mobility.routines {
            XCTAssertFalse(r.steps.isEmpty, r.id)
            XCTAssertTrue((5...15).contains(r.minutes), "\(r.id): \(r.minutes) min")
            XCTAssertTrue(r.steps.allSatisfy { !$0.cue.isEmpty && $0.seconds >= 20 })
            XCTAssertEqual(Set(r.steps.map(\.id)).count, r.steps.count, "step ids must be unique in \(r.id)")
        }
    }

    func testOneSidedMovesBecomeTwoSteps() throws {
        let r = try XCTUnwrap(Mobility.routine("hips-back"))
        let hip = r.steps.filter { $0.name == "Half-kneeling hip flexor stretch" }
        XCTAssertEqual(hip.map(\.side), ["Left", "Right"])
        XCTAssertNil(r.steps.first?.side)
    }

    func testCardioKinds() {
        XCTAssertTrue(CardioKind.run.hasDistance)
        XCTAssertFalse(CardioKind.intervals.hasDistance)
        XCTAssertEqual(CardioKind(rawValue: "bike"), .bike)
        XCTAssertTrue(CardioKind.allCases.allSatisfy { !$0.label.isEmpty && !$0.symbol.isEmpty })
    }
}
