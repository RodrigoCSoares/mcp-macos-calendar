import EventKit
import Foundation
import Logging

@MainActor
final class CalendarManager {
    private let store: EKEventStore
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

    // MARK: - Events

    func listEvents(from startDate: Date, to endDate: Date, calendarName: String? = nil) throws -> [CalendarEvent] {
        try ensureEventAccess()
        let calendars = try calendarName.map { try resolveCalendars([$0], for: .event) }
        let predicate = store.predicateForEvents(withStart: startDate, end: endDate, calendars: calendars)
        return store.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
            .map(CalendarEvent.from)
    }

    func getEvent(identifier: String) throws -> CalendarEvent {
        try ensureEventAccess()
        guard let event = store.event(withIdentifier: identifier) else {
            throw CalendarError.notFound("Event with ID '\(identifier)' not found")
        }
        return CalendarEvent.from(event)
    }

    func createEvent(_ input: CreateEventInput) throws -> CalendarEvent {
        try ensureEventAccess()
        let start = try parseISO8601(input.startDate, label: "start date")
        let end = try parseISO8601(input.endDate, label: "end date")

        let event = EKEvent(eventStore: store)
        event.title = input.title
        event.startDate = start
        event.endDate = end
        event.isAllDay = input.isAllDay ?? false
        input.location.map { event.location = $0 }
        input.notes.map { event.notes = $0 }
        input.url.flatMap(URL.init(string:)).map { event.url = $0 }
        event.calendar = try input.calendarName.map { try resolveCalendar($0, for: .event) }
            ?? store.defaultCalendarForNewEvents
        applyAlarms(input.alarmMinutesBefore, to: event)
        try applyRecurrence(input.recurrence, to: event)

        try store.save(event, span: .thisEvent, commit: true)
        logger.info("Created event: \(input.title)")
        return CalendarEvent.from(event)
    }

    func updateEvent(_ input: UpdateEventInput) throws -> CalendarEvent {
        try ensureEventAccess()
        guard let event = store.event(withIdentifier: input.eventId) else {
            throw CalendarError.notFound("Event with ID '\(input.eventId)' not found")
        }

        input.title.map { event.title = $0 }
        if let s = input.startDate { event.startDate = try parseISO8601(s, label: "start date") }
        if let e = input.endDate { event.endDate = try parseISO8601(e, label: "end date") }
        input.isAllDay.map { event.isAllDay = $0 }
        input.location.map { event.location = $0 }
        input.notes.map { event.notes = $0 }
        input.url.flatMap(URL.init(string:)).map { event.url = $0 }
        if let name = input.calendarName { event.calendar = try resolveCalendar(name, for: .event) }
        replaceAlarms(input.alarmMinutesBefore, on: event)
        try replaceRecurrence(input.recurrence, on: event)

        let span: EKSpan = (input.applyToFutureEvents == true) ? .futureEvents : .thisEvent
        try store.save(event, span: span, commit: true)
        logger.info("Updated event: \(event.title ?? "Unknown")")
        return CalendarEvent.from(event)
    }

    func deleteEvent(identifier: String, futureEvents: Bool = false) throws {
        try ensureEventAccess()
        guard let event = store.event(withIdentifier: identifier) else {
            throw CalendarError.notFound("Event with ID '\(identifier)' not found")
        }
        try store.remove(event, span: futureEvents ? .futureEvents : .thisEvent, commit: true)
        logger.info("Deleted event: \(event.title ?? "Unknown")")
    }

    func searchEvents(query: String, from startDate: Date, to endDate: Date, calendarName: String? = nil) throws -> [CalendarEvent] {
        try ensureEventAccess()
        let calendars = try calendarName.map { try resolveCalendars([$0], for: .event) }
        let predicate = store.predicateForEvents(withStart: startDate, end: endDate, calendars: calendars)
        let lowered = query.lowercased()
        return store.events(matching: predicate)
            .filter { event in
                [event.title, event.location, event.notes]
                    .compactMap { $0?.lowercased() }
                    .contains { $0.contains(lowered) }
            }
            .sorted { $0.startDate < $1.startDate }
            .map(CalendarEvent.from)
    }

    func listUpcomingEvents(count: Int, calendarName: String? = nil) throws -> [CalendarEvent] {
        try ensureEventAccess()
        let now = Date()
        let end = Calendar.current.date(byAdding: .year, value: 1, to: now)!
        let calendars = try calendarName.map { try resolveCalendars([$0], for: .event) }
        let predicate = store.predicateForEvents(withStart: now, end: end, calendars: calendars)
        return Array(
            store.events(matching: predicate)
                .sorted { $0.startDate < $1.startDate }
                .prefix(count)
                .map(CalendarEvent.from)
        )
    }

    func moveEvent(identifier: String, newStartDate: String, newEndDate: String?, applyToFutureEvents: Bool = false) throws -> CalendarEvent {
        try ensureEventAccess()
        guard let event = store.event(withIdentifier: identifier) else {
            throw CalendarError.notFound("Event with ID '\(identifier)' not found")
        }
        let newStart = try parseISO8601(newStartDate, label: "new start date")
        let duration = event.endDate.timeIntervalSince(event.startDate)
        event.startDate = newStart
        event.endDate = try newEndDate.map { try parseISO8601($0, label: "new end date") }
            ?? newStart.addingTimeInterval(duration)
        let span: EKSpan = applyToFutureEvents ? .futureEvents : .thisEvent
        try store.save(event, span: span, commit: true)
        logger.info("Moved event: \(event.title ?? "Unknown")")
        return CalendarEvent.from(event)
    }

    func duplicateEvent(identifier: String, newStartDate: String, newEndDate: String?) throws -> CalendarEvent {
        try ensureEventAccess()
        guard let source = store.event(withIdentifier: identifier) else {
            throw CalendarError.notFound("Event with ID '\(identifier)' not found")
        }
        let newStart = try parseISO8601(newStartDate, label: "new start date")
        let duration = source.endDate.timeIntervalSince(source.startDate)

        let event = EKEvent(eventStore: store)
        event.title = source.title
        event.startDate = newStart
        event.endDate = try newEndDate.map { try parseISO8601($0, label: "new end date") }
            ?? newStart.addingTimeInterval(duration)
        event.isAllDay = source.isAllDay
        event.location = source.location
        event.notes = source.notes
        event.url = source.url
        event.calendar = source.calendar
        source.alarms?.forEach { event.addAlarm(EKAlarm(relativeOffset: $0.relativeOffset)) }

        try store.save(event, span: .thisEvent, commit: true)
        logger.info("Duplicated event: \(source.title ?? "Unknown")")
        return CalendarEvent.from(event)
    }

    func listRecurringEvents(from startDate: Date, to endDate: Date, calendarName: String? = nil) throws -> [CalendarEvent] {
        try ensureEventAccess()
        let calendars = try calendarName.map { try resolveCalendars([$0], for: .event) }
        let predicate = store.predicateForEvents(withStart: startDate, end: endDate, calendars: calendars)
        return store.events(matching: predicate)
            .filter(\.hasRecurrenceRules)
            .sorted { $0.startDate < $1.startDate }
            .map(CalendarEvent.from)
    }

    func listTodayEvents(calendarName: String? = nil) throws -> [CalendarEvent] {
        let (start, end) = dayBounds(for: Date())
        return try listEvents(from: start, to: end, calendarName: calendarName)
    }

    func listTomorrowEvents(calendarName: String? = nil) throws -> [CalendarEvent] {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        let (start, end) = dayBounds(for: tomorrow)
        return try listEvents(from: start, to: end, calendarName: calendarName)
    }

    // MARK: - Reminders

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

        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: (reminders ?? []).map { CalendarReminder.from($0) })
            }
        }
    }

    func createReminder(_ input: CreateReminderInput) throws -> CalendarReminder {
        try ensureReminderAccess()
        let reminder = EKReminder(eventStore: store)
        reminder.title = input.title
        input.notes.map { reminder.notes = $0 }
        input.priority.map { reminder.priority = $0 }
        input.startDate.flatMap(parseISO8601Optional).map { reminder.startDateComponents = dateComponents(from: $0) }
        input.dueDate.flatMap(parseISO8601Optional).map { reminder.dueDateComponents = dateComponents(from: $0) }
        reminder.calendar = try input.calendarName.map { try resolveCalendar($0, for: .reminder) }
            ?? store.defaultCalendarForNewReminders()
        applyAlarms(input.alarmMinutesBefore, to: reminder)
        try applyRecurrence(input.recurrence, to: reminder)

        try store.save(reminder, commit: true)
        logger.info("Created reminder: \(input.title)")
        return CalendarReminder.from(reminder)
    }

    func updateReminder(_ input: UpdateReminderInput) throws -> CalendarReminder {
        try ensureReminderAccess()
        guard let reminder = store.calendarItem(withIdentifier: input.reminderId) as? EKReminder else {
            throw CalendarError.notFound("Reminder with ID '\(input.reminderId)' not found")
        }

        input.title.map { reminder.title = $0 }
        input.notes.map { reminder.notes = $0 }
        input.priority.map { reminder.priority = $0 }
        input.isCompleted.map { reminder.isCompleted = $0 }
        input.startDate.flatMap(parseISO8601Optional).map { reminder.startDateComponents = dateComponents(from: $0) }
        input.dueDate.flatMap(parseISO8601Optional).map { reminder.dueDateComponents = dateComponents(from: $0) }
        if let name = input.calendarName { reminder.calendar = try resolveCalendar(name, for: .reminder) }
        replaceAlarms(input.alarmMinutesBefore, on: reminder)
        try replaceRecurrence(input.recurrence, on: reminder)

        try store.save(reminder, commit: true)
        logger.info("Updated reminder: \(reminder.title ?? "Unknown")")
        return CalendarReminder.from(reminder)
    }

    func deleteReminder(identifier: String) throws {
        try ensureReminderAccess()
        guard let reminder = store.calendarItem(withIdentifier: identifier) as? EKReminder else {
            throw CalendarError.notFound("Reminder with ID '\(identifier)' not found")
        }
        try store.remove(reminder, commit: true)
        logger.info("Deleted reminder: \(reminder.title ?? "Unknown")")
    }

    func getReminder(identifier: String) throws -> CalendarReminder {
        try ensureReminderAccess()
        guard let reminder = store.calendarItem(withIdentifier: identifier) as? EKReminder else {
            throw CalendarError.notFound("Reminder with ID '\(identifier)' not found")
        }
        return CalendarReminder.from(reminder)
    }

    func searchReminders(query: String, calendarName: String? = nil) async throws -> [CalendarReminder] {
        try ensureReminderAccess()
        let calendars = try calendarName.map { try resolveCalendars([$0], for: .reminder) }
        let predicate = store.predicateForReminders(in: calendars)
        let lowered = query.lowercased()
        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                let results = (reminders ?? [])
                    .filter { r in
                        [r.title, r.notes]
                            .compactMap { $0?.lowercased() }
                            .contains { $0.contains(lowered) }
                    }
                    .map { CalendarReminder.from($0) }
                continuation.resume(returning: results)
            }
        }
    }

    func completeReminder(identifier: String) throws -> CalendarReminder {
        try ensureReminderAccess()
        guard let reminder = store.calendarItem(withIdentifier: identifier) as? EKReminder else {
            throw CalendarError.notFound("Reminder with ID '\(identifier)' not found")
        }
        reminder.isCompleted = true
        try store.save(reminder, commit: true)
        logger.info("Completed reminder: \(reminder.title ?? "Unknown")")
        return CalendarReminder.from(reminder)
    }

    func uncompleteReminder(identifier: String) throws -> CalendarReminder {
        try ensureReminderAccess()
        guard let reminder = store.calendarItem(withIdentifier: identifier) as? EKReminder else {
            throw CalendarError.notFound("Reminder with ID '\(identifier)' not found")
        }
        reminder.isCompleted = false
        try store.save(reminder, commit: true)
        logger.info("Uncompleted reminder: \(reminder.title ?? "Unknown")")
        return CalendarReminder.from(reminder)
    }

    func listOverdueReminders(calendarName: String? = nil) async throws -> [CalendarReminder] {
        try ensureReminderAccess()
        let calendars = try calendarName.map { try resolveCalendars([$0], for: .reminder) }
        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil, ending: Date(), calendars: calendars
        )
        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: (reminders ?? []).map { CalendarReminder.from($0) })
            }
        }
    }

    func batchCompleteReminders(identifiers: [String]) throws -> [CalendarReminder] {
        try ensureReminderAccess()
        let results = try identifiers.map { id -> CalendarReminder in
            guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else {
                throw CalendarError.notFound("Reminder with ID '\(id)' not found")
            }
            reminder.isCompleted = true
            try store.save(reminder, commit: false)
            return CalendarReminder.from(reminder)
        }
        try store.commit()
        logger.info("Batch completed \(identifiers.count) reminders")
        return results
    }

    // MARK: - Calendars

    func listCalendars(for entityType: EKEntityType) -> [CalendarInfo] {
        store.calendars(for: entityType).map(CalendarInfo.from)
    }

    func listSources() -> [SourceInfo] {
        store.sources.map(SourceInfo.from)
    }

    func createCalendar(title: String, sourceName: String, entityType: EKEntityType) throws -> CalendarInfo {
        try entityType == .event ? ensureEventAccess() : ensureReminderAccess()

        guard let source = store.sources.first(where: { $0.title == sourceName }) else {
            let available = store.sources.map(\.title).joined(separator: ", ")
            throw CalendarError.notFound("Source '\(sourceName)' not found. Available sources: \(available)")
        }

        let calendar = EKCalendar(for: entityType, eventStore: store)
        calendar.title = title
        calendar.source = source
        try store.saveCalendar(calendar, commit: true)
        logger.info("Created calendar: \(title)")
        return CalendarInfo.from(calendar)
    }

    func deleteCalendar(identifier: String) throws {
        let calendar = store.calendars(for: .event).first { $0.calendarIdentifier == identifier }
            ?? store.calendars(for: .reminder).first { $0.calendarIdentifier == identifier }
        guard let calendar else {
            throw CalendarError.notFound("Calendar with ID '\(identifier)' not found")
        }
        try store.removeCalendar(calendar, commit: true)
        logger.info("Deleted calendar: \(calendar.title)")
    }

    func getCalendar(identifier: String? = nil, name: String? = nil) throws -> CalendarInfo {
        let calendar: EKCalendar?
        if let identifier {
            calendar = store.calendars(for: .event).first { $0.calendarIdentifier == identifier }
                ?? store.calendars(for: .reminder).first { $0.calendarIdentifier == identifier }
        } else if let name {
            calendar = store.calendars(for: .event).first { $0.title == name }
                ?? store.calendars(for: .reminder).first { $0.title == name }
        } else {
            throw CalendarError.invalidInput("Either calendarId or calendarName must be provided")
        }
        guard let calendar else {
            throw CalendarError.notFound("Calendar not found")
        }
        return CalendarInfo.from(calendar)
    }

    func renameCalendar(identifier: String, newTitle: String) throws -> CalendarInfo {
        let calendar = store.calendars(for: .event).first { $0.calendarIdentifier == identifier }
            ?? store.calendars(for: .reminder).first { $0.calendarIdentifier == identifier }
        guard let calendar else {
            throw CalendarError.notFound("Calendar with ID '\(identifier)' not found")
        }
        guard calendar.allowsContentModifications else {
            throw CalendarError.operationFailed("Calendar '\(calendar.title)' is immutable")
        }
        let oldTitle = calendar.title
        calendar.title = newTitle
        try store.saveCalendar(calendar, commit: true)
        logger.info("Renamed calendar: \(oldTitle) -> \(newTitle)")
        return CalendarInfo.from(calendar)
    }

    // MARK: - Availability

    func checkAvailability(_ input: AvailabilityInput) throws -> AvailabilityResult {
        try ensureEventAccess()
        let start = try parseISO8601(input.startDate, label: "start date")
        let end = try parseISO8601(input.endDate, label: "end date")
        let calendars = try input.calendarNames.map { try resolveCalendars($0, for: .event) }
        let minimumSlot = TimeInterval((input.minimumSlotMinutes ?? 30) * 60)

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        let busyEvents = store.events(matching: predicate)
            .filter { $0.availability != .free }
            .sorted { $0.startDate < $1.startDate }

        let busyIntervals = mergeIntervals(busyEvents.map { (max($0.startDate, start), min($0.endDate, end)) })
        let busySlots = busyIntervals.map(TimeSlot.from)
        let freeSlots = gapSlots(in: start...end, excluding: busyIntervals, minimumDuration: minimumSlot)

        return AvailabilityResult(
            freeSlots: freeSlots,
            busySlots: busySlots,
            totalFreeMinutes: freeSlots.reduce(0) { $0 + $1.durationMinutes },
            totalBusyMinutes: busySlots.reduce(0) { $0 + $1.durationMinutes }
        )
    }
}

// MARK: - Private Helpers

private extension CalendarManager {

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

    func dateComponents(from date: Date) -> DateComponents {
        Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    }

    func applyAlarms(_ minutes: [Int]?, to item: EKCalendarItem) {
        minutes?.forEach { item.addAlarm(EKAlarm(relativeOffset: TimeInterval(-$0 * 60))) }
    }

    func applyRecurrence(_ recurrence: RecurrenceInput?, to item: EKCalendarItem) throws {
        guard let recurrence else { return }
        item.addRecurrenceRule(try recurrence.toEKRecurrenceRule())
    }

    func replaceAlarms(_ minutes: [Int]?, on item: EKCalendarItem) {
        guard let minutes else { return }
        item.alarms?.forEach { item.removeAlarm($0) }
        minutes.forEach { item.addAlarm(EKAlarm(relativeOffset: TimeInterval(-$0 * 60))) }
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
}

// MARK: - Date Parsing

@MainActor
private enum ISO8601 {
    static let flexible: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static let standard = ISO8601DateFormatter()

    static func parse(_ string: String) -> Date? {
        flexible.date(from: string) ?? standard.date(from: string)
    }
}

@MainActor
private func parseISO8601(_ string: String, label: String) throws -> Date {
    guard let date = ISO8601.parse(string) else {
        throw CalendarError.invalidInput("Invalid \(label): \(string)")
    }
    return date
}

@MainActor
private func parseISO8601Optional(_ string: String) -> Date? {
    ISO8601.parse(string)
}

// MARK: - Interval Merging

private func mergeIntervals(_ intervals: [(Date, Date)]) -> [(Date, Date)] {
    intervals.reduce(into: []) { merged, interval in
        if let last = merged.last, interval.0 <= last.1 {
            merged[merged.count - 1].1 = max(last.1, interval.1)
        } else {
            merged.append(interval)
        }
    }
}

private func gapSlots(in range: ClosedRange<Date>, excluding busy: [(Date, Date)], minimumDuration: TimeInterval) -> [TimeSlot] {
    var cursor = range.lowerBound
    var slots: [TimeSlot] = []

    for interval in busy {
        let gap = interval.0.timeIntervalSince(cursor)
        if interval.0 > cursor && gap >= minimumDuration {
            slots.append(TimeSlot.from((cursor, interval.0)))
        }
        cursor = max(cursor, interval.1)
    }

    let trailing = range.upperBound.timeIntervalSince(cursor)
    if range.upperBound > cursor && trailing >= minimumDuration {
        slots.append(TimeSlot.from((cursor, range.upperBound)))
    }

    return slots
}

private extension TimeSlot {
    static func from(_ interval: (Date, Date)) -> TimeSlot {
        TimeSlot(
            startDate: interval.0,
            endDate: interval.1,
            durationMinutes: Int(interval.1.timeIntervalSince(interval.0) / 60)
        )
    }
}
