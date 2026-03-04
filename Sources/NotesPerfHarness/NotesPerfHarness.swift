// swiftlint:disable type_body_length function_body_length cyclomatic_complexity
import Foundation
import NotesDomain
import NotesFeatures
import NotesStorage

#if os(macOS)
    import AppKit
    import NotesSync
    import NotesUI
    import QuartzCore
    import SwiftUI
#endif

@main
struct NotesPerfHarness {
    static func main() async {
        do {
            let options = try Options.parse(arguments: Array(CommandLine.arguments.dropFirst()))
            let report = try await run(options: options)
            report.printLines()
            if let reportPath = options.reportPath {
                try report.writeJSON(to: URL(fileURLWithPath: reportPath))
            }
            if report.status == .failed {
                exit(1)
            }
        } catch {
            fputs("error: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func run(options: Options) async throws -> PerfReport {
        let launchSamples = try await runLaunchToInteractiveBenchmark(
            runs: options.runs,
            noteCount: options.launchDatasetNotes,
            taskCount: options.launchDatasetTasks,
        )
        let launchSummary = summarize(samples: launchSamples)

        let editorSamples = try await runEditorLatencyBenchmarks(
            noteCount: options.editorDatasetNotes,
            runs: options.runs,
        )
        let openNoteSummary = summarize(samples: editorSamples.openNote)
        let saveNoteSummary = summarize(samples: editorSamples.saveNote)
        let wikilinkBacklinksSummary = summarize(samples: editorSamples.wikilinkBacklinks)

        let createNoteSamples = try await runCreateNoteBenchmark(runs: options.runs)
        let createNoteSummary = summarize(samples: createNoteSamples)
        let search50kSamples = try await runSearch50KBenchmark(
            datasetSize: options.searchDatasetNotes,
            runs: options.searchRuns,
        )
        let search50kSummary = summarize(samples: search50kSamples)

        var kanbanSummary: LatencySummary?
        var kanbanFPSP95: Double?
        var kanbanDragSummary: LatencySummary?

        #if os(macOS)
            let kanbanDragSamples = try await runKanbanDragCommitBenchmark(
                runs: options.runs,
                taskCount: options.kanbanTaskCount,
            )
            kanbanDragSummary = summarize(samples: kanbanDragSamples)

            if !options.skipKanbanRender {
                let kanbanSamples = try await runKanbanRenderBenchmark(
                    runs: options.runs,
                    warmupRuns: options.warmupRuns,
                    taskCount: options.kanbanTaskCount,
                )
                let summary = summarize(samples: kanbanSamples)
                kanbanSummary = summary
                kanbanFPSP95 = framesPerSecond(fromMilliseconds: summary.p95)
            }
        #endif

        var failures: [String] = []

        if launchSummary.p95 > options.maxLaunchToInteractiveP95MS {
            failures.append(
                String(
                    format: "launch_to_interactive_p95_ms %.3f exceeds max %.3f",
                    launchSummary.p95,
                    options.maxLaunchToInteractiveP95MS,
                ),
            )
        }
        if openNoteSummary.p95 > options.maxOpenNoteP95MS {
            failures.append(
                String(
                    format: "open_note_p95_ms %.3f exceeds max %.3f",
                    openNoteSummary.p95,
                    options.maxOpenNoteP95MS,
                ),
            )
        }
        if saveNoteSummary.p95 > options.maxSaveNoteEditP95MS {
            failures.append(
                String(
                    format: "save_note_edit_p95_ms %.3f exceeds max %.3f",
                    saveNoteSummary.p95,
                    options.maxSaveNoteEditP95MS,
                ),
            )
        }
        if wikilinkBacklinksSummary.p95 > options.maxWikilinkBacklinksRefreshP95MS {
            failures.append(
                String(
                    format: "wikilink_backlinks_refresh_p95_ms %.3f exceeds max %.3f",
                    wikilinkBacklinksSummary.p95,
                    options.maxWikilinkBacklinksRefreshP95MS,
                ),
            )
        }
        if createNoteSummary.p95 > options.maxCreateNoteP95MS {
            failures.append(
                String(
                    format: "create_note_p95_ms %.3f exceeds max %.3f",
                    createNoteSummary.p95,
                    options.maxCreateNoteP95MS,
                ),
            )
        }
        if search50kSummary.p95 > options.maxSearch50kP95MS {
            failures.append(
                String(
                    format: "search_50k_p95_ms %.3f exceeds max %.3f",
                    search50kSummary.p95,
                    options.maxSearch50kP95MS,
                ),
            )
        }

        if let kanbanSummary {
            let maxKanbanFrameP95MS = options.maxKanbanFrameP95MS
            if kanbanSummary.p95 > maxKanbanFrameP95MS {
                failures.append(
                    String(
                        format: "kanban_render_frame_p95_ms %.3f exceeds max %.3f",
                        kanbanSummary.p95,
                        maxKanbanFrameP95MS,
                    ),
                )
            }

            if let kanbanFPSP95 {
                if kanbanFPSP95 + 0.000_1 < options.targetFPS {
                    failures.append(
                        String(
                            format: "kanban_render_fps_p95 %.2f below target %.2f",
                            kanbanFPSP95,
                            options.targetFPS,
                        ),
                    )
                }
            }
        }
        if let kanbanDragSummary, kanbanDragSummary.p95 > options.maxKanbanDragCommitP95MS {
            failures.append(
                String(
                    format: "kanban_drag_commit_p95_ms %.3f exceeds max %.3f",
                    kanbanDragSummary.p95,
                    options.maxKanbanDragCommitP95MS,
                ),
            )
        }

        return PerfReport(
            options: options,
            launchToInteractive: launchSummary,
            openNote: openNoteSummary,
            saveNoteEdit: saveNoteSummary,
            wikilinkBacklinksRefresh: wikilinkBacklinksSummary,
            createNote: createNoteSummary,
            search50k: search50kSummary,
            kanbanDragCommit: kanbanDragSummary,
            kanbanRender: kanbanSummary,
            kanbanFPSP95: kanbanFPSP95,
            failures: failures,
        )
    }

    private static func runLaunchToInteractiveBenchmark(runs: Int, noteCount: Int, taskCount: Int) async throws -> [Double] {
        let folder = try makeTempFolder(component: "launch")
        let dbURL = folder.appendingPathComponent("launch.sqlite")
        try await seedWorkspaceDatabase(
            databaseURL: dbURL,
            noteCount: noteCount,
            taskCount: taskCount,
            targetTitle: "Launch Target",
        )

        var samples: [Double] = []
        samples.reserveCapacity(runs)
        let clock = ContinuousClock()

        for _ in 0 ..< runs {
            let start = clock.now
            do {
                let store = try SQLiteStore(databaseURL: dbURL)
                let workspace = WorkspaceService(store: store)
                _ = try await workspace.listNoteListItems(limit: 50, offset: 0)
                _ = try await workspace.listTasks(filter: .all)
            }
            let elapsed = start.duration(to: clock.now)
            samples.append(milliseconds(from: elapsed))
        }

        return samples
    }

    private static func runEditorLatencyBenchmarks(noteCount: Int, runs: Int) async throws -> EditorLatencySamples {
        let folder = try makeTempFolder(component: "editor")
        let dbURL = folder.appendingPathComponent("editor.sqlite")
        try await seedWorkspaceDatabase(
            databaseURL: dbURL,
            noteCount: noteCount,
            taskCount: 200,
            targetTitle: "Target",
        )

        let store = try SQLiteStore(databaseURL: dbURL)
        let workspace = WorkspaceService(store: store)
        let notes = try await workspace.listNotes()
        guard let editable = notes.first, let target = notes.first(where: { $0.title == "Target" }) else {
            throw PerfHarnessError.invalidFixture("Editor benchmark requires seeded notes.")
        }
        let noteIDs = notes.map(\.id)
        let parser = WikiLinkParser()
        let clock = ContinuousClock()

        _ = try await store.fetchNote(id: editable.id)
        _ = try await workspace.backlinks(for: target.id)

        var openSamples: [Double] = []
        var saveSamples: [Double] = []
        var wikilinkSamples: [Double] = []
        openSamples.reserveCapacity(runs)
        saveSamples.reserveCapacity(runs)
        wikilinkSamples.reserveCapacity(runs)

        let editableTitle = editable.title
        for run in 0 ..< runs {
            let openStart = clock.now
            _ = try await store.fetchNote(id: noteIDs[run % noteIDs.count])
            openSamples.append(milliseconds(from: openStart.duration(to: clock.now)))

            let updatedBody = "Perf save iteration \(run). Links [[Target]] and [[Note \(run % max(1, noteCount - 1))]]."
            let saveStart = clock.now
            _ = try await workspace.updateNote(id: editable.id, title: editableTitle, body: updatedBody)
            saveSamples.append(milliseconds(from: saveStart.duration(to: clock.now)))

            let wikiStart = clock.now
            _ = parser.linkedTitles(in: updatedBody)
            _ = try await workspace.backlinks(for: target.id)
            wikilinkSamples.append(milliseconds(from: wikiStart.duration(to: clock.now)))
        }

        return EditorLatencySamples(
            openNote: openSamples,
            saveNote: saveSamples,
            wikilinkBacklinks: wikilinkSamples,
        )
    }

    private static func runCreateNoteBenchmark(runs: Int) async throws -> [Double] {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("notes-perf-harness")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let store = try SQLiteStore(databaseURL: folder.appendingPathComponent("notes.sqlite"))
        let workspace = WorkspaceService(store: store)

        var samples: [Double] = []
        samples.reserveCapacity(runs)

        let clock = ContinuousClock()
        for index in 0 ..< runs {
            let start = clock.now
            _ = try await workspace.createNote(
                title: "Perf Note \(index)",
                body: "Body for benchmark iteration \(index).",
            )
            let elapsed = start.duration(to: clock.now)
            samples.append(milliseconds(from: elapsed))
        }

        return samples
    }

    private static func runSearch50KBenchmark(datasetSize: Int, runs: Int) async throws -> [Double] {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("notes-perf-harness")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let store = try SQLiteStore(databaseURL: folder.appendingPathComponent("search.sqlite"))
        let workspace = WorkspaceService(store: store)
        let base = Date(timeIntervalSince1970: 1_700_000_000)

        for index in 0 ..< datasetSize {
            let isLaunchNote = (index % 9) == 0
            _ = try await store.upsertNote(
                Note(
                    title: isLaunchNote ? "Launch planning note \(index)" : "General note \(index)",
                    body: isLaunchNote
                        ? "Launch roadmap milestones and checklist item \(index)."
                        : "Archived context for weekly operations \(index).",
                    updatedAt: base.addingTimeInterval(Double(index)),
                ),
            )
        }

        // Warm query caches to reduce cold-start skew.
        _ = try await workspace.searchNotesPage(query: "launch", mode: .smart, limit: 50, offset: 0)

        var samples: [Double] = []
        samples.reserveCapacity(runs)
        let clock = ContinuousClock()
        for _ in 0 ..< runs {
            let start = clock.now
            _ = try await workspace.searchNotesPage(query: "launch", mode: .smart, limit: 50, offset: 0)
            let elapsed = start.duration(to: clock.now)
            samples.append(milliseconds(from: elapsed))
        }
        return samples
    }

    #if os(macOS)
        @MainActor
        private static func runKanbanRenderBenchmark(
            runs: Int,
            warmupRuns: Int,
            taskCount: Int,
        ) async throws -> [Double] {
            let folder = FileManager.default.temporaryDirectory
                .appendingPathComponent("notes-perf-harness")
                .appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

            let store = try SQLiteStore(databaseURL: folder.appendingPathComponent("kanban.sqlite"))
            let service = WorkspaceService(store: store)

            let statuses = TaskStatus.allCases
            for index in 0 ..< taskCount {
                _ = try await service.createTask(
                    NewTaskInput(
                        title: "Card \(index)",
                        status: statuses[index % statuses.count],
                        priority: 3,
                    ),
                )
            }

            let provider = InMemoryCalendarProvider()
            let viewModel = AppViewModel(
                service: service,
                calendarProviderFactory: { provider },
                syncCalendarID: "",
            )

            await viewModel.reloadTasks()

            let renderer = KanbanRenderer(viewModel: viewModel)
            defer { renderer.teardown() }

            var samples: [Double] = []
            samples.reserveCapacity(runs)
            let availableStatuses = TaskStatus.allCases
            let timeout: TimeInterval = 1.0

            renderer.requestRender()
            guard var previousDraw = renderer.waitForNextDraw(after: nil, timeout: timeout) else {
                throw PerfHarnessError.kanbanFrameTimeout(iteration: 0)
            }

            for tick in 0 ..< (warmupRuns + runs) {
                let status = availableStatuses[tick % availableStatuses.count]
                viewModel.setDropTargetStatus(status)
                viewModel.setDropTargetTaskID(nil)

                renderer.requestRender()
                guard let currentDraw = renderer.waitForNextDraw(after: previousDraw, timeout: timeout) else {
                    throw PerfHarnessError.kanbanFrameTimeout(iteration: tick + 1)
                }

                if tick >= warmupRuns {
                    samples.append(Double(currentDraw - previousDraw) / 1_000_000)
                }
                previousDraw = currentDraw
            }

            viewModel.endTaskDrag()
            return samples
        }

        private static func runKanbanDragCommitBenchmark(
            runs: Int,
            taskCount: Int,
        ) async throws -> [Double] {
            let folder = try makeTempFolder(component: "kanban-drag")
            let dbURL = folder.appendingPathComponent("kanban-drag.sqlite")
            try await seedWorkspaceDatabase(
                databaseURL: dbURL,
                noteCount: 64,
                taskCount: max(3, taskCount),
                targetTitle: "Drag Target",
            )

            let store = try SQLiteStore(databaseURL: dbURL)
            let workspace = WorkspaceService(store: store)
            let clock = ContinuousClock()
            var samples: [Double] = []
            samples.reserveCapacity(runs)

            for index in 0 ..< runs {
                let backlogTasks = try await store.fetchTasks(includeDeleted: false)
                    .filter { $0.status == .backlog }
                    .sorted { $0.kanbanOrder < $1.kanbanOrder }
                guard backlogTasks.count >= 2 else {
                    throw PerfHarnessError.invalidFixture("Kanban drag benchmark requires at least two backlog tasks.")
                }

                let moving: Task
                let before: Task
                if index.isMultiple(of: 2) {
                    moving = backlogTasks[1]
                    before = backlogTasks[0]
                } else {
                    moving = backlogTasks[0]
                    before = backlogTasks[1]
                }

                let start = clock.now
                _ = try await workspace.moveTask(taskID: moving.id, to: .backlog, beforeTaskID: before.id)
                samples.append(milliseconds(from: start.duration(to: clock.now)))
            }

            return samples
        }

        @MainActor
        private final class KanbanRenderer {
            private let window: NSWindow
            private let hostingView: InstrumentedHostingView<KanbanBoardView>
            private let viewModel: AppViewModel // periphery:ignore
            private var latestDrawTimestampNS: UInt64?

            init(viewModel: AppViewModel) {
                self.viewModel = viewModel
                let app = NSApplication.shared
                app.setActivationPolicy(.prohibited)

                let frame = NSRect(x: 0, y: 0, width: 1440, height: 920)
                window = NSWindow(
                    contentRect: frame,
                    styleMask: [.borderless],
                    backing: .buffered,
                    defer: false,
                )
                window.isReleasedWhenClosed = false
                window.ignoresMouseEvents = true
                window.orderFrontRegardless()

                hostingView = InstrumentedHostingView(rootView: KanbanBoardView(viewModel: viewModel))
                hostingView.onDraw = { [weak self] in
                    self?.latestDrawTimestampNS = DispatchTime.now().uptimeNanoseconds
                }
                hostingView.frame = frame
                hostingView.autoresizingMask = [.width, .height]
                window.contentView = hostingView
                window.layoutIfNeeded()
                window.displayIfNeeded()
            }

            func requestRender() {
                hostingView.needsDisplay = true
                window.contentView?.needsDisplay = true
            }

            func waitForNextDraw(after previousTimestampNS: UInt64?, timeout: TimeInterval) -> UInt64? {
                let deadline = Date().addingTimeInterval(timeout)
                while Date() < deadline {
                    if let latest = latestDrawTimestampNS,
                       previousTimestampNS == nil || latest > previousTimestampNS!
                    {
                        return latest
                    }
                    RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 1.0 / 240.0))
                }
                return nil
            }

            func teardown() {
                window.orderOut(nil)
                window.close()
            }
        }

        private final class InstrumentedHostingView<Content: View>: NSHostingView<Content> {
            var onDraw: (() -> Void)?

            override func draw(_ dirtyRect: NSRect) {
                super.draw(dirtyRect)
                onDraw?()
            }
        }
    #endif

    private static func summarize(samples: [Double]) -> LatencySummary {
        precondition(!samples.isEmpty, "At least one sample is required")
        let sorted = samples.sorted()
        let avg = sorted.reduce(0, +) / Double(sorted.count)
        let p50 = percentile(0.50, sorted: sorted)
        let p95 = percentile(0.95, sorted: sorted)

        return LatencySummary(
            min: sorted.first ?? 0,
            max: sorted.last ?? 0,
            avg: avg,
            p50: p50,
            p95: p95,
        )
    }

    private static func percentile(_ percentile: Double, sorted: [Double]) -> Double {
        let rank = Int(ceil(percentile * Double(sorted.count)))
        let index = min(sorted.count - 1, max(0, rank - 1))
        return sorted[index]
    }

    private static func milliseconds(from duration: Duration) -> Double {
        let components = duration.components
        return (Double(components.seconds) * 1000) + (Double(components.attoseconds) / 1_000_000_000_000_000)
    }

    private static func makeTempFolder(component: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("notes-perf-harness")
            .appendingPathComponent(component)
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private static func seedWorkspaceDatabase(
        databaseURL: URL,
        noteCount: Int,
        taskCount: Int,
        targetTitle: String,
    ) async throws {
        let store = try SQLiteStore(databaseURL: databaseURL)
        let workspace = WorkspaceService(store: store)
        let base = Date(timeIntervalSince1970: 1_700_000_000)

        var seededNotes: [Note] = []
        seededNotes.reserveCapacity(max(1, noteCount))
        let targetNote = try await store.upsertNote(
            Note(
                title: targetTitle,
                body: "Root note for perf harness.",
                updatedAt: base,
            ),
        )
        seededNotes.append(targetNote)

        if noteCount > 1 {
            for index in 1 ..< noteCount {
                let body = if index.isMultiple(of: 3) {
                    "Linked context [[\(targetTitle)]] \(index)"
                } else {
                    "General context \(index)"
                }
                let note = try await store.upsertNote(
                    Note(
                        title: "Note \(index)",
                        body: body,
                        updatedAt: base.addingTimeInterval(Double(index)),
                    ),
                )
                seededNotes.append(note)
            }
        }

        let statuses = TaskStatus.allCases
        for index in 0 ..< taskCount {
            _ = try await workspace.createTask(
                NewTaskInput(
                    noteID: seededNotes[index % seededNotes.count].id,
                    title: "Task \(index)",
                    details: "Drag benchmark task \(index)",
                    status: statuses[index % statuses.count],
                    priority: 3,
                ),
            )
        }
    }

    private static func framesPerSecond(fromMilliseconds milliseconds: Double) -> Double {
        guard milliseconds > 0 else {
            return .infinity
        }
        return 1000 / milliseconds
    }
}

private struct LatencySummary: Codable {
    let min: Double
    let max: Double
    let avg: Double
    let p50: Double
    let p95: Double
}

private struct EditorLatencySamples {
    let openNote: [Double]
    let saveNote: [Double]
    let wikilinkBacklinks: [Double]
}

private enum HarnessStatus: String, Codable {
    case ok
    case failed
}

private struct PerfReport: Codable {
    let options: Options
    let launchToInteractive: LatencySummary
    let openNote: LatencySummary
    let saveNoteEdit: LatencySummary
    let wikilinkBacklinksRefresh: LatencySummary
    let createNote: LatencySummary
    let search50k: LatencySummary
    let kanbanDragCommit: LatencySummary?
    let kanbanRender: LatencySummary?
    let kanbanFPSP95: Double?
    let failures: [String]

    var status: HarnessStatus {
        failures.isEmpty ? .ok : .failed
    }

    func printLines() {
        print("notes_perfharness_runs=\(options.runs)")
        print("notes_perfharness_warmup_runs=\(options.warmupRuns)")
        print("notes_perfharness_kanban_cards=\(options.kanbanTaskCount)")
        print("launch_dataset_notes=\(options.launchDatasetNotes)")
        print("launch_dataset_tasks=\(options.launchDatasetTasks)")
        print("editor_dataset_notes=\(options.editorDatasetNotes)")
        print("search_50k_dataset_size=\(options.searchDatasetNotes)")
        print("search_50k_runs=\(options.searchRuns)")

        print(String(format: "launch_to_interactive_min_ms=%.3f", launchToInteractive.min))
        print(String(format: "launch_to_interactive_p50_ms=%.3f", launchToInteractive.p50))
        print(String(format: "launch_to_interactive_p95_ms=%.3f", launchToInteractive.p95))
        print(String(format: "launch_to_interactive_avg_ms=%.3f", launchToInteractive.avg))
        print(String(format: "launch_to_interactive_max_ms=%.3f", launchToInteractive.max))
        print(String(format: "launch_to_interactive_p95_slo_ms=%.3f", options.maxLaunchToInteractiveP95MS))

        print(String(format: "open_note_min_ms=%.3f", openNote.min))
        print(String(format: "open_note_p50_ms=%.3f", openNote.p50))
        print(String(format: "open_note_p95_ms=%.3f", openNote.p95))
        print(String(format: "open_note_avg_ms=%.3f", openNote.avg))
        print(String(format: "open_note_max_ms=%.3f", openNote.max))
        print(String(format: "open_note_p95_slo_ms=%.3f", options.maxOpenNoteP95MS))

        print(String(format: "save_note_edit_min_ms=%.3f", saveNoteEdit.min))
        print(String(format: "save_note_edit_p50_ms=%.3f", saveNoteEdit.p50))
        print(String(format: "save_note_edit_p95_ms=%.3f", saveNoteEdit.p95))
        print(String(format: "save_note_edit_avg_ms=%.3f", saveNoteEdit.avg))
        print(String(format: "save_note_edit_max_ms=%.3f", saveNoteEdit.max))
        print(String(format: "save_note_edit_p95_slo_ms=%.3f", options.maxSaveNoteEditP95MS))

        print(String(format: "wikilink_backlinks_refresh_min_ms=%.3f", wikilinkBacklinksRefresh.min))
        print(String(format: "wikilink_backlinks_refresh_p50_ms=%.3f", wikilinkBacklinksRefresh.p50))
        print(String(format: "wikilink_backlinks_refresh_p95_ms=%.3f", wikilinkBacklinksRefresh.p95))
        print(String(format: "wikilink_backlinks_refresh_avg_ms=%.3f", wikilinkBacklinksRefresh.avg))
        print(String(format: "wikilink_backlinks_refresh_max_ms=%.3f", wikilinkBacklinksRefresh.max))
        print(String(format: "wikilink_backlinks_refresh_p95_slo_ms=%.3f", options.maxWikilinkBacklinksRefreshP95MS))

        print(String(format: "create_note_min_ms=%.3f", createNote.min))
        print(String(format: "create_note_p50_ms=%.3f", createNote.p50))
        print(String(format: "create_note_p95_ms=%.3f", createNote.p95))
        print(String(format: "create_note_avg_ms=%.3f", createNote.avg))
        print(String(format: "create_note_max_ms=%.3f", createNote.max))
        print(String(format: "create_note_p95_slo_ms=%.3f", options.maxCreateNoteP95MS))

        print(String(format: "search_50k_min_ms=%.3f", search50k.min))
        print(String(format: "search_50k_p50_ms=%.3f", search50k.p50))
        print(String(format: "search_50k_p95_ms=%.3f", search50k.p95))
        print(String(format: "search_50k_avg_ms=%.3f", search50k.avg))
        print(String(format: "search_50k_max_ms=%.3f", search50k.max))
        print(String(format: "search_50k_p95_slo_ms=%.3f", options.maxSearch50kP95MS))

        if let kanbanDragCommit {
            print(String(format: "kanban_drag_commit_min_ms=%.3f", kanbanDragCommit.min))
            print(String(format: "kanban_drag_commit_p50_ms=%.3f", kanbanDragCommit.p50))
            print(String(format: "kanban_drag_commit_p95_ms=%.3f", kanbanDragCommit.p95))
            print(String(format: "kanban_drag_commit_avg_ms=%.3f", kanbanDragCommit.avg))
            print(String(format: "kanban_drag_commit_max_ms=%.3f", kanbanDragCommit.max))
            print(String(format: "kanban_drag_commit_p95_slo_ms=%.3f", options.maxKanbanDragCommitP95MS))
        }

        if let kanbanRender {
            print(String(format: "kanban_render_frame_min_ms=%.3f", kanbanRender.min))
            print(String(format: "kanban_render_frame_p50_ms=%.3f", kanbanRender.p50))
            print(String(format: "kanban_render_frame_p95_ms=%.3f", kanbanRender.p95))
            print(String(format: "kanban_render_frame_avg_ms=%.3f", kanbanRender.avg))
            print(String(format: "kanban_render_frame_max_ms=%.3f", kanbanRender.max))
            print(String(format: "kanban_render_frame_p95_slo_ms=%.3f", options.maxKanbanFrameP95MS))
            print(String(format: "kanban_target_fps=%.2f", options.targetFPS))
            if let kanbanFPSP95 {
                print(String(format: "kanban_render_fps_p95=%.2f", kanbanFPSP95))
            }
        }

        if failures.isEmpty {
            print("status=ok")
        } else {
            for failure in failures {
                print("failure=\(failure)")
            }
            print("status=failed")
        }
    }

    func writeJSON(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}

private struct Options: Codable {
    var runs: Int = 240
    var warmupRuns: Int = 40
    var kanbanTaskCount: Int = 1000
    var launchDatasetNotes: Int = 2000
    var launchDatasetTasks: Int = 1000
    var editorDatasetNotes: Int = 10000
    var searchDatasetNotes: Int = 50000
    var searchRuns: Int = 40
    var targetFPS: Double = 120
    var maxLaunchToInteractiveP95MS: Double = 200
    var maxOpenNoteP95MS: Double = 40
    var maxSaveNoteEditP95MS: Double = 30
    var maxWikilinkBacklinksRefreshP95MS: Double = 50
    var maxCreateNoteP95MS: Double = 30
    var maxSearch50kP95MS: Double = 80
    var maxKanbanDragCommitP95MS: Double = 50
    var maxKanbanFrameP95MS: Double
    var skipKanbanRender: Bool = false
    var reportPath: String?

    init() {
        maxKanbanFrameP95MS = 1000 / targetFPS
    }

    static func parse(arguments: [String]) throws -> Options {
        var options = Options()
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--runs":
                options.runs = try parsePositiveInt(flag: argument, value: value(after: argument, index: &index, from: arguments))
            case "--warmup-runs":
                options.warmupRuns = try parseNonNegativeInt(flag: argument, value: value(after: argument, index: &index, from: arguments))
            case "--kanban-cards":
                let val = try value(after: argument, index: &index, from: arguments)
                options.kanbanTaskCount = try parsePositiveInt(flag: argument, value: val)
            case "--launch-dataset-notes":
                let val = try value(after: argument, index: &index, from: arguments)
                options.launchDatasetNotes = try parsePositiveInt(flag: argument, value: val)
            case "--launch-dataset-tasks":
                let val = try value(after: argument, index: &index, from: arguments)
                options.launchDatasetTasks = try parsePositiveInt(flag: argument, value: val)
            case "--editor-dataset-notes":
                let val = try value(after: argument, index: &index, from: arguments)
                options.editorDatasetNotes = try parsePositiveInt(flag: argument, value: val)
            case "--search-dataset-notes":
                let val = try value(after: argument, index: &index, from: arguments)
                options.searchDatasetNotes = try parsePositiveInt(flag: argument, value: val)
            case "--search-runs":
                options.searchRuns = try parsePositiveInt(flag: argument, value: value(after: argument, index: &index, from: arguments))
            case "--target-fps":
                options.targetFPS = try parsePositiveDouble(flag: argument, value: value(after: argument, index: &index, from: arguments))
                options.maxKanbanFrameP95MS = 1000 / options.targetFPS
            case "--max-launch-p95-ms":
                let val = try value(after: argument, index: &index, from: arguments)
                options.maxLaunchToInteractiveP95MS = try parsePositiveDouble(flag: argument, value: val)
            case "--max-open-note-p95-ms":
                let val = try value(after: argument, index: &index, from: arguments)
                options.maxOpenNoteP95MS = try parsePositiveDouble(flag: argument, value: val)
            case "--max-save-note-p95-ms":
                let val = try value(after: argument, index: &index, from: arguments)
                options.maxSaveNoteEditP95MS = try parsePositiveDouble(flag: argument, value: val)
            case "--max-wikilink-backlinks-p95-ms":
                options.maxWikilinkBacklinksRefreshP95MS = try parsePositiveDouble(
                    flag: argument,
                    value: value(after: argument, index: &index, from: arguments),
                )
            case "--max-create-note-p95-ms":
                let val = try value(after: argument, index: &index, from: arguments)
                options.maxCreateNoteP95MS = try parsePositiveDouble(flag: argument, value: val)
            case "--max-search-50k-p95-ms":
                let val = try value(after: argument, index: &index, from: arguments)
                options.maxSearch50kP95MS = try parsePositiveDouble(flag: argument, value: val)
            case "--max-kanban-drag-commit-p95-ms":
                let val = try value(after: argument, index: &index, from: arguments)
                options.maxKanbanDragCommitP95MS = try parsePositiveDouble(flag: argument, value: val)
            case "--max-kanban-frame-p95-ms":
                let val = try value(after: argument, index: &index, from: arguments)
                options.maxKanbanFrameP95MS = try parsePositiveDouble(flag: argument, value: val)
            case "--skip-kanban-render":
                options.skipKanbanRender = true
            case "--report-json":
                options.reportPath = try value(after: argument, index: &index, from: arguments)
            case "--help", "-h":
                throw PerfHarnessError.helpRequested
            default:
                throw PerfHarnessError.invalidArgument("Unknown flag: \(argument)")
            }
            index += 1
        }

        return options
    }

    private static func value(after flag: String, index: inout Int, from arguments: [String]) throws -> String {
        let nextIndex = index + 1
        if arguments.indices.contains(nextIndex) {
            index = nextIndex
            return arguments[nextIndex]
        }
        throw PerfHarnessError.invalidArgument("\(flag) requires a value")
    }

    private static func parsePositiveInt(flag: String, value: String) throws -> Int {
        guard let parsed = Int(value), parsed > 0 else {
            throw PerfHarnessError.invalidArgument("\(flag) expects a positive integer")
        }
        return parsed
    }

    private static func parseNonNegativeInt(flag: String, value: String) throws -> Int {
        guard let parsed = Int(value), parsed >= 0 else {
            throw PerfHarnessError.invalidArgument("\(flag) expects a non-negative integer")
        }
        return parsed
    }

    private static func parsePositiveDouble(flag: String, value: String) throws -> Double {
        guard let parsed = Double(value), parsed > 0 else {
            throw PerfHarnessError.invalidArgument("\(flag) expects a positive number")
        }
        return parsed
    }
}

private enum PerfHarnessError: LocalizedError {
    case invalidArgument(String)
    case invalidFixture(String)
    case helpRequested
    case kanbanFrameTimeout(iteration: Int)

    var errorDescription: String? {
        switch self {
        case let .invalidArgument(message):
            "\(message)\n\n\(Self.usageText)"
        case let .invalidFixture(message):
            message
        case .helpRequested:
            Self.usageText
        case let .kanbanFrameTimeout(iteration):
            "Timed out waiting for rendered Kanban frame at iteration \(iteration)."
        }
    }

    private static let usageText = """
    notes-perf-harness options:
      --runs <n>                         Number of measured samples per benchmark (default: 240)
      --warmup-runs <n>                  Warmup samples for rendering benchmark (default: 40)
      --kanban-cards <n>                 Number of cards used for kanban rendering benchmark (default: 1000)
      --launch-dataset-notes <n>         Dataset size for launch benchmark (default: 2000)
      --launch-dataset-tasks <n>         Task count for launch benchmark (default: 1000)
      --editor-dataset-notes <n>         Dataset size for open/save/wiki benchmark (default: 10000)
      --search-dataset-notes <n>         Number of notes used for search benchmark (default: 50000)
      --search-runs <n>                  Number of measured search samples (default: 40)
      --target-fps <hz>                  Target refresh rate for gating (default: 120)
      --max-launch-p95-ms <ms>           Launch-to-interactive p95 gate (default: 200)
      --max-open-note-p95-ms <ms>        Open-note p95 gate (default: 40)
      --max-save-note-p95-ms <ms>        Save-note-edit p95 gate (default: 30)
      --max-wikilink-backlinks-p95-ms <ms> Wiki-link/backlinks refresh p95 gate (default: 50)
      --max-kanban-frame-p95-ms <ms>     Explicit p95 frame-time gate (default: 1000/target-fps)
      --max-kanban-drag-commit-p95-ms    Kanban drag reorder commit p95 gate (default: 50)
      --max-create-note-p95-ms <ms>      Note creation p95 gate (default: 30)
      --max-search-50k-p95-ms <ms>       Search-at-50k p95 gate (default: 80)
      --skip-kanban-render               Skip the kanban rendering benchmark
      --report-json <path>               Optional JSON report output path
    """
}
