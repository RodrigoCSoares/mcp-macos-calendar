import EventKit
import Foundation
import Logging
import MCP

@MainActor
final class CalendarMCPServer {
    let server: Server
    let calendarManager: CalendarManager
    let encoder: JSONEncoder
    let decoder: JSONDecoder
    private let logger: Logger

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
            let args = try encoder.encode(params.arguments ?? [:])

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

    func encodeResult<T: Encodable>(_ value: T, prefix: String? = nil) throws -> CallTool.Result {
        let json = String(data: try encoder.encode(value), encoding: .utf8) ?? "{}"
        let text = prefix.map { "\($0)\n\(json)" } ?? json
        return .init(content: [.text(text)])
    }

    func textResult(_ message: String) -> CallTool.Result {
        .init(content: [.text(message)])
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
