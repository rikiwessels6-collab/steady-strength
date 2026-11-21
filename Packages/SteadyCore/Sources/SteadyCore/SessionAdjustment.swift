import Foundation

/// Personal changes to one upcoming session, identified by its place in a particular plan.
public struct SessionAdjustment: Codable, Equatable, Sendable {
    public let programID: String
    public let planStart: Date
    public let sessionIndex: Int
    public var version: SessionVersion = .standard
    public var swaps: [Int: String] = [:]
    public var movedFrom: Date?
    public var movedTo: Date?

    public init(programID: String, planStart: Date, sessionIndex: Int) {
        self.programID = programID
        self.planStart = planStart
        self.sessionIndex = sessionIndex
    }

    public func applies(programID: String, planStart: Date, sessionIndex: Int) -> Bool {
        self.programID == programID && self.planStart == planStart && self.sessionIndex == sessionIndex
    }

    public static func preferredDay(onOrAfter now: Date, weekdays: [Int],
                                    calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: now)
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
            .first { weekdays.contains(calendar.component(.weekday, from: $0)) } ?? start
    }

    /// Move just this occurrence. Other dates keep their recurring weekday preference.
    public func isTrainingDay(_ date: Date, weekdays: [Int], calendar: Calendar = .current) -> Bool {
        if let movedTo, calendar.isDate(date, inSameDayAs: movedTo) { return true }
        if let movedFrom, calendar.isDate(date, inSameDayAs: movedFrom) { return false }
        return weekdays.contains(calendar.component(.weekday, from: date))
    }
}
