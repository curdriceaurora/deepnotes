import Foundation
import XCTest
@testable import NotesDomain

final class DomainErrorsAndModelsTests: XCTestCase {
    func testSmoke_DomainValidationErrorDescriptions() {
        XCTAssertEqual(
            DomainValidationError.invalidPriority(9).errorDescription,
            "Task priority must be between 0 and 5, got 9.",
        )
        XCTAssertEqual(
            DomainValidationError.invalidDateRange.errorDescription,
            "Start date must be before end date.",
        )
        XCTAssertEqual(
            DomainValidationError.missingStableID.errorDescription,
            "Stable task ID is required for deterministic sync.",
        )
    }

    func testSmoke_StorageErrorDescriptions() {
        XCTAssertEqual(
            StorageError.openDatabase(path: "/tmp/db", reason: "no permission").errorDescription,
            "Failed to open SQLite database at /tmp/db: no permission",
        )
        XCTAssertEqual(
            StorageError.prepareStatement(reason: "syntax").errorDescription,
            "Failed to prepare SQL statement: syntax",
        )
        XCTAssertEqual(
            StorageError.executeStatement(reason: "busy").errorDescription,
            "Failed to execute SQL statement: busy",
        )
        XCTAssertEqual(
            StorageError.transactionFailed(reason: "deadlock").errorDescription,
            "SQLite transaction failed: deadlock",
        )
        XCTAssertEqual(
            StorageError.dataCorruption(reason: "bad row").errorDescription,
            "Unexpected SQLite data: bad row",
        )
    }

    func testSmoke_SyncErrorDescriptions() {
        XCTAssertEqual(
            SyncError.missingEventIdentifier.errorDescription,
            "Calendar provider did not return an event identifier; cannot persist binding.",
        )
        XCTAssertEqual(
            SyncError.unsupportedCalendarChange(reason: "calendar missing").errorDescription,
            "Received unsupported calendar change: calendar missing",
        )
    }

    func testSmoke_CalendarProviderErrorDescriptionsAndRetryability() {
        XCTAssertEqual(
            CalendarProviderError.transient(reason: "timeout").errorDescription,
            "Transient calendar provider failure: timeout",
        )
        XCTAssertEqual(
            CalendarProviderError.permanent(reason: "invalid credentials").errorDescription,
            "Permanent calendar provider failure: invalid credentials",
        )
        XCTAssertTrue(CalendarProviderError.transient(reason: "x").isRetryable)
        XCTAssertFalse(CalendarProviderError.permanent(reason: "x").isRetryable)
    }

    func testSmoke_TaskValidationFailsInvalidPriority() {
        XCTAssertThrowsError(
            try Task(stableID: "id", title: "Task", priority: 10, updatedAt: Date()),
        ) { error in
            XCTAssertEqual(error as? DomainValidationError, .invalidPriority(10))
        }
    }

    func testSmoke_TaskValidationFailsInvalidRange() {
        XCTAssertThrowsError(
            try Task(
                stableID: "id",
                title: "Task",
                dueStart: Date(timeIntervalSince1970: 1000),
                dueEnd: Date(timeIntervalSince1970: 999),
                updatedAt: Date(),
            ),
        ) { error in
            XCTAssertEqual(error as? DomainValidationError, .invalidDateRange)
        }
    }

    func testSmoke_CalendarEventValidationFailsInvalidRange() {
        XCTAssertThrowsError(
            try CalendarEvent(
                calendarID: "calendar",
                title: "Invalid",
                startDate: Date(timeIntervalSince1970: 2000),
                endDate: Date(timeIntervalSince1970: 1000),
                updatedAt: Date(),
            ),
        ) { error in
            XCTAssertEqual(error as? DomainValidationError, .invalidDateRange)
        }
    }

    func testSmoke_TaskSortOrderAllCases() {
        let allCases = TaskSortOrder.allCases
        XCTAssertEqual(allCases.count, 4)
        XCTAssertTrue(allCases.contains(.dueDate))
        XCTAssertTrue(allCases.contains(.priority))
        XCTAssertTrue(allCases.contains(.title))
        XCTAssertTrue(allCases.contains(.creationDate))
    }

    func testSmoke_TaskSortOrderTitleProperty() {
        XCTAssertEqual(TaskSortOrder.dueDate.title, "Due Date")
        XCTAssertEqual(TaskSortOrder.priority.title, "Priority")
        XCTAssertEqual(TaskSortOrder.title.title, "Title")
        XCTAssertEqual(TaskSortOrder.creationDate.title, "Date Added")
    }

    func testSmoke_TaskSortOrderCodable() throws {
        let cases: [TaskSortOrder] = [.dueDate, .priority, .title, .creationDate]
        for sortOrder in cases {
            let encoded = try JSONEncoder().encode(sortOrder)
            let decoded = try JSONDecoder().decode(TaskSortOrder.self, from: encoded)
            XCTAssertEqual(decoded, sortOrder)
        }
    }

    func testSmoke_TaskSortOrderRawValue() {
        XCTAssertEqual(TaskSortOrder.dueDate.rawValue, "dueDate")
        XCTAssertEqual(TaskSortOrder.priority.rawValue, "priority")
        XCTAssertEqual(TaskSortOrder.title.rawValue, "title")
        XCTAssertEqual(TaskSortOrder.creationDate.rawValue, "creationDate")
    }
}
