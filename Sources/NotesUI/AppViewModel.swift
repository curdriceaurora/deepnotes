import Foundation
import Observation
import os
import NotesDomain
import NotesFeatures
import NotesSync

public enum NoteEditMode: String, Sendable {
    case edit
    case preview
}

public typealias CalendarProviderFactory = @Sendable () -> CalendarProvider

public enum RecurrenceEditScope: String, Sendable {
    case thisOccurrence
    case entireSeries
}

public struct RecurrenceEditPrompt: Sendable, Equatable {
    public let taskID: UUID
    public let targetStatus: TaskStatus
    public let beforeTaskID: UUID?
    public let occurrenceDate: Date?
}

public struct RecurrenceDeletePrompt: Sendable, Equatable {
    public let taskID: UUID
    public let occurrenceDate: Date?
}

@MainActor
@Observable
public final class AppViewModel {
    public private(set) var notesTotalCount: Int = 0
    public private(set) var notesNextOffset: Int?
    private static let notesPageSize = 50
    private static let signposter = OSSignposter(subsystem: "com.notes.app", category: "Launch")

    public private(set) var notes: [NoteListItem] = []
    public var selectedNoteID: UUID?
    public var selectedNoteTitle: String = ""
    public var selectedNoteBody: String = ""
    public var noteSearchQuery: String = ""
    public private(set) var noteSearchSnippetsByID: [UUID: String] = [:]
    public private(set) var wikiLinkSuggestions: [String] = []
    public private(set) var isWikiLinkSuggestionVisible: Bool = false
    public var quickOpenQuery: String = ""
    public var isQuickOpenPresented: Bool = false
    public private(set) var quickOpenResults: [NoteListItem] = []
    public private(set) var backlinks: [NoteBacklink] = []
    public private(set) var unlinkedMentions: [NoteBacklink] = []
    public private(set) var graphNodes: [GraphNode] = []
    public private(set) var graphEdges: [GraphEdge] = []
    public private(set) var templates: [NoteTemplate] = []
    public var isTemplatePickerPresented: Bool = false
    public var isTemplateManagerPresented: Bool = false
    public var newTemplateName: String = ""
    public var newTemplateBody: String = ""
    public private(set) var allTagsList: [String] = []
    public private(set) var selectedTagFilter: String?
    public var noteEditMode: NoteEditMode = .edit
    public private(set) var renderedMarkdown: AttributedString = AttributedString()

    public private(set) var tasks: [Task] = []
    public var taskFilter: TaskListFilter = .all
    public var quickTaskTitle: String = ""
    public var quickTaskPriority: Int = 3
    public var selectedTaskForEditing: Task?
    public var newSubtaskTitle: String = ""

    // Multi-select state
    public var isMultiSelectMode: Bool = false
    public private(set) var selectedTaskIDs: Set<UUID> = []
    public private(set) var kanbanColumns: [KanbanColumn] = []
    public var kanbanGrouping: KanbanGrouping = .none
    public var isColumnEditorPresented: Bool = false
    public var newColumnTitle: String = ""
    public private(set) var allLabels: [TaskLabel] = []
    private var allTasks: [Task] = []
    private var tasksByColumn: [UUID: [Task]] = [:]

    public var syncCalendarID: String = ""
    public private(set) var isSyncing: Bool = false
    public private(set) var syncStatusText: String = "Idle"
    public private(set) var lastSyncReport: SyncRunReport?
    public private(set) var lastDiagnosticsExportURL: URL?
    public private(set) var lastDiagnosticsExportText: String = ""
    public private(set) var recurrenceEditPrompt: RecurrenceEditPrompt?
    public private(set) var recurrenceDeletePrompt: RecurrenceDeletePrompt?
    public private(set) var recurrenceConflictMessage: String?

    public private(set) var isBusy: Bool = false
    public private(set) var errorMessage: String?
    public private(set) var draggingTaskID: UUID?
    public private(set) var dropTargetStatus: TaskStatus?
    public private(set) var dropTargetColumnID: UUID?
    public private(set) var dropTargetTaskID: UUID?

    private let service: WorkspaceServicing
    private let calendarProviderFactory: CalendarProviderFactory
    private var pendingTaskMutation: PendingTaskMutation?
    private var pendingTaskDeletion: PendingTaskDeletion?
    private var noteSearchDebounceTask: _Concurrency.Task<Void, Never>?
    private var periodicSyncTask: _Concurrency.Task<Void, Never>?

    public init(
        service: WorkspaceServicing,
        calendarProviderFactory: @escaping CalendarProviderFactory,
        syncCalendarID: String
    ) {
        self.service = service
        self.calendarProviderFactory = calendarProviderFactory
        self.syncCalendarID = syncCalendarID
    }

    public func load() async {
        let signpostID = Self.signposter.makeSignpostID()
        let state = Self.signposter.beginInterval("load", id: signpostID)
        await runTask {
            try await service.seedDemoDataIfNeeded()
            try await reloadKanbanColumns()
            async let r1: () = reloadNotes(selectFirstIfNeeded: true)
            async let r2: () = reloadTags()
            async let r3: () = loadGraph()
            async let r4: () = reloadTemplates()
            async let r5: () = reloadTasksWithoutWrapper()
            async let r6: Bool = service.requestNotificationPermission()
            try await r1; try await r2; try await r3; try await r4; try await r5; _ = try await r6
        }
        Self.signposter.endInterval("load", state)
        // Start periodic auto-sync (every 5 minutes when app is active)
        periodicSyncTask = _Concurrency.Task { [weak self] in
            while !_Concurrency.Task.isCancelled {
                try? await _Concurrency.Task.sleep(for: .seconds(300)) // 5 minutes
                guard !_Concurrency.Task.isCancelled else { break }
                await self?.autoSync()
            }
        }
    }

    public func loadMoreNotes() async {
        guard let nextOffset = notesNextOffset, noteSearchQuery.isEmpty, selectedTagFilter == nil else { return }
        await runTask {
            let page = try await service.listNoteListItems(limit: Self.notesPageSize, offset: nextOffset)
            notes.append(contentsOf: page.items)
            notesTotalCount = page.totalCount
            notesNextOffset = page.nextOffset
        }
    }

    public func createNote() async {
        await runTask {
            let created = try await service.createNote(title: "New Note", body: "")
            noteSearchQuery = ""
            try await reloadNotes(selectFirstIfNeeded: false)
            await selectNote(id: created.id)
        }
    }

    public func saveSelectedNote() async {
        guard let selectedNoteID else {
            return
        }

        await runTask {
            _ = try await service.updateNote(id: selectedNoteID, title: selectedNoteTitle, body: selectedNoteBody)
            try await reloadNotes(selectFirstIfNeeded: false)
            try await reloadTags()
            try await reloadBacklinks(for: selectedNoteID)
        }
    }

    public func selectNote(id: UUID?) async {
        await runTask {
            try await selectNoteWithoutWrapper(id: id)
        }
    }

    public func createQuickTask() async {
        let title = quickTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            return
        }

        let priority = quickTaskPriority
        await runTask {
            _ = try await service.createTask(
                NewTaskInput(
                    noteID: selectedNoteID,
                    title: title,
                    details: selectedNoteBody.isEmpty ? "" : "From note: \(selectedNoteTitle)",
                    dueStart: Calendar.current.date(byAdding: .hour, value: 2, to: Date()),
                    dueEnd: Calendar.current.date(byAdding: .hour, value: 3, to: Date()),
                    status: .next,
                    priority: priority
                )
            )
            quickTaskTitle = ""
            quickTaskPriority = 3
            await reloadTasks()
        }
    }

    public func openTaskDetail(taskID: UUID) {
        selectedTaskForEditing = allTasks.first(where: { $0.id == taskID })
    }

    public func closeTaskDetail() {
        selectedTaskForEditing = nil
    }

    public func saveTaskDetail(_ task: Task) async {
        await runTask {
            _ = try await service.updateTask(task)
            try await reloadTasksWithoutWrapper()
        }
        selectedTaskForEditing = nil
    }

    public func addSubtask(to parentID: UUID) async {
        let trimmed = newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        await runTask {
            _ = try await service.addSubtask(to: parentID, title: trimmed)
            try await reloadTasksWithoutWrapper()
        }
        newSubtaskTitle = ""
    }

    public func toggleSubtask(parentTaskID: UUID, subtaskID: UUID, isCompleted: Bool) async {
        await runTask {
            _ = try await service.toggleSubtask(parentTaskID: parentTaskID, subtaskID: subtaskID, isCompleted: isCompleted)
            try await reloadTasksWithoutWrapper()
        }
    }

    public func deleteSubtask(parentTaskID: UUID, subtaskID: UUID) async {
        await runTask {
            _ = try await service.deleteSubtask(parentTaskID: parentTaskID, subtaskID: subtaskID)
            try await reloadTasksWithoutWrapper()
        }
    }

    public func tagsForTask(_ task: Task) -> [String] {
        guard let noteID = task.noteID else { return [] }
        return notes.first(where: { $0.id == noteID })?.tags ?? []
    }

    public func reloadTasks() async {
        await runTask {
            try await reloadTasksWithoutWrapper()
        }
    }

    public func setTaskFilter(_ filter: TaskListFilter) async {
        taskFilter = filter
        await reloadTasks()
    }

    public func setNoteSearchQuery(_ query: String) async {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        noteSearchQuery = normalized
        noteSearchDebounceTask?.cancel()
        noteSearchDebounceTask = _Concurrency.Task {
            try? await _Concurrency.Task.sleep(for: .milliseconds(300))
            guard !_Concurrency.Task.isCancelled else { return }
            await runTask { try await reloadNotes(selectFirstIfNeeded: false) }
        }
    }

    public func navigateToNoteByTitle(_ title: String) async {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return }
        guard let match = notes.first(where: { $0.title.lowercased() == normalized }) else { return }
        await selectNote(id: match.id)
    }

    public func toggleNoteEditMode() {
        switch noteEditMode {
        case .edit:
            noteEditMode = .preview
            renderedMarkdown = MarkdownRenderer().render(selectedNoteBody, noteTitles: notes.map(\.title))
        case .preview:
            noteEditMode = .edit
        }
    }

    public func filterByTag(_ tag: String?) async {
        selectedTagFilter = tag
        await runTask {
            try await reloadNotes(selectFirstIfNeeded: false)
        }
    }

    public func updateSelectedNoteBody(_ body: String) {
        selectedNoteBody = body
        refreshWikiLinkSuggestions()
    }

    public func refreshWikiLinkSuggestions() {
        let pattern = #"\[\[([^\]\n]*)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            wikiLinkSuggestions = []
            isWikiLinkSuggestionVisible = false
            return
        }
        let range = NSRange(selectedNoteBody.startIndex..<selectedNoteBody.endIndex, in: selectedNoteBody)
        guard let match = regex.firstMatch(in: selectedNoteBody, options: [], range: range),
              match.numberOfRanges >= 2,
              let queryRange = Range(match.range(at: 1), in: selectedNoteBody)
        else {
            wikiLinkSuggestions = []
            isWikiLinkSuggestionVisible = false
            return
        }

        let query = selectedNoteBody[queryRange]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        let candidates = notes
            .map(\.title)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let ranked = FuzzyMatcher().rank(query: query, candidates: candidates)

        wikiLinkSuggestions = Array(ranked.prefix(8).map(\.title))
        isWikiLinkSuggestionVisible = !wikiLinkSuggestions.isEmpty
    }

    public func applyWikiLinkSuggestion(_ title: String) {
        let pattern = #"\[\[([^\]\n]*)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return
        }

        let range = NSRange(selectedNoteBody.startIndex..<selectedNoteBody.endIndex, in: selectedNoteBody)
        guard let match = regex.firstMatch(in: selectedNoteBody, options: [], range: range),
              let fullRange = Range(match.range(at: 0), in: selectedNoteBody)
        else {
            return
        }

        selectedNoteBody.replaceSubrange(fullRange, with: "[[\(title)]]")
        wikiLinkSuggestions = []
        isWikiLinkSuggestionVisible = false
    }

    public func insertMarkdownHeading() {
        insertMarkdownLinePrefix("# ")
    }

    public func insertMarkdownBullet() {
        insertMarkdownLinePrefix("- ")
    }

    public func insertMarkdownCheckbox() {
        insertMarkdownLinePrefix("- [ ] ")
    }

    public func openQuickSwitcher() {
        quickOpenQuery = ""
        quickOpenResults = notes
        isQuickOpenPresented = true
    }

    public func closeQuickSwitcher() {
        isQuickOpenPresented = false
        quickOpenQuery = ""
        quickOpenResults = []
    }

    public func setQuickOpenQuery(_ query: String) {
        quickOpenQuery = query
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            quickOpenResults = notes
            return
        }
        quickOpenResults = notes
            .filter { $0.title.localizedCaseInsensitiveContains(trimmed) }
    }

    public func selectQuickOpenResult(noteID: UUID) async {
        await selectNote(id: noteID)
        closeQuickSwitcher()
    }

    public func noteSearchSnippet(for noteID: UUID) -> String? {
        noteSearchSnippetsByID[noteID]
    }

    public func toggleTaskCompletion(taskID: UUID, isCompleted: Bool) async {
        let targetStatus: TaskStatus = isCompleted ? .done : .next
        await requestTaskMove(taskID: taskID, to: targetStatus, beforeTaskID: nil)
    }

    public func moveTask(taskID: UUID, to status: TaskStatus, beforeTaskID: UUID? = nil) async {
        await requestTaskMove(taskID: taskID, to: status, beforeTaskID: beforeTaskID)
    }

    public func deleteTask(taskID: UUID) async {
        await requestTaskDeletion(taskID: taskID)
    }

    public func toggleMultiSelectMode() {
        isMultiSelectMode.toggle()
        if !isMultiSelectMode {
            exitMultiSelectMode()
        }
    }

    private func exitMultiSelectMode() {
        selectedTaskIDs.removeAll()
        isMultiSelectMode = false
    }

    public func toggleTaskSelection(taskID: UUID) {
        if selectedTaskIDs.contains(taskID) {
            selectedTaskIDs.remove(taskID)
        } else {
            selectedTaskIDs.insert(taskID)
        }
    }

    public func isTaskSelected(_ taskID: UUID) -> Bool {
        selectedTaskIDs.contains(taskID)
    }

    public func bulkMoveTasksToStatus(_ status: TaskStatus) async {
        guard !selectedTaskIDs.isEmpty else { return }
        await runTask {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for taskID in selectedTaskIDs {
                    group.addTask {
                        _ = try await self.service.moveTask(taskID: taskID, to: status, beforeTaskID: nil)
                    }
                }
                try await group.waitForAll()
            }
            try await reloadTasksWithoutWrapper()
            self.exitMultiSelectMode()
        }
    }

    public func resolveRecurrenceEditPrompt(scope: RecurrenceEditScope) async {
        guard let pendingTaskMutation else {
            recurrenceEditPrompt = nil
            return
        }
        recurrenceEditPrompt = nil
        self.pendingTaskMutation = nil

        await applyTaskMutation(
            taskID: pendingTaskMutation.taskID,
            to: pendingTaskMutation.targetStatus,
            beforeTaskID: pendingTaskMutation.beforeTaskID,
            scope: scope
        )
    }

    public func dismissRecurrenceEditPrompt() {
        recurrenceEditPrompt = nil
        pendingTaskMutation = nil
    }

    public func resolveRecurrenceDeletePrompt(scope: RecurrenceEditScope) async {
        guard let pendingTaskDeletion else {
            recurrenceDeletePrompt = nil
            return
        }
        recurrenceDeletePrompt = nil
        self.pendingTaskDeletion = nil

        await applyTaskDeletion(taskID: pendingTaskDeletion.taskID, scope: scope)
    }

    public func dismissRecurrenceDeletePrompt() {
        recurrenceDeletePrompt = nil
        pendingTaskDeletion = nil
    }

    private func requestTaskMove(taskID: UUID, to status: TaskStatus, beforeTaskID: UUID?) async {
        guard let task = taskByID(taskID) else {
            return
        }

        if let occurrenceDate = TaskCalendarMapper.recurrenceExceptionDate(in: task.details) {
            pendingTaskMutation = PendingTaskMutation(
                taskID: taskID,
                targetStatus: status,
                beforeTaskID: beforeTaskID,
                occurrenceDate: occurrenceDate
            )
            recurrenceEditPrompt = RecurrenceEditPrompt(
                taskID: taskID,
                targetStatus: status,
                beforeTaskID: beforeTaskID,
                occurrenceDate: occurrenceDate
            )
            return
        }

        await applyTaskMutation(taskID: taskID, to: status, beforeTaskID: beforeTaskID, scope: .thisOccurrence)
    }

    private func requestTaskDeletion(taskID: UUID) async {
        guard let task = taskByID(taskID) else {
            return
        }

        if let occurrenceDate = TaskCalendarMapper.recurrenceExceptionDate(in: task.details) {
            pendingTaskDeletion = PendingTaskDeletion(taskID: taskID, occurrenceDate: occurrenceDate)
            recurrenceDeletePrompt = RecurrenceDeletePrompt(taskID: taskID, occurrenceDate: occurrenceDate)
            return
        }

        await applyTaskDeletion(taskID: taskID, scope: .thisOccurrence)
    }

    private func applyOptimisticTaskMove(taskID: UUID, to status: TaskStatus) {
        guard let idx = allTasks.firstIndex(where: { $0.id == taskID }) else { return }
        var updated = allTasks[idx]
        updated.status = status
        allTasks[idx] = updated
        if let tIdx = tasks.firstIndex(where: { $0.id == taskID }) { tasks[tIdx] = updated }
        rebuildTaskCache(sourceTasks: allTasks)
    }

    private func applyTaskMutation(taskID: UUID, to status: TaskStatus, beforeTaskID: UUID?, scope: RecurrenceEditScope) async {
        await runTask {
            if scope == .entireSeries,
               let existing = taskByID(taskID),
               TaskCalendarMapper.recurrenceExceptionDate(in: existing.details) != nil
            {
                let seriesTasks = try await service.listAllTasks().filter { $0.stableID == existing.stableID }
                let hasSeriesAnchor = seriesTasks.contains {
                    TaskCalendarMapper.recurrenceExceptionDate(in: $0.details) == nil && ($0.recurrenceRule?.isEmpty == false)
                }
                guard hasSeriesAnchor else {
                    throw RecurrenceSeriesResolutionError.parentSeriesNotFound
                }

                let seriesIDs = Set(seriesTasks.map(\.id))
                let insertionAnchor = beforeTaskID.flatMap { seriesIDs.contains($0) ? nil : $0 }
                let orderedSeries = seriesTasks.sorted(by: Self.kanbanTaskSort)

                for seriesTask in orderedSeries {
                    if TaskCalendarMapper.recurrenceExceptionDate(in: seriesTask.details) != nil {
                        var normalized = seriesTask
                        normalized.details = TaskCalendarMapper.removingRecurrenceExceptionMarker(from: seriesTask.details)
                        _ = try await service.updateTask(normalized)
                    }
                    _ = try await service.moveTask(taskID: seriesTask.id, to: status, beforeTaskID: insertionAnchor)
                }
                try await reloadTasksWithoutWrapper()
                return
            }

            // Optimistic update: reflect status change immediately before persistence
            applyOptimisticTaskMove(taskID: taskID, to: status)
            _ = try await service.moveTask(taskID: taskID, to: status, beforeTaskID: beforeTaskID)
            try await reloadTasksWithoutWrapper()
        }
    }

    private func applyTaskDeletion(taskID: UUID, scope: RecurrenceEditScope) async {
        await runTask {
            let allTasks = try await service.listAllTasks()
            if scope == .entireSeries,
               let existing = allTasks.first(where: { $0.id == taskID }),
               TaskCalendarMapper.recurrenceExceptionDate(in: existing.details) != nil {
                let seriesTasks = allTasks.filter { $0.stableID == existing.stableID }
                let hasSeriesAnchor = seriesTasks.contains {
                    TaskCalendarMapper.recurrenceExceptionDate(in: $0.details) == nil && ($0.recurrenceRule?.isEmpty == false)
                }
                guard hasSeriesAnchor else {
                    throw RecurrenceSeriesResolutionError.parentSeriesNotFound
                }

                for seriesTask in seriesTasks {
                    try await service.deleteTask(taskID: seriesTask.id)
                }
                try await reloadTasksWithoutWrapper()
                return
            }

            try await service.deleteTask(taskID: taskID)
            try await reloadTasksWithoutWrapper()
        }
    }

    public func beginTaskDrag(taskID: UUID) {
        draggingTaskID = taskID
    }

    public func setDropTargetStatus(_ status: TaskStatus?) {
        dropTargetStatus = status
        if let status {
            dropTargetColumnID = kanbanColumns.first(where: { $0.builtInStatus == status })?.id
        } else {
            dropTargetColumnID = nil
        }
    }

    public func setDropTargetColumn(_ columnID: UUID?) {
        dropTargetColumnID = columnID
        if let columnID, let col = kanbanColumns.first(where: { $0.id == columnID }) {
            dropTargetStatus = col.builtInStatus
        } else {
            dropTargetStatus = nil
        }
    }

    public func setDropTargetTaskID(_ taskID: UUID?) {
        dropTargetTaskID = taskID
    }

    public func endTaskDrag() {
        draggingTaskID = nil
        dropTargetStatus = nil
        dropTargetColumnID = nil
        dropTargetTaskID = nil
    }

    public func performTaskDrop(taskPayloads: [String], to status: TaskStatus, beforeTaskID: UUID?) -> Bool {
        defer { endTaskDrag() }

        guard let drop = taskDropInput(from: taskPayloads, to: status, beforeTaskID: beforeTaskID) else {
            return false
        }

        if let occurrenceDate = drop.occurrenceDate {
            pendingTaskMutation = PendingTaskMutation(
                taskID: drop.taskID,
                targetStatus: drop.status,
                beforeTaskID: drop.beforeTaskID,
                occurrenceDate: occurrenceDate
            )
            recurrenceEditPrompt = RecurrenceEditPrompt(
                taskID: drop.taskID,
                targetStatus: drop.status,
                beforeTaskID: drop.beforeTaskID,
                occurrenceDate: occurrenceDate
            )
            return false
        }
        if drop.isNoOp {
            return true
        }

        _Concurrency.Task {
            await applyTaskMutation(taskID: drop.taskID, to: drop.status, beforeTaskID: drop.beforeTaskID, scope: .thisOccurrence)
        }
        return true
    }

    public func handleTaskDrop(taskPayloads: [String], to status: TaskStatus, beforeTaskID: UUID?) async -> Bool {
        defer { endTaskDrag() }

        guard let drop = taskDropInput(from: taskPayloads, to: status, beforeTaskID: beforeTaskID) else {
            return false
        }

        if let occurrenceDate = drop.occurrenceDate {
            pendingTaskMutation = PendingTaskMutation(
                taskID: drop.taskID,
                targetStatus: drop.status,
                beforeTaskID: drop.beforeTaskID,
                occurrenceDate: occurrenceDate
            )
            recurrenceEditPrompt = RecurrenceEditPrompt(
                taskID: drop.taskID,
                targetStatus: drop.status,
                beforeTaskID: drop.beforeTaskID,
                occurrenceDate: occurrenceDate
            )
            return false
        }
        if drop.isNoOp {
            return true
        }

        await moveTask(taskID: drop.taskID, to: drop.status, beforeTaskID: drop.beforeTaskID)
        if recurrenceEditPrompt != nil {
            return false
        }
        return errorMessage == nil
    }

    private func taskDropInput(from payloads: [String], to status: TaskStatus, beforeTaskID: UUID?) -> TaskDropInput? {
        guard let first = payloads.first, let taskID = UUID(uuidString: first) else {
            return nil
        }

        guard let current = taskByID(taskID) else {
            return nil
        }
        if beforeTaskID == taskID {
            return TaskDropInput(
                taskID: taskID,
                status: status,
                beforeTaskID: beforeTaskID,
                occurrenceDate: nil,
                isNoOp: true
            )
        }
        if current.status == status && beforeTaskID == nil {
            let ordered = tasks(for: status)
            if ordered.last?.id == taskID {
                return TaskDropInput(
                    taskID: taskID,
                    status: status,
                    beforeTaskID: beforeTaskID,
                    occurrenceDate: nil,
                    isNoOp: true
                )
            }
        }

        return TaskDropInput(
            taskID: taskID,
            status: status,
            beforeTaskID: beforeTaskID,
            occurrenceDate: TaskCalendarMapper.recurrenceExceptionDate(in: current.details),
            isNoOp: false
        )
    }

    public func tasks(for status: TaskStatus) -> [Task] {
        guard let column = kanbanColumns.first(where: { $0.builtInStatus == status }) else { return [] }
        return tasksForColumn(column.id)
    }

    public func tasksForColumn(_ columnID: UUID) -> [Task] {
        tasksByColumn[columnID] ?? []
    }

    public func groupedTasks(for columnID: UUID) -> [(key: String, tasks: [Task])] {
        let columnTasks = tasksForColumn(columnID)
        switch kanbanGrouping {
        case .none:
            return [("", columnTasks)]
        case .priority:
            var groups: [String: [Task]] = [:]
            for task in columnTasks {
                let key = "P\(task.priority)"
                groups[key, default: []].append(task)
            }
            return groups.sorted { $0.key < $1.key }.map { (key: $0.key, tasks: $0.value) }
        case .note:
            var groups: [String: [Task]] = [:]
            for task in columnTasks {
                let noteTitle: String
                if let noteID = task.noteID, let note = notes.first(where: { $0.id == noteID }) {
                    noteTitle = note.title
                } else {
                    noteTitle = "No Note"
                }
                groups[noteTitle, default: []].append(task)
            }
            return groups.sorted { $0.key < $1.key }.map { (key: $0.key, tasks: $0.value) }
        case .label:
            var groups: [String: [Task]] = [:]
            for task in columnTasks {
                let key = task.labels.first?.name ?? "No Label"
                groups[key, default: []].append(task)
            }
            return groups.sorted { $0.key < $1.key }.map { (key: $0.key, tasks: $0.value) }
        }
    }

    public func runSync() async {
        let calendarID = syncCalendarID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !calendarID.isEmpty else {
            errorMessage = "Calendar ID is required before syncing."
            return
        }

        isSyncing = true
        syncStatusText = "Syncing..."

        await runTask {
            defer {
                isSyncing = false
            }

            let report = try await service.runSync(
                configuration: SyncEngineConfiguration(
                    checkpointID: "default",
                    calendarID: calendarID,
                    taskBatchSize: 500,
                    policy: .lastWriteWins
                ),
                calendarProvider: calendarProviderFactory()
            )
            lastSyncReport = report
            recurrenceConflictMessage = Self.extractRecurrenceConflictMessage(from: report)
            syncStatusText = "Sync complete at \(DateFormatter.syncTimeFormatter.string(from: Date()))"
            try await reloadTasksWithoutWrapper()
        }
    }

    public func autoSync() async {
        let calendarID = syncCalendarID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !calendarID.isEmpty else { return }
        // Silent sync: no isBusy flag, errors swallowed
        try? await service.runSync(
            configuration: SyncEngineConfiguration(
                checkpointID: "default",
                calendarID: calendarID,
                taskBatchSize: 500,
                policy: .lastWriteWins
            ),
            calendarProvider: calendarProviderFactory()
        )
        try? await reloadTasksWithoutWrapper()
    }

    public func exportSyncDiagnostics() async {
        await runTask {
            guard let report = lastSyncReport else {
                throw SyncDiagnosticsExportError.missingReport
            }
            guard !report.diagnostics.isEmpty else {
                throw SyncDiagnosticsExportError.noDiagnostics
            }

            let content = diagnosticsExportText(from: report)
            let fileURL = try writeDiagnosticsExport(content: content)

            lastDiagnosticsExportText = content
            lastDiagnosticsExportURL = fileURL
            syncStatusText = "Diagnostics exported to \(fileURL.path)"
        }
    }

    private func reloadTags() async throws {
        allTagsList = try await service.allTags()
    }

    private func reloadNotes(selectFirstIfNeeded: Bool) async throws {
        if noteSearchQuery.isEmpty {
            if let tag = selectedTagFilter {
                notes = try await service.listNoteListItems(tag: tag)
                notesTotalCount = notes.count
                notesNextOffset = nil
            } else {
                let page = try await service.listNoteListItems(limit: Self.notesPageSize, offset: 0)
                notes = page.items
                notesTotalCount = page.totalCount
                notesNextOffset = page.nextOffset
            }
            noteSearchSnippetsByID = [:]
        } else {
            let page = try await service.searchNotesPage(
                query: noteSearchQuery,
                mode: .smart,
                limit: 100,
                offset: 0
            )
            notes = page.hits.map { $0.note.listItem }
            notesTotalCount = page.totalCount
            notesNextOffset = nil
            noteSearchSnippetsByID = Dictionary(uniqueKeysWithValues: page.hits.compactMap { hit in
                guard let snippet = hit.snippet else {
                    return nil
                }
                return (hit.note.id, snippet)
            })
        }
        if isQuickOpenPresented {
            setQuickOpenQuery(quickOpenQuery)
        }

        if selectFirstIfNeeded, selectedNoteID == nil {
            try await selectNoteWithoutWrapper(id: notes.first?.id)
        } else if let selectedNoteID {
            let selectedIsInNewList = notes.contains(where: { $0.id == selectedNoteID })
            if selectedIsInNewList {
                try await selectNoteWithoutWrapper(id: selectedNoteID)
            } else {
                try await selectNoteWithoutWrapper(id: nil)
            }
        }
    }

    private func reloadTasksWithoutWrapper() async throws {
        async let filtered = service.listTasks(filter: taskFilter)
        async let all = service.listAllTasks()
        tasks = try await filtered
        allTasks = try await all
        rebuildTaskCache(sourceTasks: allTasks)
    }

    private func rebuildTaskCache(sourceTasks: [Task]) {
        var next: [UUID: [Task]] = [:]
        for column in kanbanColumns {
            next[column.id] = []
        }
        for task in sourceTasks {
            if let columnID = task.kanbanColumnID, next[columnID] != nil {
                next[columnID, default: []].append(task)
            } else if let column = kanbanColumns.first(where: { $0.builtInStatus == task.status }) {
                next[column.id, default: []].append(task)
            }
        }
        for columnID in next.keys {
            next[columnID]?.sort(by: Self.kanbanTaskSort)
        }
        tasksByColumn = next

        var seen = Set<String>()
        var labels: [TaskLabel] = []
        for task in sourceTasks {
            for label in task.labels {
                let key = label.name.lowercased()
                if !seen.contains(key) {
                    seen.insert(key)
                    labels.append(label)
                }
            }
        }
        allLabels = labels.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    private func taskByID(_ taskID: UUID) -> Task? {
        allTasks.first(where: { $0.id == taskID }) ?? tasks.first(where: { $0.id == taskID })
    }

    private static func kanbanTaskSort(_ lhs: Task, _ rhs: Task) -> Bool {
        if lhs.kanbanOrder != rhs.kanbanOrder {
            return lhs.kanbanOrder < rhs.kanbanOrder
        }
        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt > rhs.updatedAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func reloadBacklinks(for noteID: UUID) async throws {
        backlinks = try await service.backlinks(for: noteID)
    }

    private func selectNoteWithoutWrapper(id: UUID?) async throws {
        selectedNoteID = id
        noteEditMode = .edit
        guard let id else {
            selectedNoteID = nil
            selectedNoteTitle = ""
            selectedNoteBody = ""
            wikiLinkSuggestions = []
            isWikiLinkSuggestionVisible = false
            backlinks = []
            unlinkedMentions = []
            return
        }

        guard let selected = try await service.fetchNote(id: id) else {
            selectedNoteID = nil
            selectedNoteTitle = ""
            selectedNoteBody = ""
            wikiLinkSuggestions = []
            isWikiLinkSuggestionVisible = false
            backlinks = []
            unlinkedMentions = []
            return
        }

        selectedNoteTitle = selected.title
        selectedNoteBody = selected.body
        wikiLinkSuggestions = []
        isWikiLinkSuggestionVisible = false
        try await reloadBacklinks(for: id)
        unlinkedMentions = try await service.unlinkedMentions(for: id)
    }

    private func insertMarkdownLinePrefix(_ prefix: String) {
        let trimmedPrefix = prefix.trimmingCharacters(in: .newlines)
        guard !trimmedPrefix.isEmpty else {
            return
        }

        if selectedNoteBody.isEmpty {
            selectedNoteBody = trimmedPrefix + " "
        } else if selectedNoteBody.hasSuffix("\n") {
            selectedNoteBody += trimmedPrefix + " "
        } else {
            selectedNoteBody += "\n" + trimmedPrefix + " "
        }
        refreshWikiLinkSuggestions()
    }

    private static func extractRecurrenceConflictMessage(from report: SyncRunReport) -> String? {
        let detachedConflict = report.diagnostics.first { entry in
            let normalized = entry.message.lowercased()
            return normalized.contains("detached recurrence exception") && entry.severity != .info
        }
        return detachedConflict?.message
    }

    private func runTask(_ work: () async throws -> Void) async {
        isBusy = true
        errorMessage = nil
        do {
            try await work()
        } catch {
            errorMessage = error.localizedDescription
        }
        isBusy = false
    }

    private func diagnosticsExportText(from report: SyncRunReport) -> String {
        var lines: [String] = []
        lines.append("NotesEngine Sync Diagnostics")
        lines.append("Generated: \(DateFormatter.syncDiagnosticTimestampFormatter.string(from: Date()))")
        lines.append("Calendar ID: \(syncCalendarID)")
        lines.append("Summary:")
        lines.append("  tasksPushed=\(report.tasksPushed)")
        lines.append("  eventsPulled=\(report.eventsPulled)")
        lines.append("  tasksImported=\(report.tasksImported)")
        lines.append("  tasksUpdatedFromCalendar=\(report.tasksUpdatedFromCalendar)")
        lines.append("  tasksDeletedFromCalendar=\(report.tasksDeletedFromCalendar)")
        lines.append("  eventsDeletedFromTasks=\(report.eventsDeletedFromTasks)")
        lines.append("  finalTaskVersionCursor=\(report.finalTaskVersionCursor)")
        lines.append("  finalCalendarToken=\(report.finalCalendarToken ?? "")")
        lines.append("")
        lines.append("Diagnostics:")

        for entry in report.diagnostics {
            let timestamp = DateFormatter.syncDiagnosticTimestampFormatter.string(from: entry.timestamp)
            let entityType = entry.entityType?.rawValue ?? "-"
            let entityID = entry.entityID?.uuidString ?? "-"
            let taskID = entry.taskID?.uuidString ?? "-"
            let eventID = entry.eventIdentifier ?? "-"
            let externalID = entry.externalIdentifier ?? "-"
            let providerError = entry.providerError ?? "-"
            let attempt = entry.attempt.map(String.init) ?? "-"
            lines.append(
                "\(timestamp) [\(entry.severity.rawValue.uppercased())] " +
                "op=\(entry.operation.rawValue) " +
                "entityType=\(entityType) entityID=\(entityID) " +
                "taskID=\(taskID) eventID=\(eventID) externalID=\(externalID) " +
                "attempt=\(attempt) providerError=\(providerError) message=\(entry.message)"
            )
        }

        return lines.joined(separator: "\n")
    }

    private func writeDiagnosticsExport(content: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("notes-engine-diagnostics", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let filename = "sync-diagnostics-\(Int(Date().timeIntervalSince1970)).txt"
        let fileURL = folder.appendingPathComponent(filename)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    public func createKanbanColumn() async {
        let title = newColumnTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        await runTask {
            _ = try await service.createKanbanColumn(title: title)
            newColumnTitle = ""
            try await reloadKanbanColumns()
            rebuildTaskCache(sourceTasks: allTasks)
        }
    }

    public func deleteKanbanColumn(id: UUID) async {
        guard let col = kanbanColumns.first(where: { $0.id == id }) else { return }
        guard col.builtInStatus == nil else {
            errorMessage = "Cannot delete a built-in column."
            return
        }
        await runTask {
            try await service.deleteKanbanColumn(id: id)
            try await reloadKanbanColumns()
            try await reloadTasksWithoutWrapper()
        }
    }

    public func updateKanbanColumn(_ column: KanbanColumn) async {
        await runTask {
            _ = try await service.updateKanbanColumn(column)
            try await reloadKanbanColumns()
        }
    }

    public func addLabelToTask(taskID: UUID, label: TaskLabel) async {
        await runTask {
            _ = try await service.addLabelToTask(taskID: taskID, label: label)
            try await reloadTasksWithoutWrapper()
        }
    }

    public func removeLabelFromTask(taskID: UUID, labelName: String) async {
        await runTask {
            _ = try await service.removeLabelFromTask(taskID: taskID, labelName: labelName)
            try await reloadTasksWithoutWrapper()
        }
    }

    private func reloadKanbanColumns() async throws {
        kanbanColumns = try await service.listKanbanColumns()
    }

    public func openDailyNote() async {
        await runTask {
            let note = try await service.createOrOpenDailyNote(date: Date())
            noteSearchQuery = ""
            try await reloadNotes(selectFirstIfNeeded: false)
            try await loadGraph()
            await selectNote(id: note.id)
        }
    }

    public func linkMention(sourceNoteID: UUID) async {
        guard !selectedNoteTitle.isEmpty else {
            return
        }

        await runTask {
            _ = try await service.linkMention(in: sourceNoteID, targetTitle: selectedNoteTitle)
            try await reloadNotes(selectFirstIfNeeded: false)
            if let selectedNoteID {
                unlinkedMentions = try await service.unlinkedMentions(for: selectedNoteID)
            }
        }
    }

    public func reloadGraph() async {
        await runTask {
            try await loadGraph()
        }
    }

    public func createNoteFromTemplate(templateID: UUID) async {
        await runTask {
            let created = try await service.createNote(title: "New Note", body: "", templateID: templateID)
            noteSearchQuery = ""
            isTemplatePickerPresented = false
            try await reloadNotes(selectFirstIfNeeded: false)
            await selectNote(id: created.id)
        }
    }

    public func createTemplate() async {
        let trimmedName = newTemplateName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return
        }

        await runTask {
            _ = try await service.createTemplate(name: trimmedName, body: newTemplateBody)
            newTemplateName = ""
            newTemplateBody = ""
            try await reloadTemplates()
        }
    }

    public func deleteTemplate(id: UUID) async {
        await runTask {
            try await service.deleteTemplate(id: id)
            try await reloadTemplates()
        }
    }

    public func showNewNoteOptions() async {
        if templates.isEmpty {
            await createNote()
        } else {
            isTemplatePickerPresented = true
        }
    }

    private func loadGraph() async throws {
        let edges = try await service.graphEdges()
        let notes = try await service.listNotes()

        var nodesByID: [UUID: GraphNode] = [:]
        for note in notes {
            let tagCount = note.tags.count
            nodesByID[note.id] = GraphNode(id: note.id, title: note.title, tagCount: tagCount)
        }

        graphNodes = Array(nodesByID.values)

        var graphEdgeSet = Set<String>()
        var graphEdgeArray: [GraphEdge] = []
        for (fromID, toID, _, _) in edges {
            let edgeKey = "\(fromID):\(toID)"
            if !graphEdgeSet.contains(edgeKey) {
                graphEdgeSet.insert(edgeKey)
                graphEdgeArray.append(GraphEdge(fromID: fromID, toID: toID))
            }
        }
        graphEdges = graphEdgeArray
    }

    private func reloadTemplates() async throws {
        templates = try await service.listTemplates()
    }
}

private struct PendingTaskMutation {
    let taskID: UUID
    let targetStatus: TaskStatus
    let beforeTaskID: UUID?
    let occurrenceDate: Date?
}

private struct PendingTaskDeletion {
    let taskID: UUID
    let occurrenceDate: Date?
}

private struct TaskDropInput {
    let taskID: UUID
    let status: TaskStatus
    let beforeTaskID: UUID?
    let occurrenceDate: Date?
    let isNoOp: Bool
}

private enum RecurrenceSeriesResolutionError: LocalizedError {
    case parentSeriesNotFound

    var errorDescription: String? {
        switch self {
        case .parentSeriesNotFound:
            return "Could not resolve a parent recurring series for this occurrence."
        }
    }
}

private extension DateFormatter {
    static let syncTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    static let syncDiagnosticTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}

private enum SyncDiagnosticsExportError: LocalizedError {
    case missingReport
    case noDiagnostics

    var errorDescription: String? {
        switch self {
        case .missingReport:
            return "Run sync before exporting diagnostics."
        case .noDiagnostics:
            return "No diagnostics available to export."
        }
    }
}
