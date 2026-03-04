import NotesDomain
import XCTest
@testable import NotesFeatures

actor MockNotificationScheduler: NotificationScheduling {
    private(set) var scheduledTaskIDs: [UUID] = []
    private(set) var cancelledTaskIDs: [UUID] = []
    private(set) var authorizationRequested = false

    func requestAuthorization() async -> Bool {
        authorizationRequested = true
        return true
    }

    func scheduleReminder(for task: Task) async {
        scheduledTaskIDs.append(task.id)
    }

    func cancelReminder(for taskID: UUID) async {
        cancelledTaskIDs.append(taskID)
    }

    func cancelAllReminders() async {
        cancelledTaskIDs.removeAll()
        scheduledTaskIDs.removeAll()
    }
}

final class NotificationSchedulerTests: XCTestCase {
    var scheduler: MockNotificationScheduler!

    override func setUp() {
        super.setUp()
        scheduler = MockNotificationScheduler()
    }

    func testRequestAuthorizationReturnsTrue() async {
        let result = await scheduler.requestAuthorization()
        XCTAssertTrue(result)
        let authed = await scheduler.authorizationRequested
        XCTAssertTrue(authed)
    }

    func testScheduleReminderAppendsTaskID() async throws {
        let task = try Task(
            noteID: nil,
            stableID: "test",
            title: "Test Task",
            details: "",
            dueStart: Date().addingTimeInterval(3600),
            dueEnd: nil,
            status: .next,
        )
        await scheduler.scheduleReminder(for: task)
        let scheduled = await scheduler.scheduledTaskIDs
        XCTAssertTrue(scheduled.contains(task.id))
    }

    func testCancelReminderAppendsTaskID() async {
        let taskID = UUID()
        await scheduler.cancelReminder(for: taskID)
        let cancelled = await scheduler.cancelledTaskIDs
        XCTAssertTrue(cancelled.contains(taskID))
    }

    func testCancelAllRemindersClears() async {
        let id1 = UUID()
        let id2 = UUID()
        await scheduler.cancelReminder(for: id1)
        await scheduler.cancelReminder(for: id2)
        await scheduler.cancelAllReminders()
        let cancelled = await scheduler.cancelledTaskIDs
        XCTAssertTrue(cancelled.isEmpty)
    }
}
