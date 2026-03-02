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
        .confirmationDialog(
            "Recurring Task Edit",
            isPresented: Binding(
                get: { viewModel.recurrenceEditPrompt != nil },
                set: { isPresented in
                    if !isPresented {
                        viewModel.dismissRecurrenceEditPrompt()
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("This Occurrence") {
                _Concurrency.Task {
                    await viewModel.resolveRecurrenceEditPrompt(scope: .thisOccurrence)
                }
            }

            Button("Entire Series") {
                _Concurrency.Task {
                    await viewModel.resolveRecurrenceEditPrompt(scope: .entireSeries)
                }
            }

            Button("Cancel", role: .cancel) {
                viewModel.dismissRecurrenceEditPrompt()
            }
        } message: {
            if let occurrenceDate = viewModel.recurrenceEditPrompt?.occurrenceDate {
                Text("Choose whether to update only the detached occurrence (\(occurrenceDate.formatted(date: .abbreviated, time: .shortened))) or the parent series.")
            } else {
                Text("Choose whether to update only the detached occurrence or the parent series.")
            }
        }
        .confirmationDialog(
            "Recurring Task Delete",
            isPresented: Binding(
                get: { viewModel.recurrenceDeletePrompt != nil },
                set: { isPresented in
                    if !isPresented {
                        viewModel.dismissRecurrenceDeletePrompt()
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("This Occurrence", role: .destructive) {
                _Concurrency.Task {
                    await viewModel.resolveRecurrenceDeletePrompt(scope: .thisOccurrence)
                }
            }

            Button("Entire Series", role: .destructive) {
                _Concurrency.Task {
                    await viewModel.resolveRecurrenceDeletePrompt(scope: .entireSeries)
                }
            }

            Button("Cancel", role: .cancel) {
                viewModel.dismissRecurrenceDeletePrompt()
            }
        } message: {
            if let occurrenceDate = viewModel.recurrenceDeletePrompt?.occurrenceDate {
                Text("Delete only detached occurrence (\(occurrenceDate.formatted(date: .abbreviated, time: .shortened))) or delete the entire recurring series.")
            } else {
                Text("Delete only this detached occurrence or the entire recurring series.")
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
                    viewModel.openQuickSwitcher()
                } label: {
                    Image(systemName: "magnifyingglass.circle")
                }
                .buttonStyle(.plain)
                .keyboardShortcut("o", modifiers: [.command])
                .accessibilityIdentifier("quickOpenButton")
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
                    VStack(alignment: .leading, spacing: 4) {
                        Label(note.title, systemImage: note.id == viewModel.selectedNoteID ? "doc.text.fill" : "doc.text")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if let snippet = viewModel.noteSearchSnippet(for: note.id) {
                            Text(highlightedSearchSnippet(snippet))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityIdentifier("noteSnippet_\(note.id.uuidString)")
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("noteRow_\(note.id.uuidString)")
            }
        }
    }

    private func highlightedSearchSnippet(_ snippet: String) -> AttributedString {
        let openTag = "<mark>"
        let closeTag = "</mark>"

        var result = AttributedString()
        var searchStart = snippet.startIndex
        while let openRange = snippet.range(of: openTag, range: searchStart..<snippet.endIndex) {
            let prefix = String(snippet[searchStart..<openRange.lowerBound])
            if !prefix.isEmpty {
                result.append(AttributedString(prefix))
            }

            let markedStart = openRange.upperBound
            guard let closeRange = snippet.range(of: closeTag, range: markedStart..<snippet.endIndex) else {
                let remainder = String(snippet[openRange.lowerBound..<snippet.endIndex])
                result.append(AttributedString(remainder))
                return result
            }

            let markedValue = String(snippet[markedStart..<closeRange.lowerBound])
            if !markedValue.isEmpty {
                var highlighted = AttributedString(markedValue)
                highlighted.foregroundColor = .accentColor
                highlighted.inlinePresentationIntent = .stronglyEmphasized
                result.append(highlighted)
            }
            searchStart = closeRange.upperBound
        }

        let tail = String(snippet[searchStart..<snippet.endIndex])
        if !tail.isEmpty {
            result.append(AttributedString(tail))
        }
        return result
    }

    private var noteEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Title", text: $viewModel.selectedNoteTitle)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("noteTitleField")

            TextEditor(text: $viewModel.selectedNoteBody)
                .onChange(of: viewModel.selectedNoteBody) { _, newValue in
                    viewModel.updateSelectedNoteBody(newValue)
                }
                .font(.body)
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.2))
                }
                .accessibilityIdentifier("noteBodyEditor")

            if viewModel.isWikiLinkSuggestionVisible {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(viewModel.wikiLinkSuggestions.enumerated()), id: \.offset) { index, suggestion in
                            Button {
                                viewModel.applyWikiLinkSuggestion(suggestion)
                            } label: {
                                Label(suggestion, systemImage: "link")
                            }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("wikiSuggestion_\(index)")
                        }
                    }
                }
                .accessibilityIdentifier("wikiSuggestionsBar")
            }

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

            HStack(spacing: 8) {
                Button {
                    viewModel.insertMarkdownHeading()
                } label: {
                    Label("Heading", systemImage: "textformat.size.larger")
                }
                .buttonStyle(.bordered)
                .keyboardShortcut("1", modifiers: [.command, .shift])
                .accessibilityIdentifier("insertHeadingButton")

                Button {
                    viewModel.insertMarkdownBullet()
                } label: {
                    Label("Bullet", systemImage: "list.bullet")
                }
                .buttonStyle(.bordered)
                .keyboardShortcut("8", modifiers: [.command, .shift])
                .accessibilityIdentifier("insertBulletButton")

                Button {
                    viewModel.insertMarkdownCheckbox()
                } label: {
                    Label("Checkbox", systemImage: "checklist")
                }
                .buttonStyle(.bordered)
                .keyboardShortcut("x", modifiers: [.command, .shift])
                .accessibilityIdentifier("insertCheckboxButton")
            }

            Divider()

            Text("Backlinks")
                .font(.headline)

            if viewModel.backlinks.isEmpty {
                Label("No backlinks yet", systemImage: "link")
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
        .sheet(isPresented: $viewModel.isQuickOpenPresented) {
            QuickOpenSheetView(viewModel: viewModel)
        }
    }
}

private struct QuickOpenSheetView: View {
    @Bindable var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Quick Open", systemImage: "magnifyingglass")
                    .font(.headline)
                Spacer()
                Button("Close") {
                    viewModel.closeQuickSwitcher()
                }
                .accessibilityIdentifier("quickOpenCloseButton")
            }

            TextField("Search notes", text: $viewModel.quickOpenQuery)
                .textFieldStyle(.roundedBorder)
                .onChange(of: viewModel.quickOpenQuery) { _, newValue in
                    viewModel.setQuickOpenQuery(newValue)
                }
                .accessibilityIdentifier("quickOpenSearchField")

            List(viewModel.quickOpenResults, id: \.id) { note in
                Button {
                    _Concurrency.Task { await viewModel.selectQuickOpenResult(noteID: note.id) }
                } label: {
                    Label(note.title, systemImage: "doc.text")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("quickOpenRow_\(note.id.uuidString)")
            }
            .accessibilityIdentifier("quickOpenResultsList")
        }
        .padding()
        .frame(minWidth: 520, minHeight: 420)
        .onAppear {
            viewModel.setQuickOpenQuery(viewModel.quickOpenQuery)
        }
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

            Spacer(minLength: 0)

            Button(role: .destructive) {
                _Concurrency.Task { await viewModel.deleteTask(taskID: task.id) }
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("deleteTask_\(task.id.uuidString)")
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
        GeometryReader { geometry in
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(TaskStatus.allCases, id: \.self) { status in
                        columnView(status: status, boardHeight: geometry.size.height)
                    }
                }
                .padding()
            }
        }
    }

    private func columnView(status: TaskStatus, boardHeight: CGFloat) -> some View {
        let isDropTarget = viewModel.dropTargetStatus == status

        return VStack(alignment: .leading, spacing: 10) {
            Label(status.uiTitle, systemImage: status.uiIcon)
                .font(.headline)

            let cards = viewModel.tasks(for: status)
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 10) {
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
                }
                .padding(.bottom, 4)
            }
            .frame(height: max(180, boardHeight - 78), alignment: .top)
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
            viewModel.performTaskDrop(taskPayloads: payloads, to: status, beforeTaskID: nil)
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
        let moveLeftAction = {
            guard let previous = status.previous else { return }
            _Concurrency.Task { await viewModel.moveTask(taskID: task.id, to: previous) }
        }
        let moveRightAction = {
            guard let next = status.next else { return }
            _Concurrency.Task { await viewModel.moveTask(taskID: task.id, to: next) }
        }

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
                if status.previous != nil {
                    Button {
                        moveLeftAction()
                    } label: {
                        Image(systemName: "arrow.left.circle")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("moveLeft_\(task.id.uuidString)")
                }

                Spacer(minLength: 0)

                Button(role: .destructive) {
                    _Concurrency.Task { await viewModel.deleteTask(taskID: task.id) }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("deleteKanbanTask_\(task.id.uuidString)")

                if status.next != nil {
                    Button {
                        moveRightAction()
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
            viewModel.performTaskDrop(taskPayloads: payloads, to: status, beforeTaskID: task.id)
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
        .focusable()
        #if os(macOS)
        .onMoveCommand { direction in
            switch direction {
            case .left:
                moveLeftAction()
            case .right:
                moveRightAction()
            default:
                break
            }
        }
        #endif
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

            if let recurrenceConflictMessage = viewModel.recurrenceConflictMessage {
                Section("Recurrence Conflicts") {
                    Label(recurrenceConflictMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("recurrenceConflictBanner")
                }
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
