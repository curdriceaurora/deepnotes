# Testing Strategy

## Test Targets

Each test target mirrors a source layer:

| Test Target | Source Layer | Focus |
|-------------|-------------|-------|
| `NotesDomainTests` | NotesDomain | Model validation, error handling |
| `NotesStorageTests` | NotesStorage | SQLite correctness, versions, tombstones, migrations |
| `NotesSyncTests` | NotesSync | Push/import/delete round-trips, conflict resolution |
| `NotesFeaturesTests` | NotesFeatures | Workflow rules, filters, backlinks, status transitions |
| `NotesUITests` | NotesUI | ViewInspector interaction tests, structural assertions |

## Running Tests

```bash
# Full suite
swift test

# Single target
swift test NotesUITests

# Single test
swift test --filter NotesUITests.AppViewModelTests.testDeleteNote

# With clean output
swift test 2>&1 | xcbeautify
```

Test suites are parallelized where possible.

## Coverage Gates

Enforced by `./Scripts/run-coverage-gates.sh`:

| Category | Minimum |
|----------|---------|
| Functional | ≥ 90% |
| Integration | ≥ 99% |
| Error descriptions | ≥ 99% |
| UI orchestration (AppViewModel) | ≥ 95% |
| View-layer (Views.swift) | ≥ 85% |

## Test Doubles

### WorkspaceServiceSpy

Records all method calls with arguments. Returns configurable responses. Used by UI tests to verify AppViewModel behavior without storage/sync.

### MockWorkspaceService

Simpler mock that returns preset values. Used for structural view tests where call recording isn't needed.

### InMemoryCalendarProvider

In-memory CalendarProvider implementation. Supports all protocol methods. Used by sync tests.

### Test Helpers

Consolidated in `Tests/NotesUITests/TestHelpers.swift`:
- `@MainActor makeTestAppViewModel()` — factory using WorkspaceServiceSpy
- `@MainActor waitUntil()` — async polling with timeout
- `flushAsyncActions()` — drain async queue

## Validation Protocol

Before committing ANY code:

1. **Build**: `swift build` must succeed
2. **Lint**: `./Scripts/run-lint.sh` must pass (SwiftLint + SwiftFormat + Periphery)
3. **Tests**: `swift test` — all tests must pass
4. **Coverage**: `./Scripts/run-coverage-gates.sh` must pass
5. **Perf gates** (if perf-sensitive): `./Scripts/run-perf-gates.sh` must pass
6. **Diff review**: `git diff --staged` — check for incomplete refactors, debug prints, missing tests

## Code Review Protocol

Before every commit:

1. **Run `/simplify`**: Catch duplication, quality issues, efficiency problems
2. **Verify API correctness**: Check that documentation examples match actual public APIs
3. **Review diff**: Verify async/wait conditions, state mutation order, no race conditions
4. **Check duplication**: `grep -r "pattern" Sources/ Tests/` — no duplicate helpers
5. **Validate locally**: Run relevant tests, verify changes work

### Anti-patterns
- Never push code that failed `/simplify` review
- Never commit examples without verifying the actual API they reference
- Never commit wait conditions that don't test what you intend
- Never commit duplicate helpers — always consolidate
- Never push without running modified tests locally

## Multi-Step Plan Discipline

When executing a numbered plan:
1. Enumerate steps before starting
2. Complete each step fully
3. After each step, state: "✓ Step N complete. Remaining: [list]"
4. Only after ALL steps are done, report completion

### Anti-patterns
- Never say "All done" mid-plan
- Never skip validation and push untested code
- Never start fixing cosmetic feedback in a feature PR — file as separate issues
- Never include already-completed tasks in a new plan
