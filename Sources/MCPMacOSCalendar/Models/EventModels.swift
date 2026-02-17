import EventKit
import Foundation

// MARK: - Event Models

struct CalendarEvent: Codable, Sendable {
    let identifier: String
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let location: String?
    let notes: String?
    let url: String?
    let calendarName: String
    let availability: String
    let hasRecurrenceRules: Bool
    let attendees: [Attendee]?

    struct Attendee: Codable, Sendable {
        let name: String?
        let email: String?
        let role: String
        let type: String
        let status: String
        let isCurrentUser: Bool
    }
}

struct CreateEventInput: Codable, Sendable {
    let title: String
    let startDate: String
    let endDate: String
    let isAllDay: Bool?
    let location: String?
    let notes: String?
    let url: String?
    let calendarName: String?
    let alarmMinutesBefore: [Int]?
    let recurrence: RecurrenceInput?
}

struct UpdateEventInput: Codable, Sendable {
    let eventId: String
    let title: String?
    let startDate: String?
    let endDate: String?
    let isAllDay: Bool?
    let location: String?
    let notes: String?
    let url: String?
    let calendarName: String?
    let alarmMinutesBefore: [Int]?
    let recurrence: RecurrenceInput?
    let applyToFutureEvents: Bool?
}

// MARK: - EKEvent Conversion

extension CalendarEvent {
    @MainActor
    static func from(_ event: EKEvent) -> CalendarEvent {
        CalendarEvent(
            identifier: event.eventIdentifier,
            title: event.title ?? "Untitled",
            startDate: event.startDate,
            endDate: event.endDate,
            isAllDay: event.isAllDay,
            location: event.location,
            notes: event.notes,
            url: event.url?.absoluteString,
            calendarName: event.calendar?.title ?? "Unknown",
            availability: event.availability.label,
            hasRecurrenceRules: event.hasRecurrenceRules,
            attendees: event.attendees?.map(Attendee.from)
        )
    }
}

extension CalendarEvent.Attendee {
    @MainActor
    static func from(_ participant: EKParticipant) -> CalendarEvent.Attendee {
        .init(
            name: participant.name,
            email: participant.url.absoluteString.replacingOccurrences(of: "mailto:", with: ""),
            role: participant.participantRole.label,
            type: participant.participantType.label,
            status: participant.participantStatus.label,
            isCurrentUser: participant.isCurrentUser
        )
    }
}
