import CoreLocation
import EventKit
import Foundation

// MARK: - Event Models

struct CalendarEvent: Codable, Sendable {
    let identifier: String
    let externalIdentifier: String?
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let location: String?
    let structuredLocation: StructuredLocationInfo?
    let notes: String?
    let url: String?
    let calendarName: String
    let availability: String
    let status: String
    let timeZone: String?
    let hasRecurrenceRules: Bool
    let isDetached: Bool
    let occurrenceDate: Date?
    let organizer: Attendee?
    let attendees: [Attendee]?
    let creationDate: Date?
    let lastModifiedDate: Date?

    struct Attendee: Codable, Sendable {
        let name: String?
        let email: String?
        let role: String
        let type: String
        let status: String
        let isCurrentUser: Bool
    }
}

struct StructuredLocationInfo: Codable, Sendable {
    let title: String?
    let latitude: Double?
    let longitude: Double?
    let radius: Double?
}

struct CreateEventInput: Codable, Sendable {
    let title: String
    let startDate: String
    let endDate: String
    let isAllDay: Bool?
    let location: String?
    let structuredLocation: StructuredLocationInput?
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
    let structuredLocation: StructuredLocationInput?
    let notes: String?
    let url: String?
    let calendarName: String?
    let alarmMinutesBefore: [Int]?
    let recurrence: RecurrenceInput?
    let applyToFutureEvents: Bool?
}

struct StructuredLocationInput: Codable, Sendable {
    let title: String?
    let latitude: Double
    let longitude: Double
    let radius: Double?

    func toEKStructuredLocation() -> EKStructuredLocation {
        let loc = EKStructuredLocation(title: title ?? "")
        loc.geoLocation = CLLocation(latitude: latitude, longitude: longitude)
        if let radius { loc.radius = radius }
        return loc
    }
}

// MARK: - EKEvent Conversion

extension CalendarEvent {
    @MainActor
    static func from(_ event: EKEvent) -> CalendarEvent {
        CalendarEvent(
            identifier: event.eventIdentifier,
            externalIdentifier: event.calendarItemExternalIdentifier,
            title: event.title ?? "Untitled",
            startDate: event.startDate,
            endDate: event.endDate,
            isAllDay: event.isAllDay,
            location: event.location,
            structuredLocation: event.structuredLocation.flatMap(StructuredLocationInfo.from),
            notes: event.notes,
            url: event.url?.absoluteString,
            calendarName: event.calendar?.title ?? "Unknown",
            availability: event.availability.label,
            status: event.status.label,
            timeZone: event.timeZone?.identifier,
            hasRecurrenceRules: event.hasRecurrenceRules,
            isDetached: event.isDetached,
            occurrenceDate: event.occurrenceDate,
            organizer: event.organizer.map(Attendee.from),
            attendees: event.attendees?.map(Attendee.from),
            creationDate: event.creationDate,
            lastModifiedDate: event.lastModifiedDate
        )
    }
}

extension StructuredLocationInfo {
    static func from(_ location: EKStructuredLocation) -> StructuredLocationInfo? {
        let geo = location.geoLocation
        // Only include if there's at least a title or coordinates
        guard location.title != nil || geo != nil else { return nil }
        return StructuredLocationInfo(
            title: location.title,
            latitude: geo?.coordinate.latitude,
            longitude: geo?.coordinate.longitude,
            radius: location.radius > 0 ? location.radius : nil
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
