import SwiftUI
import NotesDomain
import NotesFeatures
import NotesSync

public struct NotesRootView: View {
    @Bindable var viewModel: AppViewModel

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        TabView {
            NotesEditorView(viewModel: viewModel)
                .tabItem { Label("Notes", systemImage: "note.text") }

            TasksListView(viewModel: viewModel)
                .tabItem { Label("Tasks", systemImage: "checklist.unchecked") }

            KanbanBoardView(viewModel: viewModel)
                .tabItem { Label("Board", systemImage: "square.grid.3x3.fill") }

            SyncDashboardView(viewModel: viewModel)
                .tabItem { Label("Sync", systemImage: "arrow.triangle.2.circlepath.circle") }
        }
        .task { await viewModel.load() }
        .overlay(alignment: .bottom) {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .padding(10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 12)
                    .accessibilityIdentifier("globalErrorBanner")
            }
        }
    }
}

public struct NotesEditorView: View {
    @Bindable var viewModel: AppViewModel

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        HStack(spacing: 0) {
            notesList
                .frame(minWidth: 260, idealWidth: 280, maxWidth: 320)

            Divider()

            noteEditor
        }
    }

    private var notesList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Notes", systemImage: "book.closed")
                    .font(.headline)
                Spacer()
                Button {
                    _Concurrency.Task { await viewModel.createNote() }
                } label: {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("newNoteButton")
            }
            .padding([.horizontal, .top])

            TextField("Search notes", text: $viewModel.noteSearchQuery)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
                .onChange(of: viewModel.noteSearchQuery) { _, newValue in
                    _Concurrency.Task { await viewModel.setNoteSearchQuery(newValue) }
                }
                .accessibilityIdentifier("noteSearchField")

            List(viewModel.notes, id: \.id) { note in
                Button {
                    _Concurrency.Task { await viewModel.selectNote(id: note.id) }
                } label: {
                    Label(note.title, systemImage: note.id == viewModel.selectedNoteID ? "doc.text.fill" : "doc.text")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("noteRow_\(note.id.uuidString)")
            }
        }
    }

    private var noteEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Title", text: $viewModel.selectedNoteTitle)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("noteTitleField")

            TextEditor(text: $viewModel.selectedNoteBody)
                .font(.body)
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.2))
                }
                .accessibilityIdentifier("noteBodyEditor")

            HStack(spacing: 10) {
                Button {
                    _Concurrency.Task { await viewModel.saveSelectedNote() }
                } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("saveNoteButton")

                TextField("Quick task title", text: $viewModel.quickTaskTitle)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("quickTaskField")

                Button {
                    _Concurrency.Task { await viewModel.createQuickTask() }
                } label: {
                    Label("Add Task", systemImage: "plus.rectangle.on.folder")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("quickTaskButton")
            }

            Divider()

            Text("Backlinks")
                .font(.headline)

            if viewModel.backlinks.isEmpty {
                Label("No backlinks yet", systemImage: "link.badge.minus")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("backlinksEmptyState")
            } else {
                List(viewModel.backlinks, id: \.sourceNoteID) { backlink in
                    Label(backlink.sourceTitle, systemImage: "link")
                }
                .accessibilityIdentifier("backlinksList")
                .frame(minHeight: 120)
            }

            Spacer(minLength: 0)
        }
        .padding()
    }
}

public struct TasksListView: View {
    @Bindable var viewModel: AppViewModel

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 12) {
            Picker("Filter", selection: $viewModel.taskFilter) {
                ForEach(TaskListFilter.allCases, id: \.self) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: viewModel.taskFilter) { _, newValue in
                _Concurrency.Task { await viewModel.setTaskFilter(newValue) }
            }
            .accessibilityIdentifier("taskFilterPicker")

            List(viewModel.tasks, id: \.id) { task in
                taskRow(task)
            }
            .accessibilityIdentifier("tasksList")
        }
        .padding()
    }

    private func taskRow(_ task: Task) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                _Concurrency.Task { await viewModel.toggleTaskCompletion(taskID: task.id, isCompleted: task.status != .done) }
            } label: {
                Image(systemName: task.status == .done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(task.status == .done ? .green : .secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .strikethrough(task.status == .done)

                HStack(spacing: 8) {
                    Label(task.status.uiTitle, systemImage: task.status.uiIcon)
                    if let due = task.dueStart {
                        Label(due.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("taskRow_\(task.id.uuidString)")
    }
}

public struct KanbanBoardView: View {
    @Bindable var viewModel: AppViewModel

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 16) {
                ForEach(TaskStatus.allCases, id: \.self) { status in
                    columnView(status: status)
                }
            }
            .padding()
        }
    }

    private func columnView(status: TaskStatus) -> some View {
        let isDropTarget = viewModel.dropTargetStatus == status

        return VStack(alignment: .leading, spacing: 10) {
            Label(status.uiTitle, systemImage: status.uiIcon)
                .font(.headline)

            let cards = viewModel.tasks(for: status)
            if cards.isEmpty {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.secondary.opacity(0.08))
                    .frame(height: 48)
                    .overlay(
                        Text("No cards")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    )
            } else {
                ForEach(cards, id: \.id) { task in
                    taskCard(task: task, status: status)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(width: 250)
        .background(
            isDropTarget ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 14)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isDropTarget ? Color.accentColor : Color.secondary.opacity(0.15), lineWidth: isDropTarget ? 2 : 1)
        )
        .dropDestination(for: String.self) { payloads, _ in
            guard payloads.contains(where: { UUID(uuidString: $0) != nil }) else {
                return false
            }
            _Concurrency.Task {
                _ = await viewModel.handleTaskDrop(taskPayloads: payloads, to: status, beforeTaskID: nil)
            }
            return true
        } isTargeted: { targeted in
            if targeted {
                viewModel.setDropTargetStatus(status)
            } else if viewModel.dropTargetStatus == status {
                viewModel.setDropTargetStatus(nil)
            }
        }
        .accessibilityIdentifier("kanbanColumn_\(status.rawValue)")
    }

    private func taskCard(task: Task, status: TaskStatus) -> some View {
        let isDropTarget = viewModel.dropTargetTaskID == task.id

        return VStack(alignment: .leading, spacing: 8) {
            Text(task.title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .lineLimit(2)

            if let due = task.dueStart {
                Label(due.formatted(date: .numeric, time: .shortened), systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                if let previous = status.previous {
                    Button {
                        _Concurrency.Task { await viewModel.moveTask(taskID: task.id, to: previous) }
                    } label: {
                        Image(systemName: "arrow.left.circle")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("moveLeft_\(task.id.uuidString)")
                }

                Spacer(minLength: 0)

                if let next = status.next {
                    Button {
                        _Concurrency.Task { await viewModel.moveTask(taskID: task.id, to: next) }
                    } label: {
                        Image(systemName: "arrow.right.circle")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("moveRight_\(task.id.uuidString)")
                }
            }
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isDropTarget ? Color.accentColor : Color.secondary.opacity(0.2),
                    lineWidth: isDropTarget ? 2 : 1
                )
        )
        .dropDestination(for: String.self) { payloads, _ in
            guard payloads.contains(where: { UUID(uuidString: $0) != nil }) else {
                return false
            }
            _Concurrency.Task {
                _ = await viewModel.handleTaskDrop(taskPayloads: payloads, to: status, beforeTaskID: task.id)
            }
            return true
        } isTargeted: { targeted in
            if targeted {
                viewModel.setDropTargetStatus(status)
                viewModel.setDropTargetTaskID(task.id)
            } else if viewModel.dropTargetTaskID == task.id {
                viewModel.setDropTargetTaskID(nil)
            }
        }
        .onDrag {
            viewModel.beginTaskDrag(taskID: task.id)
            return NSItemProvider(object: task.id.uuidString as NSString)
        }
        .accessibilityIdentifier("kanbanCard_\(task.id.uuidString)")
    }
}

public struct SyncDashboardView: View {
    @Bindable var viewModel: AppViewModel

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        SwiftUI.Form {
            Section("Calendar") {
                TextField("Calendar Identifier", text: $viewModel.syncCalendarID)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("syncCalendarField")
                Text("Use `list-calendars` from CLI to find the Apple Calendar ID.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Sync") {
                Button {
                    _Concurrency.Task { await viewModel.runSync() }
                } label: {
                    Label(viewModel.isSyncing ? "Syncing..." : "Run Two-Way Sync", systemImage: "arrow.triangle.2.circlepath.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isSyncing)
                .accessibilityIdentifier("runSyncButton")

                Label(viewModel.syncStatusText, systemImage: "waveform.path.ecg")
                    .accessibilityIdentifier("syncStatusText")
            }

            if let report = viewModel.lastSyncReport {
                Section("Last Report") {
                    LabeledContent("Tasks pushed", value: "\(report.tasksPushed)")
                    LabeledContent("Events pulled", value: "\(report.eventsPulled)")
                    LabeledContent("Tasks imported", value: "\(report.tasksImported)")
                    LabeledContent("Calendar deletes", value: "\(report.tasksDeletedFromCalendar)")

                    Button {
                        _Concurrency.Task { await viewModel.exportSyncDiagnostics() }
                    } label: {
                        Label("Export Diagnostics", systemImage: "square.and.arrow.up.on.square")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("exportSyncDiagnosticsButton")

                    if let exportURL = viewModel.lastDiagnosticsExportURL {
                        Text("Exported: \(exportURL.path)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("syncDiagnosticsExportPath")
                    }
                }
                .accessibilityIdentifier("syncReportSection")

                Section("Diagnostics") {
                    if report.diagnostics.isEmpty {
                        Label("No diagnostics captured in last run", systemImage: "checkmark.circle")
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("syncDiagnosticsEmptyState")
                    } else {
                        ForEach(Array(report.diagnostics.enumerated()), id: \.offset) { index, entry in
                            VStack(alignment: .leading, spacing: 4) {
                                Label(entry.operation.rawValue, systemImage: entry.severity.uiIcon)
                                    .font(.subheadline)
                                Text(entry.message)
                                    .font(.caption)
                                Text(
                                    "Entity: \(entry.entityType?.rawValue ?? "-")/\(entry.entityID?.uuidString ?? "-") " +
                                    "• Task: \(entry.taskID?.uuidString ?? "-") • Event: \(entry.eventIdentifier ?? "-")"
                                )
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .accessibilityIdentifier("syncDiagnosticRow_\(index)")
                        }
                    }
                }
                .accessibilityIdentifier("syncDiagnosticsSection")
            }
        }
    }
}

private extension SyncDiagnosticSeverity {
    var uiIcon: String {
        switch self {
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .error: return "xmark.octagon"
        }
    }
}

private extension TaskStatus {
    var uiTitle: String {
        switch self {
        case .backlog: return "Backlog"
        case .next: return "Next"
        case .doing: return "Doing"
        case .waiting: return "Waiting"
        case .done: return "Done"
        }
    }

    var uiIcon: String {
        switch self {
        case .backlog: return "tray"
        case .next: return "bolt"
        case .doing: return "play.circle"
        case .waiting: return "pause.circle"
        case .done: return "checkmark.circle"
        }
    }

    var previous: TaskStatus? {
        switch self {
        case .backlog: return nil
        case .next: return .backlog
        case .doing: return .next
        case .waiting: return .doing
        case .done: return .waiting
        }
    }

    var next: TaskStatus? {
        switch self {
        case .backlog: return .next
        case .next: return .doing
        case .doing: return .waiting
        case .waiting: return .done
        case .done: return nil
        }
    }
}
