import EventKit
import Foundation

// MARK: - Reminder Operations

extension CalendarManager {

    func listReminders(calendarName: String? = nil, filter: ReminderFilter = .all) async throws -> [CalendarReminder] {
        try ensureReminderAccess()
        let calendars = try calendarName.map { try resolveCalendars([$0], for: .reminder) }

        let predicate: NSPredicate = switch filter {
        case .all:
            store.predicateForReminders(in: calendars)
        case .incomplete(let start, let end):
            store.predicateForIncompleteReminders(withDueDateStarting: start, ending: end, calendars: calendars)
        case .completed(let start, let end):
            store.predicateForCompletedReminders(withCompletionDateStarting: start, ending: end, calendars: calendars)
        }

        return await fetchReminders(matching: predicate)
    }

    func createReminder(_ input: CreateReminderInput) throws -> CalendarReminder {
        try ensureReminderAccess()
        let reminder = EKReminder(eventStore: store)
        reminder.title = input.title
        input.notes.map { reminder.notes = $0 }
        input.priority.map { reminder.priority = $0 }
        input.startDate.flatMap(ISO8601Parsing.parse).map { reminder.startDateComponents = dateComponents(from: $0) }
        input.dueDate.flatMap(ISO8601Parsing.parse).map { reminder.dueDateComponents = dateComponents(from: $0) }
        reminder.calendar = try input.calendarName.map { try resolveCalendar($0, for: .reminder) }
            ?? store.defaultCalendarForNewReminders()
        applyAlarms(input.alarmMinutesBefore, to: reminder)
        try applyRecurrence(input.recurrence, to: reminder)

        try store.save(reminder, commit: true)
        return CalendarReminder.from(reminder)
    }

    func updateReminder(_ input: UpdateReminderInput) throws -> CalendarReminder {
        try ensureReminderAccess()
        let reminder = try resolveReminder(input.reminderId)

        input.title.map { reminder.title = $0 }
        input.notes.map { reminder.notes = $0 }
        input.priority.map { reminder.priority = $0 }
        input.isCompleted.map { reminder.isCompleted = $0 }
        input.startDate.flatMap(ISO8601Parsing.parse).map { reminder.startDateComponents = dateComponents(from: $0) }
        input.dueDate.flatMap(ISO8601Parsing.parse).map { reminder.dueDateComponents = dateComponents(from: $0) }
        if let name = input.calendarName { reminder.calendar = try resolveCalendar(name, for: .reminder) }
        replaceAlarms(input.alarmMinutesBefore, on: reminder)
        try replaceRecurrence(input.recurrence, on: reminder)

        try store.save(reminder, commit: true)
        return CalendarReminder.from(reminder)
    }

    func deleteReminder(identifier: String) throws {
        try ensureReminderAccess()
        let reminder = try resolveReminder(identifier)
        try store.remove(reminder, commit: true)
    }

    func getReminder(identifier: String) throws -> CalendarReminder {
        try ensureReminderAccess()
        return CalendarReminder.from(try resolveReminder(identifier))
    }

    func searchReminders(query: String, calendarName: String? = nil) async throws -> [CalendarReminder] {
        try ensureReminderAccess()
        let calendars = try calendarName.map { try resolveCalendars([$0], for: .reminder) }
        let predicate = store.predicateForReminders(in: calendars)
        let lowered = query.lowercased()
        return await fetchReminders(matching: predicate).filter { r in
            [r.title, r.notes]
                .compactMap { $0?.lowercased() }
                .contains { $0.contains(lowered) }
        }
    }

    func setReminderCompletion(identifier: String, completed: Bool) throws -> CalendarReminder {
        try ensureReminderAccess()
        let reminder = try resolveReminder(identifier)
        reminder.isCompleted = completed
        try store.save(reminder, commit: true)
        return CalendarReminder.from(reminder)
    }

    func listOverdueReminders(calendarName: String? = nil) async throws -> [CalendarReminder] {
        try ensureReminderAccess()
        let calendars = try calendarName.map { try resolveCalendars([$0], for: .reminder) }
        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil, ending: Date(), calendars: calendars
        )
        return await fetchReminders(matching: predicate)
    }

    func batchCompleteReminders(identifiers: [String]) throws -> [CalendarReminder] {
        try ensureReminderAccess()
        let results = try identifiers.map { id -> CalendarReminder in
            let reminder = try resolveReminder(id)
            reminder.isCompleted = true
            try store.save(reminder, commit: false)
            return CalendarReminder.from(reminder)
        }
        try store.commit()
        return results
    }
}
