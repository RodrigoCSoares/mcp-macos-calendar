import EventKit
import Foundation

// MARK: - Calendar, Source & Availability Operations

extension CalendarManager {

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
        return CalendarInfo.from(calendar)
    }

    func deleteCalendar(identifier: String) throws {
        let calendar = try resolveAnyCalendar(identifier)
        try store.removeCalendar(calendar, commit: true)
    }

    func getCalendar(identifier: String? = nil, name: String? = nil) throws -> CalendarInfo {
        let calendar: EKCalendar?
        if let identifier {
            calendar = try? resolveAnyCalendar(identifier)
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
        let calendar = try resolveAnyCalendar(identifier)
        guard calendar.allowsContentModifications else {
            throw CalendarError.operationFailed("Calendar '\(calendar.title)' is immutable")
        }
        calendar.title = newTitle
        try store.saveCalendar(calendar, commit: true)
        return CalendarInfo.from(calendar)
    }

    // MARK: - Availability

    func checkAvailability(_ input: AvailabilityInput) throws -> AvailabilityResult {
        try ensureEventAccess()
        let (start, end) = try ISO8601Parsing.parseDateRange(start: input.startDate, end: input.endDate)
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
