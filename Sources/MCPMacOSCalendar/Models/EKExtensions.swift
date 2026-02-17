import EventKit
import Foundation

// MARK: - EK Enum Labels

extension EKEventAvailability {
    var label: String {
        switch self {
        case .busy: "busy"
        case .free: "free"
        case .tentative: "tentative"
        case .unavailable: "unavailable"
        case .notSupported: "notSupported"
        @unknown default: "unknown"
        }
    }
}

extension EKParticipantRole {
    var label: String {
        switch self {
        case .required: "required"
        case .optional: "optional"
        case .chair: "chair"
        case .nonParticipant: "nonParticipant"
        case .unknown: "unknown"
        @unknown default: "unknown"
        }
    }
}

extension EKParticipantType {
    var label: String {
        switch self {
        case .person: "person"
        case .room: "room"
        case .resource: "resource"
        case .group: "group"
        case .unknown: "unknown"
        @unknown default: "unknown"
        }
    }
}

extension EKParticipantStatus {
    var label: String {
        switch self {
        case .pending: "pending"
        case .accepted: "accepted"
        case .declined: "declined"
        case .tentative: "tentative"
        case .delegated: "delegated"
        case .completed: "completed"
        case .inProcess: "inProcess"
        case .unknown: "unknown"
        @unknown default: "unknown"
        }
    }
}

extension EKEventStatus {
    var label: String {
        switch self {
        case .none: "none"
        case .confirmed: "confirmed"
        case .tentative: "tentative"
        case .canceled: "cancelled"
        @unknown default: "unknown"
        }
    }
}

extension EKCalendarType {
    var label: String {
        switch self {
        case .local: "local"
        case .calDAV: "calDAV"
        case .exchange: "exchange"
        case .subscription: "subscription"
        case .birthday: "birthday"
        @unknown default: "unknown"
        }
    }
}

extension EKSourceType {
    var label: String {
        switch self {
        case .local: "local"
        case .exchange: "exchange"
        case .calDAV: "calDAV"
        case .mobileMe: "iCloud"
        case .subscribed: "subscribed"
        case .birthdays: "birthdays"
        @unknown default: "unknown"
        }
    }
}

// MARK: - DateComponents Formatting

extension DateComponents {
    var formatted: String {
        [
            year.map { "year:\($0)" },
            month.map { "month:\($0)" },
            day.map { "day:\($0)" },
            hour.map { "hour:\($0)" },
            minute.map { "minute:\($0)" },
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }
}
