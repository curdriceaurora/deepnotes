import Foundation
import SwiftUI
import NotesUI
import NotesStorage
import NotesFeatures
import NotesSync

@main
struct NotesApplication: App {
    @State private var viewModel: AppViewModel

    init() {
        let databaseURL = Self.defaultDatabaseURL()

        do {
            try FileManager.default.createDirectory(
                at: databaseURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let store = try SQLiteStore(databaseURL: databaseURL)
            let service = WorkspaceService(store: store)

            #if canImport(EventKit)
            let liveProvider = EventKitCalendarProvider()
            let providerFactory: CalendarProviderFactory = { liveProvider }
            #else
            let localProvider = InMemoryCalendarProvider()
            let providerFactory: CalendarProviderFactory = { localProvider }
            #endif

            _viewModel = State(initialValue: AppViewModel(
                service: service,
                calendarProviderFactory: providerFactory,
                syncCalendarID: ""
            ))
        } catch {
            fatalError("Failed to initialize app storage at \(databaseURL.path): \(error.localizedDescription)")
        }
    }

    var body: some Scene {
        WindowGroup("Deep Notes") {
            NotesRootView(viewModel: viewModel)
        }
        .defaultSize(width: 1260, height: 860)
    }

    private static func defaultDatabaseURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return appSupport
            .appendingPathComponent("NotesEngine", isDirectory: true)
            .appendingPathComponent("notes.sqlite", isDirectory: false)
    }
}
