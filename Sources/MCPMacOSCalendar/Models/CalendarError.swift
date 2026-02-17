import Foundation

enum CalendarError: Error, LocalizedError {
    case accessDenied(String)
    case notFound(String)
    case invalidInput(String)
    case operationFailed(String)

    var errorDescription: String? {
        switch self {
        case .accessDenied(let msg): "Access denied: \(msg)"
        case .notFound(let msg): "Not found: \(msg)"
        case .invalidInput(let msg): "Invalid input: \(msg)"
        case .operationFailed(let msg): "Operation failed: \(msg)"
        }
    }
}
