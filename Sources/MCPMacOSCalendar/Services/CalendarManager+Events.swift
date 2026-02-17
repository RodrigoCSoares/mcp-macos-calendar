import CoreLocation
import EventKit
import Foundation

// MARK: - Event Operations

extension CalendarManager {

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
        return CalendarEvent.from(try resolveEvent(identifier))
    }

    func createEvent(_ input: CreateEventInput) throws -> CalendarEvent {
        try ensureEventAccess()
        let start = try ISO8601Parsing.require(input.startDate, label: "start date")
        let end = try ISO8601Parsing.require(input.endDate, label: "end date")

        let event = EKEvent(eventStore: store)
        event.title = input.title
        event.startDate = start
        event.endDate = end
        event.isAllDay = input.isAllDay ?? false
        input.location.map { event.location = $0 }
        input.structuredLocation.map { event.structuredLocation = $0.toEKStructuredLocation() }
        input.notes.map { event.notes = $0 }
        input.url.flatMap(URL.init(string:)).map { event.url = $0 }
        event.calendar = try input.calendarName.map { try resolveCalendar($0, for: .event) }
            ?? store.defaultCalendarForNewEvents
        applyAlarms(input.alarmMinutesBefore, to: event)
        try applyRecurrence(input.recurrence, to: event)

        try store.save(event, span: .thisEvent, commit: true)
        return CalendarEvent.from(event)
    }

    func updateEvent(_ input: UpdateEventInput) throws -> CalendarEvent {
        try ensureEventAccess()
        let event = try resolveEvent(input.eventId)

        input.title.map { event.title = $0 }
        if let s = input.startDate { event.startDate = try ISO8601Parsing.require(s, label: "start date") }
        if let e = input.endDate { event.endDate = try ISO8601Parsing.require(e, label: "end date") }
        input.isAllDay.map { event.isAllDay = $0 }
        input.location.map { event.location = $0 }
        input.structuredLocation.map { event.structuredLocation = $0.toEKStructuredLocation() }
        input.notes.map { event.notes = $0 }
        input.url.flatMap(URL.init(string:)).map { event.url = $0 }
        if let name = input.calendarName { event.calendar = try resolveCalendar(name, for: .event) }
        replaceAlarms(input.alarmMinutesBefore, on: event)
        try replaceRecurrence(input.recurrence, on: event)

        let span: EKSpan = (input.applyToFutureEvents == true) ? .futureEvents : .thisEvent
        try store.save(event, span: span, commit: true)
        return CalendarEvent.from(event)
    }

    func deleteEvent(identifier: String, futureEvents: Bool = false) throws {
        try ensureEventAccess()
        let event = try resolveEvent(identifier)
        try store.remove(event, span: futureEvents ? .futureEvents : .thisEvent, commit: true)
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
        let event = try resolveEvent(identifier)
        let newStart = try ISO8601Parsing.require(newStartDate, label: "new start date")
        let duration = event.endDate.timeIntervalSince(event.startDate)
        event.startDate = newStart
        event.endDate = try newEndDate.map { try ISO8601Parsing.require($0, label: "new end date") }
            ?? newStart.addingTimeInterval(duration)
        let span: EKSpan = applyToFutureEvents ? .futureEvents : .thisEvent
        try store.save(event, span: span, commit: true)
        return CalendarEvent.from(event)
    }

    func duplicateEvent(identifier: String, newStartDate: String, newEndDate: String?) throws -> CalendarEvent {
        try ensureEventAccess()
        let source = try resolveEvent(identifier)
        let newStart = try ISO8601Parsing.require(newStartDate, label: "new start date")
        let duration = source.endDate.timeIntervalSince(source.startDate)

        let event = EKEvent(eventStore: store)
        event.title = source.title
        event.startDate = newStart
        event.endDate = try newEndDate.map { try ISO8601Parsing.require($0, label: "new end date") }
            ?? newStart.addingTimeInterval(duration)
        event.isAllDay = source.isAllDay
        event.location = source.location
        event.notes = source.notes
        event.url = source.url
        event.calendar = source.calendar
        source.alarms?.forEach { event.addAlarm(EKAlarm(relativeOffset: $0.relativeOffset)) }

        try store.save(event, span: .thisEvent, commit: true)
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

    func listEventsRelative(daysFromNow: Int, calendarName: String? = nil) throws -> [CalendarEvent] {
        let target = Calendar.current.date(byAdding: .day, value: daysFromNow, to: Date())!
        let (start, end) = dayBounds(for: target)
        return try listEvents(from: start, to: end, calendarName: calendarName)
    }
}
