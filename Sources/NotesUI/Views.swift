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
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.red.gradient, in: Capsule())
                    .shadow(color: .red.opacity(0.3), radius: 8, y: 4)
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .accessibilityIdentifier("globalErrorBanner")
            }
        }
        .animation(.spring(duration: 0.4), value: viewModel.errorMessage != nil)
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
        .sheet(isPresented: $viewModel.isQuickOpenPresented) {
            QuickOpenSheetView(viewModel: viewModel)
        }
    }

    private var notesList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text("Notes")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button {
                    viewModel.openQuickSwitcher()
                } label: {
                    Image(systemName: "magnifyingglass")
                        .accessibilityHidden(true)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("o", modifiers: [.command])
                .accessibilityIdentifier("quickOpenButton")
                Button {
                    _Concurrency.Task { await viewModel.createNote() }
                } label: {
                    Image(systemName: "square.and.pencil")
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("newNoteButton")
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
                TextField("Search", text: $viewModel.noteSearchQuery)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                    .onChange(of: viewModel.noteSearchQuery) { _, newValue in
                        _Concurrency.Task { await viewModel.setNoteSearchQuery(newValue) }
                    }
                    .accessibilityIdentifier("noteSearchField")
            }
            .padding(8)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            List(viewModel.notes, id: \.id) { note in
                let isSelected = note.id == viewModel.selectedNoteID
                Button {
                    _Concurrency.Task { await viewModel.selectNote(id: note.id) }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(note.title)
                            .font(.subheadline.weight(isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                            .lineLimit(1)
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
                    .padding(.vertical, 2)
                }
                .buttonStyle(.plain)
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
                        .padding(.horizontal, 4)
                )
                .accessibilityIdentifier("noteRow_\(note.id.uuidString)")
            }
            .listStyle(.sidebar)
        }
        .background(Color.secondary.opacity(0.04))
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
        VStack(alignment: .leading, spacing: 0) {
            TextField("Note Title", text: $viewModel.selectedNoteTitle)
                .textFieldStyle(.plain)
                .font(.title2.weight(.bold))
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 8)
                .accessibilityIdentifier("noteTitleField")

            TextEditor(text: $viewModel.selectedNoteBody)
                .onChange(of: viewModel.selectedNoteBody) { _, newValue in
                    viewModel.updateSelectedNoteBody(newValue)
                }
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 16)
                .accessibilityIdentifier("noteBodyEditor")

            if viewModel.isWikiLinkSuggestionVisible {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(viewModel.wikiLinkSuggestions.enumerated()), id: \.offset) { index, suggestion in
                            Button {
                                viewModel.applyWikiLinkSuggestion(suggestion)
                            } label: {
                                Label(suggestion, systemImage: "link")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .accessibilityIdentifier("wikiSuggestion_\(index)")
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.vertical, 6)
                .background(.ultraThinMaterial)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .accessibilityIdentifier("wikiSuggestionsBar")
            }

            Divider().padding(.horizontal, 16)

            HStack(spacing: 8) {
                editorToolbarButtons

                Divider().frame(height: 20)

                Button {
                    _Concurrency.Task { await viewModel.saveSelectedNote() }
                } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.accentColor)
                .accessibilityIdentifier("saveNoteButton")

                Divider().frame(height: 20)

                TextField("Quick task…", text: $viewModel.quickTaskTitle)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                    .padding(6)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                    .accessibilityIdentifier("quickTaskField")

                Button {
                    _Concurrency.Task { await viewModel.createQuickTask() }
                } label: {
                    Label("Add Task", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("quickTaskButton")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)

            DisclosureGroup {
                if viewModel.backlinks.isEmpty {
                    Label("No backlinks yet", systemImage: "link")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 8)
                        .accessibilityIdentifier("backlinksEmptyState")
                } else {
                    List(viewModel.backlinks, id: \.sourceNoteID) { backlink in
                        Label(backlink.sourceTitle, systemImage: "arrow.turn.up.left")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .listStyle(.plain)
                    .frame(minHeight: 120)
                    .accessibilityIdentifier("backlinksList")
                }
            } label: {
                Label("Backlinks", systemImage: "link")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .animation(.spring(duration: 0.3), value: viewModel.isWikiLinkSuggestionVisible)
    }

    private var editorToolbarButtons: some View {
        HStack(spacing: 4) {
            Button {
                viewModel.insertMarkdownHeading()
            } label: {
                Label("Heading", systemImage: "textformat.size.larger")
            }
            .keyboardShortcut("1", modifiers: [.command, .shift])
            .accessibilityIdentifier("insertHeadingButton")

            Button {
                viewModel.insertMarkdownBullet()
            } label: {
                Label("Bullet", systemImage: "list.bullet")
            }
            .keyboardShortcut("8", modifiers: [.command, .shift])
            .accessibilityIdentifier("insertBulletButton")

            Button {
                viewModel.insertMarkdownCheckbox()
            } label: {
                Label("Checkbox", systemImage: "checklist")
            }
            .keyboardShortcut("x", modifiers: [.command, .shift])
            .accessibilityIdentifier("insertCheckboxButton")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

struct QuickOpenSheetView: View {
    @Bindable var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.body)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
                TextField("Search notes…", text: $viewModel.quickOpenQuery)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .onChange(of: viewModel.quickOpenQuery) { _, newValue in
                        viewModel.setQuickOpenQuery(newValue)
                    }
                    .accessibilityIdentifier("quickOpenSearchField")
                Button("Close") {
                    viewModel.closeQuickSwitcher()
                }
                .accessibilityIdentifier("quickOpenCloseButton")
            }
            .padding(16)

            Divider()

            List(viewModel.quickOpenResults, id: \.id) { note in
                Button {
                    _Concurrency.Task { await viewModel.selectQuickOpenResult(noteID: note.id) }
                } label: {
                    Label(note.title, systemImage: "doc.text")
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 2)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("quickOpenRow_\(note.id.uuidString)")
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .accessibilityIdentifier("quickOpenResultsList")
        }
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
        VStack(spacing: 0) {
            Picker("Filter", selection: $viewModel.taskFilter) {
                ForEach(TaskListFilter.allCases, id: \.self) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: viewModel.taskFilter) { _, newValue in
                _Concurrency.Task { await viewModel.setTaskFilter(newValue) }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .accessibilityIdentifier("taskFilterPicker")

            List(viewModel.tasks, id: \.id) { task in
                taskRow(task)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .accessibilityIdentifier("tasksList")
        }
    }

    private func taskRow(_ task: Task) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                _Concurrency.Task { await viewModel.toggleTaskCompletion(taskID: task.id, isCompleted: task.status != .done) }
            } label: {
                Image(systemName: task.status == .done ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(task.status == .done ? Color.green : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(.body)
                    .strikethrough(task.status == .done)
                    .foregroundStyle(task.status == .done ? .secondary : .primary)

                HStack(spacing: 6) {
                    Text(task.status.uiTitle)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(task.status.accentColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(task.status.accentColor.opacity(0.12), in: Capsule())
                    if let due = task.dueStart {
                        Label(due.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                            .font(.caption)
                            .foregroundStyle(DueDateStyle.color(for: due))
                    }
                }
            }

            Spacer(minLength: 0)

            Button(role: .destructive) {
                _Concurrency.Task { await viewModel.deleteTask(taskID: task.id) }
            } label: {
                Image(systemName: "trash")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("deleteTask_\(task.id.uuidString)")
        }
        .padding(12)
        .dnCard()
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
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(TaskStatus.allCases, id: \.self) { status in
                        columnView(status: status, boardHeight: geometry.size.height)
                    }
                }
                .padding(16)
            }
        }
    }

    private func columnView(status: TaskStatus, boardHeight: CGFloat) -> some View {
        let isDropTarget = viewModel.dropTargetStatus == status
        let cards = viewModel.tasks(for: status)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: status.uiIcon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(status.accentColor)
                Text(status.uiTitle)
                    .font(.subheadline.weight(.semibold))
                Text("\(cards.count)")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
            .padding(.horizontal, 4)

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 8) {
                    if cards.isEmpty {
                        VStack(spacing: 6) {
                            Image(systemName: "rectangle.on.rectangle.slash")
                                .font(.title3)
                                .foregroundStyle(.quaternary)
                            Text("No cards")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
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
        .frame(width: 260)
        .dnColumn(isDropTarget: isDropTarget)
        .animation(.spring(duration: 0.25), value: isDropTarget)
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

        return HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(status.accentColor)
                .frame(width: 3)
                .padding(.vertical, 6)

            VStack(alignment: .leading, spacing: 6) {
                Text(task.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)

                if let due = task.dueStart {
                    Label(due.formatted(date: .numeric, time: .shortened), systemImage: "clock")
                        .font(.caption2)
                        .foregroundStyle(DueDateStyle.color(for: due))
                }

                HStack(spacing: 0) {
                    if status.previous != nil {
                        Button {
                            moveLeftAction()
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.caption.weight(.semibold))
                                .frame(width: 28, height: 24)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("moveLeft_\(task.id.uuidString)")
                    }

                    Spacer(minLength: 0)

                    Button(role: .destructive) {
                        _Concurrency.Task { await viewModel.deleteTask(taskID: task.id) }
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption)
                            .frame(width: 28, height: 24)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("deleteKanbanTask_\(task.id.uuidString)")

                    if status.next != nil {
                        Button {
                            moveRightAction()
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .frame(width: 28, height: 24)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("moveRight_\(task.id.uuidString)")
                    }
                }
                .foregroundStyle(.tertiary)
            }
            .padding(.leading, 10)
            .padding(.trailing, 8)
            .padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dnCard(cornerRadius: 8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isDropTarget ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .animation(.spring(duration: 0.2), value: isDropTarget)
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
            Section {
                TextField("Calendar Identifier", text: $viewModel.syncCalendarID)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("syncCalendarField")
                Text("Use `list-calendars` from CLI to find the Apple Calendar ID.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } header: {
                Label("Calendar", systemImage: "calendar")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack(spacing: 12) {
                    Button {
                        _Concurrency.Task { await viewModel.runSync() }
                    } label: {
                        HStack(spacing: 8) {
                            if viewModel.isSyncing {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text(viewModel.isSyncing ? "Syncing…" : "Run Two-Way Sync")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isSyncing)
                    .accessibilityIdentifier("runSyncButton")

                    HStack(spacing: 6) {
                        Image(systemName: viewModel.isSyncing ? "arrow.triangle.2.circlepath" : "checkmark.circle")
                            .font(.caption)
                            .foregroundStyle(viewModel.isSyncing ? .orange : .green)
                            .symbolEffect(.rotate, isActive: viewModel.isSyncing)
                        Text(viewModel.syncStatusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityIdentifier("syncStatusText")
                }
            } header: {
                Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if let report = viewModel.lastSyncReport {
                Section {
                    HStack(spacing: 16) {
                        syncMetric(label: "Pushed", value: report.tasksPushed, icon: "arrow.up.circle", color: .blue)
                        syncMetric(label: "Pulled", value: report.eventsPulled, icon: "arrow.down.circle", color: .green)
                        syncMetric(label: "Imported", value: report.tasksImported, icon: "plus.circle", color: .orange)
                        syncMetric(label: "Deleted", value: report.tasksDeletedFromCalendar, icon: "minus.circle", color: .red)
                    }

                    HStack(spacing: 8) {
                        Button {
                            _Concurrency.Task { await viewModel.exportSyncDiagnostics() }
                        } label: {
                            Label("Export Diagnostics", systemImage: "square.and.arrow.up")
                                .font(.subheadline)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityIdentifier("exportSyncDiagnosticsButton")

                        if let exportURL = viewModel.lastDiagnosticsExportURL {
                            Text("Exported: \(exportURL.path)")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .accessibilityIdentifier("syncDiagnosticsExportPath")
                        }
                    }
                } header: {
                    Label("Last Report", systemImage: "chart.bar")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("syncReportSection")

                Section {
                    if report.diagnostics.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                            Text("No diagnostics captured in last run")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityIdentifier("syncDiagnosticsEmptyState")
                    } else {
                        ForEach(Array(report.diagnostics.enumerated()), id: \.offset) { index, entry in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Image(systemName: entry.severity.uiIcon)
                                        .font(.caption)
                                        .foregroundStyle(entry.severity.uiColor)
                                    Text(entry.operation.rawValue)
                                        .font(.subheadline.weight(.medium))
                                }
                                Text(entry.message)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(
                                    "Entity: \(entry.entityType?.rawValue ?? "-")/\(entry.entityID?.uuidString ?? "-") " +
                                    "• Task: \(entry.taskID?.uuidString ?? "-") • Event: \(entry.eventIdentifier ?? "-")"
                                )
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            }
                            .accessibilityIdentifier("syncDiagnosticRow_\(index)")
                        }
                    }
                } header: {
                    Label("Diagnostics", systemImage: "stethoscope")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("syncDiagnosticsSection")
            }

            if let recurrenceConflictMessage = viewModel.recurrenceConflictMessage {
                Section("Recurrence Conflicts") {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.title3)
                            .foregroundStyle(.orange)
                        Text(recurrenceConflictMessage)
                            .font(.subheadline)
                    }
                    .accessibilityIdentifier("recurrenceConflictBanner")
                }
            }
        }
        .formStyle(.grouped)
    }

    private func syncMetric(label: String, value: Int, icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            Text("\(value)")
                .font(.title3.weight(.semibold).monospacedDigit())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private extension SyncDiagnosticSeverity {
    var uiIcon: String {
        switch self {
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }

    var uiColor: Color {
        switch self {
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
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
