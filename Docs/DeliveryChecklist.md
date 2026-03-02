# Delivery Checklist

Last updated: 2026-03-02

## Decision: migration stress tests now?

Short answer: not full stress testing yet, but do set up the migration test harness now.

Why:
- The project is still early, so there are no multiple historical schemas to replay yet.
- Waiting too long makes migration coverage expensive once several schema versions exist.
- A lightweight harness now prevents future blind spots with minimal effort.

Minimum now:
- [x] Add migration test harness with fixture loading and version assertions.
- [x] Add `fresh install` migration test (empty DB bootstrap).
- [x] Add `idempotent reopen` migration test (open same DB twice, no schema drift).

Required before first public beta / external users:
- [ ] Add replay tests from every released schema version to latest.
- [ ] Add large-data migration perf test with rollback/recovery checks.

## Project Next Steps

### 1. CI quality gates (enforcement)
- [x] Workflow exists for coverage gates on PR/push.
- [x] Add explicit `swift test` step in CI so failures are independently surfaced.
- [ ] Add branch protection requiring coverage workflow pass before merge.
- [x] Add CI artifact upload for coverage reports.

Acceptance criteria:
- Every PR to `main` is blocked until tests and coverage gates pass.

### 2. Production sync hardening
- [x] Implement deterministic conflict policy: last-write-wins + source tie-break + normalized timestamps.
- [x] Add sync diagnostics model (operation, task/event IDs, provider error, timestamp).
- [x] Add Sync Diagnostics UI + export action.
- [x] Add retry/backoff policy tests for transient EventKit failures.

Acceptance criteria:
- Same input history always resolves to same persisted state.
- Failed syncs are explainable from diagnostics without reproducing.

### 3. Kanban completion (ordering)
- [x] Add persistent in-column ordering key for tasks.
- [x] Implement drag reorder inside each status column.
- [x] Preserve ordering through app relaunch and sync cycles.
- [ ] Add UI tests for reorder in same column and cross-column move + position.

Acceptance criteria:
- Reordered cards remain stable after restart and after sync.

### 4. Search quality and scale
- [x] Add phrase search support.
- [x] Add prefix search support.
- [x] Add result snippets with match highlighting.
- [x] Add paginated search API (offset/cursor + limit).
- [x] Add perf tests at 50k+ notes with latency budget assertions.

Acceptance criteria:
- Typical query returns within defined latency budget on target hardware.

### 5. Calendar recurrence UX
- [x] Expose recurrence-exception state in task/event UI.
- [x] Add edit flow choice: this occurrence vs entire series.
- [x] Add delete flow choice: this occurrence vs entire series.
- [x] Add conflict messaging for detached occurrences edited externally.

Acceptance criteria:
- Users can intentionally modify one occurrence without corrupting series rules.

### 6. Release prep
- [ ] Add schema upgrade matrix tests for all released DB versions.
- [ ] Add crash-safe recovery tests around migration and sync checkpoint writes.
- [ ] Create macOS + iOS smoke checklist for pre-release validation.
- [ ] Add release checklist runbook with rollback plan.

Acceptance criteria:
- Release candidate can be validated by checklist with reproducible pass/fail evidence.
