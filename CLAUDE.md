# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Quick Commands

### Building & Running

```bash
# Run all tests
swift test

# Run a single test target (e.g., NotesUI tests)
swift test NotesUITests

# Run a specific test (match test function name)
swift test --filter NotesUITests.AppViewModelTests.testDeleteNote

# Build app target
swift build --product notes-app

# Run app
swift run notes-app

# Run CLI
swift run notes-cli seed --db ./data/notes.sqlite

# Run performance harness (release mode)
swift build --product notes-perf-harness -c release
./.build/release/notes-perf-harness
```

### Quality Gates

```bash
# Run test coverage gates (minimum project quality bar)
./Scripts/run-coverage-gates.sh

# Run performance gates (release mode, ProMotion rendering)
./Scripts/run-perf-gates.sh
```

### Linting & Formatting

```bash
# Run all lint checks (SwiftLint + SwiftFormat + Periphery)
./Scripts/run-lint.sh

# Apply SwiftFormat to all source and test files
./Scripts/run-format.sh

# Install pre-commit hooks (one-time per clone)
./Scripts/install-git-hooks.sh

# Build with clean output
swift build 2>&1 | xcbeautify

# Test with clean output
swift test 2>&1 | xcbeautify
```

**Coverage minimums:**
- Functional: ≥ 90%
- Integration: ≥ 99%
- Error descriptions: ≥ 99%
- UI orchestration (AppViewModel): ≥ 95%
- View-layer (Views.swift): ≥ 85%

**Performance budgets (p95):**
- Launch-to-interactive: ≤ 900ms
- Open note: ≤ 40ms
- Save note edit: ≤ 30ms
- Kanban render: ≤ 8.333ms (120Hz budget)
- Kanban drag reorder: ≤ 50ms
- Create note: ≤ 30ms
- Search at 50k notes: ≤ 80ms
- Sync push (500 tasks): ≤ 200ms
- Sync pull (500 events): ≤ 200ms
- Sync round-trip (mixed ops): ≤ 300ms
- Sync conflict resolution: ≤ 250ms

## Architecture Overview

This is a **local-first, multi-feature notes app** with a clean layered architecture:

### Target Dependencies (layered)
```
NotesDomain (models & protocols)
    ↓
NotesStorage (SQLite persistence)
    ↓
NotesSync (two-way calendar sync)
    ↓
NotesFeatures (business workflows)
    ↓
NotesUI (SwiftUI screens)
    ↓
NotesApp (entry point & wiring)
```

### Core Concepts

1. **NotesDomain**: Pure models and protocols
   - `Note`, `Task`, `Subtask`, `CalendarBinding`, `SyncCheckpoint`, `NoteTemplate`
   - Protocols: `NoteStore`, `TaskStore`, `CalendarProvider`
   - Errors: typed enums (`NoteError`, `TaskError`, etc.)

2. **NotesStorage**: SQLite actor managing persistence
   - WAL mode for responsiveness
   - Monotonic version cursors (`task_version`, `note_version`) for incremental sync
   - Tombstone records (`deleted_at` field) for reliable deletes
   - Migration bootstrap on first run

3. **NotesSync**: Two-way sync with calendar providers
   - `TwoWaySyncEngine` orchestrates pull → push → resolve conflicts → persist
   - `EventKitCalendarProvider` (live), `InMemoryCalendarProvider` (tests)
   - Conflict policies: `lastWriteWins`, `taskPriority`, `calendarPriority`
   - Deterministic resolution with timestamp normalization

4. **NotesFeatures**: Business logic layer
   - `WorkspaceService`: main orchestrator for note/task workflows
   - `WikiLinkParser`: `[[wikilink]]` extraction and validation
   - Task filtering: `All`, `Today`, `Upcoming`, `Overdue`, `Completed`
   - Backlink resolution and graph edge computation
   - Search with caching (LRU, max 8 results)
   - Subtask auto-completion on parent status change

5. **NotesUI**: SwiftUI components and app state
   - `AppViewModel`: single orchestration point (note/task selection, filters, sync status)
   - Screens: `NotesEditorView`, `TasksListView`, `KanbanBoardView`, `SyncDashboardView`, `GraphView`
   - Uses `ViewInspector` for UI testing
   - Theme: `Theme.swift` with priority colors, date styles, markdown formatting

6. **NotesApp**: App target with live wiring
   - Instantiates `SQLiteStore`, `EventKitCalendarProvider`, `WorkspaceService`
   - Tab-based navigation: Notes, Tasks, Kanban, Calendar Sync, Graph

### Key Design Patterns

**Stable IDs for sync**: Tasks use immutable `stableID` so edits/renames don't create duplicate calendar events.

**Tombstones for deletes**: Records are soft-deleted (store `deletedAt` timestamp). Hard deletes never happen. This prevents ghost re-creation if sync is delayed.

**Monotonic versioning**: Tables track `version` and `updated_at` per record. Sync uses cursors to query only changed records since last pull.

**Service spies for testing**: Test targets define `WorkspaceServiceSpy` and `MockWorkspaceService` that conform to protocols. Allows testing UI layers in isolation.

**Lazy loading & pagination**: Note bodies lazy-load; search results paginate in chunks of 50 (cursor-based, not offset-based).

**In-memory indexes**: `LinkIndex` precomputes title→ID mappings and note→links edges for fast backlink/graph queries. Invalidated on mutations.

## Test Strategy

Each test target mirrors a source layer:

- **NotesStorageTests**: SQLite table correctness, version/tombstone semantics, migration
- **NotesSyncTests**: Push/import/delete round-trip behavior, conflict resolution
- **NotesDomainTests**: Model validation, error handling
- **NotesFeaturesTests**: Workflow rules (filters, backlinks, status transitions)
- **NotesUITests**: ViewInspector-based interaction tests (tap, select, move) and structural assertions

Test suites are parallelized where possible. Use `swift test --filter <test-name>` to run single tests during development.

## Important Patterns

### SQLite Actor
- `NotesStorage.SQLiteStore` is an actor; always `await` calls
- WAL mode enabled for concurrent reads during writes
- Migrations run on first `.initialize()` call

### Async/Await
- Storage queries are async (actor)
- Sync pulls and pushes are async
- UI uses `@MainActor` for view state mutations
- Tests use `XCTestExpectation` or Swift's native async/await test support

### Error Handling
- Typed errors per module (e.g., `NoteError.notFound`, `TaskError.invalidPriority`)
- Sync failures include detailed diagnostics (operation, IDs, provider error, timestamp)
- UI shows errors via `SyncDiagnosticsView`

### Markdown & Links
- Notes support `[[wikilink]]` syntax (case-insensitive, space-tolerant)
- Backlinks auto-populate in sidebar; updating a wikilink updates all backlinks
- Unlinked mentions detect plain-text note titles and offer linking
- Graph view visualizes all edges (directed, force-directed layout)

### Performance Profiling
- Launch profiling: `os_signpost` markers with `Xcode Instruments` integration
- Perf harness: loads 50k+ seeds and measures latencies
- Cursor-based pagination avoids offset scanning on large lists
- Search results cached (LRU, invalidated on mutations)

## Code Organization

**Key files to understand first:**
- `Sources/NotesDomain/Models.swift` — all entity types and protocols
- `Sources/NotesFeatures/WorkspaceService.swift` — orchestrator interface
- `Sources/NotesUI/AppViewModel.swift` — UI state and interactions
- `Sources/NotesUI/Views.swift` — SwiftUI components (editor, tasks, kanban, etc.)
- `Scripts/run-coverage-gates.sh` — test gate thresholds

**Typical task workflow:**
1. Add model to `NotesDomain/Models.swift` if needed
2. Update `NotesStorage/SQLiteStore.swift` table schema + CRUD
3. Update `NotesFeatures/WorkspaceService.swift` protocol/implementation if new workflow
4. Add UI in `NotesUI/Views.swift` and bind to `AppViewModel`
5. Add tests to corresponding test target
6. Verify gates: `./Scripts/run-coverage-gates.sh && ./Scripts/run-perf-gates.sh`

## Concurrency Model

The project uses **Swift 6 language mode** (`swift-tools-version: 6.0`), which enables strict concurrency checking by default — no explicit flags needed. Key patterns:

- **Domain models**: All structs with value semantics (automatically `Sendable`)
- **Storage**: `SQLiteStore` is an `actor` — all access is isolated
- **Sync**: `TwoWaySyncEngine` is a `Sendable` final class with immutable properties
- **UI**: All views and `AppViewModel` are `@MainActor`-isolated
- **Protocols**: `NoteStore`, `CalendarProvider`, etc. require `Sendable` conformance

See `Docs/CONCURRENCY_ARCHITECTURE.md` for the full architecture and compliance details.

## Configuration

- **Swift**: 6.2 (see `Package.swift`)
- **Platforms**: macOS 26.0, iOS 26.0
- **Main dependencies**: `swift-markdown` (parsing), `ViewInspector` (UI testing)
- **Test framework**: XCTest (native Swift testing)

## Release & CI

- PR/push triggers `.github/workflows/coverage-gates.yml`
- Coverage gates block merge (enforce minimums)
- Performance gates run in release mode on every push
- Baseline perf values: `Docs/perf-baseline.env`
- Release runbook: `Docs/ReleaseRunbook.md`
- Smoke checklist: `Docs/SmokeChecklist.md`

## Mandatory Validation Protocol

Before declaring ANY step complete or committing ANY code, follow this checklist:

1. **Build check**: Verify the project builds without errors
   - Swift: `swift build` should succeed

2. **Lint check**: Run all static analysis tools
   - `./Scripts/run-lint.sh` must pass (SwiftLint + SwiftFormat + Periphery)

3. **Test suite**: Run the full test suite — all tests must pass
   - `swift test` (full suite)
   - `swift test <target>` (specific target during development)

4. **Coverage gates**: Verify minimum coverage thresholds are met
   - `./Scripts/run-coverage-gates.sh` must pass

5. **Performance gates**: Check performance budgets (if making performance-sensitive changes)
   - `./Scripts/run-perf-gates.sh` must pass

6. **Diff review**: Read your own `git diff --staged` before committing and check for:
   - Incomplete refactors or half-finished code
   - Removed code that shouldn't be removed
   - Hardcoded paths or debug prints
   - Missing test coverage for new logic
   - Code organization and readability

7. **Commit**: Only after steps 1-6 pass, commit with clear conventional commit format

### Anti-patterns to avoid:
- NEVER say "All done" or summarize completion mid-plan. Complete ALL steps first.
- NEVER skip the validation protocol and push untested code.
- NEVER start fixing stylistic or cosmetic feedback in a feature PR — file them as separate issues.
- NEVER include already-completed tasks in a new plan.
- If given a multi-step plan with N steps, complete and confirm ALL N steps before reporting completion.

### Multi-step plan discipline:
When given a numbered plan, you must:
1. Enumerate the steps before starting
2. Complete each step fully
3. After each step, state: "✓ Step N complete. Remaining: [list]"
4. Only after ALL steps are done, say the plan is complete

## Mandatory Code Review Protocol

**CRITICAL: Complete BEFORE every commit. Do NOT skip.**

This prevents issues from reaching Copilot review (external iteration cost).

### Step 1: Run `/simplify` code review
When you've finished editing code:
```bash
/simplify
```
Address ALL findings:
- Code reuse violations (duplicate helpers, redundant logic)
- Quality issues (leaky abstractions, parameter sprawl, copy-paste code)
- Efficiency problems (unnecessary work, N+1 patterns, redundant checks)

**Do NOT commit until all /simplify findings are resolved.**

### Step 2: Verify API correctness (for documentation/examples)
For any changes to:
- DocC examples and API documentation
- Code comments referencing public APIs
- Test setup code showing API usage

**Verification checklist:**
- [ ] Search the actual implementation for the method/type being referenced
- [ ] Verify parameter names, types, and return values match
- [ ] Check exception types (don't confuse `TaskError` with `DomainValidationError`)
- [ ] Ensure examples use public APIs only (check `public` keyword in source)
- [ ] Run the example code mentally or compile-check if possible

### Step 3: Review your own diff for logic errors
```bash
git diff --staged
```
For changes involving async/concurrency/logic:
- [ ] Verify wait conditions actually test what you intend (not tautologies)
- [ ] Check that debounce/delay logic accounts for actual timing
- [ ] Confirm state mutations happen in the right order
- [ ] Ensure no race conditions in concurrent code
- [ ] Verify error handling paths are tested

### Step 4: Check for duplication
```bash
grep -r "function_name\|helper_pattern" Sources/ Tests/
```
- [ ] No duplicate helper implementations with slightly different logic
- [ ] No copy-pasted test setup that could be extracted
- [ ] No similar patterns in different files that should be unified

### Step 5: Validate changes
- Run relevant tests: `swift test --filter "TestName"`
- For documentation: verify DocC builds without broken links
- For async code: ensure it actually waits for the condition you're testing

**Only after ALL 5 steps pass, proceed to commit.**

### Anti-patterns to avoid:
- NEVER push code that failed `/simplify` review
- NEVER commit examples without verifying the actual API they reference
- NEVER commit wait conditions that don't actually wait for what you intend
- NEVER commit duplicate helpers (always consolidate)
- NEVER push without running the modified tests locally

## Permissions & Autonomy

**Full Autonomy Granted**: All actions required for Phase-level project delivery are pre-authorized. You have complete autonomy to:

### Bash & Swift Operations
- All bash commands within this project directory (no prompting required)
- Building, testing, and running code
- File operations (read, write, delete)
- Git operations (commit, push, branch management, branch creation)
- Script execution (coverage gates, perf gates, linting)
- Any other shell operations within `/Users/rahul/Projects/notes-placeholder`
- Swift compiler invocations and package operations
- Temporary scripting in `/tmp/` for code analysis, transformation, or automation (no prompting required)

### Code Changes
- Modify any source files to fix concurrency issues, update architecture, or implement features
- Add new files, delete unused files, refactor existing code
- Update configuration files (Package.swift, .swiftlint.yml, etc.)
- Modify test files, add new test cases
- Update documentation and CLAUDE.md itself

### Git & CI Workflow
- Create feature branches
- Commit changes with conventional commit messages
- Push to feature branches
- Create pull requests
- Merge pull requests (using squash merge when appropriate)
- Delete branches after merge
- Update delivery checklists and tracking documents

### Code Review & Quality Gates
- Run `/simplify` code review and address all findings
- Run coverage and performance gates
- Make corrections based on review feedback
- Commit and push fixes without additional prompting

### GitHub API-Based PR Review Workflow

For ALL PR reviews, use GitHub API directly instead of relying on `gh pr view` summaries:

**Steps:**
1. **Fetch ALL review comments via GitHub API**:
   ```bash
   gh api repos/OWNER/REPO/pulls/PR_NUM/reviews/REVIEW_ID/comments | jq '.[] | {line, path, body}'
   ```

2. **Address each comment individually** with a corresponding reply:
   ```bash
   gh api repos/OWNER/REPO/pulls/PR_NUM/comments/COMMENT_ID/replies -X POST -f "body=..."
   ```

3. **Resolve threads via GraphQL** (replies alone do NOT resolve threads):
   ```bash
   # Get unresolved thread IDs
   gh api graphql -f query='{
     repository(owner: "OWNER", name: "REPO") {
       pullRequest(number: PR_NUM) {
         reviewThreads(first: 50) {
           nodes { id isResolved comments(first: 1) { nodes { body } } }
         }
       }
     }
   }' --jq '.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved == false) | .id'

   # Resolve each thread
   gh api graphql -f query='mutation {
     resolveReviewThread(input: {threadId: "THREAD_ID"}) {
       thread { isResolved }
     }
   }'
   ```

4. **Track resolution**: Make code fix → Reply to comment → Resolve thread → Push

**Why**: Prevents skipped comments, ensures comprehensive feedback addressed, creates audit trail. Thread resolution is required — GitHub does not auto-resolve threads from replies.

**This autonomy applies to all Phase-level delivery work. For work outside the current phase, defer to user instructions.**

## API Stability & Deprecation

### Public API Changes

All public APIs must maintain backward compatibility within a major version. Never remove or significantly change public APIs without a deprecation period.

**Deprecation process:**

1. Mark the old API as deprecated:
   ```swift
   @available(*, deprecated, renamed: "newName", message: "Use newName() instead")
   public func oldName() { }
   ```

2. Document in `CHANGELOG.md` under "Deprecated" section

3. Minimum deprecation period: **2 releases** (e.g., v1.0 → v1.1 → v2.0)

4. Remove in next major version only

**Breaking changes** (API removals, signature changes) are only allowed in major version bumps. Document all breaking changes in CHANGELOG.md.

### Semantic Versioning

This project follows SemVer:
- **MAJOR.MINOR.PATCH** (e.g., v1.2.3)
- **MAJOR**: Breaking API changes only
- **MINOR**: New features (backward compatible)
- **PATCH**: Bug fixes

See `Package.swift` for current version.

## Known Limitations

1. Calendar recurrence exception editing not fully hardened
2. EventKit identifiers can drift; bindings store both `eventIdentifier` and `externalIdentifier`
3. iOS TestFlight/App Store distribution requires native Xcode app hosts (shared modules ready)
