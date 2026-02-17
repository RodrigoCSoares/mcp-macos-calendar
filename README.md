# mcp-macos-calendar

A native Swift MCP server for macOS Calendar and Reminders. Gives AI assistants (Claude Desktop, OpenCode, etc.) full access to your calendars and reminder lists via [EventKit](https://developer.apple.com/documentation/eventkit).

**Entirely written in Swift** -- no bridges, no wrappers. Uses Apple's EventKit framework directly for maximum reliability and performance.

## Features

- **29 tools** covering events, reminders, calendars, and availability
- **3 resources** for browsing calendars and sources
- Full CRUD for events and reminders
- Search events and reminders by text
- Convenience tools: `today`, `tomorrow`, `list_upcoming`, `complete_reminder`
- Batch operations (complete multiple reminders at once)
- Recurrence rules (daily, weekly, monthly, yearly with advanced options)
- Attendees (read-only) and availability checking
- Multiple alarm support
- Works with all calendar sources (iCloud, Exchange, Google, CalDAV, local)
- **Two transport modes**: stdio (for Claude Desktop / OpenCode) and Streamable HTTP
- Strict Swift 6 concurrency

## Requirements

- macOS 14.0 (Sonoma) or later
- Swift 6.0+
- Calendar and Reminders permissions (prompted on first run)

## Build

```bash
git clone https://github.com/user/mcp-macos-calendar.git
cd mcp-macos-calendar
swift build
```

The binary will be at `.build/debug/MCPMacOSCalendar`.

## Setup

### Claude Desktop

Add to your Claude Desktop config (`~/Library/Application Support/Claude/claude_desktop_config.json`):

```json
{
  "mcpServers": {
    "calendar": {
      "command": "/path/to/mcp-macos-calendar/.build/debug/MCPMacOSCalendar",
      "args": ["--transport", "stdio"]
    }
  }
}
```

### OpenCode

Add to your OpenCode config (`~/.config/opencode/opencode.json`):

```json
{
  "mcp": {
    "calendar": {
      "type": "local",
      "command": ["/path/to/mcp-macos-calendar/.build/debug/MCPMacOSCalendar", "--transport", "stdio"],
      "enabled": true
    }
  }
}
```

### HTTP Mode

For clients that support Streamable HTTP transport:

```bash
.build/debug/MCPMacOSCalendar --transport http --port 8080
```

The MCP endpoint will be available at `http://127.0.0.1:8080/mcp`.

## Permissions

On first run, macOS will prompt you to grant Calendar and Reminders access. You can also enable these in **System Settings > Privacy & Security > Calendars** and **Reminders**.

If you deny Reminders access, the server will still work for calendar events -- reminder tools will return errors.

## Tools

### Events

| Tool | Description |
|---|---|
| `list_events` | Query events by date range, optionally filtered by calendar |
| `get_event` | Get event details by ID, including attendees |
| `create_event` | Create event with title, time, location, notes, URL, alarms, recurrence |
| `update_event` | Update any event field (partial updates supported) |
| `delete_event` | Delete event (single occurrence or all future) |
| `search_events` | Full-text search across event titles, notes, and locations |
| `list_upcoming` | List next N upcoming events (no date range needed) |
| `move_event` | Move event to a new time (preserves duration) |
| `duplicate_event` | Clone an event to a different date/time |
| `list_recurring_events` | List events with recurrence rules in a date range |
| `today` | List all events for today (no parameters needed) |
| `tomorrow` | List all events for tomorrow (no parameters needed) |

### Reminders

| Tool | Description |
|---|---|
| `list_reminders` | List reminders -- filter by list, status (all/incomplete/completed), date range |
| `get_reminder` | Get reminder details by ID |
| `create_reminder` | Create reminder with title, notes, due date, priority, alarms, recurrence |
| `update_reminder` | Update reminder fields, mark complete/incomplete |
| `delete_reminder` | Delete a reminder |
| `search_reminders` | Full-text search across reminder titles and notes |
| `complete_reminder` | Mark a reminder as complete |
| `uncomplete_reminder` | Mark a completed reminder as incomplete |
| `list_overdue_reminders` | List incomplete reminders past their due date |
| `batch_complete_reminders` | Mark multiple reminders complete at once |

### Calendars & Sources

| Tool | Description |
|---|---|
| `list_calendars` | List event calendars and/or reminder lists |
| `get_calendar` | Get calendar details by ID or name |
| `create_calendar` | Create a new calendar or reminder list under a source |
| `delete_calendar` | Delete a calendar (and all its events/reminders) |
| `rename_calendar` | Rename an existing calendar or reminder list |
| `list_sources` | List calendar sources (iCloud, Exchange, Local, etc.) |
| `check_availability` | Find free/busy time slots in a date range |

## Resources

| URI | Description |
|---|---|
| `calendars://event-calendars` | All event calendars with source and type info |
| `calendars://reminder-lists` | All reminder lists |
| `calendars://sources` | Calendar sources (iCloud, Exchange, etc.) |

## CLI Options

```
USAGE: mcp-macos-calendar [--transport <transport>] [--port <port>] [--host <host>] [--log-level <log-level>]

OPTIONS:
  -t, --transport <transport>   Transport mode: stdio or http (default: stdio)
  -p, --port <port>             HTTP port, only for http transport (default: 8080)
  --host <host>                 HTTP host, only for http transport (default: 127.0.0.1)
  -l, --log-level <log-level>   trace, debug, info, notice, warning, error, critical (default: info)
  --version                     Show the version
  -h, --help                    Show help information
```
