import Foundation
import Observation
import NotesDomain
import NotesFeatures
import NotesSync

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
    public private(set) var notes: [Note] = []
    public var selectedNoteID: UUID?
    public var selectedNoteTitle: String = ""
    public var selectedNoteBody: String = ""
    public var noteSearchQuery: String = ""
    public private(set) var noteSearchSnippetsByID: [UUID: String] = [:]
    public private(set) var wikiLinkSuggestions: [String] = []
    public private(set) var isWikiLinkSuggestionVisible: Bool = false
    public var quickOpenQuery: String = ""
    public var isQuickOpenPresented: Bool = false
    public private(set) var quickOpenResults: [Note] = []
    public private(set) var backlinks: [NoteBacklink] = []

    public private(set) var tasks: [Task] = []
    public var taskFilter: TaskListFilter = .all
    public var quickTaskTitle: String = ""
    private var allTasks: [Task] = []
    private var tasksByStatus: [TaskStatus: [Task]] = [:]

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
    public private(set) var dropTargetTaskID: UUID?

    private let service: WorkspaceServicing
    private let calendarProviderFactory: CalendarProviderFactory
    private var pendingTaskMutation: PendingTaskMutation?
    private var pendingTaskDeletion: PendingTaskDeletion?

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
        await runTask {
            try await service.seedDemoDataIfNeeded()
            try await reloadNotes(selectFirstIfNeeded: true)
            await reloadTasks()
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

        await runTask {
            _ = try await service.createTask(
                NewTaskInput(
                    noteID: selectedNoteID,
                    title: title,
                    details: selectedNoteBody.isEmpty ? "" : "From note: \(selectedNoteTitle)",
                    dueStart: Calendar.current.date(byAdding: .hour, value: 2, to: Date()),
                    dueEnd: Calendar.current.date(byAdding: .hour, value: 3, to: Date()),
                    status: .next,
                    priority: 3
                )
            )
            quickTaskTitle = ""
            await reloadTasks()
        }
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

        let suggestions = notes
            .map(\.title)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .filter { query.isEmpty || $0.lowercased().contains(query) }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

        wikiLinkSuggestions = Array(suggestions.prefix(8))
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
            .filter { $0.title.localizedCaseInsensitiveContains(trimmed) || $0.body.localizedCaseInsensitiveContains(trimmed) }
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
    }

    public func setDropTargetTaskID(_ taskID: UUID?) {
        dropTargetTaskID = taskID
    }

    public func endTaskDrag() {
        draggingTaskID = nil
        dropTargetStatus = nil
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
        tasksByStatus[status] ?? []
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

    private func reloadNotes(selectFirstIfNeeded: Bool) async throws {
        if noteSearchQuery.isEmpty {
            notes = try await service.listNotes()
            noteSearchSnippetsByID = [:]
        } else {
            let page = try await service.searchNotesPage(
                query: noteSearchQuery,
                mode: .smart,
                limit: 100,
                offset: 0
            )
            notes = page.hits.map(\.note)
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
            try await selectNoteWithoutWrapper(id: selectedNoteID)
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
        var next: [TaskStatus: [Task]] = [:]
        for status in TaskStatus.allCases {
            next[status] = []
        }
        for task in sourceTasks {
            next[task.status, default: []].append(task)
        }
        for status in TaskStatus.allCases {
            next[status]?.sort(by: Self.kanbanTaskSort)
        }
        tasksByStatus = next
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
        guard let id, let selected = notes.first(where: { $0.id == id }) else {
            selectedNoteID = nil
            selectedNoteTitle = ""
            selectedNoteBody = ""
            wikiLinkSuggestions = []
            isWikiLinkSuggestionVisible = false
            backlinks = []
            return
        }

        selectedNoteTitle = selected.title
        selectedNoteBody = selected.body
        wikiLinkSuggestions = []
        isWikiLinkSuggestionVisible = false
        try await reloadBacklinks(for: id)
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
