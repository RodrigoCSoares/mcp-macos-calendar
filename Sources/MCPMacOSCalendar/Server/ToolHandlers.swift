import EventKit
import Foundation
import MCP

// MARK: - Event Tool Handlers

extension CalendarMCPServer {

    func handleListEvents(_ data: Data) throws -> [CalendarEvent] {
        let input = try decoder.decode(DateRangeInput.self, from: data)
        let (start, end) = try ISO8601Parsing.parseDateRange(start: input.startDate, end: input.endDate)
        return try calendarManager.listEvents(from: start, to: end, calendarName: input.calendarName)
    }

    func handleGetEvent(_ data: Data) throws -> CalendarEvent {
        try calendarManager.getEvent(identifier: decoder.decode(EventIdInput.self, from: data).eventId)
    }

    func handleCreateEvent(_ data: Data) throws -> CalendarEvent {
        try calendarManager.createEvent(decoder.decode(CreateEventInput.self, from: data))
    }

    func handleUpdateEvent(_ data: Data) throws -> CalendarEvent {
        try calendarManager.updateEvent(decoder.decode(UpdateEventInput.self, from: data))
    }

    func handleDeleteEvent(_ data: Data) throws -> String {
        struct Input: Decodable { let eventId: String; let deleteFutureEvents: Bool? }
        let input = try decoder.decode(Input.self, from: data)
        try calendarManager.deleteEvent(identifier: input.eventId, futureEvents: input.deleteFutureEvents ?? false)
        return "Event deleted successfully."
    }

    func handleSearchEvents(_ data: Data) throws -> [CalendarEvent] {
        struct Input: Decodable { let query: String; let startDate: String; let endDate: String; let calendarName: String? }
        let input = try decoder.decode(Input.self, from: data)
        let (start, end) = try ISO8601Parsing.parseDateRange(start: input.startDate, end: input.endDate)
        return try calendarManager.searchEvents(query: input.query, from: start, to: end, calendarName: input.calendarName)
    }

    func handleListUpcoming(_ data: Data) throws -> [CalendarEvent] {
        struct Input: Decodable { let count: Int?; let calendarName: String? }
        let input = try decoder.decode(Input.self, from: data)
        return try calendarManager.listUpcomingEvents(count: input.count ?? 10, calendarName: input.calendarName)
    }

    func handleMoveEvent(_ data: Data) throws -> CalendarEvent {
        struct Input: Decodable { let eventId: String; let newStartDate: String; let newEndDate: String?; let applyToFutureEvents: Bool? }
        let input = try decoder.decode(Input.self, from: data)
        return try calendarManager.moveEvent(
            identifier: input.eventId, newStartDate: input.newStartDate,
            newEndDate: input.newEndDate, applyToFutureEvents: input.applyToFutureEvents ?? false
        )
    }

    func handleDuplicateEvent(_ data: Data) throws -> CalendarEvent {
        struct Input: Decodable { let eventId: String; let newStartDate: String; let newEndDate: String? }
        let input = try decoder.decode(Input.self, from: data)
        return try calendarManager.duplicateEvent(identifier: input.eventId, newStartDate: input.newStartDate, newEndDate: input.newEndDate)
    }

    func handleListRecurringEvents(_ data: Data) throws -> [CalendarEvent] {
        let input = try decoder.decode(DateRangeInput.self, from: data)
        let (start, end) = try ISO8601Parsing.parseDateRange(start: input.startDate, end: input.endDate)
        return try calendarManager.listRecurringEvents(from: start, to: end, calendarName: input.calendarName)
    }

    func handleToday(_ data: Data) throws -> [CalendarEvent] {
        let input = try decoder.decode(CalendarNameInput.self, from: data)
        return try calendarManager.listEventsRelative(daysFromNow: 0, calendarName: input.calendarName)
    }

    func handleTomorrow(_ data: Data) throws -> [CalendarEvent] {
        let input = try decoder.decode(CalendarNameInput.self, from: data)
        return try calendarManager.listEventsRelative(daysFromNow: 1, calendarName: input.calendarName)
    }
}

// MARK: - Reminder Tool Handlers

extension CalendarMCPServer {

    func handleListReminders(_ data: Data) async throws -> [CalendarReminder] {
        struct Input: Decodable { let calendarName: String?; let filter: String?; let startDate: String?; let endDate: String? }
        let input = try decoder.decode(Input.self, from: data)

        let reminderFilter: ReminderFilter = switch input.filter {
        case "incomplete":
            .incomplete(start: input.startDate.flatMap(ISO8601Parsing.parse), end: input.endDate.flatMap(ISO8601Parsing.parse))
        case "completed":
            .completed(start: input.startDate.flatMap(ISO8601Parsing.parse), end: input.endDate.flatMap(ISO8601Parsing.parse))
        default:
            .all
        }

        return try await calendarManager.listReminders(calendarName: input.calendarName, filter: reminderFilter)
    }

    func handleCreateReminder(_ data: Data) throws -> CalendarReminder {
        try calendarManager.createReminder(decoder.decode(CreateReminderInput.self, from: data))
    }

    func handleUpdateReminder(_ data: Data) throws -> CalendarReminder {
        try calendarManager.updateReminder(decoder.decode(UpdateReminderInput.self, from: data))
    }

    func handleDeleteReminder(_ data: Data) throws -> String {
        try calendarManager.deleteReminder(identifier: decoder.decode(ReminderIdInput.self, from: data).reminderId)
        return "Reminder deleted successfully."
    }

    func handleGetReminder(_ data: Data) throws -> CalendarReminder {
        try calendarManager.getReminder(identifier: decoder.decode(ReminderIdInput.self, from: data).reminderId)
    }

    func handleSearchReminders(_ data: Data) async throws -> [CalendarReminder] {
        struct Input: Decodable { let query: String; let calendarName: String? }
        let input = try decoder.decode(Input.self, from: data)
        return try await calendarManager.searchReminders(query: input.query, calendarName: input.calendarName)
    }

    func handleCompleteReminder(_ data: Data) throws -> CalendarReminder {
        try calendarManager.setReminderCompletion(
            identifier: decoder.decode(ReminderIdInput.self, from: data).reminderId, completed: true
        )
    }

    func handleUncompleteReminder(_ data: Data) throws -> CalendarReminder {
        try calendarManager.setReminderCompletion(
            identifier: decoder.decode(ReminderIdInput.self, from: data).reminderId, completed: false
        )
    }

    func handleListOverdueReminders(_ data: Data) async throws -> [CalendarReminder] {
        let input = try decoder.decode(CalendarNameInput.self, from: data)
        return try await calendarManager.listOverdueReminders(calendarName: input.calendarName)
    }

    func handleBatchCompleteReminders(_ data: Data) throws -> [CalendarReminder] {
        struct Input: Decodable { let reminderIds: [String] }
        return try calendarManager.batchCompleteReminders(identifiers: decoder.decode(Input.self, from: data).reminderIds)
    }
}

// MARK: - Calendar & Source Tool Handlers

extension CalendarMCPServer {

    func handleListCalendars(_ data: Data) throws -> [CalendarInfo] {
        struct Input: Decodable { let type: String? }
        return switch try decoder.decode(Input.self, from: data).type {
        case "event": calendarManager.listCalendars(for: .event)
        case "reminder": calendarManager.listCalendars(for: .reminder)
        default: calendarManager.listCalendars(for: .event) + calendarManager.listCalendars(for: .reminder)
        }
    }

    func handleGetCalendar(_ data: Data) throws -> CalendarInfo {
        struct Input: Decodable { let calendarId: String?; let calendarName: String? }
        let input = try decoder.decode(Input.self, from: data)
        return try calendarManager.getCalendar(identifier: input.calendarId, name: input.calendarName)
    }

    func handleCreateCalendar(_ data: Data) throws -> CalendarInfo {
        struct Input: Decodable { let title: String; let sourceName: String; let type: String? }
        let input = try decoder.decode(Input.self, from: data)
        let entityType: EKEntityType = (input.type == "reminder") ? .reminder : .event
        return try calendarManager.createCalendar(title: input.title, sourceName: input.sourceName, entityType: entityType)
    }

    func handleDeleteCalendar(_ data: Data) throws -> String {
        struct Input: Decodable { let calendarId: String }
        try calendarManager.deleteCalendar(identifier: decoder.decode(Input.self, from: data).calendarId)
        return "Calendar deleted successfully."
    }

    func handleRenameCalendar(_ data: Data) throws -> CalendarInfo {
        struct Input: Decodable { let calendarId: String; let newTitle: String }
        let input = try decoder.decode(Input.self, from: data)
        return try calendarManager.renameCalendar(identifier: input.calendarId, newTitle: input.newTitle)
    }

    func handleListSources() -> [SourceInfo] {
        calendarManager.listSources()
    }

    func handleCheckAvailability(_ data: Data) throws -> AvailabilityResult {
        try calendarManager.checkAvailability(decoder.decode(AvailabilityInput.self, from: data))
    }
}
