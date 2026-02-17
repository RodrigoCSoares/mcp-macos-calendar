import EventKit
import Foundation
import Logging

@MainActor
final class CalendarManager {
    let store: EKEventStore
    private let logger: Logger

    private(set) var hasEventAccess = false
    private(set) var hasReminderAccess = false

    init(logger: Logger = Logger(label: "mcp-macos-calendar.manager")) {
        self.store = EKEventStore()
        self.logger = logger
    }

    // MARK: - Access

    func requestEventAccess() async throws {
        hasEventAccess = try await store.requestFullAccessToEvents()
        guard hasEventAccess else {
            throw CalendarError.accessDenied(
                "Calendar event access not granted. Go to System Settings > Privacy & Security > Calendars and enable access."
            )
        }
        logger.info("Calendar event access granted")
    }

    func requestReminderAccess() async throws {
        hasReminderAccess = try await store.requestFullAccessToReminders()
        guard hasReminderAccess else {
            throw CalendarError.accessDenied(
                "Reminders access not granted. Go to System Settings > Privacy & Security > Reminders and enable access."
            )
        }
        logger.info("Reminders access granted")
    }

    // MARK: - Shared Helpers

    func ensureEventAccess() throws {
        guard hasEventAccess else {
            throw CalendarError.accessDenied("Calendar event access has not been granted.")
        }
    }

    func ensureReminderAccess() throws {
        guard hasReminderAccess else {
            throw CalendarError.accessDenied("Reminder access has not been granted.")
        }
    }

    func resolveEvent(_ identifier: String) throws -> EKEvent {
        guard let event = store.event(withIdentifier: identifier) else {
            throw CalendarError.notFound("Event with ID '\(identifier)' not found")
        }
        return event
    }

    func resolveReminder(_ identifier: String) throws -> EKReminder {
        guard let reminder = store.calendarItem(withIdentifier: identifier) as? EKReminder else {
            throw CalendarError.notFound("Reminder with ID '\(identifier)' not found")
        }
        return reminder
    }

    func resolveAnyCalendar(_ identifier: String) throws -> EKCalendar {
        guard let cal = store.calendars(for: .event).first(where: { $0.calendarIdentifier == identifier })
            ?? store.calendars(for: .reminder).first(where: { $0.calendarIdentifier == identifier })
        else {
            throw CalendarError.notFound("Calendar with ID '\(identifier)' not found")
        }
        return cal
    }

    func resolveCalendar(_ name: String, for entityType: EKEntityType) throws -> EKCalendar {
        guard let cal = store.calendars(for: entityType).first(where: { $0.title == name }) else {
            throw CalendarError.notFound("Calendar '\(name)' not found")
        }
        return cal
    }

    func resolveCalendars(_ names: [String], for entityType: EKEntityType) throws -> [EKCalendar] {
        let calendars = names.compactMap { name in
            store.calendars(for: entityType).first { $0.title == name }
        }
        if calendars.isEmpty {
            throw CalendarError.notFound("None of the specified calendars were found")
        }
        return calendars
    }

    func applyAlarms(_ minutes: [Int]?, to item: EKCalendarItem) {
        minutes?.forEach { item.addAlarm(EKAlarm(relativeOffset: TimeInterval(-$0 * 60))) }
    }

    func replaceAlarms(_ minutes: [Int]?, on item: EKCalendarItem) {
        guard let minutes else { return }
        item.alarms?.forEach { item.removeAlarm($0) }
        minutes.forEach { item.addAlarm(EKAlarm(relativeOffset: TimeInterval(-$0 * 60))) }
    }

    func applyRecurrence(_ recurrence: RecurrenceInput?, to item: EKCalendarItem) throws {
        guard let recurrence else { return }
        item.addRecurrenceRule(try recurrence.toEKRecurrenceRule())
    }

    func replaceRecurrence(_ recurrence: RecurrenceInput?, on item: EKCalendarItem) throws {
        guard let recurrence else { return }
        item.recurrenceRules?.forEach { item.removeRecurrenceRule($0) }
        item.addRecurrenceRule(try recurrence.toEKRecurrenceRule())
    }

    func dayBounds(for date: Date) -> (Date, Date) {
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        let end = cal.date(byAdding: .day, value: 1, to: start)!
        return (start, end)
    }

    func dateComponents(from date: Date) -> DateComponents {
        Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    }
}

// MARK: - Async Reminder Fetching

// EKEventStore.fetchReminders dispatches its completion handler on an internal queue.
// When called from @MainActor with withCheckedContinuation, the callback can deadlock
// because EventKit internally may need the main thread. We use Task.detached to ensure
// the continuation is set up off the main actor, preventing deadlock.
extension CalendarManager {
    func fetchReminders(matching predicate: NSPredicate) async -> [CalendarReminder] {
        let box = UnsafeSendableBox(store: store, predicate: predicate)
        return await Task.detached {
            await withCheckedContinuation { continuation in
                box.store.fetchReminders(matching: box.predicate) { reminders in
                    continuation.resume(returning: (reminders ?? []).map(CalendarReminder.from))
                }
            }
        }.value
    }
}

// EKEventStore.fetchReminders is documented as thread-safe. This box bypasses
// Sendable checks to allow calling it from a detached task.
private struct UnsafeSendableBox: @unchecked Sendable {
    let store: EKEventStore
    let predicate: NSPredicate
}
