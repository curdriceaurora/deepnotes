# Contributing to NotesEngine

Thank you for your interest in contributing! This document outlines the process and expectations for contributing to NotesEngine.

## Getting Started

### Prerequisites

- macOS 13+
- Swift 6.2
- Xcode 16+

### Setup

```bash
# Clone the repository
git clone https://github.com/curdriceaurora/deepnotes.git
cd deepnotes

# Build the project
swift build

# Run all tests
swift test

# Run specific test target
swift test NotesUITests

# Run coverage gates
./Scripts/run-coverage-gates.sh

# Run performance gates
./Scripts/run-perf-gates.sh

# Install pre-commit hooks (one-time per clone)
./Scripts/install-git-hooks.sh
```

## Code Standards

### Style & Quality

The project uses **SwiftLint**, **SwiftFormat**, and **Periphery** for code quality:

```bash
# Run all lint checks
./Scripts/run-lint.sh

# Apply code formatting
./Scripts/run-format.sh

# Check formatting without applying
swiftformat Sources/ Tests/ --lint --config .swiftformat
```

**Key standards:**
- **Indentation**: 4 spaces (configured in `.swiftlint.yml`)
- **Line length**: 140 warning / 160 error (SwiftFormat wraps at 160; prefer ≤140 for new code)
- **Cyclomatic complexity**: 15 warning / 25 error
- **Access control**: Explicit `public`, `internal`, `private` declarations
- **Imports**: Alphabetically sorted (test imports at bottom)
- **Dead code**: Identified by Periphery, removed or suppressed with `// periphery:ignore`

See [Docs/LINTING.md](Docs/LINTING.md) for comprehensive linting guide.

### Code Organization

```
Sources/
├── NotesDomain/       # Pure models, protocols, errors
├── NotesStorage/      # SQLite persistence layer
├── NotesSync/         # Two-way calendar sync
├── NotesFeatures/     # Business logic & workflows
├── NotesUI/           # SwiftUI views & view model
└── NotesApp/          # App entry point & wiring

Tests/
├── NotesDomainTests/
├── NotesStorageTests/
├── NotesSyncTests/
├── NotesFeaturesTests/
└── NotesUITests/
```

**Layering rule**: Layers only depend on layers below them. Never import upward:
- ✅ NotesUI imports NotesFeatures
- ❌ NotesFeatures should NOT import NotesUI

### Naming Conventions

- **Types**: PascalCase (`Task`, `TaskStatus`, `WorkspaceService`)
- **Functions/variables**: camelCase (`listTasks`, `createNote`)
- **Constants**: camelCase or ALL_CAPS for compile-time constants
- **Enums**: Cases are lowercase (`case all`, `case today`)
- **Protocols**: Noun or adjective (`Sendable`, `TaskStore`)
- **Private helpers**: Prefix with `_` or mark `fileprivate`

### Testing

**All code changes require tests.** Write tests in the corresponding test target:

```
Sources/NotesFeatures/MyFeature.swift       →  Tests/NotesFeaturesTests/MyFeatureTests.swift
Sources/NotesUI/ViewModels/AppViewModel.swift  →  Tests/NotesUITests/AppViewModelTests.swift
```

**Test coverage minimums** (enforced by CI):
- Functional: ≥ 90%
- Integration: ≥ 99%
- Error descriptions: ≥ 99%
- UI orchestration (AppViewModel): ≥ 95%
- View layer (Views.swift): ≥ 85%

**Test naming**:
```swift
// Good: describes what, given what conditions, expect what
func testListTasksFiltersByDueDate_whenUpcomingFilter_returnsOnlyFutureTasks()

// Bad: vague
func testListTasks()
```

**Test structure**:
```swift
func testSomething() {
    // Arrange: set up test data
    let task = Task(...)

    // Act: perform the action
    let result = try await service.updateTask(task)

    // Assert: verify the result
    XCTAssertEqual(result.title, task.title)
}
```

### Documentation

**Public APIs must have doc comments:**

```swift
/// Returns a filtered and sorted list of tasks.
///
/// - Parameters:
///   - filter: The filter to apply (all, today, upcoming, overdue, completed)
///   - sortOrder: The sort order (dueDate, priority, title, creationDate)
/// - Returns: An array of tasks matching the filter and sort order
/// - Throws: `TaskError.storageFailure` if the database query fails
public func listTasks(filter: TaskListFilter, sortOrder: TaskSortOrder) async throws -> [Task]
```

**Comment guidelines:**
- Start with a one-line summary
- Add parameters, return value, and throws sections for public methods
- Include examples for complex logic
- Explain the "why", not just the "what"

### Performance

- Use `async/await` for I/O-bound operations (database, network)
- Avoid blocking main thread
- Profile with `os_signpost` and Instruments before optimizing
- See [Docs/PERFORMANCE.md](Docs/PERFORMANCE.md) for profiling guidance

## Making Changes

### Branching

Create feature branches from `main`:

```bash
git checkout -b feature/brief-description
# or
git checkout -b fix/issue-number
```

**Branch naming**:
- `feature/xyz` for new features
- `fix/xyz` for bug fixes
- `docs/xyz` for documentation
- `refactor/xyz` for refactoring

### Commit Messages

Write clear, descriptive commit messages:

```
feat: add task sort options (due date, priority, title, creation date)

- Add TaskSortOrder enum with 4 cases
- Implement sortComparator logic in WorkspaceService
- Update AppViewModel to persist selected sort order
- Add 12 new tests covering all sort cases and filters

Fixes #42
```

**Format**:
- **Type**: `feat`, `fix`, `docs`, `test`, `refactor`, `perf`, `ci`
- **Scope**: Optional area (e.g., `feat(sync):`, `fix(storage):`)
- **Subject**: Imperative, lowercase, no period
- **Body**: Explain *why*, not *what* (the diff shows what)
- **Footer**: Reference issues (`Fixes #123`, `Closes #456`)

### Pull Requests

1. **Before pushing:**
   ```bash
   swift test                      # Run tests
   ./Scripts/run-coverage-gates.sh # Check coverage
   swiftlint lint --fix            # Fix style issues
   ```

2. **Create the PR** with a clear description:
   ```
   ## Summary
   Adds task sorting feature allowing users to sort tasks by due date, priority, title, or creation date.

   ## Fixes
   Closes #42

   ## Test Plan
   - [x] Run full test suite: `swift test`
   - [x] Verify coverage gates pass: `./Scripts/run-coverage-gates.sh`
   - [x] Manual testing: Create tasks, apply filters, verify sort options work
   - [x] Test with saved preferences: Close and reopen app, verify sort order persists
   ```

3. **CI checks** (automated, all must pass):
   - ✅ `lint`: SwiftLint style checks
   - ✅ `coverage`: Test coverage minimums
   - ✅ `performance`: Performance budgets

4. **Code review**: At least 1 approval required before merge

5. **Merge**: Use "Squash and merge" to keep history clean

## Large Changes

For features affecting multiple layers (domain → storage → service → UI):

1. **Open an issue** describing the feature and design
2. **Discuss** before writing code
3. **Break into smaller PRs** (one per layer):
   - PR 1: Add domain models + tests
   - PR 2: Add storage layer + tests
   - PR 3: Add service logic + tests
   - PR 4: Add UI + integration tests

This makes review easier and catches issues early.

## API Stability

### Deprecation Policy

When changing public APIs:

1. **Add deprecation warning**:
   ```swift
   @available(*, deprecated, renamed: "newName", message: "Use newName() instead")
   public func oldName() { }
   ```

2. **Document in CHANGELOG.md** under "Deprecated"

3. **Remove in next major version** (semantic versioning)

4. **Minimum deprecation period**: 2 releases (e.g., v1.0 → v1.1 → v2.0)

### Breaking Changes

Breaking changes only in major versions:
- ✅ Allowed in 1.0 → 2.0 (major version bump)
- ❌ NOT allowed in 1.0 → 1.1 (minor version bump)

Document all breaking changes in CHANGELOG.md.

## Versioning

This project follows **Semantic Versioning**:

- **MAJOR.MINOR.PATCH** (e.g., 1.2.3)
- **MAJOR**: Incompatible API changes
- **MINOR**: New features, backward compatible
- **PATCH**: Bug fixes

See [Package.swift](Package.swift) for current version.

## Reporting Issues

Use GitHub Issues for:
- **Bugs**: Include steps to reproduce, expected vs actual behavior
- **Features**: Describe the use case and expected behavior
- **Questions**: Use GitHub Discussions (if available)

## Performance Budgets

Changes should not increase:
- Launch-to-interactive time (budget: 900ms)
- Open-note latency (budget: 40ms)
- Search latency at 50k notes (budget: 80ms)
- Kanban render frame time (budget: 8.333ms @ 120Hz)

Measure before/after with:
```bash
./Scripts/run-perf-gates.sh
```

## Questions?

- Open an issue for bugs or feature requests
- Check [CLAUDE.md](CLAUDE.md) for project guidance
- See [Docs/Architecture.md](Docs/Architecture.md) for design overview
- Review [README.md](README.md) for quick start

## Code of Conduct

Be respectful, inclusive, and constructive in all interactions. We value diverse perspectives and welcome contributions from everyone.
