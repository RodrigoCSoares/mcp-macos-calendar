import Foundation

@MainActor
enum ISO8601Parsing {
    static let flexible: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static let standard = ISO8601DateFormatter()

    static func parse(_ string: String) -> Date? {
        flexible.date(from: string) ?? standard.date(from: string)
    }

    static func require(_ string: String, label: String) throws -> Date {
        guard let date = parse(string) else {
            throw CalendarError.invalidInput("Invalid \(label): \(string)")
        }
        return date
    }

    static func parseDateRange(start: String, end: String) throws -> (Date, Date) {
        let s = try require(start, label: "startDate")
        let e = try require(end, label: "endDate")
        return (s, e)
    }
}
