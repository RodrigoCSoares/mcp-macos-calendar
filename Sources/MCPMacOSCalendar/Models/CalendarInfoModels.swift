import EventKit
import Foundation

// MARK: - Calendar / Source Models

struct CalendarInfo: Codable, Sendable {
    let identifier: String
    let title: String
    let type: String
    let sourceName: String
    let isImmutable: Bool
    let isSubscribed: Bool
    let allowsContentModifications: Bool
    let color: String?
}

struct SourceInfo: Codable, Sendable {
    let identifier: String
    let title: String
    let type: String
}

// MARK: - EKCalendar / EKSource Conversion

extension CalendarInfo {
    @MainActor
    static func from(_ calendar: EKCalendar) -> CalendarInfo {
        CalendarInfo(
            identifier: calendar.calendarIdentifier,
            title: calendar.title,
            type: calendar.type.label,
            sourceName: calendar.source?.title ?? "Unknown",
            isImmutable: calendar.isImmutable,
            isSubscribed: calendar.isSubscribed,
            allowsContentModifications: calendar.allowsContentModifications,
            color: calendar.cgColor.map(Self.colorToHex)
        )
    }

    private static func colorToHex(_ cgColor: CGColor) -> String {
        guard let c = cgColor.components, c.count >= 3 else { return "#000000" }
        return String(format: "#%02X%02X%02X", Int(c[0] * 255), Int(c[1] * 255), Int(c[2] * 255))
    }
}

extension SourceInfo {
    @MainActor
    static func from(_ source: EKSource) -> SourceInfo {
        SourceInfo(
            identifier: source.sourceIdentifier,
            title: source.title,
            type: source.sourceType.label
        )
    }
}
