// swift-tools-version: 6.0
import PackageDescription

// Swift 6 language mode enables strict concurrency by default — no additional flags needed
let strictConcurrencySettings: [SwiftSetting] = []

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
            swiftSettings: strictConcurrencySettings
        ),
        .target(
            name: "NotesStorage",
            dependencies: ["NotesDomain"],
            swiftSettings: strictConcurrencySettings
        ),
        .target(
            name: "NotesSync",
            dependencies: ["NotesDomain", "NotesStorage"],
            swiftSettings: strictConcurrencySettings
        ),
        .target(
            name: "NotesFeatures",
            dependencies: ["NotesDomain", "NotesStorage", "NotesSync"],
            swiftSettings: strictConcurrencySettings
        ),
        .target(
            name: "NotesUI",
            dependencies: ["NotesDomain", "NotesFeatures", .product(name: "Markdown", package: "swift-markdown")],
            swiftSettings: strictConcurrencySettings
        ),
        .executableTarget(
            name: "NotesApp",
            dependencies: ["NotesUI", "NotesFeatures", "NotesDomain", "NotesStorage", "NotesSync"],
            swiftSettings: strictConcurrencySettings
        ),
        .executableTarget(
            name: "NotesCLI",
            dependencies: ["NotesSync", "NotesStorage", "NotesDomain"],
            swiftSettings: strictConcurrencySettings
        ),
        .executableTarget(
            name: "NotesPerfHarness",
            dependencies: ["NotesFeatures", "NotesStorage", "NotesDomain", "NotesUI", "NotesSync"],
            path: "Sources/NotesPerfHarness",
            swiftSettings: strictConcurrencySettings
        ),
        .testTarget(
            name: "NotesStorageTests",
            dependencies: ["NotesStorage", "NotesDomain"],
            swiftSettings: strictConcurrencySettings
        ),
        .testTarget(
            name: "NotesSyncTests",
            dependencies: ["NotesSync", "NotesStorage", "NotesDomain"],
            swiftSettings: strictConcurrencySettings
        ),
        .testTarget(
            name: "NotesDomainTests",
            dependencies: ["NotesDomain"],
            swiftSettings: strictConcurrencySettings
        ),
        .testTarget(
            name: "NotesFeaturesTests",
            dependencies: ["NotesFeatures", "NotesStorage", "NotesDomain", "NotesSync"],
            swiftSettings: strictConcurrencySettings
        ),
        .testTarget(
            name: "NotesUITests",
            dependencies: ["NotesUI", "NotesFeatures", "NotesDomain", .product(name: "ViewInspector", package: "ViewInspector")],
            swiftSettings: strictConcurrencySettings
        )
    ]
)
