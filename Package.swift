// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "NotesEngine",
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
        .package(url: "https://github.com/nalexn/ViewInspector.git", from: "0.9.11"),
        .package(url: "https://github.com/apple/swift-markdown.git", from: "0.5.0")
    ],
    targets: [
        .target(name: "NotesDomain"),
        .target(name: "NotesStorage", dependencies: ["NotesDomain"]),
        .target(name: "NotesSync", dependencies: ["NotesDomain", "NotesStorage"]),
        .target(name: "NotesFeatures", dependencies: ["NotesDomain", "NotesStorage", "NotesSync"]),
        .target(name: "NotesUI", dependencies: ["NotesDomain", "NotesFeatures", .product(name: "Markdown", package: "swift-markdown")]),
        .executableTarget(name: "NotesApp", dependencies: ["NotesUI", "NotesFeatures", "NotesDomain", "NotesStorage", "NotesSync"]),
        .executableTarget(name: "NotesCLI", dependencies: ["NotesSync", "NotesStorage", "NotesDomain"]),
        .executableTarget(
            name: "NotesPerfHarness",
            dependencies: ["NotesFeatures", "NotesStorage", "NotesDomain", "NotesUI", "NotesSync"],
            path: "Sources/NotesPerfHarness"
        ),
        .testTarget(name: "NotesStorageTests", dependencies: ["NotesStorage", "NotesDomain"]),
        .testTarget(name: "NotesSyncTests", dependencies: ["NotesSync", "NotesStorage", "NotesDomain"]),
        .testTarget(name: "NotesDomainTests", dependencies: ["NotesDomain"]),
        .testTarget(name: "NotesFeaturesTests", dependencies: ["NotesFeatures", "NotesStorage", "NotesDomain", "NotesSync"]),
        .testTarget(name: "NotesUITests", dependencies: ["NotesUI", "NotesFeatures", "NotesDomain", .product(name: "ViewInspector", package: "ViewInspector")])
    ]
)
