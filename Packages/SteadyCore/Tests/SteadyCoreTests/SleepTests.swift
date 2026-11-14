import XCTest
@testable import SteadyCore

final class SleepTests: XCTestCase {
    var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date { cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))! }

    func testOverlappingDevicesAreCountedOnce() {
        let watch = DateInterval(start: at(1, 23), end: at(2, 7))
        let phone = DateInterval(start: at(1, 23, 30), end: at(2, 6, 30))
        let n = SleepMath.nights([watch, phone], calendar: cal)
        XCTAssertEqual(n.count, 1)
        XCTAssertEqual(n[0].hours, 8, accuracy: 0.001)
        XCTAssertEqual(n[0].night, cal.startOfDay(for: at(1, 0)))
    }

    func testNapsAreSeparateAndIgnoredByTheAverage() {
        let night = DateInterval(start: at(1, 23), end: at(2, 7))
        let nap = DateInterval(start: at(2, 14), end: at(2, 14, 30))
        let n = SleepMath.nights([night, nap], calendar: cal)
        XCTAssertEqual(n.count, 2)
        XCTAssertEqual(n.map(\.hours).sorted(), [0.5, 8])
        XCTAssertEqual(SleepMath.average(n) ?? 0, 8, accuracy: 0.001)
        XCTAssertNil(SleepMath.average([SleepNight(night: at(1, 0), hours: 1)]))
    }

    func testSplitSleepWithAWakingGapAddsUp() {
        let a = DateInterval(start: at(3, 22, 30), end: at(4, 2))
        let b = DateInterval(start: at(4, 3), end: at(4, 6, 30))
        let n = SleepMath.nights([b, a], calendar: cal)
        XCTAssertEqual(n.count, 1)
        XCTAssertEqual(n[0].hours, 7, accuracy: 0.001)
    }

    func testBedtimeAndWakeSpanTheNight() {
        let cal = Calendar(identifier: .gregorian)
        let bed = Date(timeIntervalSince1970: 1_700_000_000)
        let parts = [DateInterval(start: bed, duration: 3 * 3600),
                     DateInterval(start: bed.addingTimeInterval(3.5 * 3600), duration: 4 * 3600)]
        let night = SleepMath.nights(parts, calendar: cal).last
        XCTAssertEqual(night?.bedtime, bed)
        XCTAssertEqual(night?.wake, bed.addingTimeInterval(7.5 * 3600))
        XCTAssertEqual(night?.hours ?? 0, 7, accuracy: 0.001)       // the half-hour awake isn't counted
        XCTAssertEqual(SleepMath.text(7.4), "7 h 24 m")
        XCTAssertEqual(SleepMath.text(6), "6 h 00 m")
    }
}
