import EventKit
import Foundation

// MARK: - Recurrence Input

struct RecurrenceInput: Codable, Sendable {
    let frequency: String
    let interval: Int?
    let daysOfWeek: [DayOfWeekInput]?
    let daysOfMonth: [Int]?
    let monthsOfYear: [Int]?
    let weeksOfYear: [Int]?
    let setPositions: [Int]?
    let occurrenceCount: Int?
    let endDate: String?
}

struct DayOfWeekInput: Codable, Sendable {
    let dayOfWeek: Int
    let weekNumber: Int?
}

// MARK: - Conversion to EKRecurrenceRule

private let weekdayMap: [Int: EKWeekday] = [
    1: .sunday, 2: .monday, 3: .tuesday, 4: .wednesday,
    5: .thursday, 6: .friday, 7: .saturday,
]

private let frequencyMap: [String: EKRecurrenceFrequency] = [
    "daily": .daily, "weekly": .weekly, "monthly": .monthly, "yearly": .yearly,
]

extension RecurrenceInput {
    @MainActor func toEKRecurrenceRule() throws -> EKRecurrenceRule {
        guard let freq = frequencyMap[frequency.lowercased()] else {
            throw CalendarError.invalidInput("Invalid frequency: \(frequency). Use daily, weekly, monthly, or yearly.")
        }

        let recurrenceInterval = interval ?? 1
        let end = try recurrenceEnd()

        let ekDaysOfWeek = daysOfWeek?.compactMap { day -> EKRecurrenceDayOfWeek? in
            guard let weekday = weekdayMap[day.dayOfWeek] else { return nil }
            return day.weekNumber.map { EKRecurrenceDayOfWeek(weekday, weekNumber: $0) }
                ?? EKRecurrenceDayOfWeek(weekday)
        }

        let ekDaysOfMonth = daysOfMonth?.map { NSNumber(value: $0) }
        let ekMonths = monthsOfYear?.map { NSNumber(value: $0) }
        let ekWeeks = weeksOfYear?.map { NSNumber(value: $0) }
        let ekPositions = setPositions?.map { NSNumber(value: $0) }

        let hasAdvancedFields = [ekDaysOfWeek != nil, ekDaysOfMonth != nil, ekMonths != nil, ekWeeks != nil, ekPositions != nil].contains(true)

        guard hasAdvancedFields else {
            return EKRecurrenceRule(recurrenceWith: freq, interval: recurrenceInterval, end: end)
        }

        return EKRecurrenceRule(
            recurrenceWith: freq,
            interval: recurrenceInterval,
            daysOfTheWeek: ekDaysOfWeek,
            daysOfTheMonth: ekDaysOfMonth,
            monthsOfTheYear: ekMonths,
            weeksOfTheYear: ekWeeks,
            daysOfTheYear: nil,
            setPositions: ekPositions,
            end: end
        )
    }

    @MainActor private func recurrenceEnd() throws -> EKRecurrenceEnd? {
        if let count = occurrenceCount {
            return EKRecurrenceEnd(occurrenceCount: count)
        }
        guard let endDateStr = endDate else { return nil }
        guard let date = ISO8601Parsing.parse(endDateStr) else {
            throw CalendarError.invalidInput("Invalid end date format: \(endDateStr)")
        }
        return EKRecurrenceEnd(end: date)
    }
}
