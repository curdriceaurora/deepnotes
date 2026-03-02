import Foundation
import NotesDomain
import NotesStorage
import NotesSync
#if canImport(EventKit)
import EventKit
#endif

@main
struct NotesCLI {
    static func main() async {
        do {
            try await run()
        } catch {
            fputs("error: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func run() async throws {
        let args = CommandLine.arguments.dropFirst()
        guard let command = args.first else {
            printUsage()
            return
        }

        switch command {
        case "seed":
            let dbPath = value(for: "--db", in: Array(args.dropFirst())) ?? "./notes.db"
            try await seedDatabase(databasePath: dbPath)
            print("Seeded sample tasks into \(dbPath)")

        case "sync-memory":
            let dbPath = value(for: "--db", in: Array(args.dropFirst())) ?? "./notes.db"
            let calendarID = value(for: "--calendar", in: Array(args.dropFirst())) ?? "local-dev-calendar"
            try await syncWithInMemoryProvider(databasePath: dbPath, calendarID: calendarID)

        case "list-calendars":
            #if canImport(EventKit)
            try await listCalendars()
            #else
            throw SyncError.unsupportedCalendarChange(reason: "EventKit is unavailable on this platform")
            #endif

        case "sync-eventkit":
            #if canImport(EventKit)
            let dbPath = value(for: "--db", in: Array(args.dropFirst())) ?? "./notes.db"
            guard let calendarID = value(for: "--calendar", in: Array(args.dropFirst())) else {
                throw SyncError.unsupportedCalendarChange(reason: "--calendar <id> is required for sync-eventkit")
            }
            try await syncWithEventKit(databasePath: dbPath, calendarID: calendarID)
            #else
            throw SyncError.unsupportedCalendarChange(reason: "EventKit is unavailable on this platform")
            #endif

        default:
            printUsage()
        }
    }

    private static func seedDatabase(databasePath: String) async throws {
        let store = try await makeStore(databasePath: databasePath)
        let now = Date()

        let tasks: [Task] = [
            try Task(
                stableID: "task-call-supplier",
                title: "Call supplier",
                details: "Confirm MOQ and lead times.",
                dueStart: now.addingTimeInterval(3600),
                dueEnd: now.addingTimeInterval(5400),
                status: .next,
                priority: 4,
                recurrenceRule: nil,
                updatedAt: now
            ),
            try Task(
                stableID: "task-draft-launch-email",
                title: "Draft launch email",
                details: "Link to [[Q2 Launch Plan]].",
                dueStart: now.addingTimeInterval(7200),
                dueEnd: now.addingTimeInterval(9000),
                status: .doing,
                priority: 3,
                recurrenceRule: nil,
                updatedAt: now
            ),
            try Task(
                stableID: "task-weekly-budget-review",
                title: "Review budget",
                details: "Recurring Monday review.",
                dueStart: now.addingTimeInterval(86400),
                dueEnd: now.addingTimeInterval(90000),
                status: .waiting,
                priority: 2,
                recurrenceRule: "FREQ=WEEKLY;BYDAY=MO;BYHOUR=9;BYMINUTE=0",
                updatedAt: now
            )
        ]

        for task in tasks {
            _ = try await store.upsertTask(task)
        }
    }

    private static func syncWithInMemoryProvider(databasePath: String, calendarID: String) async throws {
        let store = try await makeStore(databasePath: databasePath)
        let provider = InMemoryCalendarProvider()

        let seededEvent = try CalendarEvent(
            eventIdentifier: nil,
            externalIdentifier: nil,
            calendarID: calendarID,
            title: "Imported from calendar",
            notes: "task-stable-id:task-imported-from-calendar",
            startDate: Date().addingTimeInterval(1800),
            endDate: Date().addingTimeInterval(3600),
            recurrenceRule: nil,
            isCompleted: false,
            updatedAt: Date(),
            sourceStableID: "task-imported-from-calendar"
        )
        await provider.seed(event: seededEvent)

        let engine = TwoWaySyncEngine(
            taskStore: store,
            bindingStore: store,
            checkpointStore: store,
            calendarProvider: provider
        )

        let report = try await engine.runOnce(
            configuration: SyncEngineConfiguration(
                checkpointID: "default",
                calendarID: calendarID,
                taskBatchSize: 500,
                policy: .lastWriteWins
            )
        )

        print("Sync completed")
        print("tasksPushed=\(report.tasksPushed) eventsPulled=\(report.eventsPulled) tasksImported=\(report.tasksImported)")
    }

    #if canImport(EventKit)
    private static func listCalendars() async throws {
        let store = EKEventStore()
        let granted = try await store.requestFullAccessToEvents()
        guard granted else {
            throw SyncError.unsupportedCalendarChange(reason: "Calendar permission denied")
        }

        for calendar in store.calendars(for: .event) {
            print("\(calendar.title)\t\(calendar.calendarIdentifier)")
        }
    }

    private static func syncWithEventKit(databasePath: String, calendarID: String) async throws {
        let store = try await makeStore(databasePath: databasePath)
        let provider = EventKitCalendarProvider()
        let engine = TwoWaySyncEngine(
            taskStore: store,
            bindingStore: store,
            checkpointStore: store,
            calendarProvider: provider
        )

        let report = try await engine.runOnce(
            configuration: SyncEngineConfiguration(
                checkpointID: "default",
                calendarID: calendarID,
                taskBatchSize: 500,
                policy: .lastWriteWins
            )
        )

        print("Sync completed")
        print("tasksPushed=\(report.tasksPushed) eventsPulled=\(report.eventsPulled) tasksImported=\(report.tasksImported) updatesFromCalendar=\(report.tasksUpdatedFromCalendar)")
    }
    #endif

    private static func makeStore(databasePath: String) async throws -> SQLiteStore {
        let dbURL = URL(fileURLWithPath: databasePath)
        let directory = dbURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return try SQLiteStore(databaseURL: dbURL)
    }

    private static func value(for flag: String, in args: [String]) -> String? {
        guard let index = args.firstIndex(of: flag), args.indices.contains(index + 1) else {
            return nil
        }
        return args[index + 1]
    }

    private static func printUsage() {
        print("""
        notes-cli commands:
          seed --db <path>                      Seed sample tasks
          sync-memory --db <path> --calendar <id>
          list-calendars                        Print EventKit calendar IDs
          sync-eventkit --db <path> --calendar <id>
        """)
    }
}
