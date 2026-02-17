import EventKit
import Foundation
import Logging
import MCP

@MainActor
final class CalendarMCPServer {
    let server: Server
    let calendarManager: CalendarManager
    private let logger: Logger
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(logger: Logger = Logger(label: "mcp-macos-calendar.server")) {
        self.logger = logger
        self.calendarManager = CalendarManager(logger: logger)

        self.encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        self.decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        self.server = Server(
            name: "mcp-macos-calendar",
            version: "1.0.0",
            capabilities: .init(
                resources: .init(subscribe: false, listChanged: false),
                tools: .init(listChanged: false)
            )
        )
    }

    func start(transport: any Transport) async throws {
        try await calendarManager.requestEventAccess()
        do { try await calendarManager.requestReminderAccess() }
        catch { logger.warning("Reminder access not granted: \(error)") }

        await registerHandlers()
        logger.info("MCP Calendar server starting...")
        try await server.start(transport: transport)
        await server.waitUntilCompleted()
    }

    // MARK: - Handler Registration

    private func registerHandlers() async {
        let mcpServer = self

        await server.withMethodHandler(ListTools.self) { @Sendable _ in
            .init(tools: await mcpServer.toolDefinitions)
        }

        await server.withMethodHandler(CallTool.self) { @Sendable params in
            await mcpServer.dispatchTool(params)
        }

        await server.withMethodHandler(ListResources.self) { @Sendable _ in
            .init(resources: [
                Resource(name: "Event Calendars", uri: "calendars://event-calendars",
                         description: "List of all event calendars", mimeType: "application/json"),
                Resource(name: "Reminder Lists", uri: "calendars://reminder-lists",
                         description: "List of all reminder calendars/lists", mimeType: "application/json"),
                Resource(name: "Calendar Sources", uri: "calendars://sources",
                         description: "Available calendar sources (iCloud, Exchange, Local, etc.)", mimeType: "application/json"),
            ])
        }

        await server.withMethodHandler(ReadResource.self) { @Sendable params in
            try await mcpServer.readResource(params)
        }
    }

    // MARK: - Tool Dispatch

    private func dispatchTool(_ params: CallTool.Parameters) async -> CallTool.Result {
        do {
            let args = try JSONEncoder().encode(params.arguments ?? [:])

            switch params.name {
            case "list_events":       return try encodeResult(handleListEvents(args))
            case "get_event":         return try encodeResult(handleGetEvent(args))
            case "create_event":      return try encodeResult(handleCreateEvent(args), prefix: "Event created successfully:")
            case "update_event":      return try encodeResult(handleUpdateEvent(args), prefix: "Event updated successfully:")
            case "delete_event":      return try textResult(handleDeleteEvent(args))
            case "search_events":     return try encodeResult(handleSearchEvents(args))
            case "list_upcoming":     return try encodeResult(handleListUpcoming(args))
            case "move_event":        return try encodeResult(handleMoveEvent(args), prefix: "Event moved successfully:")
            case "duplicate_event":   return try encodeResult(handleDuplicateEvent(args), prefix: "Event duplicated successfully:")
            case "list_recurring_events": return try encodeResult(handleListRecurringEvents(args))
            case "today":             return try encodeResult(handleToday(args))
            case "tomorrow":          return try encodeResult(handleTomorrow(args))
            case "list_reminders":    return try await encodeResult(handleListReminders(args))
            case "get_reminder":      return try encodeResult(handleGetReminder(args))
            case "create_reminder":   return try encodeResult(handleCreateReminder(args), prefix: "Reminder created:")
            case "update_reminder":   return try encodeResult(handleUpdateReminder(args), prefix: "Reminder updated:")
            case "delete_reminder":   return try textResult(handleDeleteReminder(args))
            case "search_reminders":  return try await encodeResult(handleSearchReminders(args))
            case "complete_reminder": return try encodeResult(handleCompleteReminder(args), prefix: "Reminder completed:")
            case "uncomplete_reminder": return try encodeResult(handleUncompleteReminder(args), prefix: "Reminder uncompleted:")
            case "list_overdue_reminders": return try await encodeResult(handleListOverdueReminders(args))
            case "batch_complete_reminders": return try encodeResult(handleBatchCompleteReminders(args), prefix: "Reminders completed:")
            case "list_calendars":    return try encodeResult(handleListCalendars(args))
            case "get_calendar":      return try encodeResult(handleGetCalendar(args))
            case "create_calendar":   return try encodeResult(handleCreateCalendar(args), prefix: "Calendar created:")
            case "delete_calendar":   return try textResult(handleDeleteCalendar(args))
            case "rename_calendar":   return try encodeResult(handleRenameCalendar(args), prefix: "Calendar renamed:")
            case "list_sources":      return try encodeResult(handleListSources())
            case "check_availability": return try encodeResult(handleCheckAvailability(args))
            default:
                return .init(content: [.text("Unknown tool: \(params.name)")], isError: true)
            }
        } catch {
            return .init(content: [.text("Error: \(error.localizedDescription)")], isError: true)
        }
    }

    // MARK: - Result Encoding

    private func encodeResult<T: Encodable>(_ value: T, prefix: String? = nil) throws -> CallTool.Result {
        let json = String(data: try encoder.encode(value), encoding: .utf8) ?? "{}"
        let text = prefix.map { "\($0)\n\(json)" } ?? json
        return .init(content: [.text(text)])
    }

    private func textResult(_ message: String) -> CallTool.Result {
        .init(content: [.text(message)])
    }

    // MARK: - Event Handlers

    private func handleListEvents(_ data: Data) throws -> [CalendarEvent] {
        struct Input: Decodable { let startDate: String; let endDate: String; let calendarName: String? }
        let input = try decoder.decode(Input.self, from: data)
        let formatter = ISO8601DateFormatter()
        guard let start = formatter.date(from: input.startDate) else { throw CalendarError.invalidInput("Invalid startDate") }
        guard let end = formatter.date(from: input.endDate) else { throw CalendarError.invalidInput("Invalid endDate") }
        return try calendarManager.listEvents(from: start, to: end, calendarName: input.calendarName)
    }

    private func handleGetEvent(_ data: Data) throws -> CalendarEvent {
        struct Input: Decodable { let eventId: String }
        return try calendarManager.getEvent(identifier: decoder.decode(Input.self, from: data).eventId)
    }

    private func handleCreateEvent(_ data: Data) throws -> CalendarEvent {
        try calendarManager.createEvent(decoder.decode(CreateEventInput.self, from: data))
    }

    private func handleUpdateEvent(_ data: Data) throws -> CalendarEvent {
        try calendarManager.updateEvent(decoder.decode(UpdateEventInput.self, from: data))
    }

    private func handleDeleteEvent(_ data: Data) throws -> String {
        struct Input: Decodable { let eventId: String; let deleteFutureEvents: Bool? }
        let input = try decoder.decode(Input.self, from: data)
        try calendarManager.deleteEvent(identifier: input.eventId, futureEvents: input.deleteFutureEvents ?? false)
        return "Event deleted successfully."
    }

    // MARK: - Reminder Handlers

    private func handleListReminders(_ data: Data) async throws -> [CalendarReminder] {
        struct Input: Decodable { let calendarName: String?; let filter: String?; let startDate: String?; let endDate: String? }
        let input = try decoder.decode(Input.self, from: data)
        let formatter = ISO8601DateFormatter()

        let reminderFilter: ReminderFilter = switch input.filter {
        case "incomplete":
            .incomplete(start: input.startDate.flatMap(formatter.date), end: input.endDate.flatMap(formatter.date))
        case "completed":
            .completed(start: input.startDate.flatMap(formatter.date), end: input.endDate.flatMap(formatter.date))
        default:
            .all
        }

        return try await calendarManager.listReminders(calendarName: input.calendarName, filter: reminderFilter)
    }

    private func handleCreateReminder(_ data: Data) throws -> CalendarReminder {
        try calendarManager.createReminder(decoder.decode(CreateReminderInput.self, from: data))
    }

    private func handleUpdateReminder(_ data: Data) throws -> CalendarReminder {
        try calendarManager.updateReminder(decoder.decode(UpdateReminderInput.self, from: data))
    }

    private func handleDeleteReminder(_ data: Data) throws -> String {
        struct Input: Decodable { let reminderId: String }
        try calendarManager.deleteReminder(identifier: decoder.decode(Input.self, from: data).reminderId)
        return "Reminder deleted successfully."
    }

    // MARK: - Calendar Handlers

    private func handleListCalendars(_ data: Data) throws -> [CalendarInfo] {
        struct Input: Decodable { let type: String? }
        return switch try decoder.decode(Input.self, from: data).type {
        case "event": calendarManager.listCalendars(for: .event)
        case "reminder": calendarManager.listCalendars(for: .reminder)
        default: calendarManager.listCalendars(for: .event) + calendarManager.listCalendars(for: .reminder)
        }
    }

    private func handleCreateCalendar(_ data: Data) throws -> CalendarInfo {
        struct Input: Decodable { let title: String; let sourceName: String; let type: String? }
        let input = try decoder.decode(Input.self, from: data)
        let entityType: EKEntityType = (input.type == "reminder") ? .reminder : .event
        return try calendarManager.createCalendar(title: input.title, sourceName: input.sourceName, entityType: entityType)
    }

    private func handleDeleteCalendar(_ data: Data) throws -> String {
        struct Input: Decodable { let calendarId: String }
        try calendarManager.deleteCalendar(identifier: decoder.decode(Input.self, from: data).calendarId)
        return "Calendar deleted successfully."
    }

    // MARK: - New Event Handlers

    private func handleSearchEvents(_ data: Data) throws -> [CalendarEvent] {
        struct Input: Decodable { let query: String; let startDate: String; let endDate: String; let calendarName: String? }
        let input = try decoder.decode(Input.self, from: data)
        let formatter = ISO8601DateFormatter()
        guard let start = formatter.date(from: input.startDate) else { throw CalendarError.invalidInput("Invalid startDate") }
        guard let end = formatter.date(from: input.endDate) else { throw CalendarError.invalidInput("Invalid endDate") }
        return try calendarManager.searchEvents(query: input.query, from: start, to: end, calendarName: input.calendarName)
    }

    private func handleListUpcoming(_ data: Data) throws -> [CalendarEvent] {
        struct Input: Decodable { let count: Int?; let calendarName: String? }
        let input = try decoder.decode(Input.self, from: data)
        return try calendarManager.listUpcomingEvents(count: input.count ?? 10, calendarName: input.calendarName)
    }

    private func handleMoveEvent(_ data: Data) throws -> CalendarEvent {
        struct Input: Decodable { let eventId: String; let newStartDate: String; let newEndDate: String?; let applyToFutureEvents: Bool? }
        let input = try decoder.decode(Input.self, from: data)
        return try calendarManager.moveEvent(
            identifier: input.eventId, newStartDate: input.newStartDate,
            newEndDate: input.newEndDate, applyToFutureEvents: input.applyToFutureEvents ?? false
        )
    }

    private func handleDuplicateEvent(_ data: Data) throws -> CalendarEvent {
        struct Input: Decodable { let eventId: String; let newStartDate: String; let newEndDate: String? }
        let input = try decoder.decode(Input.self, from: data)
        return try calendarManager.duplicateEvent(identifier: input.eventId, newStartDate: input.newStartDate, newEndDate: input.newEndDate)
    }

    private func handleListRecurringEvents(_ data: Data) throws -> [CalendarEvent] {
        struct Input: Decodable { let startDate: String; let endDate: String; let calendarName: String? }
        let input = try decoder.decode(Input.self, from: data)
        let formatter = ISO8601DateFormatter()
        guard let start = formatter.date(from: input.startDate) else { throw CalendarError.invalidInput("Invalid startDate") }
        guard let end = formatter.date(from: input.endDate) else { throw CalendarError.invalidInput("Invalid endDate") }
        return try calendarManager.listRecurringEvents(from: start, to: end, calendarName: input.calendarName)
    }

    private func handleToday(_ data: Data) throws -> [CalendarEvent] {
        struct Input: Decodable { let calendarName: String? }
        let input = try decoder.decode(Input.self, from: data)
        return try calendarManager.listTodayEvents(calendarName: input.calendarName)
    }

    private func handleTomorrow(_ data: Data) throws -> [CalendarEvent] {
        struct Input: Decodable { let calendarName: String? }
        let input = try decoder.decode(Input.self, from: data)
        return try calendarManager.listTomorrowEvents(calendarName: input.calendarName)
    }

    // MARK: - New Reminder Handlers

    private func handleGetReminder(_ data: Data) throws -> CalendarReminder {
        struct Input: Decodable { let reminderId: String }
        return try calendarManager.getReminder(identifier: decoder.decode(Input.self, from: data).reminderId)
    }

    private func handleSearchReminders(_ data: Data) async throws -> [CalendarReminder] {
        struct Input: Decodable { let query: String; let calendarName: String? }
        let input = try decoder.decode(Input.self, from: data)
        return try await calendarManager.searchReminders(query: input.query, calendarName: input.calendarName)
    }

    private func handleCompleteReminder(_ data: Data) throws -> CalendarReminder {
        struct Input: Decodable { let reminderId: String }
        return try calendarManager.completeReminder(identifier: decoder.decode(Input.self, from: data).reminderId)
    }

    private func handleUncompleteReminder(_ data: Data) throws -> CalendarReminder {
        struct Input: Decodable { let reminderId: String }
        return try calendarManager.uncompleteReminder(identifier: decoder.decode(Input.self, from: data).reminderId)
    }

    private func handleListOverdueReminders(_ data: Data) async throws -> [CalendarReminder] {
        struct Input: Decodable { let calendarName: String? }
        let input = try decoder.decode(Input.self, from: data)
        return try await calendarManager.listOverdueReminders(calendarName: input.calendarName)
    }

    private func handleBatchCompleteReminders(_ data: Data) throws -> [CalendarReminder] {
        struct Input: Decodable { let reminderIds: [String] }
        return try calendarManager.batchCompleteReminders(identifiers: decoder.decode(Input.self, from: data).reminderIds)
    }

    // MARK: - New Calendar Handlers

    private func handleGetCalendar(_ data: Data) throws -> CalendarInfo {
        struct Input: Decodable { let calendarId: String?; let calendarName: String? }
        let input = try decoder.decode(Input.self, from: data)
        return try calendarManager.getCalendar(identifier: input.calendarId, name: input.calendarName)
    }

    private func handleRenameCalendar(_ data: Data) throws -> CalendarInfo {
        struct Input: Decodable { let calendarId: String; let newTitle: String }
        let input = try decoder.decode(Input.self, from: data)
        return try calendarManager.renameCalendar(identifier: input.calendarId, newTitle: input.newTitle)
    }

    private func handleListSources() throws -> [SourceInfo] {
        calendarManager.listSources()
    }

    // MARK: - Availability

    private func handleCheckAvailability(_ data: Data) throws -> AvailabilityResult {
        try calendarManager.checkAvailability(decoder.decode(AvailabilityInput.self, from: data))
    }

    // MARK: - Resources

    private func readResource(_ params: ReadResource.Parameters) throws -> ReadResource.Result {
        let (data, uri): (Encodable, String) = switch params.uri {
        case "calendars://event-calendars":
            (calendarManager.listCalendars(for: .event), params.uri)
        case "calendars://reminder-lists":
            (calendarManager.listCalendars(for: .reminder), params.uri)
        case "calendars://sources":
            (calendarManager.listSources(), params.uri)
        default:
            throw MCPError.invalidRequest("Unknown resource URI: \(params.uri)")
        }

        let json = String(data: try encoder.encode(data), encoding: .utf8) ?? "[]"
        return .init(contents: [.text(json, uri: uri, mimeType: "application/json")])
    }
}

// MARK: - Tool Definitions

extension CalendarMCPServer {
    var toolDefinitions: [Tool] {
        [
            tool("list_events",
                 "List calendar events within a date range. Returns event details including title, time, location, and attendees.",
                 properties: [
                    "startDate": stringProp("Start of date range in ISO 8601 format"),
                    "endDate": stringProp("End of date range in ISO 8601 format"),
                    "calendarName": stringProp("Optional: filter to a specific calendar by name"),
                 ],
                 required: ["startDate", "endDate"]),

            tool("get_event",
                 "Get detailed information about a specific event by its ID, including attendees and recurrence info.",
                 properties: ["eventId": stringProp("The unique identifier of the event")],
                 required: ["eventId"]),

            tool("create_event",
                 "Create a new calendar event with title, time, location, notes, URL, alarms, recurrence rules, and target calendar.",
                 properties: [
                    "title": stringProp("Event title"),
                    "startDate": stringProp("Start time in ISO 8601 format"),
                    "endDate": stringProp("End time in ISO 8601 format"),
                    "isAllDay": boolProp("Whether this is an all-day event (default false)"),
                    "location": stringProp("Event location"),
                    "notes": stringProp("Event notes/description"),
                    "url": stringProp("URL associated with the event"),
                    "calendarName": stringProp("Target calendar name. Uses default if not specified."),
                    "alarmMinutesBefore": intArrayProp("Minutes before the event to trigger alarms (e.g. [15, 60])"),
                    "recurrence": recurrenceSchema,
                 ],
                 required: ["title", "startDate", "endDate"]),

            tool("update_event",
                 "Update an existing calendar event. Only specify fields you want to change.",
                 properties: [
                    "eventId": stringProp("The unique identifier of the event to update"),
                    "title": stringProp("New event title"),
                    "startDate": stringProp("New start time in ISO 8601 format"),
                    "endDate": stringProp("New end time in ISO 8601 format"),
                    "isAllDay": boolProp("Whether this is an all-day event"),
                    "location": stringProp("New event location"),
                    "notes": stringProp("New event notes"),
                    "url": stringProp("New URL"),
                    "calendarName": stringProp("Move event to this calendar"),
                    "alarmMinutesBefore": intArrayProp("Replace alarms with these minute offsets"),
                    "recurrence": recurrenceSchema,
                    "applyToFutureEvents": boolProp("For recurring events: apply to future occurrences (default false)"),
                 ],
                 required: ["eventId"]),

            tool("delete_event",
                 "Delete a calendar event by its ID. For recurring events, can optionally delete all future occurrences.",
                 properties: [
                    "eventId": stringProp("The unique identifier of the event to delete"),
                    "deleteFutureEvents": boolProp("Also delete all future occurrences (default false)"),
                 ],
                 required: ["eventId"]),

            tool("list_reminders",
                 "List reminders from the Reminders app. Filter by list, status (all/incomplete/completed), and date range.",
                 properties: [
                    "calendarName": stringProp("Filter to a specific reminder list by name"),
                    "filter": enumProp(["all", "incomplete", "completed"], "Filter by status (default: all)"),
                    "startDate": stringProp("Start of date range (ISO 8601)"),
                    "endDate": stringProp("End of date range (ISO 8601)"),
                 ]),

            tool("create_reminder",
                 "Create a new reminder with title, notes, dates, priority, alarms, and recurrence.",
                 properties: [
                    "title": stringProp("Reminder title"),
                    "notes": stringProp("Reminder notes"),
                    "startDate": stringProp("Start date (ISO 8601)"),
                    "dueDate": stringProp("Due date (ISO 8601)"),
                    "priority": intProp("Priority: 0=none, 1=high, 5=medium, 9=low"),
                    "calendarName": stringProp("Target reminder list. Uses default if not specified."),
                    "alarmMinutesBefore": intArrayProp("Minutes before due date to trigger alarms"),
                    "recurrence": recurrenceSchema,
                 ],
                 required: ["title"]),

            tool("update_reminder",
                 "Update an existing reminder. Only specify fields you want to change. Can mark as complete/incomplete.",
                 properties: [
                    "reminderId": stringProp("The unique identifier of the reminder"),
                    "title": stringProp("New title"),
                    "notes": stringProp("New notes"),
                    "startDate": stringProp("New start date (ISO 8601)"),
                    "dueDate": stringProp("New due date (ISO 8601)"),
                    "priority": intProp("Priority: 0=none, 1=high, 5=medium, 9=low"),
                    "isCompleted": boolProp("Mark completed (true) or incomplete (false)"),
                    "calendarName": stringProp("Move to this reminder list"),
                    "alarmMinutesBefore": intArrayProp("Replace alarms with these minute offsets"),
                    "recurrence": recurrenceSchema,
                 ],
                 required: ["reminderId"]),

            tool("delete_reminder",
                 "Delete a reminder by its ID.",
                 properties: ["reminderId": stringProp("The unique identifier of the reminder to delete")],
                 required: ["reminderId"]),

            tool("list_calendars",
                 "List all available calendars (event calendars and/or reminder lists) with source and type info.",
                 properties: [
                    "type": enumProp(["event", "reminder", "all"], "Type of calendars to list (default: all)"),
                 ]),

            tool("create_calendar",
                 "Create a new calendar or reminder list under a specific source (e.g. iCloud, Exchange).",
                 properties: [
                    "title": stringProp("Name for the new calendar"),
                    "sourceName": stringProp("Source to create under (e.g. 'iCloud')"),
                    "type": enumProp(["event", "reminder"], "Create event calendar or reminder list (default: event)"),
                 ],
                 required: ["title", "sourceName"]),

            tool("delete_calendar",
                 "Delete a calendar or reminder list by its ID. WARNING: deletes all events/reminders in it.",
                 properties: ["calendarId": stringProp("The unique identifier of the calendar to delete")],
                 required: ["calendarId"]),

            tool("check_availability",
                 "Check availability in a date range. Returns free and busy time slots.",
                 properties: [
                    "startDate": stringProp("Start of date range (ISO 8601)"),
                    "endDate": stringProp("End of date range (ISO 8601)"),
                    "calendarNames": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                        "description": .string("Optional: only check these calendars"),
                    ]),
                    "minimumSlotMinutes": intProp("Minimum free slot duration in minutes (default: 30)"),
                 ],
                 required: ["startDate", "endDate"]),

            // New Event Tools

            tool("search_events",
                 "Full-text search across event titles, notes, and locations within a date range.",
                 properties: [
                    "query": stringProp("Search text to match against title, notes, and location"),
                    "startDate": stringProp("Start of date range (ISO 8601)"),
                    "endDate": stringProp("End of date range (ISO 8601)"),
                    "calendarName": stringProp("Optional: filter to a specific calendar by name"),
                 ],
                 required: ["query", "startDate", "endDate"]),

            tool("list_upcoming",
                 "List the next N upcoming events starting from now. No date range needed.",
                 properties: [
                    "count": intProp("Number of upcoming events to return (default: 10)"),
                    "calendarName": stringProp("Optional: filter to a specific calendar by name"),
                 ]),

            tool("move_event",
                 "Move an event to a new time. Preserves duration unless a new end date is specified.",
                 properties: [
                    "eventId": stringProp("The unique identifier of the event to move"),
                    "newStartDate": stringProp("New start time in ISO 8601 format"),
                    "newEndDate": stringProp("Optional: new end time. If omitted, duration is preserved."),
                    "applyToFutureEvents": boolProp("For recurring events: apply to future occurrences (default false)"),
                 ],
                 required: ["eventId", "newStartDate"]),

            tool("duplicate_event",
                 "Clone an existing event to a new date/time. Copies title, location, notes, URL, alarms, and calendar.",
                 properties: [
                    "eventId": stringProp("The unique identifier of the event to duplicate"),
                    "newStartDate": stringProp("Start time for the duplicate in ISO 8601 format"),
                    "newEndDate": stringProp("Optional: end time for the duplicate. If omitted, original duration is preserved."),
                 ],
                 required: ["eventId", "newStartDate"]),

            tool("list_recurring_events",
                 "List events that have recurrence rules within a date range.",
                 properties: [
                    "startDate": stringProp("Start of date range (ISO 8601)"),
                    "endDate": stringProp("End of date range (ISO 8601)"),
                    "calendarName": stringProp("Optional: filter to a specific calendar by name"),
                 ],
                 required: ["startDate", "endDate"]),

            tool("today",
                 "List all events for today. No date parameters needed.",
                 properties: [
                    "calendarName": stringProp("Optional: filter to a specific calendar by name"),
                 ]),

            tool("tomorrow",
                 "List all events for tomorrow. No date parameters needed.",
                 properties: [
                    "calendarName": stringProp("Optional: filter to a specific calendar by name"),
                 ]),

            // New Reminder Tools

            tool("get_reminder",
                 "Get detailed information about a specific reminder by its ID.",
                 properties: ["reminderId": stringProp("The unique identifier of the reminder")],
                 required: ["reminderId"]),

            tool("search_reminders",
                 "Full-text search across reminder titles and notes.",
                 properties: [
                    "query": stringProp("Search text to match against title and notes"),
                    "calendarName": stringProp("Optional: filter to a specific reminder list by name"),
                 ],
                 required: ["query"]),

            tool("complete_reminder",
                 "Mark a reminder as complete.",
                 properties: ["reminderId": stringProp("The unique identifier of the reminder to complete")],
                 required: ["reminderId"]),

            tool("uncomplete_reminder",
                 "Mark a previously completed reminder as incomplete.",
                 properties: ["reminderId": stringProp("The unique identifier of the reminder to uncomplete")],
                 required: ["reminderId"]),

            tool("list_overdue_reminders",
                 "List incomplete reminders that are past their due date.",
                 properties: [
                    "calendarName": stringProp("Optional: filter to a specific reminder list by name"),
                 ]),

            tool("batch_complete_reminders",
                 "Mark multiple reminders as complete at once.",
                 properties: [
                    "reminderIds": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                        "description": .string("Array of reminder IDs to mark as complete"),
                    ]),
                 ],
                 required: ["reminderIds"]),

            // New Calendar Tools

            tool("get_calendar",
                 "Get detailed information about a specific calendar by its ID or name.",
                 properties: [
                    "calendarId": stringProp("The unique identifier of the calendar"),
                    "calendarName": stringProp("The name of the calendar (used if calendarId is not provided)"),
                 ]),

            tool("rename_calendar",
                 "Rename an existing calendar or reminder list.",
                 properties: [
                    "calendarId": stringProp("The unique identifier of the calendar to rename"),
                    "newTitle": stringProp("The new name for the calendar"),
                 ],
                 required: ["calendarId", "newTitle"]),

            tool("list_sources",
                 "List all available calendar sources (iCloud, Exchange, Local, etc.).",
                 properties: [:]),
        ]
    }
}

// MARK: - Schema Helpers

private func tool(_ name: String, _ description: String, properties: [String: Value], required: [String] = []) -> Tool {
    var schema: [String: Value] = [
        "type": .string("object"),
        "properties": .object(properties),
    ]
    if !required.isEmpty {
        schema["required"] = .array(required.map { .string($0) })
    }
    return Tool(name: name, description: description, inputSchema: .object(schema))
}

private func stringProp(_ description: String) -> Value {
    .object(["type": .string("string"), "description": .string(description)])
}

private func boolProp(_ description: String) -> Value {
    .object(["type": .string("boolean"), "description": .string(description)])
}

private func intProp(_ description: String) -> Value {
    .object(["type": .string("integer"), "description": .string(description)])
}

private func intArrayProp(_ description: String) -> Value {
    .object(["type": .string("array"), "items": .object(["type": .string("integer")]), "description": .string(description)])
}

private func enumProp(_ values: [String], _ description: String) -> Value {
    .object(["type": .string("string"), "enum": .array(values.map { .string($0) }), "description": .string(description)])
}

private let recurrenceSchema: Value = .object([
    "type": .string("object"),
    "description": .string("Recurrence rule for repeating events/reminders"),
    "properties": .object([
        "frequency": enumProp(["daily", "weekly", "monthly", "yearly"], "How often the event repeats"),
        "interval": intProp("Interval between recurrences (default 1)"),
        "daysOfWeek": .object([
            "type": .string("array"),
            "description": .string("Days of week (1=Sun..7=Sat) with optional weekNumber"),
            "items": .object([
                "type": .string("object"),
                "properties": .object([
                    "dayOfWeek": .object(["type": .string("integer")]),
                    "weekNumber": .object(["type": .string("integer")]),
                ]),
            ]),
        ]),
        "daysOfMonth": intArrayProp("Days of month (1-31, negative from end)"),
        "monthsOfYear": intArrayProp("Months (1-12)"),
        "weeksOfYear": intArrayProp("Weeks of year (1-53)"),
        "setPositions": intArrayProp("Ordinal positions (e.g. 2 = 2nd, -1 = last)"),
        "occurrenceCount": intProp("End after this many occurrences"),
        "endDate": stringProp("End date (ISO 8601). Don't set both endDate and occurrenceCount."),
    ]),
    "required": .array([.string("frequency")]),
])
