import XCTest
@testable import SteadyCore

final class HardDayTests: XCTestCase {
    func testExtraGoesToCarbsOnlyOnHardDays() {
        XCTAssertTrue(HardDay.targets(calories: 2400, carbs: 250, extraKcal: 200, isHardDay: false) == (2400, 250))
        XCTAssertTrue(HardDay.targets(calories: 2400, carbs: 250, extraKcal: 200, isHardDay: true) == (2600, 300))
        XCTAssertTrue(HardDay.targets(calories: 2400, carbs: 250, extraKcal: 0, isHardDay: true) == (2400, 250))
    }

    func testHealthAddBackIsTheChosenShare() {
        XCTAssertEqual(HardDay.healthExtra(burnedKcal: 643, percent: 50), 320)
        XCTAssertEqual(HardDay.healthExtra(burnedKcal: 643, percent: 0), 0)
        XCTAssertEqual(HardDay.healthExtra(burnedKcal: 0, percent: 100), 0)
        XCTAssertEqual(HardDay.healthExtra(burnedKcal: 500, percent: 150), 500)
    }

    func testHardDayAndHealthAreNotAddedTogether() {
        XCTAssertEqual(HardDay.extra(manualKcal: 200, isHardDay: true, healthKcal: 320), 320)
        XCTAssertEqual(HardDay.extra(manualKcal: 200, isHardDay: true, healthKcal: 0), 200)
        XCTAssertEqual(HardDay.extra(manualKcal: 200, isHardDay: false, healthKcal: 150), 150)
        XCTAssertEqual(HardDay.extra(manualKcal: 200, isHardDay: false, healthKcal: 0), 0)
    }

    func testKeyIsTheLocalCalendarDay() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Australia/Sydney")!
        let d = ISO8601DateFormatter().date(from: "2026-11-18T14:30:00Z")!   // 1:30 am on the 19th in Sydney
        XCTAssertEqual(HardDay.key(d, calendar: cal), "2026-11-19")
    }

    func testToggleAddsRemovesAndTrims() {
        XCTAssertEqual(HardDay.toggled([], key: "2026-11-18"), ["2026-11-18"])
        XCTAssertEqual(HardDay.toggled(["2026-11-18"], key: "2026-11-18"), [])
        let many = (0..<200).map { String(format: "2026-%03d", $0) }
        XCTAssertEqual(HardDay.toggled(many, key: "2027-001").count, HardDay.maxKept)
        XCTAssertEqual(HardDay.toggled(many, key: "2027-001").last, "2027-001")
    }
}
