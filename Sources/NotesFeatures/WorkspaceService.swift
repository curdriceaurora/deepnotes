// swiftlint:disable type_body_length
import Foundation
import NotesDomain
import NotesStorage
import NotesSync

public enum TaskListFilter: String, CaseIterable, Codable, Sendable {
    case all
    case today
    case upcoming
    case overdue
    case completed

    public var title: String {
        switch self {
        case .all: "All"
        case .today: "Today"
        case .upcoming: "Upcoming"
        case .overdue: "Overdue"
        case .completed: "Completed"
        }
    }
}

public struct NoteBacklink: Equatable, Sendable {
    public var sourceNoteID: UUID
    public var sourceTitle: String

    public init(sourceNoteID: UUID, sourceTitle: String) {
        self.sourceNoteID = sourceNoteID
        self.sourceTitle = sourceTitle
    }
}

public struct NewTaskInput: Sendable {
    public var noteID: UUID?
    public var title: String
    public var details: String
    public var dueStart: Date?
    public var dueEnd: Date?
    public var status: TaskStatus
    public var priority: Int
    public var recurrenceRule: String?

    public init(
        noteID: UUID? = nil,
        title: String,
        details: String = "",
        dueStart: Date? = nil,
        dueEnd: Date? = nil,
        status: TaskStatus = .backlog,
        priority: Int = 3,
        recurrenceRule: String? = nil,
    ) {
        self.noteID = noteID
        self.title = title
        self.details = details
        self.dueStart = dueStart
        self.dueEnd = dueEnd
        self.status = status
        self.priority = priority
        self.recurrenceRule = recurrenceRule
    }
}

public protocol WorkspaceServicing: Sendable {
    func fetchNote(id: UUID) async throws -> Note?
    func listNotes() async throws -> [Note]
    func searchNotes(query: String, limit: Int) async throws -> [Note]
    func searchNotesPage(query: String, mode: NoteSearchMode, limit: Int, offset: Int) async throws -> NoteSearchPage
    func listAllTasks() async throws -> [Task]
    func createNote(title: String, body: String) async throws -> Note
    func updateNote(id: UUID, title: String, body: String) async throws -> Note
    func backlinks(for noteID: UUID) async throws -> [NoteBacklink]
    func listTasks(filter: TaskListFilter) async throws -> [Task]
    func createTask(_ input: NewTaskInput) async throws -> Task
    func updateTask(_ task: Task) async throws -> Task
    func deleteTask(taskID: UUID) async throws
    func moveTask(taskID: UUID, to status: TaskStatus, beforeTaskID: UUID?) async throws -> Task
    func setTaskStatus(taskID: UUID, status: TaskStatus) async throws -> Task
    func toggleTaskCompletion(taskID: UUID, isCompleted: Bool) async throws -> Task
    func notesByTag(_ tag: String) async throws -> [Note]
    func allTags() async throws -> [String]
    func listNoteListItems() async throws -> [NoteListItem]
    func listNoteListItems(tag: String) async throws -> [NoteListItem]
    func listNoteListItems(limit: Int, offset: Int) async throws -> NoteListItemPage
    func runSync(configuration: SyncEngineConfiguration, calendarProvider: CalendarProvider) async throws -> SyncRunReport
    func seedDemoDataIfNeeded() async throws
    func unlinkedMentions(for noteID: UUID) async throws -> [NoteBacklink]
    func linkMention(in sourceNoteID: UUID, targetTitle: String) async throws -> Note
    func graphEdges() async throws -> [(from: UUID, to: UUID, fromTitle: String, toTitle: String)]
    func createOrOpenDailyNote(date: Date) async throws -> Note
    func listTemplates() async throws -> [NoteTemplate]
    func createTemplate(name: String, body: String) async throws -> NoteTemplate
    func deleteTemplate(id: UUID) async throws
    func createNote(title: String, body: String, templateID: UUID?) async throws -> Note
    func listKanbanColumns() async throws -> [KanbanColumn]
    func createKanbanColumn(title: String) async throws -> KanbanColumn
    func updateKanbanColumn(_ column: KanbanColumn) async throws -> KanbanColumn
    func deleteKanbanColumn(id: UUID) async throws
    func addLabelToTask(taskID: UUID, label: TaskLabel) async throws -> Task
    func removeLabelFromTask(taskID: UUID, labelName: String) async throws -> Task
    func addSubtask(to parentTaskID: UUID, title: String) async throws -> Task
    func toggleSubtask(parentTaskID: UUID, subtaskID: UUID, isCompleted: Bool) async throws -> Task
    func deleteSubtask(parentTaskID: UUID, subtaskID: UUID) async throws -> Task
    func requestNotificationPermission() async -> Bool
    func listTasks(filter: TaskListFilter, sortOrder: TaskSortOrder) async throws -> [Task]
}

public actor WorkspaceService: WorkspaceServicing {
    private let taskStore: TaskStore
    private let noteStore: NoteStore
    private let bindingStore: CalendarBindingStore
    private let checkpointStore: SyncCheckpointStore
    private let templateStore: TemplateStore
    private let kanbanColumnStore: KanbanColumnStore
    private let mapper: TaskCalendarMapper
    private let clock: Clock
    private let linkParser: WikiLinkParser
    private let tagParser: TagParser
    private var notificationScheduler: NotificationScheduling?

    /// Search result cache (LRU, max 8)
    private struct SearchCacheKey: Hashable {
        let query: String
        let mode: NoteSearchMode
        let offset: Int
        let limit: Int
    }

    private var searchCache: [SearchCacheKey: NoteSearchPage] = [:]
    private var searchCacheOrder: [SearchCacheKey] = []

    /// Backlinks link index — precomputed from all notes
    private struct LinkIndex {
        let titleToID: [String: UUID]
        let noteLinks: [UUID: Set<String>]
        let noteTitles: [UUID: String]
    }

    private var linkIndex: LinkIndex?

    public init(
        taskStore: TaskStore,
        noteStore: NoteStore,
        bindingStore: CalendarBindingStore,
        checkpointStore: SyncCheckpointStore,
        templateStore: TemplateStore,
        kanbanColumnStore: KanbanColumnStore,
        mapper: TaskCalendarMapper = TaskCalendarMapper(),
        clock: Clock = SystemClock(),
        linkParser: WikiLinkParser = WikiLinkParser(),
        tagParser: TagParser = TagParser(),
        notificationScheduler: NotificationScheduling? = nil,
    ) {
        self.taskStore = taskStore
        self.noteStore = noteStore
        self.bindingStore = bindingStore
        self.checkpointStore = checkpointStore
        self.templateStore = templateStore
        self.kanbanColumnStore = kanbanColumnStore
        self.mapper = mapper
        self.clock = clock
        self.linkParser = linkParser
        self.tagParser = tagParser
        self.notificationScheduler = notificationScheduler
    }

    private func getNotificationScheduler() -> NotificationScheduling {
        if let scheduler = notificationScheduler {
            return scheduler
        }
        // Use NoOpNotificationScheduler as fallback (safe for tests where UserNotificationScheduler
        // would crash due to missing app bundle)
        let scheduler = NoOpNotificationScheduler()
        self.notificationScheduler = scheduler
        return scheduler
    }

    public init(store: SQLiteStore) {
        self.init(
            taskStore: store,
            noteStore: store,
            bindingStore: store,
            checkpointStore: store,
            templateStore: store,
            kanbanColumnStore: store,
        )
    }

    public func fetchNote(id: UUID) async throws -> Note? {
        try await noteStore.fetchNote(id: id)
    }

    public func listNotes() async throws -> [Note] {
        try await noteStore.fetchNotes(includeDeleted: false)
    }

    public func searchNotes(query: String, limit: Int = 50) async throws -> [Note] {
        let page = try await searchNotesPage(
            query: query,
            mode: .smart,
            limit: limit,
            offset: 0,
        )
        return page.hits.map(\.note)
    }

    public func searchNotesPage(
        query: String,
        mode: NoteSearchMode = .smart,
        limit: Int = 50,
        offset: Int = 0,
    ) async throws -> NoteSearchPage {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedLimit = max(1, limit)
        let normalizedOffset = max(0, offset)
        guard !trimmed.isEmpty else {
            let notes = try await listNotes()
            let start = min(normalizedOffset, notes.count)
            let end = min(notes.count, start + normalizedLimit)
            let pageNotes = Array(notes[start ..< end])
            return NoteSearchPage(
                query: trimmed,
                mode: mode,
                offset: normalizedOffset,
                limit: normalizedLimit,
                totalCount: notes.count,
                hits: pageNotes.map { NoteSearchHit(note: $0, snippet: nil, rank: 0) },
            )
        }

        let cacheKey = SearchCacheKey(query: trimmed, mode: mode, offset: normalizedOffset, limit: normalizedLimit)
        if let cached = searchCache[cacheKey] {
            if let idx = searchCacheOrder.firstIndex(of: cacheKey) {
                searchCacheOrder.remove(at: idx)
                searchCacheOrder.append(cacheKey)
            }
            return cached
        }

        let result = try await noteStore.searchNotes(
            query: trimmed,
            mode: mode,
            limit: normalizedLimit,
            offset: normalizedOffset,
        )

        searchCache[cacheKey] = result
        searchCacheOrder.append(cacheKey)
        if searchCacheOrder.count > 8 {
            let evicted = searchCacheOrder.removeFirst()
            searchCache.removeValue(forKey: evicted)
        }

        return result
    }

    public func createNote(title: String, body: String) async throws -> Note {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackTitle = "Untitled \(ISO8601DateFormatter().string(from: clock.now()))"
        let tags = tagParser.extractTags(from: body)

        let note = Note(
            title: trimmedTitle.isEmpty ? fallbackTitle : trimmedTitle,
            body: body,
            tags: tags,
            updatedAt: clock.now(),
        )
        let created = try await noteStore.upsertNote(note)
        invalidateCaches()
        return created
    }

    public func createNote(title: String, body: String, templateID: UUID?) async throws -> Note {
        var finalBody = body
        if let templateID {
            let templates = try await templateStore.fetchTemplates()
            if let template = templates.first(where: { $0.id == templateID }) {
                finalBody = template.body
            }
        }
        return try await createNote(title: title, body: finalBody)
    }

    public func updateNote(id: UUID, title: String, body: String) async throws -> Note {
        guard let existing = try await noteStore.fetchNote(id: id), existing.deletedAt == nil else {
            throw StorageError.dataCorruption(reason: "Cannot update missing note \(id)")
        }

        let previousTitle = existing.title
        let normalizedPreviousTitle = normalizedWikiLinkTitle(previousTitle)
        let normalizedUpdatedTitle = normalizedWikiLinkTitle(title)
        let shouldPropagateRename =
            !normalizedPreviousTitle.isEmpty &&
            normalizedPreviousTitle != normalizedUpdatedTitle &&
            !normalizedUpdatedTitle.isEmpty

        var next = existing
        next.title = title
        next.body = body
        next.tags = tagParser.extractTags(from: body)
        next.updatedAt = clock.now()
        let updatedNote = try await noteStore.upsertNote(next)
        invalidateCaches()

        guard shouldPropagateRename else {
            return updatedNote
        }

        let notes = try await noteStore.fetchNotes(includeDeleted: false)
        let conflictingOldTitleCount = notes
            .count(where: { $0.id != id && normalizedWikiLinkTitle($0.title) == normalizedPreviousTitle })

        guard conflictingOldTitleCount == 0 else {
            return updatedNote
        }

        for note in notes where note.id != id {
            let rewrittenBody = rewriteWikiLinks(
                in: note.body,
                fromNormalizedTitle: normalizedPreviousTitle,
                toTitle: title,
            )
            guard rewrittenBody != note.body else {
                continue
            }

            var rewritten = note
            rewritten.body = rewrittenBody
            rewritten.updatedAt = clock.now()
            _ = try await noteStore.upsertNote(rewritten)
        }

        return updatedNote
    }

    public func backlinks(for noteID: UUID) async throws -> [NoteBacklink] {
        let index = try await getOrBuildLinkIndex()
        guard let targetTitle = index.noteTitles[noteID] else {
            return []
        }
        let normalizedTarget = targetTitle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedTarget.isEmpty else {
            return []
        }

        var results: [NoteBacklink] = []
        for (sourceID, linkedTitles) in index.noteLinks where sourceID != noteID {
            if linkedTitles.contains(normalizedTarget), let sourceTitle = index.noteTitles[sourceID] {
                results.append(NoteBacklink(sourceNoteID: sourceID, sourceTitle: sourceTitle))
            }
        }
        return results.sorted { $0.sourceTitle.localizedCaseInsensitiveCompare($1.sourceTitle) == .orderedAscending }
    }

    public func notesByTag(_ tag: String) async throws -> [Note] {
        try await noteStore.fetchNotesByTag(tag)
    }

    public func allTags() async throws -> [String] {
        let notes = try await noteStore.fetchNotes(includeDeleted: false)
        var seen = Set<String>()
        var result: [String] = []
        for note in notes {
            for tag in note.tags {
                let lowered = tag.lowercased()
                if !seen.contains(lowered) {
                    seen.insert(lowered)
                    result.append(lowered)
                }
            }
        }
        return result.sorted()
    }

    public func listNoteListItems() async throws -> [NoteListItem] {
        try await noteStore.fetchNoteListItems(includeDeleted: false)
    }

    public func listNoteListItems(tag: String) async throws -> [NoteListItem] {
        try await noteStore.fetchNoteListItemsByTag(tag)
    }

    public func listNoteListItems(limit: Int, offset: Int) async throws -> NoteListItemPage {
        try await noteStore.fetchNoteListItems(includeDeleted: false, limit: limit, offset: offset)
    }

    private func invalidateCaches() {
        searchCache.removeAll()
        searchCacheOrder.removeAll()
        linkIndex = nil
    }

    private func getOrBuildLinkIndex() async throws -> LinkIndex {
        if let existing = linkIndex {
            return existing
        }
        let notes = try await noteStore.fetchNotes(includeDeleted: false)
        var titleToID: [String: UUID] = [:]
        var noteLinks: [UUID: Set<String>] = [:]
        var noteTitles: [UUID: String] = [:]
        for note in notes {
            let normalized = note.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !normalized.isEmpty {
                titleToID[normalized] = note.id
            }
            noteTitles[note.id] = note.title
            let linked = linkParser.linkedTitles(in: note.body)
            noteLinks[note.id] = Set(linked.map { $0.lowercased() })
        }
        let index = LinkIndex(titleToID: titleToID, noteLinks: noteLinks, noteTitles: noteTitles)
        linkIndex = index
        return index
    }

    public func listTasks(filter: TaskListFilter) async throws -> [Task] {
        try await listTasks(filter: filter, sortOrder: .dueDate)
    }

    public func listTasks(filter: TaskListFilter, sortOrder: TaskSortOrder) async throws -> [Task] {
        let tasks = try await taskStore.fetchTasks(includeDeleted: false)
        let now = clock.now()
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: now)
        let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart

        let filtered = tasks.filter { task in
            switch filter {
            case .all:
                return task.status != .done
            case .today:
                guard let due = task.dueStart else { return false }
                return due >= now && due < tomorrowStart && task.status != .done
            case .upcoming:
                guard let due = task.dueStart else { return false }
                return due >= tomorrowStart && task.status != .done
            case .overdue:
                guard let due = task.dueStart else { return false }
                return due < now && task.status != .done
            case .completed:
                return task.status == .done || task.completedAt != nil
            }
        }

        return filtered.sorted(by: sortComparator(sortOrder))
    }

    private func sortComparator(_ order: TaskSortOrder) -> (Task, Task) -> Bool {
        switch order {
        case .dueDate:
            { lhs, rhs in
                switch (lhs.dueStart, rhs.dueStart) {
                case let (l?, r?): l < r
                case (_?, nil): true
                case (nil, _?): false
                case (nil, nil): lhs.updatedAt > rhs.updatedAt
                }
            }
        case .priority:
            { lhs, rhs in
                lhs.priority != rhs.priority
                    ? lhs.priority < rhs.priority
                    : lhs.updatedAt > rhs.updatedAt
            }
        case .title:
            { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .creationDate:
            { $0.updatedAt > $1.updatedAt }
        }
    }

    public func createTask(_ input: NewTaskInput) async throws -> Task {
        let allTasks = try await taskStore.fetchTasks(includeDeleted: false)
        let task = try Task(
            noteID: input.noteID,
            stableID: UUID().uuidString.lowercased(),
            title: input.title,
            details: input.details,
            dueStart: input.dueStart,
            dueEnd: input.dueEnd,
            status: input.status,
            priority: input.priority,
            recurrenceRule: input.recurrenceRule,
            kanbanOrder: nextKanbanOrderForAppend(status: input.status, tasks: allTasks),
            updatedAt: clock.now(),
        )
        let saved = try await taskStore.upsertTask(task)
        _Concurrency.Task { await self.getNotificationScheduler().scheduleReminder(for: saved) }
        return saved
    }

    public func listAllTasks() async throws -> [Task] {
        try await taskStore.fetchTasks(includeDeleted: false)
    }

    public func updateTask(_ task: Task) async throws -> Task {
        var copy = task
        copy.updatedAt = clock.now()
        let saved = try await taskStore.upsertTask(copy)
        _Concurrency.Task { await self.getNotificationScheduler().scheduleReminder(for: saved) }
        return saved
    }

    public func deleteTask(taskID: UUID) async throws {
        guard let task = try await taskStore.fetchTask(id: taskID), task.deletedAt == nil else {
            throw StorageError.dataCorruption(reason: "Cannot delete missing task \(taskID)")
        }
        _Concurrency.Task { await self.getNotificationScheduler().cancelReminder(for: taskID) }
        try await taskStore.tombstoneTask(id: taskID, at: clock.now())
    }

    public func moveTask(taskID: UUID, to status: TaskStatus, beforeTaskID: UUID?) async throws -> Task {
        guard var task = try await taskStore.fetchTask(id: taskID), task.deletedAt == nil else {
            throw StorageError.dataCorruption(reason: "Cannot update missing task \(taskID)")
        }

        var tasks = try await taskStore.fetchTasks(includeDeleted: false)
        var desiredOrder = try kanbanOrder(
            forMovingTaskID: taskID,
            targetStatus: status,
            beforeTaskID: beforeTaskID,
            tasks: tasks,
        )

        if desiredOrder.isNaN {
            try await rebalanceKanbanOrder(for: status, excludingTaskID: taskID)
            tasks = try await taskStore.fetchTasks(includeDeleted: false)
            desiredOrder = try kanbanOrder(
                forMovingTaskID: taskID,
                targetStatus: status,
                beforeTaskID: beforeTaskID,
                tasks: tasks,
            )
        }

        if task.status == status, abs(task.kanbanOrder - desiredOrder) <= Self.kanbanOrderEpsilon {
            return task
        }

        task.status = status
        task.kanbanOrder = desiredOrder
        task.kanbanColumnID = nil
        task.updatedAt = clock.now()
        if status == .done {
            task.completedAt = task.completedAt ?? clock.now()
        } else {
            task.completedAt = nil
        }

        let saved = try await taskStore.upsertTask(task)
        if status == .done {
            _Concurrency.Task { await self.getNotificationScheduler().cancelReminder(for: taskID) }
        } else {
            _Concurrency.Task { await self.getNotificationScheduler().scheduleReminder(for: saved) }
        }
        return saved
    }

    public func setTaskStatus(taskID: UUID, status: TaskStatus) async throws -> Task {
        try await moveTask(taskID: taskID, to: status, beforeTaskID: nil)
    }

    public func toggleTaskCompletion(taskID: UUID, isCompleted: Bool) async throws -> Task {
        try await setTaskStatus(taskID: taskID, status: isCompleted ? .done : .next)
    }

    public func runSync(configuration: SyncEngineConfiguration, calendarProvider: CalendarProvider) async throws -> SyncRunReport {
        let engine = TwoWaySyncEngine(
            taskStore: taskStore,
            noteStore: noteStore,
            bindingStore: bindingStore,
            checkpointStore: checkpointStore,
            calendarProvider: calendarProvider,
            mapper: mapper,
            clock: clock,
        )

        return try await engine.runOnce(configuration: configuration)
    }

    public func seedDemoDataIfNeeded() async throws {
        let notes = try await noteStore.fetchNotes(includeDeleted: false)
        if notes.isEmpty {
            let planning = try await createNote(
                title: "Q2 Launch Plan",
                body: "# Goals\n- Ship planning app\n\n## Linked\n- [[Vendor Call Notes]]",
            )

            _ = try await createNote(
                title: "Vendor Call Notes",
                body: "Prepare talking points from [[Q2 Launch Plan]].",
            )

            var datedNote = Note(
                title: "Launch review card",
                body: "Calendar-linked note card for launch review.",
                dateStart: clock.now().addingTimeInterval(7200),
                dateEnd: clock.now().addingTimeInterval(10800),
                isAllDay: false,
                recurrenceRule: nil,
                calendarSyncEnabled: true,
                updatedAt: clock.now(),
            )
            datedNote = try await noteStore.upsertNote(datedNote)

            _ = try await createTask(NewTaskInput(
                noteID: planning.id,
                title: "Call supplier",
                details: "Finalize lead time",
                dueStart: clock.now().addingTimeInterval(3600),
                dueEnd: clock.now().addingTimeInterval(5400),
                status: .next,
                priority: 4,
            ))

            _ = try await createTask(NewTaskInput(
                noteID: planning.id,
                title: "Draft launch email",
                details: "Reference [[Q2 Launch Plan]]",
                dueStart: clock.now().addingTimeInterval(7200),
                dueEnd: clock.now().addingTimeInterval(9000),
                status: .doing,
                priority: 3,
            ))

            _ = try await createTask(NewTaskInput(
                noteID: planning.id,
                title: "Review budget",
                details: "Weekly review",
                dueStart: clock.now().addingTimeInterval(86400),
                dueEnd: clock.now().addingTimeInterval(90000),
                status: .waiting,
                priority: 2,
                recurrenceRule: "FREQ=WEEKLY;BYDAY=MO;BYHOUR=9;BYMINUTE=0",
            ))
        }
    }

    public func listKanbanColumns() async throws -> [KanbanColumn] {
        try await kanbanColumnStore.fetchColumns()
    }

    public func createKanbanColumn(title: String) async throws -> KanbanColumn {
        let existing = try await kanbanColumnStore.fetchColumns()
        let maxPosition = existing.map(\.position).max() ?? -1
        let column = KanbanColumn(title: title, position: maxPosition + 1)
        return try await kanbanColumnStore.upsertColumn(column)
    }

    public func updateKanbanColumn(_ column: KanbanColumn) async throws -> KanbanColumn {
        try await kanbanColumnStore.upsertColumn(column)
    }

    public func deleteKanbanColumn(id: UUID) async throws {
        let columns = try await kanbanColumnStore.fetchColumns()
        guard let target = columns.first(where: { $0.id == id }) else { return }
        guard target.builtInStatus == nil else { return }
        try await kanbanColumnStore.deleteColumn(id: id)
    }

    public func addLabelToTask(taskID: UUID, label: TaskLabel) async throws -> Task {
        guard var task = try await taskStore.fetchTask(id: taskID), task.deletedAt == nil else {
            throw StorageError.dataCorruption(reason: "Cannot update missing task \(taskID)")
        }
        let alreadyExists = task.labels.contains(where: { $0.name.lowercased() == label.name.lowercased() })
        if !alreadyExists {
            task.labels.append(label)
        }
        return try await updateTask(task)
    }

    public func removeLabelFromTask(taskID: UUID, labelName: String) async throws -> Task {
        guard var task = try await taskStore.fetchTask(id: taskID), task.deletedAt == nil else {
            throw StorageError.dataCorruption(reason: "Cannot update missing task \(taskID)")
        }
        task.labels.removeAll(where: { $0.name.lowercased() == labelName.lowercased() })
        return try await updateTask(task)
    }

    public func addSubtask(to parentTaskID: UUID, title: String) async throws -> Task {
        guard var task = try await taskStore.fetchTask(id: parentTaskID), task.deletedAt == nil else {
            throw StorageError.dataCorruption(reason: "Cannot update missing task \(parentTaskID)")
        }
        let subtask = Subtask(title: title, order: task.subtasks.count)
        task.subtasks.append(subtask)
        return try await updateTask(task)
    }

    public func toggleSubtask(parentTaskID: UUID, subtaskID: UUID, isCompleted: Bool) async throws -> Task {
        guard var task = try await taskStore.fetchTask(id: parentTaskID), task.deletedAt == nil else {
            throw StorageError.dataCorruption(reason: "Cannot update missing task \(parentTaskID)")
        }
        guard let index = task.subtasks.firstIndex(where: { $0.id == subtaskID }) else {
            throw StorageError.dataCorruption(reason: "Cannot find subtask \(subtaskID)")
        }
        task.subtasks[index].isCompleted = isCompleted

        // Auto-complete parent task when all subtasks are completed.
        // Note: Parent can still be manually marked as done even with incomplete subtasks.
        if isCompleted, task.subtasks.allSatisfy(\.isCompleted), task.status != .done {
            task.status = .done
            task.completedAt = clock.now()
        }

        return try await updateTask(task)
    }

    public func deleteSubtask(parentTaskID: UUID, subtaskID: UUID) async throws -> Task {
        guard var task = try await taskStore.fetchTask(id: parentTaskID), task.deletedAt == nil else {
            throw StorageError.dataCorruption(reason: "Cannot update missing task \(parentTaskID)")
        }
        task.subtasks.removeAll(where: { $0.id == subtaskID })

        var order = 0
        for i in task.subtasks.indices {
            task.subtasks[i].order = order
            order += 1
        }

        return try await updateTask(task)
    }

    public func requestNotificationPermission() async -> Bool {
        await getNotificationScheduler().requestAuthorization()
    }

    private func nextKanbanOrderForAppend(status: TaskStatus, tasks: [Task]) -> Double {
        let existingMax = tasks
            .filter { $0.status == status }
            .map(\.kanbanOrder)
            .max() ?? 0
        return existingMax + 1
    }

    private func kanbanOrder(
        forMovingTaskID taskID: UUID,
        targetStatus: TaskStatus,
        beforeTaskID: UUID?,
        tasks: [Task],
    ) throws -> Double {
        let targetTasks = tasks
            .filter { $0.id != taskID && $0.status == targetStatus }
            .sorted(by: Self.kanbanSort)

        guard !targetTasks.isEmpty else {
            return 1
        }

        let beforeIndex = beforeTaskID.flatMap { candidateID in
            targetTasks.firstIndex(where: { $0.id == candidateID })
        }

        if let beforeIndex {
            let next = targetTasks[beforeIndex].kanbanOrder
            if beforeIndex == 0 {
                return next - 1
            }
            let previous = targetTasks[beforeIndex - 1].kanbanOrder
            let gap = next - previous
            if gap <= Self.kanbanOrderEpsilon {
                return .nan
            }
            return previous + (gap / 2)
        }

        return (targetTasks.last?.kanbanOrder ?? 0) + 1
    }

    private func rebalanceKanbanOrder(for status: TaskStatus, excludingTaskID: UUID) async throws {
        let orderedTasks = try await taskStore.fetchTasks(includeDeleted: false)
            .filter { $0.status == status && $0.id != excludingTaskID }
            .sorted(by: Self.kanbanSort)

        for (index, existing) in orderedTasks.enumerated() {
            let newOrder = Double(index + 1)
            if abs(existing.kanbanOrder - newOrder) <= Self.kanbanOrderEpsilon {
                continue
            }

            var copy = existing
            copy.kanbanOrder = newOrder
            copy.updatedAt = clock.now()
            _ = try await taskStore.upsertTask(copy)
        }
    }

    private static let kanbanOrderEpsilon: Double = 1e-6

    private static func kanbanSort(_ lhs: Task, _ rhs: Task) -> Bool {
        if abs(lhs.kanbanOrder - rhs.kanbanOrder) > kanbanOrderEpsilon {
            return lhs.kanbanOrder < rhs.kanbanOrder
        }
        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt > rhs.updatedAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func normalizedWikiLinkTitle(_ title: String) -> String {
        title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func rewriteWikiLinks(
        in body: String,
        fromNormalizedTitle: String,
        toTitle: String,
    ) -> String {
        guard !fromNormalizedTitle.isEmpty else {
            return body
        }
        guard let regex = try? NSRegularExpression(pattern: #"\[\[([^\]|]+)(\|[^\]]+)?\]\]"#) else {
            return body
        }

        let nsRange = NSRange(body.startIndex ..< body.endIndex, in: body)
        let matches = regex.matches(in: body, range: nsRange)
        guard !matches.isEmpty else {
            return body
        }

        var rewritten = body
        for match in matches.reversed() {
            guard
                match.numberOfRanges >= 3,
                let fullRange = Range(match.range(at: 0), in: rewritten),
                let titleRange = Range(match.range(at: 1), in: rewritten)
            else {
                continue
            }

            let linkedTitle = rewritten[titleRange]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard linkedTitle == fromNormalizedTitle else {
                continue
            }

            let alias = if let aliasRange = Range(match.range(at: 2), in: rewritten) {
                String(rewritten[aliasRange])
            } else {
                ""
            }

            rewritten.replaceSubrange(fullRange, with: "[[\(toTitle)\(alias)]]")
        }
        return rewritten
    }

    public func unlinkedMentions(for noteID: UUID) async throws -> [NoteBacklink] {
        guard let targetNote = try await noteStore.fetchNote(id: noteID), targetNote.deletedAt == nil else {
            return []
        }

        let existingBacklinks = try await backlinks(for: noteID)
        let existingBacklinkTitles = Set(existingBacklinks.map { $0.sourceTitle.lowercased() })

        let escapedTitle = NSRegularExpression.escapedPattern(for: targetNote.title)
        guard let regex = try? NSRegularExpression(
            pattern: #"(?<!\[)\b\#(escapedTitle)\b(?!\])"#,
            options: [.caseInsensitive],
        ) else {
            return []
        }

        let allNotes = try await noteStore.fetchNotes(includeDeleted: false)
        var mentions: [NoteBacklink] = []

        for note in allNotes where note.id != noteID {
            let range = NSRange(note.body.startIndex ..< note.body.endIndex, in: note.body)
            if regex.firstMatch(in: note.body, options: [], range: range) != nil {
                let normalizedTitle = note.title.lowercased()
                if !existingBacklinkTitles.contains(normalizedTitle) {
                    mentions.append(NoteBacklink(sourceNoteID: note.id, sourceTitle: note.title))
                }
            }
        }

        return mentions
    }

    public func linkMention(in sourceNoteID: UUID, targetTitle: String) async throws -> Note {
        guard let note = try await noteStore.fetchNote(id: sourceNoteID), note.deletedAt == nil else {
            throw StorageError.dataCorruption(reason: "Cannot link mention in missing note")
        }

        let escapedTitle = NSRegularExpression.escapedPattern(for: targetTitle)
        guard let regex = try? NSRegularExpression(
            pattern: #"(?<!\[)\b\#(escapedTitle)\b(?!\])"#,
            options: [.caseInsensitive],
        ) else {
            return note
        }

        var rewritten = note.body
        let range = NSRange(note.body.startIndex ..< note.body.endIndex, in: note.body)
        if let match = regex.firstMatch(in: note.body, options: [], range: range),
           let matchRange = Range(match.range, in: note.body)
        {
            rewritten.replaceSubrange(matchRange, with: "[[\(targetTitle)]]")
        }

        return try await updateNote(id: sourceNoteID, title: note.title, body: rewritten)
    }

    public func graphEdges() async throws -> [(from: UUID, to: UUID, fromTitle: String, toTitle: String)] {
        let index = try await getOrBuildLinkIndex()
        var edges: [(from: UUID, to: UUID, fromTitle: String, toTitle: String)] = []

        for (sourceID, linkedTitles) in index.noteLinks {
            guard let fromTitle = index.noteTitles[sourceID] else { continue }
            for linkedTitle in linkedTitles {
                if let toID = index.titleToID[linkedTitle], toID != sourceID,
                   let toTitle = index.noteTitles[toID]
                {
                    edges.append((from: sourceID, to: toID, fromTitle: fromTitle, toTitle: toTitle))
                }
            }
        }

        return edges
    }

    public func createOrOpenDailyNote(date: Date) async throws -> Note {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = .current
        let dateTitle = formatter.string(from: date)

        if let existing = try await noteStore.fetchNoteByTitle(dateTitle), existing.deletedAt == nil {
            return existing
        }

        return try await createNote(title: dateTitle, body: "")
    }

    public func listTemplates() async throws -> [NoteTemplate] {
        try await templateStore.fetchTemplates()
    }

    public func createTemplate(name: String, body: String) async throws -> NoteTemplate {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw StorageError.executeStatement(reason: "Template name cannot be empty")
        }

        let template = NoteTemplate(name: trimmedName, body: body, createdAt: clock.now())
        return try await templateStore.upsertTemplate(template)
    }

    public func deleteTemplate(id: UUID) async throws {
        try await templateStore.deleteTemplate(id: id)
    }
}
