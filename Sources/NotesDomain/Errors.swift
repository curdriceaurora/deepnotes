import Foundation

public enum DomainValidationError: Error, Equatable, LocalizedError {
    case invalidPriority(Int)
    case invalidDateRange
    case missingStableID

    public var errorDescription: String? {
        switch self {
        case .invalidPriority(let value):
            return "Task priority must be between 0 and 5, got \(value)."
        case .invalidDateRange:
            return "Start date must be before end date."
        case .missingStableID:
            return "Stable task ID is required for deterministic sync."
        }
    }
}

public enum StorageError: Error, LocalizedError {
    case openDatabase(path: String, reason: String)
    case prepareStatement(reason: String)
    case executeStatement(reason: String)
    case transactionFailed(reason: String)
    case dataCorruption(reason: String)

    public var errorDescription: String? {
        switch self {
        case .openDatabase(let path, let reason):
            return "Failed to open SQLite database at \(path): \(reason)"
        case .prepareStatement(let reason):
            return "Failed to prepare SQL statement: \(reason)"
        case .executeStatement(let reason):
            return "Failed to execute SQL statement: \(reason)"
        case .transactionFailed(let reason):
            return "SQLite transaction failed: \(reason)"
        case .dataCorruption(let reason):
            return "Unexpected SQLite data: \(reason)"
        }
    }
}

public enum SyncError: Error, LocalizedError {
    case missingEventIdentifier
    case unsupportedCalendarChange(reason: String)

    public var errorDescription: String? {
        switch self {
        case .missingEventIdentifier:
            return "Calendar provider did not return an event identifier; cannot persist binding."
        case .unsupportedCalendarChange(let reason):
            return "Received unsupported calendar change: \(reason)"
        }
    }
}

public enum CalendarProviderError: Error, LocalizedError, Sendable {
    case transient(reason: String)
    case permanent(reason: String)

    public var isRetryable: Bool {
        switch self {
        case .transient:
            return true
        case .permanent:
            return false
        }
    }

    public var errorDescription: String? {
        switch self {
        case .transient(let reason):
            return "Transient calendar provider failure: \(reason)"
        case .permanent(let reason):
            return "Permanent calendar provider failure: \(reason)"
        }
    }
}
