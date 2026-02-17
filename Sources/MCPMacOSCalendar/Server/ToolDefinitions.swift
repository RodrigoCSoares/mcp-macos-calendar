import Foundation
import MCP

// MARK: - Shared Handler Input Types

struct EventIdInput: Decodable { let eventId: String }
struct ReminderIdInput: Decodable { let reminderId: String }
struct CalendarNameInput: Decodable { let calendarName: String? }
struct DateRangeInput: Decodable { let startDate: String; let endDate: String; let calendarName: String? }

// MARK: - Tool Definitions & Schema Helpers

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

            tool("list_reminders",
                 "List reminders from the Reminders app. Filter by list, status (all/incomplete/completed), and date range.",
                 properties: [
                    "calendarName": stringProp("Filter to a specific reminder list by name"),
                    "filter": enumProp(["all", "incomplete", "completed"], "Filter by status (default: all)"),
                    "startDate": stringProp("Start of date range (ISO 8601)"),
                    "endDate": stringProp("End of date range (ISO 8601)"),
                 ]),

            tool("get_reminder",
                 "Get detailed information about a specific reminder by its ID.",
                 properties: ["reminderId": stringProp("The unique identifier of the reminder")],
                 required: ["reminderId"]),

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

            tool("list_calendars",
                 "List all available calendars (event calendars and/or reminder lists) with source and type info.",
                 properties: [
                    "type": enumProp(["event", "reminder", "all"], "Type of calendars to list (default: all)"),
                 ]),

            tool("get_calendar",
                 "Get detailed information about a specific calendar by its ID or name.",
                 properties: [
                    "calendarId": stringProp("The unique identifier of the calendar"),
                    "calendarName": stringProp("The name of the calendar (used if calendarId is not provided)"),
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
