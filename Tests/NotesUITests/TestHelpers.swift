import Foundation
import XCTest
@testable import NotesDomain
@testable import NotesFeatures
@testable import NotesSync
@testable import NotesUI

// MARK: - Shared Test Helpers

/// Shared factory for creating test AppViewModels with consistent initialization.
@MainActor
func makeTestAppViewModel(service: WorkspaceServicing? = nil, calendarID: String = "dev-calendar") throws -> AppViewModel {
    let actualService: WorkspaceServicing = if let service {
        service
    } else {
        try MockWorkspaceService()
    }
    let provider = InMemoryCalendarProvider()
    return AppViewModel(
        service: actualService,
        calendarProviderFactory: { provider },
        syncCalendarID: calendarID,
    )
}

/// Polls `condition` every 20 ms until it becomes true or the deadline (default 2 s) passes.
/// Use this instead of fixed-duration sleeps so CI machines with variable scheduler latency don't cause flaky timeouts.
@MainActor
func waitUntil(
    deadline: TimeInterval = 2.0,
    file: StaticString = #file,
    line: UInt = #line,
    condition: () -> Bool,
) async {
    let start = Date()
    while !condition() {
        if Date().timeIntervalSince(start) >= deadline {
            XCTFail("Condition not met within \(deadline) s", file: file, line: line)
            return
        }
        try? await _Concurrency.Task.sleep(nanoseconds: 20_000_000) // 20 ms
    }
}

/// Sleep for 160ms to allow async state mutations and UI updates to settle.
func flushAsyncActions() async throws {
    try await _Concurrency.Task.sleep(nanoseconds: 160_000_000)
}
