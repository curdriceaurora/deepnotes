// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NotesEngine",
    defaultLocalization: "en",
    platforms: [
        .macOS("26.0"),
        .iOS("26.0")
    ],
    products: [
        .library(name: "NotesDomain", targets: ["NotesDomain"]),
        .library(name: "NotesStorage", targets: ["NotesStorage"]),
        .library(name: "NotesSync", targets: ["NotesSync"]),
        .library(name: "NotesFeatures", targets: ["NotesFeatures"]),
        .library(name: "NotesUI", targets: ["NotesUI"]),
        .executable(name: "Deep Notes", targets: ["NotesApp"]),
        .executable(name: "notes-cli", targets: ["NotesCLI"]),
        .executable(name: "notes-perf-harness", targets: ["NotesPerfHarness"])
    ],
    dependencies: [
        .package(url: "https://github.com/nalexn/ViewInspector.git", exact: "0.10.0"),
        .package(url: "https://github.com/apple/swift-markdown.git", from: "0.5.0")
    ],
    targets: [
        .target(
            name: "NotesDomain",
            swiftSettings: [.unsafeFlags(["-strict-concurrency=complete"])]
        ),
        .target(
            name: "NotesStorage",
            dependencies: ["NotesDomain"],
            swiftSettings: [.unsafeFlags(["-strict-concurrency=complete"])]
        ),
        .target(
            name: "NotesSync",
            dependencies: ["NotesDomain", "NotesStorage"],
            swiftSettings: [.unsafeFlags(["-strict-concurrency=complete"])]
        ),
        .target(
            name: "NotesFeatures",
            dependencies: ["NotesDomain", "NotesStorage", "NotesSync"],
            swiftSettings: [.unsafeFlags(["-strict-concurrency=complete"])]
        ),
        .target(
            name: "NotesUI",
            dependencies: ["NotesDomain", "NotesFeatures", .product(name: "Markdown", package: "swift-markdown")],
            swiftSettings: [.unsafeFlags(["-strict-concurrency=complete"])]
        ),
        .executableTarget(
            name: "NotesApp",
            dependencies: ["NotesUI", "NotesFeatures", "NotesDomain", "NotesStorage", "NotesSync"],
            swiftSettings: [.unsafeFlags(["-strict-concurrency=complete"])]
        ),
        .executableTarget(
            name: "NotesCLI",
            dependencies: ["NotesSync", "NotesStorage", "NotesDomain"],
            swiftSettings: [.unsafeFlags(["-strict-concurrency=complete"])]
        ),
        .executableTarget(
            name: "NotesPerfHarness",
            dependencies: ["NotesFeatures", "NotesStorage", "NotesDomain", "NotesUI", "NotesSync"],
            path: "Sources/NotesPerfHarness",
            swiftSettings: [.unsafeFlags(["-strict-concurrency=complete"])]
        ),
        .testTarget(
            name: "NotesStorageTests",
            dependencies: ["NotesStorage", "NotesDomain"],
            swiftSettings: [.unsafeFlags(["-strict-concurrency=complete"])]
        ),
        .testTarget(
            name: "NotesSyncTests",
            dependencies: ["NotesSync", "NotesStorage", "NotesDomain"],
            swiftSettings: [.unsafeFlags(["-strict-concurrency=complete"])]
        ),
        .testTarget(
            name: "NotesDomainTests",
            dependencies: ["NotesDomain"],
            swiftSettings: [.unsafeFlags(["-strict-concurrency=complete"])]
        ),
        .testTarget(
            name: "NotesFeaturesTests",
            dependencies: ["NotesFeatures", "NotesStorage", "NotesDomain", "NotesSync"],
            swiftSettings: [.unsafeFlags(["-strict-concurrency=complete"])]
        ),
        .testTarget(
            name: "NotesUITests",
            dependencies: ["NotesUI", "NotesFeatures", "NotesDomain", .product(name: "ViewInspector", package: "ViewInspector")],
            swiftSettings: [.unsafeFlags(["-strict-concurrency=complete"])]
        )
    ]
)
