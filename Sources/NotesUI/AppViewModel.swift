import Foundation
import Observation
import NotesDomain
import NotesFeatures
import NotesSync

public typealias CalendarProviderFactory = @Sendable () -> CalendarProvider

@MainActor
@Observable
public final class AppViewModel {
    public private(set) var notes: [Note] = []
    public var selectedNoteID: UUID?
    public var selectedNoteTitle: String = ""
    public var selectedNoteBody: String = ""
    public var noteSearchQuery: String = ""
    public private(set) var backlinks: [NoteBacklink] = []

    public private(set) var tasks: [Task] = []
    public var taskFilter: TaskListFilter = .all
    public var quickTaskTitle: String = ""

    public var syncCalendarID: String = ""
    public private(set) var isSyncing: Bool = false
    public private(set) var syncStatusText: String = "Idle"
    public private(set) var lastSyncReport: SyncRunReport?
    public private(set) var lastDiagnosticsExportURL: URL?
    public private(set) var lastDiagnosticsExportText: String = ""

    public private(set) var isBusy: Bool = false
    public private(set) var errorMessage: String?
    public private(set) var draggingTaskID: UUID?
    public private(set) var dropTargetStatus: TaskStatus?
    public private(set) var dropTargetTaskID: UUID?

    private let service: WorkspaceServicing
    private let calendarProviderFactory: CalendarProviderFactory

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

    public func toggleTaskCompletion(taskID: UUID, isCompleted: Bool) async {
        await runTask {
            _ = try await service.toggleTaskCompletion(taskID: taskID, isCompleted: isCompleted)
            try await reloadTasksWithoutWrapper()
        }
    }

    public func moveTask(taskID: UUID, to status: TaskStatus, beforeTaskID: UUID? = nil) async {
        await runTask {
            _ = try await service.moveTask(taskID: taskID, to: status, beforeTaskID: beforeTaskID)
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

    public func handleTaskDrop(taskPayloads: [String], to status: TaskStatus, beforeTaskID: UUID?) async -> Bool {
        guard let first = taskPayloads.first, let taskID = UUID(uuidString: first) else {
            return false
        }

        defer { endTaskDrag() }

        guard let current = tasks.first(where: { $0.id == taskID }) else {
            return false
        }
        if current.status == status && beforeTaskID == nil {
            return true
        }

        await moveTask(taskID: taskID, to: status, beforeTaskID: beforeTaskID)
        return errorMessage == nil
    }

    public func tasks(for status: TaskStatus) -> [Task] {
        tasks.filter { task in
            if task.status == .done {
                return status == .done
            }
            return task.status == status
        }
        .sorted { lhs, rhs in
            if lhs.kanbanOrder != rhs.kanbanOrder {
                return lhs.kanbanOrder < rhs.kanbanOrder
            }
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
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
        } else {
            notes = try await service.searchNotes(query: noteSearchQuery, limit: 100)
        }

        if selectFirstIfNeeded, selectedNoteID == nil {
            try await selectNoteWithoutWrapper(id: notes.first?.id)
        } else if let selectedNoteID {
            try await selectNoteWithoutWrapper(id: selectedNoteID)
        }
    }

    private func reloadTasksWithoutWrapper() async throws {
        tasks = try await service.listTasks(filter: taskFilter)
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
            backlinks = []
            return
        }

        selectedNoteTitle = selected.title
        selectedNoteBody = selected.body
        try await reloadBacklinks(for: id)
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
