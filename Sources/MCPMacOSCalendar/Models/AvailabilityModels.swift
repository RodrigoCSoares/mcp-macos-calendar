import Foundation

// MARK: - Availability Models

struct AvailabilityInput: Codable, Sendable {
    let startDate: String
    let endDate: String
    let calendarNames: [String]?
    let minimumSlotMinutes: Int?
}

struct TimeSlot: Codable, Sendable {
    let startDate: Date
    let endDate: Date
    let durationMinutes: Int
}

struct AvailabilityResult: Codable, Sendable {
    let freeSlots: [TimeSlot]
    let busySlots: [TimeSlot]
    let totalFreeMinutes: Int
    let totalBusyMinutes: Int
}
