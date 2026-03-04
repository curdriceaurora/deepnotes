import SwiftUI
import NotesDomain
import NotesFeatures
import NotesSync

@MainActor
public struct NotesRootView: View {
    @Bindable var viewModel: AppViewModel
    @Environment(\.scenePhase) private var scenePhase

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

            GraphView(viewModel: viewModel)
                .tabItem { Label("Graph", systemImage: "point.3.connected.trianglepath.dotted") }

            SyncDashboardView(viewModel: viewModel)
                .tabItem { Label("Sync", systemImage: "arrow.triangle.2.circlepath.circle") }
        }
        .task { await viewModel.load() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                _Concurrency.Task { await viewModel.autoSync() }
            }
        }
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

@MainActor
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
        .sheet(isPresented: $viewModel.isTemplatePickerPresented) {
            TemplatePickerSheetView(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.isTemplateManagerPresented) {
            TemplateManagerView(viewModel: viewModel)
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
                    _Concurrency.Task { await viewModel.openDailyNote() }
                } label: {
                    Image(systemName: "calendar.badge.plus")
                        .accessibilityHidden(true)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("d", modifiers: [.command, .option])
                .accessibilityIdentifier("dailyNoteButton")
                Button {
                    _Concurrency.Task { await viewModel.showNewNoteOptions() }
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

            if !viewModel.allTagsList.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(viewModel.allTagsList, id: \.self) { tag in
                            Button {
                                _Concurrency.Task {
                                    if viewModel.selectedTagFilter == tag {
                                        await viewModel.filterByTag(nil)
                                    } else {
                                        await viewModel.filterByTag(tag)
                                    }
                                }
                            } label: {
                                Text("#\(tag)")
                                    .font(.caption2.weight(.medium))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        viewModel.selectedTagFilter == tag
                                            ? Color.accentColor.opacity(0.2)
                                            : Color.secondary.opacity(0.1),
                                        in: Capsule()
                                    )
                                    .foregroundStyle(
                                        viewModel.selectedTagFilter == tag
                                            ? Color.accentColor
                                            : Color.secondary
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("tagFilter_\(tag)")
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .padding(.bottom, 6)
                .accessibilityIdentifier("tagFilterBar")
            }

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
                        if !note.tags.isEmpty {
                            HStack(spacing: 4) {
                                ForEach(note.tags.prefix(3), id: \.self) { tag in
                                    Text("#\(tag)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .accessibilityIdentifier("noteTags_\(note.id.uuidString)")
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
                .onAppear {
                    if note.id == viewModel.notes.last?.id {
                        _Concurrency.Task { await viewModel.loadMoreNotes() }
                    }
                }
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
            HStack {
                TextField("Note Title", text: $viewModel.selectedNoteTitle)
                    .textFieldStyle(.plain)
                    .font(.title2.weight(.bold))
                    .accessibilityIdentifier("noteTitleField")

                Button {
                    viewModel.toggleNoteEditMode()
                } label: {
                    Image(systemName: viewModel.noteEditMode == .edit ? "eye" : "pencil")
                        .font(.body)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .accessibilityIdentifier("togglePreviewButton")
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 8)

            if viewModel.noteEditMode == .edit {
                TextEditor(text: $viewModel.selectedNoteBody)
                    .onChange(of: viewModel.selectedNoteBody) { _, newValue in
                        viewModel.updateSelectedNoteBody(newValue)
                    }
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 16)
                    .accessibilityIdentifier("noteBodyEditor")
            } else {
                ScrollView {
                    Text(viewModel.renderedMarkdown)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                }
                .environment(\.openURL, OpenURLAction { url in
                    guard url.scheme == "deepnotes", url.host == "wikilink" else {
                        return .systemAction
                    }
                    let title = url.pathComponents.dropFirst().joined(separator: "/")
                        .removingPercentEncoding ?? ""
                    _Concurrency.Task {
                        await viewModel.navigateToNoteByTitle(title)
                    }
                    return .handled
                })
                .accessibilityIdentifier("noteBodyPreview")
            }

            if viewModel.isWikiLinkSuggestionVisible && viewModel.noteEditMode == .edit {
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
                if viewModel.noteEditMode == .edit {
                    editorToolbarButtons
                    Divider().frame(height: 20)
                }

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

                Menu {
                    ForEach(0...5, id: \.self) { priority in
                        Button {
                            viewModel.quickTaskPriority = priority
                        } label: {
                            if let label = PriorityDisplay.label(for: priority) {
                                Label(label, systemImage: "flag.fill")
                            } else {
                                Label("None", systemImage: "flag")
                            }
                        }
                    }
                } label: {
                    if let label = PriorityDisplay.label(for: viewModel.quickTaskPriority) {
                        Label(label, systemImage: "flag.fill")
                            .font(.caption)
                            .foregroundStyle(PriorityDisplay.color(for: viewModel.quickTaskPriority))
                    } else {
                        Label("Priority", systemImage: "flag")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("quickTaskPriorityPicker")

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
                        Button {
                            _Concurrency.Task { await viewModel.selectNote(id: backlink.sourceNoteID) }
                        } label: {
                            Label(backlink.sourceTitle, systemImage: "arrow.turn.up.left")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("backlinkRow_\(backlink.sourceNoteID.uuidString)")
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
            .padding(.bottom, 8)

            DisclosureGroup {
                if viewModel.unlinkedMentions.isEmpty {
                    Label("No unlinked mentions", systemImage: "link.badge.minus")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 8)
                        .accessibilityIdentifier("unlinkedMentionsEmptyState")
                } else {
                    List(viewModel.unlinkedMentions, id: \.sourceNoteID) { mention in
                        HStack {
                            Button {
                                _Concurrency.Task { await viewModel.selectNote(id: mention.sourceNoteID) }
                            } label: {
                                Label(mention.sourceTitle, systemImage: "text.badge.minus")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            Spacer()
                            Button {
                                _Concurrency.Task { await viewModel.linkMention(sourceNoteID: mention.sourceNoteID) }
                            } label: {
                                Text("Link")
                                    .font(.caption)
                                    .tint(.accentColor)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .accessibilityIdentifier("unlinkedMentionRow_\(mention.sourceNoteID.uuidString)")
                    }
                    .listStyle(.plain)
                    .frame(minHeight: 120)
                    .accessibilityIdentifier("unlinkedMentionsList")
                }
            } label: {
                Label("Unlinked Mentions", systemImage: "link.badge.minus")
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

@MainActor
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

@MainActor
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

            if viewModel.isMultiSelectMode {
                Divider()
                HStack(spacing: 12) {
                    Text("\(viewModel.selectedTaskIDs.count) selected")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Menu {
                        ForEach(TaskStatus.allCases, id: \.self) { status in
                            Button(status.uiTitle) {
                                _Concurrency.Task {
                                    await viewModel.bulkMoveTasksToStatus(status)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text("Move to")
                            Image(systemName: "chevron.down")
                        }
                        .font(.subheadline.weight(.medium))
                    }
                    .accessibilityIdentifier("bulkMoveMenu")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.quaternary)
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Menu {
                    ForEach(TaskSortOrder.allCases, id: \.self) { order in
                        Button {
                            _Concurrency.Task { await viewModel.setTaskSortOrder(order) }
                        } label: {
                            if viewModel.taskSortOrder == order {
                                Label(order.title, systemImage: "checkmark")
                            } else {
                                Text(order.title)
                            }
                        }
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
                .accessibilityIdentifier("taskSortMenu")

                Button {
                    viewModel.toggleMultiSelectMode()
                } label: {
                    Text(viewModel.isMultiSelectMode ? "Cancel" : "Select")
                }
                .accessibilityIdentifier("multiSelectToggleButton")
            }
        }
    }

    private func taskRow(_ task: Task) -> some View {
        HStack(alignment: .center, spacing: 12) {
            if viewModel.isMultiSelectMode {
                selectionButton(for: task)
            } else {
                completionButton(for: task)
            }

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
                    if !task.subtasks.isEmpty {
                        let done = task.subtasks.filter(\.isCompleted).count
                        Text("\(done)/\(task.subtasks.count)")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                    if let due = task.dueStart {
                        Label(due.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                            .font(.caption)
                            .foregroundStyle(DueDateStyle.color(for: due))
                    }
                }
            }

            Spacer(minLength: 0)

            if !viewModel.isMultiSelectMode {
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
        }
        .padding(12)
        .dnCard()
        .accessibilityIdentifier("taskRow_\(task.id.uuidString)")
    }

    private func selectionButton(for task: Task) -> some View {
        let isSelected = viewModel.isTaskSelected(task.id)
        return Button {
            viewModel.toggleTaskSelection(taskID: task.id)
        } label: {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isSelected ? Color.blue : Color.secondary)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
    }

    private func completionButton(for task: Task) -> some View {
        Button {
            _Concurrency.Task { await viewModel.toggleTaskCompletion(taskID: task.id, isCompleted: task.status != .done) }
        } label: {
            Image(systemName: task.status == .done ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(task.status == .done ? Color.green : Color.secondary)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
    }
}

@MainActor
public struct KanbanBoardView: View {
    @Bindable var viewModel: AppViewModel

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(viewModel.kanbanColumns) { column in
                        columnView(column: column, boardHeight: geometry.size.height)
                    }
                }
                .padding(16)
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Menu {
                    ForEach(KanbanGrouping.allCases, id: \.self) { grouping in
                        Button {
                            viewModel.kanbanGrouping = grouping
                        } label: {
                            if viewModel.kanbanGrouping == grouping {
                                Label(grouping.rawValue.capitalized, systemImage: "checkmark")
                            } else {
                                Text(grouping.rawValue.capitalized)
                            }
                        }
                    }
                } label: {
                    Label("Group", systemImage: "line.3.horizontal.decrease.circle")
                }
                .accessibilityIdentifier("kanbanGroupingPicker")

                Button {
                    viewModel.isColumnEditorPresented = true
                } label: {
                    Label("Add Column", systemImage: "plus.rectangle.on.rectangle")
                }
                .accessibilityIdentifier("addColumnButton")
            }
        }
        .sheet(item: $viewModel.selectedTaskForEditing) { task in
            KanbanCardDetailSheet(viewModel: viewModel, task: task)
        }
        .sheet(isPresented: $viewModel.isColumnEditorPresented) {
            KanbanColumnEditorSheet(viewModel: viewModel)
        }
    }

    private func columnView(column: KanbanColumn, boardHeight: CGFloat) -> some View {
        let isDropTarget = viewModel.dropTargetColumnID == column.id
        let cards = viewModel.tasksForColumn(column.id)
        let icon = column.builtInStatus?.uiIcon ?? "rectangle.stack"
        let accentColor: Color = column.builtInStatus?.accentColor ?? Color(hex: column.colorHex ?? "#888888") ?? .gray
        let isOverWip = column.wipLimit.map { cards.count >= $0 } ?? false

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(accentColor)
                Text(column.title)
                    .font(.subheadline.weight(.semibold))
                Text("\(cards.count)")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
                if let limit = column.wipLimit {
                    Text("/\(limit)")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(isOverWip ? .red : .secondary)
                }
            }
            .padding(.horizontal, 4)
            .background(isOverWip ? Color.red.opacity(0.08) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))

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
                    } else if viewModel.kanbanGrouping == .none {
                        ForEach(cards, id: \.id) { task in
                            taskCard(task: task, column: column)
                        }
                    } else {
                        let groups = viewModel.groupedTasks(for: column.id)
                        ForEach(groups, id: \.key) { group in
                            if !group.key.isEmpty {
                                Text(group.key)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 4)
                                    .padding(.top, 4)
                            }
                            ForEach(group.tasks, id: \.id) { task in
                                taskCard(task: task, column: column)
                            }
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
            if let status = column.builtInStatus {
                return viewModel.performTaskDrop(taskPayloads: payloads, to: status, beforeTaskID: nil)
            }
            return false
        } isTargeted: { targeted in
            if targeted {
                viewModel.setDropTargetColumn(column.id)
            } else if viewModel.dropTargetColumnID == column.id {
                viewModel.setDropTargetColumn(nil)
            }
        }
        .contextMenu {
            if column.builtInStatus == nil {
                Button("Edit WIP Limit...") {
                    viewModel.isColumnEditorPresented = true
                }
                Button("Delete Column", role: .destructive) {
                    _Concurrency.Task { await viewModel.deleteKanbanColumn(id: column.id) }
                }
            }
        }
        .accessibilityIdentifier(
            column.builtInStatus.map { "kanbanColumn_\($0.rawValue)" }
                ?? "kanbanColumn_\(column.id.uuidString)"
        )
    }

    private func taskCard(task: Task, column: KanbanColumn) -> some View {
        let status = column.builtInStatus ?? task.status
        let isDropTarget = viewModel.dropTargetTaskID == task.id
        let columnIndex = viewModel.kanbanColumns.firstIndex(where: { $0.id == column.id })
        let hasPrevious = columnIndex.map { $0 > 0 } ?? false
        let hasNext = columnIndex.map { $0 < viewModel.kanbanColumns.count - 1 } ?? false
        let moveLeftAction = {
            guard let idx = columnIndex, idx > 0 else { return }
            let prevCol = viewModel.kanbanColumns[idx - 1]
            if let prevStatus = prevCol.builtInStatus {
                _Concurrency.Task { await viewModel.moveTask(taskID: task.id, to: prevStatus) }
            }
        }
        let moveRightAction = {
            guard let idx = columnIndex, idx < viewModel.kanbanColumns.count - 1 else { return }
            let nextCol = viewModel.kanbanColumns[idx + 1]
            if let nextStatus = nextCol.builtInStatus {
                _Concurrency.Task { await viewModel.moveTask(taskID: task.id, to: nextStatus) }
            }
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

                HStack(spacing: 6) {
                    if let label = PriorityDisplay.label(for: task.priority) {
                        Text(label)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(PriorityDisplay.color(for: task.priority))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(PriorityDisplay.color(for: task.priority).opacity(0.2), in: Capsule())
                            .accessibilityIdentifier("priorityBadge_\(task.id.uuidString)")
                    }

                    if let due = task.dueStart {
                        Label(due.formatted(date: .numeric, time: .shortened), systemImage: "clock")
                            .font(.caption2)
                            .foregroundStyle(DueDateStyle.color(for: due))
                    }
                }

                if !task.labels.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(task.labels.prefix(3), id: \.name) { label in
                            Text(label.name)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(hex: label.colorHex) ?? .gray, in: Capsule())
                        }
                    }
                    .accessibilityIdentifier("taskLabels_\(task.id.uuidString)")
                }

                let tags = viewModel.tagsForTask(task)
                if !tags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(tags.prefix(2), id: \.self) { tag in
                            Text("#\(tag)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("taskTags_\(task.id.uuidString)")
                }

                HStack(spacing: 0) {
                    if hasPrevious {
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

                    if hasNext {
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
        .contentShape(Rectangle())
        .onTapGesture { viewModel.openTaskDetail(taskID: task.id) }
        .dnCard(cornerRadius: 8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isDropTarget ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .animation(.spring(duration: 0.2), value: isDropTarget)
        .dropDestination(for: String.self) { payloads, _ in
            if let dropStatus = column.builtInStatus {
                return viewModel.performTaskDrop(taskPayloads: payloads, to: dropStatus, beforeTaskID: task.id)
            }
            return false
        } isTargeted: { targeted in
            if targeted {
                viewModel.setDropTargetColumn(column.id)
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

@MainActor
private struct KanbanColumnEditorSheet: View {
    @Bindable var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("New Column")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
            }
            .padding()

            Divider()

            Form {
                Section("Title") {
                    TextField("Column title", text: $viewModel.newColumnTitle)
                        .accessibilityIdentifier("columnEditorTitle")
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("Save") {
                    _Concurrency.Task {
                        await viewModel.createKanbanColumn()
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.newColumnTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("columnEditorSave")
            }
            .padding()
        }
        .frame(minWidth: 300, minHeight: 200)
        .accessibilityIdentifier("kanbanColumnEditorSheet")
    }
}

@MainActor
private struct KanbanCardDetailSheet: View {
    private static let labelPalette = ["#FF0000", "#FF8800", "#FFCC00", "#00CC00", "#0088FF", "#8800FF", "#FF00AA", "#888888"]

    @Bindable var viewModel: AppViewModel
    @State private var editedTask: Task
    @State private var hasDueStart: Bool
    @State private var hasDueEnd: Bool
    @State private var newLabelName: String = ""
    @State private var newLabelColorHex: String = "#0088FF"
    @Environment(\.dismiss) private var dismiss

    init(viewModel: AppViewModel, task: Task) {
        self.viewModel = viewModel
        self._editedTask = State(initialValue: task)
        self._hasDueStart = State(initialValue: task.dueStart != nil)
        self._hasDueEnd = State(initialValue: task.dueEnd != nil)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Card Detail")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .accessibilityIdentifier("cardDetailCancel")
            }
            .padding()

            Divider()

            Form {
                Section("Title") {
                    TextField("Title", text: $editedTask.title)
                        .accessibilityIdentifier("cardDetailTitle")
                }

                Section("Details") {
                    TextEditor(text: $editedTask.details)
                        .frame(minHeight: 60)
                        .accessibilityIdentifier("cardDetailDetails")
                }

                Section("Status") {
                    Picker("Status", selection: $editedTask.status) {
                        ForEach(TaskStatus.allCases, id: \.self) { status in
                            Text(status.rawValue.capitalized).tag(status)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("cardDetailStatus")
                }

                Section("Priority") {
                    Picker("Priority", selection: $editedTask.priority) {
                        ForEach(0...5, id: \.self) { p in
                            HStack {
                                if PriorityDisplay.shouldDisplay(p) {
                                    Circle()
                                        .fill(PriorityDisplay.color(for: p))
                                        .frame(width: 8, height: 8)
                                }
                                Text(PriorityDisplay.label(for: p) ?? "None")
                            }
                            .tag(p)
                        }
                    }
                    .accessibilityIdentifier("cardDetailPriority")
                }

                Section("Due Dates") {
                    Toggle("Due Start", isOn: $hasDueStart)
                        .accessibilityIdentifier("cardDetailDueStartToggle")
                    if hasDueStart {
                        DatePicker("Start", selection: Binding(
                            get: { editedTask.dueStart ?? Date() },
                            set: { editedTask.dueStart = $0 }
                        ))
                        .accessibilityIdentifier("cardDetailDueStart")
                    }

                    Toggle("Due End", isOn: $hasDueEnd)
                        .accessibilityIdentifier("cardDetailDueEndToggle")
                    if hasDueEnd {
                        DatePicker("End", selection: Binding(
                            get: { editedTask.dueEnd ?? Date() },
                            set: { editedTask.dueEnd = $0 }
                        ))
                        .accessibilityIdentifier("cardDetailDueEnd")
                    }
                }
                .onChange(of: hasDueStart) { _, enabled in
                    if !enabled { editedTask.dueStart = nil }
                    else if editedTask.dueStart == nil { editedTask.dueStart = Date() }
                }
                .onChange(of: hasDueEnd) { _, enabled in
                    if !enabled { editedTask.dueEnd = nil }
                    else if editedTask.dueEnd == nil { editedTask.dueEnd = Date() }
                }

                Section("Linked Note") {
                    Picker("Note", selection: $editedTask.noteID) {
                        Text("None").tag(UUID?.none)
                        ForEach(viewModel.notes) { note in
                            Text(note.title).tag(UUID?.some(note.id))
                        }
                    }
                    .accessibilityIdentifier("cardDetailLinkedNote")
                }

                Section("Labels") {
                    ForEach(editedTask.labels, id: \.name) { label in
                        HStack {
                            Circle()
                                .fill(Color(hex: label.colorHex) ?? .gray)
                                .frame(width: 10, height: 10)
                            Text(label.name)
                            Spacer()
                            Button(role: .destructive) {
                                editedTask.labels.removeAll { $0.name == label.name }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    HStack {
                        TextField("Label name", text: $newLabelName)
                            .textFieldStyle(.roundedBorder)
                        HStack(spacing: 4) {
                            ForEach(Self.labelPalette, id: \.self) { hex in
                                Circle()
                                    .fill(Color(hex: hex) ?? .gray)
                                    .frame(width: 16, height: 16)
                                    .overlay(
                                        Circle()
                                            .stroke(newLabelColorHex == hex ? Color.primary : Color.clear, lineWidth: 2)
                                    )
                                    .onTapGesture { newLabelColorHex = hex }
                            }
                        }
                        Button("Add") {
                            let name = newLabelName.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !name.isEmpty else { return }
                            let label = TaskLabel(name: name, colorHex: newLabelColorHex)
                            if !editedTask.labels.contains(where: { $0.name.lowercased() == name.lowercased() }) {
                                editedTask.labels.append(label)
                            }
                            newLabelName = ""
                        }
                        .disabled(newLabelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .accessibilityIdentifier("cardDetailLabels")

                Section("Subtasks") {
                    ForEach(editedTask.subtasks, id: \.id) { subtask in
                        HStack {
                            Button {
                                _Concurrency.Task {
                                    await viewModel.toggleSubtask(parentTaskID: editedTask.id, subtaskID: subtask.id, isCompleted: !subtask.isCompleted)
                                }
                            } label: {
                                Image(systemName: subtask.isCompleted ? "checkmark.circle.fill" : "circle")
                                    .font(.subheadline)
                                    .foregroundStyle(subtask.isCompleted ? .green : .secondary)
                            }
                            .buttonStyle(.plain)

                            Text(subtask.title)
                                .strikethrough(subtask.isCompleted)
                                .foregroundStyle(subtask.isCompleted ? .secondary : .primary)

                            Spacer()

                            Button(role: .destructive) {
                                _Concurrency.Task {
                                    await viewModel.deleteSubtask(parentTaskID: editedTask.id, subtaskID: subtask.id)
                                }
                            } label: {
                                Image(systemName: "trash")
                                    .font(.subheadline)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    HStack {
                        TextField("Add subtask…", text: $viewModel.newSubtaskTitle)
                            .textFieldStyle(.roundedBorder)
                        Button("Add") {
                            _Concurrency.Task { await viewModel.addSubtask(to: editedTask.id) }
                        }
                        .disabled(viewModel.newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .accessibilityIdentifier("cardDetailSubtasks")
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("Save") {
                    _Concurrency.Task { await viewModel.saveTaskDetail(editedTask) }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("cardDetailSave")
            }
            .padding()
        }
        .frame(minWidth: 400, minHeight: 450)
        .accessibilityIdentifier("kanbanCardDetailSheet")
    }
}

@MainActor
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

@MainActor
struct TemplatePickerSheetView: View {
    @Bindable var viewModel: AppViewModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("New Note")
                    .font(.headline)
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            List {
                Section("Start with") {
                    Button {
                        _Concurrency.Task {
                            await viewModel.createNote()
                            dismiss()
                        }
                    } label: {
                        HStack {
                            Label("Blank Note", systemImage: "doc.text")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .opacity(0.5)
                        }
                    }
                    .foregroundStyle(.primary)
                }

                if !viewModel.templates.isEmpty {
                    Section("Templates") {
                        ForEach(viewModel.templates, id: \.id) { template in
                            Button {
                                _Concurrency.Task {
                                    await viewModel.createNoteFromTemplate(templateID: template.id)
                                    dismiss()
                                }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(template.name)
                                            .font(.subheadline.weight(.medium))
                                        Text(template.body.prefix(60))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .opacity(0.5)
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                }
            }
            .listStyle(.plain)

            Divider()

            HStack {
                Button {
                    viewModel.isTemplatePickerPresented = false
                    viewModel.isTemplateManagerPresented = true
                } label: {
                    Label("Manage Templates", systemImage: "ellipsis.circle")
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }
}

@MainActor
struct TemplateManagerView: View {
    @Bindable var viewModel: AppViewModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Manage Templates")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    dismiss()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            List {
                ForEach(viewModel.templates, id: \.id) { template in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(template.name)
                                .font(.subheadline.weight(.medium))
                            Text(template.body.prefix(60))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            _Concurrency.Task {
                                await viewModel.deleteTemplate(id: template.id)
                            }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .listStyle(.plain)

            Divider()

            VStack(spacing: 12) {
                TextField("Template name", text: $viewModel.newTemplateName)
                    .textFieldStyle(.roundedBorder)
                    .font(.subheadline)

                TextEditor(text: $viewModel.newTemplateBody)
                    .border(Color.gray.opacity(0.3), width: 1)
                    .font(.subheadline)
                    .frame(height: 100)
                    .scrollContentBackground(.hidden)

                Button {
                    _Concurrency.Task { await viewModel.createTemplate() }
                } label: {
                    Label("Add Template", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.accentColor)
                .disabled(viewModel.newTemplateName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(16)
        }
    }
}

@MainActor
public struct GraphView: View {
    @Bindable var viewModel: AppViewModel
    @State private var positions: [UUID: CGPoint] = [:]
    @State private var velocities: [UUID: CGSize] = [:]
    @State private var isSimulating: Bool = false

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Knowledge Graph")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button {
                    _Concurrency.Task { await viewModel.reloadGraph() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()

            GeometryReader { geometry in
                TimelineView(.animation(minimumInterval: 1/60, paused: !isSimulating)) { _ in
                    ZStack {
                        Color.secondary.opacity(0.03)

                        Canvas { context, canvasSize in
                            var currentPositions = positions
                            var currentVelocities = velocities

                            if isSimulating && !viewModel.graphNodes.isEmpty {
                                var simulator = GraphSimulator()
                                (currentPositions, currentVelocities) = simulator.step(
                                    nodes: viewModel.graphNodes,
                                    edges: viewModel.graphEdges,
                                    positions: currentPositions,
                                    velocities: currentVelocities,
                                    canvasSize: canvasSize
                                )
                                positions = currentPositions
                                velocities = currentVelocities
                            }

                            for edge in viewModel.graphEdges {
                                guard let fromPos = currentPositions[edge.fromID],
                                      let toPos = currentPositions[edge.toID] else {
                                    continue
                                }

                                var path = Path()
                                path.move(to: fromPos)
                                path.addLine(to: toPos)

                                context.stroke(
                                    path,
                                    with: .color(.secondary.opacity(0.3)),
                                    lineWidth: 1
                                )
                            }

                            for node in viewModel.graphNodes {
                                guard let position = currentPositions[node.id] else { continue }

                                let radius = CGFloat(max(14, min(30, Double(node.tagCount) + 14)))
                                let isSelected = node.id == viewModel.selectedNoteID
                                let color = isSelected ? Color.accentColor : Color.secondary

                                context.fill(
                                    Path(ellipseIn: CGRect(
                                        x: position.x - radius,
                                        y: position.y - radius,
                                        width: radius * 2,
                                        height: radius * 2
                                    )),
                                    with: .color(color.opacity(0.2))
                                )

                                context.stroke(
                                    Path(ellipseIn: CGRect(
                                        x: position.x - radius,
                                        y: position.y - radius,
                                        width: radius * 2,
                                        height: radius * 2
                                    )),
                                    with: .color(color),
                                    lineWidth: isSelected ? 2 : 1
                                )

                                var textContext = context
                                textContext.draw(
                                    Text(node.title.prefix(2).uppercased())
                                        .font(.caption2.weight(.semibold))
                                        .foregroundColor(color),
                                    at: position,
                                    anchor: .center
                                )
                            }
                        }

                        VStack {
                            HStack {
                                Spacer()
                                Button {
                                    isSimulating.toggle()
                                } label: {
                                    Image(systemName: isSimulating ? "pause.fill" : "play.fill")
                                        .font(.body)
                                        .frame(width: 44, height: 44)
                                        .background(Color.accentColor)
                                        .foregroundStyle(.white)
                                        .clipShape(Circle())
                                }
                                .buttonStyle(.plain)
                                .padding(16)
                            }
                            Spacer()
                        }
                    }
                    .onTapGesture { location in
                        for node in viewModel.graphNodes {
                            guard let position = positions[node.id] else { continue }
                            let radius = CGFloat(max(14, min(30, Double(node.tagCount) + 14)))
                            let distance = hypot(location.x - position.x, location.y - position.y)
                            if distance <= radius + 10 {
                                _Concurrency.Task { await viewModel.selectNote(id: node.id) }
                                return
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            initializeNodePositions()
            isSimulating = true
        }
        .task {
            await viewModel.reloadGraph()
            initializeNodePositions()
        }
    }

    private func initializeNodePositions() {
        var newPositions: [UUID: CGPoint] = [:]
        for node in viewModel.graphNodes {
            newPositions[node.id] = CGPoint(
                x: CGFloat.random(in: 50...400),
                y: CGFloat.random(in: 50...600)
            )
        }
        positions = newPositions
        velocities = [:]
    }
}

internal struct GraphSimulator {
    mutating func step(
        nodes: [GraphNode],
        edges: [GraphEdge],
        positions: [UUID: CGPoint],
        velocities: [UUID: CGSize],
        canvasSize: CGSize
    ) -> (positions: [UUID: CGPoint], velocities: [UUID: CGSize]) {
        var newPositions = positions
        var newVelocities = velocities

        for node in nodes {
            guard var pos = newPositions[node.id] else { continue }
            var vel = newVelocities[node.id] ?? .zero

            for other in nodes where other.id != node.id {
                guard let otherPos = newPositions[other.id] else { continue }
                let dx = pos.x - otherPos.x
                let dy = pos.y - otherPos.y
                let distance = max(hypot(dx, dy), 1)
                let repulsion = 4000 / (distance * distance)
                vel.width += (dx / distance) * repulsion
                vel.height += (dy / distance) * repulsion
            }

            for edge in edges {
                if edge.fromID == node.id, let toPos = newPositions[edge.toID] {
                    let dx = toPos.x - pos.x
                    let dy = toPos.y - pos.y
                    let distance = hypot(dx, dy)
                    vel.width += (dx / max(distance, 1)) * 0.03
                    vel.height += (dy / max(distance, 1)) * 0.03
                } else if edge.toID == node.id, let fromPos = newPositions[edge.fromID] {
                    let dx = fromPos.x - pos.x
                    let dy = fromPos.y - pos.y
                    let distance = hypot(dx, dy)
                    vel.width += (dx / max(distance, 1)) * 0.03
                    vel.height += (dy / max(distance, 1)) * 0.03
                }
            }

            vel.width *= 0.85
            vel.height *= 0.85
            pos.x += vel.width
            pos.y += vel.height

            pos.x = max(30, min(canvasSize.width - 30, pos.x))
            pos.y = max(30, min(canvasSize.height - 30, pos.y))

            newPositions[node.id] = pos
            newVelocities[node.id] = vel
        }

        return (newPositions, newVelocities)
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
