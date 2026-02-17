import ArgumentParser
import Foundation
import Logging
import MCP

@main
struct MCPCalendarCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mcp-macos-calendar",
        abstract: "MCP Calendar Server -- interact with macOS Calendar and Reminders via MCP",
        version: "1.0.0"
    )

    @Option(name: .shortAndLong, help: "Transport mode: stdio or http")
    var transport: TransportMode = .stdio

    @Option(name: .shortAndLong, help: "HTTP port (only used with --transport http)")
    var port: Int = 8080

    @Option(name: .long, help: "HTTP host (only used with --transport http)")
    var host: String = "127.0.0.1"

    @Option(name: .shortAndLong, help: "Log level: trace, debug, info, notice, warning, error, critical")
    var logLevel: String = "info"

    @MainActor
    mutating func run() async throws {
        let level = Logger.Level(rawValue: logLevel.lowercased()) ?? .info
        LoggingSystem.bootstrap { label in
            var handler = StreamLogHandler.standardError(label: label)
            handler.logLevel = level
            return handler
        }

        let logger = Logger(label: "mcp-macos-calendar")
        let server = CalendarMCPServer(logger: logger)

        let mcpTransport: any Transport = switch transport {
        case .stdio:
            { logger.info("Starting MCP Calendar server with stdio transport"); return StdioTransport() }()
        case .http:
            { logger.info("Starting MCP Calendar server with HTTP transport on \(host):\(port)")
              return StreamableHTTPTransport(host: host, port: port, logger: logger) }()
        }

        try await server.start(transport: mcpTransport)
    }
}

enum TransportMode: String, ExpressibleByArgument, Sendable {
    case stdio
    case http
}
