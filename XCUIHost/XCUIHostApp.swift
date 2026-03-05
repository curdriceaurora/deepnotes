import NotesFeatures
import NotesStorage
import NotesSync
import NotesUI
import SwiftUI

@main
struct XCUIHostApp: App {
    @State private var viewModel: AppViewModel

    init() {
        let isUITesting = CommandLine.arguments.contains("--ui-testing")
        let databaseURL = isUITesting ? Self.uiTestingDatabaseURL() : Self.defaultDatabaseURL()

        do {
            try FileManager.default.createDirectory(
                at: databaseURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let store = try SQLiteStore(databaseURL: databaseURL)
            let service = WorkspaceService(store: store)

            let providerFactory: CalendarProviderFactory
            if isUITesting {
                let localProvider = InMemoryCalendarProvider()
                providerFactory = { localProvider }
            } else {
                #if canImport(EventKit)
                    let liveProvider = EventKitCalendarProvider()
                    providerFactory = { liveProvider }
                #else
                    let localProvider = InMemoryCalendarProvider()
                    providerFactory = { localProvider }
                #endif
            }

            _viewModel = State(initialValue: AppViewModel(
                service: service,
                calendarProviderFactory: providerFactory,
                syncCalendarID: ""
            ))
        } catch {
            fatalError("XCUIHost failed to init: \(error.localizedDescription)")
        }
    }

    var body: some Scene {
        WindowGroup("Deep Notes") {
            NotesRootView(viewModel: viewModel)
        }
        .defaultSize(width: 1260, height: 860)
    }

    private static func uiTestingDatabaseURL() -> URL {
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let dbURL = tmpDir
            .appendingPathComponent("NotesEngine-UITest", isDirectory: true)
            .appendingPathComponent("notes.sqlite", isDirectory: false)
        try? FileManager.default.removeItem(at: dbURL.deletingLastPathComponent())
        return dbURL
    }

    private static func defaultDatabaseURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return appSupport
            .appendingPathComponent("NotesEngine", isDirectory: true)
            .appendingPathComponent("notes.sqlite", isDirectory: false)
    }
}
