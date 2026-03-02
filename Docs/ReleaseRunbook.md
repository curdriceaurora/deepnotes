# Release Runbook

Last updated: 2026-03-02

This runbook covers the end-to-end steps to cut a release candidate, ship it, and roll back if something goes wrong. Work through sections top to bottom. Every step that can fail has a matching rollback action.

---

## Prerequisites

- Xcode installed and the active scheme builds cleanly (`BuildProject` or `swift build`).
- All tests pass locally: `swift test`.
- `Scripts/run-coverage-gates.sh` passes (coverage thresholds met).
- `Scripts/run-perf-gates.sh` passes (migration p95 ≤ 3 000 ms, search p95 within budget).
- `SmokeChecklist.md` signed off for the target platform(s).
- You are on the `main` branch with a clean working tree.

---

## 1. Pre-release verification

### 1.1 Run the full test suite

```
swift test --parallel
```

**Pass criteria:** zero failures, zero unexpected skips.

**If tests fail:** do not proceed. Fix failures on a branch, get review, merge to `main`, then restart from §1.

### 1.2 Run quality gates

```
bash Scripts/run-coverage-gates.sh
bash Scripts/run-perf-gates.sh
```

**If a gate fails:**
- Coverage below threshold → add tests for uncovered paths, re-run.
- Migration perf over budget → profile `SQLiteStore` init on the slowest fixture, optimize, re-run.

### 1.3 Execute the smoke checklist

Open `Docs/SmokeChecklist.md`. Run every item on both macOS and iOS. Record build number, OS version, and tester initials in the sign-off table.

**Blocked items:**
- Any `[FAIL]` → file a bug, fix it, cut a new build, re-run the affected section.
- `[SKIP]` is only allowed where the checklist explicitly permits it.

---

## 2. Build and tag

### 2.1 Confirm the build number

The build number is set in the app host target. Increment it from the previous release. Do not reuse build numbers — TestFlight and the App Store reject duplicate build numbers for the same version string.

### 2.2 Archive the build (Xcode app host)

In Xcode: **Product → Archive**. Validate the archive before uploading.

> Note: the Swift Package itself does not produce an app archive. Archiving requires the native Xcode app host that wraps `NotesApp`. See Architecture §Known limitations.

### 2.3 Create the git tag

```
git tag -a v<VERSION>-b<BUILD> -m "Release v<VERSION> build <BUILD>"
git push origin v<VERSION>-b<BUILD>
```

**Rollback:** if you need to retract the tag before any public release:

```
git tag -d v<VERSION>-b<BUILD>
git push origin --delete v<VERSION>-b<BUILD>
```

---

## 3. Distribution

### 3.1 TestFlight (internal / external)

Upload the archive from Xcode Organizer or via `xcrun altool` / `xcrun notarytool`. Wait for Apple's automated review to clear.

**If Apple rejects the build:**
- Read the rejection reason in App Store Connect.
- Fix the issue on a branch, bump the build number, re-archive, re-submit. Do not delete the rejected build from App Store Connect — keep it for audit.

### 3.2 Production release (App Store)

Promote the approved TestFlight build to production in App Store Connect. Set the release date or release manually.

---

## 4. Post-release verification

After the build is live, perform a final sanity pass:

- [ ] Install the production build on a clean device / simulator.
- [ ] Run §1 (App Launch), §2 (Notes Create/Edit), §9 (Task Status), §11 (Kanban columns) from `SmokeChecklist.md` against the production binary.
- [ ] Confirm no crash reports in Xcode Organizer or your crash analytics within the first hour.
- [ ] Confirm sync runs cleanly with a real calendar ID (§15 of the smoke checklist).

---

## 5. Rollback plan

Use the rollback path appropriate for how far the release has progressed.

### 5.1 Rollback before App Store submission (archive stage)

Nothing is public. Simply do not submit. Fix the issue, increment the build number, and re-archive.

### 5.2 Rollback after TestFlight but before App Store promotion

Remove the build from external TestFlight groups in App Store Connect. Internal testers can still access it; remove their access too if the issue is severe. Do not promote the build to production.

### 5.3 Rollback after App Store release — phased rollout

If you used phased rollout, pause it immediately in App Store Connect (**Pause Phased Release**). This stops further distribution while you investigate.

### 5.4 Rollback after full App Store release

Apple does not allow pulling an app version from users who already installed it. The rollback options are:

1. **Expedited review for a fix release** — submit a patch build and request expedited review. Keep the fix targeted; do not bundle unrelated changes.
2. **Remove the app from sale temporarily** — in App Store Connect, set availability to "Remove from Sale". Existing installs continue to work; new downloads are blocked. Re-enable once the fix is live.

### 5.5 Database schema rollback

The SQLite migration path is **forward-only**. There is no automated downgrade. If a migration introduces a bug:

1. The patch release must include a new migration step that corrects the schema (e.g., drops a bad column, re-creates an index, back-fills a default).
2. The patch migration must be idempotent — safe to run on databases that were never on the bad schema.
3. Test the patch migration using `SQLiteMigrationTests` before shipping.

**Never modify an existing migration step** that has already shipped. Always add a new step.

### 5.6 Sync checkpoint rollback

If a bug corrupts `sync_checkpoints` (e.g., a wrong cursor value causes a full re-import loop):

1. The user can reset their sync state by clearing the checkpoint row via a future "Reset Sync" UI action (not yet implemented).
2. As a manual workaround: export diagnostics via `exportSyncDiagnosticsButton`, examine the checkpoint values, and guide the user to reinstall (which clears the local database).

---

## 6. Incident response checklist

If a critical bug is reported in production:

- [ ] Determine scope: crash vs. data loss vs. sync corruption vs. cosmetic.
- [ ] Reproduce on a local build using the steps from the bug report.
- [ ] If data loss or sync corruption: pause phased rollout or remove from sale (§5.3 / §5.4).
- [ ] File a bug with: steps to reproduce, affected build, affected OS versions, crash log or diagnostics export.
- [ ] Fix on a branch, land via PR with test coverage for the regression.
- [ ] Cut a patch release following this runbook from §1.
- [ ] Notify affected TestFlight testers if the bug was present in a beta.

---

## Appendix: Key file locations

| Artifact | Path |
|----------|------|
| Smoke checklist | `Docs/SmokeChecklist.md` |
| Delivery checklist | `Docs/DeliveryChecklist.md` |
| Coverage gate script | `Scripts/run-coverage-gates.sh` |
| Perf gate script | `Scripts/run-perf-gates.sh` |
| Perf baseline | `Docs/perf-baseline.env` |
| Migration tests | `Tests/NotesStorageTests/SQLiteMigrationTests.swift` |
| Crash recovery tests | `Tests/NotesStorageTests/SQLiteCrashRecoveryTests.swift` |
| Smoke tests (automated) | `Tests/NotesUITests/NotesSmokeTests.swift` |
