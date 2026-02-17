import EventKit
import Foundation

// MARK: - Event Models

struct CalendarEvent: Codable, Sendable {
    let identifier: String
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let location: String?
    let notes: String?
    let url: String?
    let calendarName: String
    let availability: String
    let hasRecurrenceRules: Bool
    let attendees: [Attendee]?

    struct Attendee: Codable, Sendable {
        let name: String?
        let email: String?
        let role: String
        let type: String
        let status: String
        let isCurrentUser: Bool
    }
}

struct CreateEventInput: Codable, Sendable {
    let title: String
    let startDate: String
    let endDate: String
    let isAllDay: Bool?
    let location: String?
    let notes: String?
    let url: String?
    let calendarName: String?
    let alarmMinutesBefore: [Int]?
    let recurrence: RecurrenceInput?
}

struct UpdateEventInput: Codable, Sendable {
    let eventId: String
    let title: String?
    let startDate: String?
    let endDate: String?
    let isAllDay: Bool?
    let location: String?
    let notes: String?
    let url: String?
    let calendarName: String?
    let alarmMinutesBefore: [Int]?
    let recurrence: RecurrenceInput?
    let applyToFutureEvents: Bool?
}

// MARK: - Reminder Models

struct CalendarReminder: Codable, Sendable {
    let identifier: String
    let title: String
    let isCompleted: Bool
    let completionDate: Date?
    let startDate: String?
    let dueDate: String?
    let priority: Int
    let notes: String?
    let calendarName: String
    let hasRecurrenceRules: Bool
}

struct CreateReminderInput: Codable, Sendable {
    let title: String
    let notes: String?
    let startDate: String?
    let dueDate: String?
    let priority: Int?
    let calendarName: String?
    let alarmMinutesBefore: [Int]?
    let recurrence: RecurrenceInput?
}

struct UpdateReminderInput: Codable, Sendable {
    let reminderId: String
    let title: String?
    let notes: String?
    let startDate: String?
    let dueDate: String?
    let priority: Int?
    let isCompleted: Bool?
    let calendarName: String?
    let alarmMinutesBefore: [Int]?
    let recurrence: RecurrenceInput?
}

// MARK: - Recurrence

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

// MARK: - Calendar / Source

struct CalendarInfo: Codable, Sendable {
    let identifier: String
    let title: String
    let type: String
    let sourceName: String
    let isImmutable: Bool
    let allowsContentModifications: Bool
    let color: String?
}

struct SourceInfo: Codable, Sendable {
    let identifier: String
    let title: String
    let type: String
}

// MARK: - Availability

struct AvailabilityInput: Codable, Sendable {
    let startDate: String
    let endDate: String
    let calendarNames: [String]?
    let minimumSlotMinutes: Int?
}

struct TimeSlot: Codable, Sendable {
    let startDate: Date
    let endDate: Date
    let durationMinutes: Int
}

struct AvailabilityResult: Codable, Sendable {
    let freeSlots: [TimeSlot]
    let busySlots: [TimeSlot]
    let totalFreeMinutes: Int
    let totalBusyMinutes: Int
}

// MARK: - Errors

enum CalendarError: Error, LocalizedError {
    case accessDenied(String)
    case notFound(String)
    case invalidInput(String)
    case operationFailed(String)

    var errorDescription: String? {
        switch self {
        case .accessDenied(let msg): return "Access denied: \(msg)"
        case .notFound(let msg): return "Not found: \(msg)"
        case .invalidInput(let msg): return "Invalid input: \(msg)"
        case .operationFailed(let msg): return "Operation failed: \(msg)"
        }
    }
}

// MARK: - EKEvent Conversion

extension CalendarEvent {
    @MainActor
    static func from(_ event: EKEvent) -> CalendarEvent {
        CalendarEvent(
            identifier: event.eventIdentifier,
            title: event.title ?? "Untitled",
            startDate: event.startDate,
            endDate: event.endDate,
            isAllDay: event.isAllDay,
            location: event.location,
            notes: event.notes,
            url: event.url?.absoluteString,
            calendarName: event.calendar?.title ?? "Unknown",
            availability: event.availability.label,
            hasRecurrenceRules: event.hasRecurrenceRules,
            attendees: event.attendees?.map(Attendee.from)
        )
    }
}

extension CalendarEvent.Attendee {
    @MainActor
    static func from(_ participant: EKParticipant) -> CalendarEvent.Attendee {
        .init(
            name: participant.name,
            email: participant.url.absoluteString.replacingOccurrences(of: "mailto:", with: ""),
            role: participant.participantRole.label,
            type: participant.participantType.label,
            status: participant.participantStatus.label,
            isCurrentUser: participant.isCurrentUser
        )
    }
}

// MARK: - EKReminder Conversion

extension CalendarReminder {
    static func from(_ reminder: EKReminder) -> CalendarReminder {
        CalendarReminder(
            identifier: reminder.calendarItemIdentifier,
            title: reminder.title ?? "Untitled",
            isCompleted: reminder.isCompleted,
            completionDate: reminder.completionDate,
            startDate: reminder.startDateComponents?.formatted,
            dueDate: reminder.dueDateComponents?.formatted,
            priority: reminder.priority,
            notes: reminder.notes,
            calendarName: reminder.calendar?.title ?? "Unknown",
            hasRecurrenceRules: reminder.hasRecurrenceRules
        )
    }
}

// MARK: - EKCalendar / EKSource Conversion

extension CalendarInfo {
    @MainActor
    static func from(_ calendar: EKCalendar) -> CalendarInfo {
        CalendarInfo(
            identifier: calendar.calendarIdentifier,
            title: calendar.title,
            type: calendar.type.label,
            sourceName: calendar.source?.title ?? "Unknown",
            isImmutable: calendar.isImmutable,
            allowsContentModifications: calendar.allowsContentModifications,
            color: calendar.cgColor.map(Self.colorToHex)
        )
    }

    private static func colorToHex(_ cgColor: CGColor) -> String {
        guard let c = cgColor.components, c.count >= 3 else { return "#000000" }
        return String(format: "#%02X%02X%02X", Int(c[0] * 255), Int(c[1] * 255), Int(c[2] * 255))
    }
}

extension SourceInfo {
    @MainActor
    static func from(_ source: EKSource) -> SourceInfo {
        SourceInfo(
            identifier: source.sourceIdentifier,
            title: source.title,
            type: source.sourceType.label
        )
    }
}

// MARK: - EK Enum Labels

extension EKEventAvailability {
    var label: String {
        switch self {
        case .busy: "busy"
        case .free: "free"
        case .tentative: "tentative"
        case .unavailable: "unavailable"
        case .notSupported: "notSupported"
        @unknown default: "unknown"
        }
    }
}

extension EKParticipantRole {
    var label: String {
        switch self {
        case .required: "required"
        case .optional: "optional"
        case .chair: "chair"
        case .nonParticipant: "nonParticipant"
        case .unknown: "unknown"
        @unknown default: "unknown"
        }
    }
}

extension EKParticipantType {
    var label: String {
        switch self {
        case .person: "person"
        case .room: "room"
        case .resource: "resource"
        case .group: "group"
        case .unknown: "unknown"
        @unknown default: "unknown"
        }
    }
}

extension EKParticipantStatus {
    var label: String {
        switch self {
        case .pending: "pending"
        case .accepted: "accepted"
        case .declined: "declined"
        case .tentative: "tentative"
        case .delegated: "delegated"
        case .completed: "completed"
        case .inProcess: "inProcess"
        case .unknown: "unknown"
        @unknown default: "unknown"
        }
    }
}

extension EKCalendarType {
    var label: String {
        switch self {
        case .local: "local"
        case .calDAV: "calDAV"
        case .exchange: "exchange"
        case .subscription: "subscription"
        case .birthday: "birthday"
        @unknown default: "unknown"
        }
    }
}

extension EKSourceType {
    var label: String {
        switch self {
        case .local: "local"
        case .exchange: "exchange"
        case .calDAV: "calDAV"
        case .mobileMe: "iCloud"
        case .subscribed: "subscribed"
        case .birthdays: "birthdays"
        @unknown default: "unknown"
        }
    }
}

// MARK: - DateComponents Formatting

extension DateComponents {
    var formatted: String {
        [
            year.map { "year:\($0)" },
            month.map { "month:\($0)" },
            day.map { "day:\($0)" },
            hour.map { "hour:\($0)" },
            minute.map { "minute:\($0)" },
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }
}

// MARK: - Recurrence Conversion

private let weekdayMap: [Int: EKWeekday] = [
    1: .sunday, 2: .monday, 3: .tuesday, 4: .wednesday,
    5: .thursday, 6: .friday, 7: .saturday,
]

private let frequencyMap: [String: EKRecurrenceFrequency] = [
    "daily": .daily, "weekly": .weekly, "monthly": .monthly, "yearly": .yearly,
]

extension RecurrenceInput {
    func toEKRecurrenceRule() throws -> EKRecurrenceRule {
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

    private func recurrenceEnd() throws -> EKRecurrenceEnd? {
        if let count = occurrenceCount {
            return EKRecurrenceEnd(occurrenceCount: count)
        }
        guard let endDateStr = endDate else { return nil }
        guard let date = ISO8601DateFormatter().date(from: endDateStr) else {
            throw CalendarError.invalidInput("Invalid end date format: \(endDateStr)")
        }
        return EKRecurrenceEnd(end: date)
    }
}

// MARK: - Reminder Filter

enum ReminderFilter: Sendable {
    case all
    case incomplete(start: Date?, end: Date?)
    case completed(start: Date?, end: Date?)
}
