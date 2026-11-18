import XCTest
@testable import SteadyCore

final class AutoBackupTests: XCTestCase {
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Australia/Sydney")!
        return c
    }
    private func date(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }

    func testDueWeekly() {
        let last = date("2026-11-10T21:00:00Z")
        XCTAssertTrue(AutoBackupPlan.isDue(last: nil))
        XCTAssertFalse(AutoBackupPlan.isDue(last: last, now: date("2026-11-16T21:00:00Z")))
        XCTAssertTrue(AutoBackupPlan.isDue(last: last, now: date("2026-11-17T20:30:00Z")))   // within the hour's slack
        XCTAssertTrue(AutoBackupPlan.isDue(last: last, now: date("2026-11-30T21:00:00Z")))
    }

    func testFileNameIsTheLocalDay() {
        XCTAssertEqual(AutoBackupPlan.fileName(date("2026-11-18T14:30:00Z"), calendar: cal), "SteadyStrength-backup-2026-11-19.json")
    }

    func testKeepsTheNewestAndLeavesOtherFilesAlone() {
        let names = (1...10).map { String(format: "SteadyStrength-backup-2026-10-%02d.json", $0) }
            + ["notes.txt", "SteadyStrength-export-2026-10-01.json"]
        let removed = AutoBackupPlan.toRemove(names.shuffled(), keep: 8)
        XCTAssertEqual(Set(removed), ["SteadyStrength-backup-2026-10-01.json", "SteadyStrength-backup-2026-10-02.json"])
        XCTAssertEqual(AutoBackupPlan.toRemove(Array(names.prefix(3)), keep: 8), [])
    }

    func testRepeatKeepsTheTimeButNotInTheFuture() {
        let breakfast = date("2026-11-17T20:15:00Z")   // 7:15 am on the 18th in Sydney
        let today = date("2026-11-18T22:00:00Z")       // 9 am on the 19th
        XCTAssertEqual(FoodRepeat.time(of: breakfast, on: today, now: today, calendar: cal), date("2026-11-18T20:15:00Z"))
        let early = date("2026-11-18T19:00:00Z")       // 6 am on the 19th, before breakfast time
        XCTAssertEqual(FoodRepeat.time(of: breakfast, on: early, now: early, calendar: cal), early)
    }

    func testPreviousDaySkipsEmptyDays() {
        let dates = [date("2026-11-14T01:00:00Z"), date("2026-11-16T02:00:00Z"), date("2026-11-18T23:00:00Z")]
        let day = date("2026-11-18T23:30:00Z")         // the 19th, which already has one entry
        XCTAssertEqual(FoodRepeat.previousDay(dates, before: day, calendar: cal), cal.startOfDay(for: dates[1]))
        XCTAssertNil(FoodRepeat.previousDay([], before: day, calendar: cal))
    }
}
