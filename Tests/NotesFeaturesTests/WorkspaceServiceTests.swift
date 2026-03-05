import Foundation
import XCTest
@testable import NotesDomain
@testable import NotesFeatures
@testable import NotesStorage
@testable import NotesSync

final class WorkspaceServiceTests: XCTestCase {
    private let testNow = Date(timeIntervalSince1970: 1_700_000_000)
    private let oneDay: TimeInterval = 86400

    func testWikiLinkParserExtractsTitlesAndAliasForms() {
        let parser = WikiLinkParser()
        let body = """
        Links: [[Q2 Launch Plan]], [[Vendor Call Notes|Vendor Notes]], [[   Team Sync   ]]
        """

        let links = parser.linkedTitles(in: body)

        XCTAssertEqual(links, ["Q2 Launch Plan", "Vendor Call Notes", "Team Sync"])
    }

    func testSmoke_BacklinksAreResolvedCaseInsensitively() async throws {
        let store = try makeStore()
        let service = WorkspaceService(
            taskStore: store,
            noteStore: store,
            bindingStore: store,
            checkpointStore: store,
            templateStore: store,
            kanbanColumnStore: store,
            clock: FixedClock(current: Date(timeIntervalSince1970: 1_700_000_000)),
        )

        let target = try await service.createNote(title: "Q2 Launch Plan", body: "Roadmap")
        _ = try await service.createNote(title: "Vendor Notes", body: "Prep from [[q2 launch plan]]")
        _ = try await service.createNote(title: "Marketing", body: "No link here")

        let backlinks = try await service.backlinks(for: target.id)

        XCTAssertEqual(backlinks.count, 1)
        XCTAssertEqual(backlinks.first?.sourceTitle, "Vendor Notes")
    }

    func testCreateNoteUsesFallbackTitleWhenEmpty() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let service = try makeService(now: now)

        let created = try await service.createNote(title: "   ", body: "Body")

        XCTAssertTrue(created.title.hasPrefix("Untitled "))
        XCTAssertEqual(created.body, "Body")
    }

    func testUpdateNoteThrowsWhenMissing() async throws {
        let service = try makeService(now: Date(timeIntervalSince1970: 1_700_000_000))

        await XCTAssertThrowsErrorAsync(
            try await service.updateNote(id: UUID(), title: "Missing", body: ""),
        )
    }

    func testBacklinksEmptyWhenTargetMissing() async throws {
        let service = try makeService(now: Date(timeIntervalSince1970: 1_700_000_000))
        let backlinks = try await service.backlinks(for: UUID())
        XCTAssertTrue(backlinks.isEmpty)
    }

    func testSmoke_SearchNotesReturnsFTSMatches() async throws {
        let service = try makeService(now: Date(timeIntervalSince1970: 1_700_000_000))

        _ = try await service.createNote(title: "Roadmap", body: "Discuss FTS launch milestones")
        _ = try await service.createNote(title: "Vendor", body: "Procurement details")

        let matches = try await service.searchNotes(query: "launch", limit: 10)
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.title, "Roadmap")
    }

    func testSearchNotesPageReturnsSnippetsAndPagination() async throws {
        let service = try makeService(now: Date(timeIntervalSince1970: 1_700_000_000))

        _ = try await service.createNote(title: "Roadmap", body: "Discuss launch milestones")
        _ = try await service.createNote(title: "Launch Risks", body: "Launch blockers and mitigations")
        _ = try await service.createNote(title: "Vendor", body: "No match content")

        let firstPage = try await service.searchNotesPage(
            query: "launch",
            mode: .smart,
            limit: 1,
            offset: 0,
        )
        XCTAssertEqual(firstPage.totalCount, 2)
        XCTAssertEqual(firstPage.hits.count, 1)
        XCTAssertEqual(firstPage.nextOffset, 1)
        XCTAssertNotNil(firstPage.hits.first?.snippet)

        let secondPage = try await service.searchNotesPage(
            query: "launch",
            mode: .smart,
            limit: 1,
            offset: 1,
        )
        XCTAssertEqual(secondPage.totalCount, 2)
        XCTAssertEqual(secondPage.hits.count, 1)
        XCTAssertNil(secondPage.nextOffset)
    }

    func testTaskFiltersReturnExpectedSlices() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let service = try makeService(now: now)

        _ = try await service.createTask(NewTaskInput(
            title: "Overdue",
            dueStart: now.addingTimeInterval(-3600),
            dueEnd: now.addingTimeInterval(-1800),
            status: .next,
            priority: 2,
        ))

        _ = try await service.createTask(NewTaskInput(
            title: "Today",
            dueStart: now.addingTimeInterval(3600),
            dueEnd: now.addingTimeInterval(7200),
            status: .doing,
            priority: 3,
        ))

        _ = try await service.createTask(NewTaskInput(
            title: "Upcoming",
            dueStart: now.addingTimeInterval(86400 * 2),
            dueEnd: now.addingTimeInterval(86400 * 2 + 3600),
            status: .waiting,
            priority: 1,
        ))

        let overdue = try await service.listTasks(filter: .overdue)
        let today = try await service.listTasks(filter: .today)
        let upcoming = try await service.listTasks(filter: .upcoming)
        let all = try await service.listTasks(filter: .all)
        let completed = try await service.listTasks(filter: .completed)

        XCTAssertEqual(overdue.map(\.title), ["Overdue"])
        XCTAssertEqual(today.map(\.title), ["Today"])
        XCTAssertEqual(upcoming.map(\.title), ["Upcoming"])
        XCTAssertEqual(Set(all.map(\.title)), Set(["Overdue", "Today", "Upcoming"]))
        XCTAssertTrue(completed.isEmpty)
    }

    func testSetTaskStatusDoneSetsCompletedAt() async throws {
        let service = try makeService(now: Date(timeIntervalSince1970: 1_700_000_000))
        let created = try await service.createTask(NewTaskInput(title: "Finish Spec", status: .doing, priority: 4))

        let done = try await service.setTaskStatus(taskID: created.id, status: .done)
        XCTAssertEqual(done.status, .done)
        XCTAssertNotNil(done.completedAt)

        let reopened = try await service.setTaskStatus(taskID: created.id, status: .next)
        XCTAssertEqual(reopened.status, .next)
        XCTAssertNil(reopened.completedAt)
    }

    func testCreateTaskAppendsKanbanOrderWithinStatus() async throws {
        let service = try makeService(now: Date(timeIntervalSince1970: 1_700_000_000))

        let first = try await service.createTask(NewTaskInput(title: "A", status: .backlog, priority: 2))
        let second = try await service.createTask(NewTaskInput(title: "B", status: .backlog, priority: 2))

        XCTAssertGreaterThan(second.kanbanOrder, first.kanbanOrder)
    }

    func testDeleteTaskTombstonesAndRemovesFromActiveLists() async throws {
        let service = try makeService(now: Date(timeIntervalSince1970: 1_700_000_000))
        let created = try await service.createTask(NewTaskInput(title: "Delete me", status: .next, priority: 2))

        try await service.deleteTask(taskID: created.id)

        let all = try await service.listTasks(filter: .all)
        XCTAssertFalse(all.contains(where: { $0.id == created.id }))
    }

    func testMoveTaskBeforeSiblingUpdatesKanbanOrder() async throws {
        let service = try makeService(now: Date(timeIntervalSince1970: 1_700_000_000))
        let first = try await service.createTask(NewTaskInput(title: "First", status: .backlog, priority: 2))
        let second = try await service.createTask(NewTaskInput(title: "Second", status: .backlog, priority: 2))

        let moved = try await service.moveTask(taskID: second.id, to: .backlog, beforeTaskID: first.id)

        XCTAssertEqual(moved.status, .backlog)
        XCTAssertLessThan(moved.kanbanOrder, first.kanbanOrder)
    }

    func testKanbanOrderingStaysStableWithThousandTasksAndRepeatedMoves() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let store = try makeStore()
        let service = WorkspaceService(
            taskStore: store,
            noteStore: store,
            bindingStore: store,
            checkpointStore: store,
            templateStore: store,
            kanbanColumnStore: store,
            clock: FixedClock(current: now),
        )

        var created: [Task] = []
        created.reserveCapacity(1000)
        for idx in 0 ..< 1000 {
            let task = try await service.createTask(
                NewTaskInput(title: "Task \(idx)", status: .backlog, priority: 2),
            )
            created.append(task)
        }

        let first = try XCTUnwrap(created.first)
        let middle = try XCTUnwrap(created[safe: created.count / 2])
        let last = try XCTUnwrap(created.last)

        _ = try await service.moveTask(taskID: last.id, to: .backlog, beforeTaskID: first.id)
        _ = try await service.moveTask(taskID: middle.id, to: .backlog, beforeTaskID: first.id)
        _ = try await service.moveTask(taskID: first.id, to: .backlog, beforeTaskID: nil)

        let backlogTasks = try await store.fetchTasks(includeDeleted: false)
            .filter { $0.status == .backlog }
            .sorted {
                if $0.kanbanOrder != $1.kanbanOrder {
                    return $0.kanbanOrder < $1.kanbanOrder
                }
                return $0.id.uuidString < $1.id.uuidString
            }

        XCTAssertEqual(backlogTasks.count, 1000)
        XCTAssertEqual(Set(backlogTasks.map(\.id)).count, 1000)
        XCTAssertTrue(backlogTasks.allSatisfy { $0.kanbanOrder.isFinite && !$0.kanbanOrder.isNaN })
        XCTAssertEqual(backlogTasks.last?.id, first.id)
    }

    func testToggleTaskCompletionBranches() async throws {
        let service = try makeService(now: Date(timeIntervalSince1970: 1_700_000_000))
        let created = try await service.createTask(NewTaskInput(title: "Toggle", status: .next, priority: 2))

        let completed = try await service.toggleTaskCompletion(taskID: created.id, isCompleted: true)
        XCTAssertEqual(completed.status, .done)
        XCTAssertNotNil(completed.completedAt)

        let reopened = try await service.toggleTaskCompletion(taskID: created.id, isCompleted: false)
        XCTAssertEqual(reopened.status, .next)
        XCTAssertNil(reopened.completedAt)
    }

    func testSetTaskStatusThrowsWhenTaskMissing() async throws {
        let service = try makeService(now: Date(timeIntervalSince1970: 1_700_000_000))
        await XCTAssertThrowsErrorAsync(
            try await service.setTaskStatus(taskID: UUID(), status: .done),
        )
    }

    func testCreateTaskPropagatesValidationError() async throws {
        let service = try makeService(now: Date(timeIntervalSince1970: 1_700_000_000))
        await XCTAssertThrowsErrorAsync(
            try await service.createTask(NewTaskInput(title: "Bad Priority", priority: 9)),
        ) { error in
            XCTAssertEqual(error as? DomainValidationError, .invalidPriority(9))
        }
    }

    func testRunSyncReturnsReportAndImportsEvent() async throws {
        let service = try makeService(now: Date(timeIntervalSince1970: 1_700_000_000))
        let provider = InMemoryCalendarProvider()
        let event = try CalendarEvent(
            eventIdentifier: nil,
            externalIdentifier: nil,
            calendarID: "cal",
            title: "From Calendar",
            notes: "task-stable-id:from-calendar",
            startDate: Date(timeIntervalSince1970: 1_700_000_500),
            endDate: Date(timeIntervalSince1970: 1_700_000_900),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_500),
            sourceStableID: "from-calendar",
        )
        await provider.seed(event: event)

        let report = try await service.runSync(
            configuration: SyncEngineConfiguration(checkpointID: "default", calendarID: "cal"),
            calendarProvider: provider,
        )

        XCTAssertEqual(report.tasksImported, 1)
        let imported = try await service.listTasks(filter: .all)
        XCTAssertTrue(imported.contains { $0.stableID == "from-calendar" })
    }

    func testSmoke_SeedDemoDataCreatesNotesAndTasksOnce() async throws {
        let service = try makeService(now: Date(timeIntervalSince1970: 1_700_000_000))

        try await service.seedDemoDataIfNeeded()
        let firstNotes = try await service.listNotes()
        let firstTasks = try await service.listTasks(filter: .all)

        try await service.seedDemoDataIfNeeded()
        let secondNotes = try await service.listNotes()
        let secondTasks = try await service.listTasks(filter: .all)

        XCTAssertFalse(firstNotes.isEmpty)
        XCTAssertFalse(firstTasks.isEmpty)
        XCTAssertEqual(firstNotes.count, secondNotes.count)
        XCTAssertEqual(firstTasks.count, secondTasks.count)
    }

    func testCreateNoteAutoExtractsTags() async throws {
        let service = try makeService(now: Date(timeIntervalSince1970: 1_700_000_000))
        let note = try await service.createNote(title: "Tagged", body: "Hello #swift #coding")
        XCTAssertEqual(note.tags, ["swift", "coding"])
    }

    func testUpdateNoteAutoExtractsTags() async throws {
        let service = try makeService(now: Date(timeIntervalSince1970: 1_700_000_000))
        let note = try await service.createNote(title: "Tagged", body: "Hello #swift")
        let updated = try await service.updateNote(id: note.id, title: "Tagged", body: "Hello #rust #go")
        XCTAssertEqual(updated.tags, ["rust", "go"])
    }

    func testAllTagsReturnsDistinctSortedTags() async throws {
        let service = try makeService(now: Date(timeIntervalSince1970: 1_700_000_000))
        _ = try await service.createNote(title: "A", body: "#beta #alpha")
        _ = try await service.createNote(title: "B", body: "#alpha #gamma")
        let tags = try await service.allTags()
        XCTAssertEqual(tags, ["alpha", "beta", "gamma"])
    }

    func testNotesByTagFiltersCorrectly() async throws {
        let service = try makeService(now: Date(timeIntervalSince1970: 1_700_000_000))
        _ = try await service.createNote(title: "A", body: "#swift")
        _ = try await service.createNote(title: "B", body: "#rust")
        let swiftNotes = try await service.notesByTag("swift")
        XCTAssertEqual(swiftNotes.count, 1)
        XCTAssertEqual(swiftNotes.first?.title, "A")
    }

    // MARK: - Kanban Column & Label feature tests

    func testCreateKanbanColumnAssignsPosition() async throws {
        let service = try makeService(now: Date(timeIntervalSince1970: 1_700_000_000))

        let columns = try await service.listKanbanColumns()
        let maxPosition = columns.map(\.position).max() ?? -1

        let custom = try await service.createKanbanColumn(title: "Review")

        XCTAssertEqual(custom.title, "Review")
        XCTAssertEqual(custom.position, maxPosition + 1)
        XCTAssertNil(custom.builtInStatus)

        let allColumns = try await service.listKanbanColumns()
        XCTAssertTrue(allColumns.contains(where: { $0.id == custom.id }))
    }

    func testDeleteKanbanColumnReassignsOrphanedTasks() async throws {
        let store = try makeStore()
        let service = WorkspaceService(
            taskStore: store,
            noteStore: store,
            bindingStore: store,
            checkpointStore: store,
            templateStore: store,
            kanbanColumnStore: store,
            clock: FixedClock(current: Date(timeIntervalSince1970: 1_700_000_000)),
        )

        let custom = try await service.createKanbanColumn(title: "Review")

        // Create a task assigned to the custom column
        var task = try await service.createTask(NewTaskInput(title: "Orphan", status: .doing, priority: 2))
        task.kanbanColumnID = custom.id
        task = try await service.updateTask(task)
        XCTAssertEqual(task.kanbanColumnID, custom.id)

        // Delete the custom column
        try await service.deleteKanbanColumn(id: custom.id)

        // Verify column is gone
        let columns = try await service.listKanbanColumns()
        XCTAssertFalse(columns.contains(where: { $0.id == custom.id }))

        // Verify task was reassigned to backlog with nil columnID
        let allTasks = try await service.listTasks(filter: .all)
        let orphan = allTasks.first(where: { $0.id == task.id })
        XCTAssertNotNil(orphan)
        XCTAssertEqual(orphan?.status, .backlog)
        XCTAssertNil(orphan?.kanbanColumnID)
    }

    func testAddLabelToTaskDeduplicatesByName() async throws {
        let service = try makeService(now: Date(timeIntervalSince1970: 1_700_000_000))

        let task = try await service.createTask(NewTaskInput(title: "Label test", status: .backlog, priority: 2))
        let label = TaskLabel(name: "Bug", colorHex: "#FF0000")

        let labeled = try await service.addLabelToTask(taskID: task.id, label: label)
        XCTAssertEqual(labeled.labels.count, 1)
        XCTAssertEqual(labeled.labels.first?.name, "Bug")

        // Add same label again (case-insensitive) — should not duplicate
        let dupeLabel = TaskLabel(name: "bug", colorHex: "#FF0000")
        let afterDupe = try await service.addLabelToTask(taskID: task.id, label: dupeLabel)
        XCTAssertEqual(afterDupe.labels.count, 1)
    }

    func testMoveTaskToBuiltInStatusClearsColumnID() async throws {
        let store = try makeStore()
        let service = WorkspaceService(
            taskStore: store,
            noteStore: store,
            bindingStore: store,
            checkpointStore: store,
            templateStore: store,
            kanbanColumnStore: store,
            clock: FixedClock(current: Date(timeIntervalSince1970: 1_700_000_000)),
        )

        let custom = try await service.createKanbanColumn(title: "Custom Col")

        var task = try await service.createTask(NewTaskInput(title: "Move test", status: .backlog, priority: 2))
        task.kanbanColumnID = custom.id
        task = try await service.updateTask(task)
        XCTAssertEqual(task.kanbanColumnID, custom.id)

        // Move to a built-in status
        let moved = try await service.moveTask(taskID: task.id, to: .next, beforeTaskID: nil)
        XCTAssertEqual(moved.status, .next)
        XCTAssertNil(moved.kanbanColumnID)
    }

    func testFetchNotesByTagInStorageLayer() async throws {
        let store = try makeStore()
        let note = Note(title: "Tagged", body: "Content", tags: ["swift", "ios"], updatedAt: Date())
        _ = try await store.upsertNote(note)
        let results = try await store.fetchNotesByTag("swift")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.tags, ["swift", "ios"])
    }

    private func makeService(now: Date) throws -> WorkspaceService {
        let store = try makeStore()
        return WorkspaceService(
            taskStore: store,
            noteStore: store,
            bindingStore: store,
            checkpointStore: store,
            templateStore: store,
            kanbanColumnStore: store,
            clock: FixedClock(current: now),
        )
    }

    func testListTasksSortedByDueDate() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let service = try makeService(now: now)
        let tomorrow = now.addingTimeInterval(86400)
        let nextWeek = now.addingTimeInterval(86400 * 7)

        let task1 = try await service.createTask(.init(
            title: "Task A", dueStart: nextWeek, priority: 3,
        ))
        let task2 = try await service.createTask(.init(
            title: "Task B", dueStart: tomorrow, priority: 3,
        ))
        let task3 = try await service.createTask(.init(
            title: "Task C", priority: 3, // No due date
        ))

        let sorted = try await service.listTasks(filter: .all, sortOrder: .dueDate)

        XCTAssertEqual(sorted[0].id, task2.id) // tomorrow first
        XCTAssertEqual(sorted[1].id, task1.id) // next week second
        XCTAssertEqual(sorted[2].id, task3.id) // no due date last
    }

    func testListTasksSortedByPriority() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let service = try makeService(now: now)

        let task1 = try await service.createTask(.init(
            title: "Low Priority", dueStart: now, priority: 4,
        ))
        let task2 = try await service.createTask(.init(
            title: "High Priority", dueStart: now, priority: 1,
        ))
        let task3 = try await service.createTask(.init(
            title: "Medium Priority", dueStart: now, priority: 2,
        ))

        let sorted = try await service.listTasks(filter: .all, sortOrder: .priority)

        XCTAssertEqual(sorted[0].id, task2.id) // priority 1
        XCTAssertEqual(sorted[1].id, task3.id) // priority 2
        XCTAssertEqual(sorted[2].id, task1.id) // priority 4
    }

    func testListTasksSortedByTitle() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let service = try makeService(now: now)

        let task1 = try await service.createTask(.init(title: "Zebra", priority: 3))
        let task2 = try await service.createTask(.init(title: "Apple", priority: 3))
        let task3 = try await service.createTask(.init(title: "Mango", priority: 3))

        let sorted = try await service.listTasks(filter: .all, sortOrder: .title)

        XCTAssertEqual(sorted[0].id, task2.id) // Apple
        XCTAssertEqual(sorted[1].id, task3.id) // Mango
        XCTAssertEqual(sorted[2].id, task1.id) // Zebra
    }

    func testListTasksSortedByCreationDate() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let service = try makeService(now: now)

        let task1 = try await service.createTask(.init(title: "First", priority: 3))
        let task2 = try await service.createTask(.init(title: "Second", priority: 3))
        let task3 = try await service.createTask(.init(title: "Third", priority: 3))

        let sorted = try await service.listTasks(filter: .all, sortOrder: .creationDate)

        // Creation date sort is descending (newest first)
        XCTAssertEqual(sorted[0].id, task3.id)
        XCTAssertEqual(sorted[1].id, task2.id)
        XCTAssertEqual(sorted[2].id, task1.id)
    }

    func testListTasksSortByDueDateWithNullValues() async throws {
        let service = try makeService(now: testNow)

        let taskWithDue = try await service.createTask(.init(title: "Has due", dueStart: testNow, priority: 3))
        let taskWithoutDue = try await service.createTask(.init(title: "No due", priority: 3))

        let sorted = try await service.listTasks(filter: .all, sortOrder: .dueDate)

        XCTAssertEqual([sorted[0].id, sorted[1].id], [taskWithDue.id, taskWithoutDue.id])
    }

    func testListTasksSortByPriorityWithEqualValues() async throws {
        let service = try makeService(now: testNow)

        let task1 = try await service.createTask(.init(title: "First", dueStart: testNow, priority: 3))
        let task2 = try await service.createTask(.init(title: "Second", dueStart: testNow, priority: 3))

        let sorted = try await service.listTasks(filter: .all, sortOrder: .priority)

        // When priorities are equal, fall back to updatedAt (descending)
        XCTAssertEqual([sorted[0].id, sorted[1].id], [task2.id, task1.id])
    }

    func testListTasksSortByTitleCaseInsensitive() async throws {
        let service = try makeService(now: testNow)

        _ = try await service.createTask(.init(title: "zebra", priority: 3))
        _ = try await service.createTask(.init(title: "APPLE", priority: 3))
        _ = try await service.createTask(.init(title: "mAnGo", priority: 3))

        let sorted = try await service.listTasks(filter: .all, sortOrder: .title)

        XCTAssertEqual(sorted.map(\.title), ["APPLE", "mAnGo", "zebra"])
    }

    func testListTasksSortWithFilterToday() async throws {
        let service = try makeService(now: testNow)
        let tomorrow = testNow.addingTimeInterval(oneDay)

        let todayTask1 = try await service.createTask(NewTaskInput(title: "Today 1", dueStart: testNow, priority: 4))
        let todayTask2 = try await service.createTask(NewTaskInput(title: "Today 2", dueStart: testNow, priority: 2))
        _ = try await service.createTask(NewTaskInput(title: "Tomorrow", dueStart: tomorrow, priority: 1))

        let sorted = try await service.listTasks(filter: .today, sortOrder: .priority)

        XCTAssertEqual(sorted.map(\.id), [todayTask2.id, todayTask1.id])
    }

    func testListTasksSortWithFilterCompleted() async throws {
        let service = try makeService(now: testNow)

        let done1 = try await service.createTask(NewTaskInput(title: "Done 1", priority: 3))
        let done2 = try await service.createTask(NewTaskInput(title: "Done 2", priority: 1))

        _ = try await service.setTaskStatus(taskID: done1.id, status: .done)
        _ = try await service.setTaskStatus(taskID: done2.id, status: .done)

        let sorted = try await service.listTasks(filter: .completed, sortOrder: .priority)

        XCTAssertEqual(sorted.map(\.id), [done2.id, done1.id])
    }

    func testSortOrderPreservesAcrossMultipleFilters() async throws {
        let service = try makeService(now: testNow)
        let futureDate = testNow.addingTimeInterval(oneDay * 7)

        _ = try await service.createTask(NewTaskInput(title: "Z-Task", dueStart: futureDate, priority: 3))
        _ = try await service.createTask(NewTaskInput(title: "A-Task", dueStart: futureDate, priority: 3))

        let expectedTitles = ["A-Task", "Z-Task"]
        var sorted = try await service.listTasks(filter: .all, sortOrder: .title)
        XCTAssertEqual(sorted.map(\.title), expectedTitles)

        // Same sort should apply to different filter
        sorted = try await service.listTasks(filter: .upcoming, sortOrder: .title)
        XCTAssertEqual(sorted.map(\.title), expectedTitles)
    }

    private func makeStore() throws -> SQLiteStore {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("notes-engine-feature-tests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return try SQLiteStore(databaseURL: folder.appendingPathComponent("notes.sqlite"))
    }
}

private func XCTAssertThrowsErrorAsync(
    _ expression: @autoclosure () async throws -> some Any,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line,
    _ errorHandler: (Error) -> Void = { _ in },
) async {
    do {
        _ = try await expression()
        XCTFail("Expected error to be thrown. \(message())", file: file, line: line)
    } catch {
        errorHandler(error)
    }
}

private struct FixedClock: Clock {
    let current: Date

    func now() -> Date {
        current
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
