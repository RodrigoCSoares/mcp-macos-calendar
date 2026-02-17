import EventKit
import Foundation

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

enum ReminderFilter: Sendable {
    case all
    case incomplete(start: Date?, end: Date?)
    case completed(start: Date?, end: Date?)
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
