import Foundation

public enum DomainValidationError: Error, Equatable, LocalizedError {
    case invalidPriority(Int)
    case invalidDateRange
    case missingStableID

    public var errorDescription: String? {
        switch self {
        case let .invalidPriority(value):
            "Task priority must be between 0 and 5, got \(value)."
        case .invalidDateRange:
            "Start date must be before end date."
        case .missingStableID:
            "Stable task ID is required for deterministic sync."
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
        case let .openDatabase(path, reason):
            "Failed to open SQLite database at \(path): \(reason)"
        case let .prepareStatement(reason):
            "Failed to prepare SQL statement: \(reason)"
        case let .executeStatement(reason):
            "Failed to execute SQL statement: \(reason)"
        case let .transactionFailed(reason):
            "SQLite transaction failed: \(reason)"
        case let .dataCorruption(reason):
            "Unexpected SQLite data: \(reason)"
        }
    }
}

public enum SyncError: Error, LocalizedError {
    case missingEventIdentifier
    case unsupportedCalendarChange(reason: String)

    public var errorDescription: String? {
        switch self {
        case .missingEventIdentifier:
            "Calendar provider did not return an event identifier; cannot persist binding."
        case let .unsupportedCalendarChange(reason):
            "Received unsupported calendar change: \(reason)"
        }
    }
}

public enum CalendarProviderError: Error, LocalizedError, Sendable {
    case transient(reason: String)
    case permanent(reason: String)

    public var isRetryable: Bool {
        switch self {
        case .transient:
            true
        case .permanent:
            false
        }
    }

    public var errorDescription: String? {
        switch self {
        case let .transient(reason):
            "Transient calendar provider failure: \(reason)"
        case let .permanent(reason):
            "Permanent calendar provider failure: \(reason)"
        }
    }
}
