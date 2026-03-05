# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Local-first, multi-feature notes app with layered architecture: NotesDomain → NotesStorage → NotesSync → NotesFeatures → NotesUI → NotesApp. See `Docs/project-map.md` for full repo structure and `Docs/Architecture.md` for architectural details. Each `Sources/<Module>/CLAUDE.md` has module-specific rules.

## Development Commands

```bash
# Build & run
swift build                                    # Build all targets
swift build --product notes-app                # Build app
swift run notes-app                            # Run app
swift run notes-cli seed --db ./data/notes.sqlite  # Seed data

# Test
swift test                                     # Full suite
swift test --filter testSmoke                  # Smoke subset (~164 tests, <10s)
./Scripts/run-smoke-tests.sh                   # Smoke tests (script wrapper)
swift test NotesUITests                        # Single target
swift test --filter NotesUITests.AppViewModelTests.testDeleteNote  # Single test

# Quality gates
./Scripts/run-coverage-gates.sh                # Coverage minimums
./Scripts/run-perf-gates.sh                    # Performance budgets (release mode)

# Lint & format
./Scripts/run-lint.sh                          # SwiftLint + SwiftFormat + Periphery
./Scripts/run-format.sh                        # Apply SwiftFormat
./Scripts/install-git-hooks.sh                 # Pre-commit hooks (one-time)

# Performance harness
swift build --product notes-perf-harness -c release && ./.build/release/notes-perf-harness

# Clean output
swift build 2>&1 | xcbeautify
swift test 2>&1 | xcbeautify
```

## Quality Thresholds

**Coverage minimums** (enforced by `run-coverage-gates.sh`):
- Functional: ≥ 90% | Integration: ≥ 99% | Error descriptions: ≥ 99%
- UI orchestration (AppViewModel): ≥ 95% | View-layer (Views.swift): ≥ 85%

**Performance budgets (p95)** (enforced by `run-perf-gates.sh`):
- Launch ≤ 900ms | Open note ≤ 40ms | Save ≤ 30ms | Create ≤ 30ms
- Kanban render ≤ 8.333ms | Kanban drag ≤ 50ms | Search@50k ≤ 80ms
- Sync push ≤ 200ms | Sync pull ≤ 200ms | Sync round-trip ≤ 300ms | Sync conflict ≤ 250ms

## Validation Protocol

Before committing ANY code, complete in order:

1. **Build**: `swift build` succeeds
2. **Lint**: `./Scripts/run-lint.sh` passes
3. **Smoke tests**: `swift test --filter testSmoke` — fast subset passes (pre-commit hook runs this automatically)
4. **Tests**: `swift test` — all pass
5. **Coverage**: `./Scripts/run-coverage-gates.sh` passes
6. **Perf** (if perf-sensitive): `./Scripts/run-perf-gates.sh` passes
7. **Diff review**: `git diff --staged` — check for incomplete refactors, debug prints, missing tests
8. **Commit**: conventional commit format only after steps 1-7 pass

See `Docs/testing.md` for the full code review protocol and multi-step plan discipline.

## Engineering Rules

- **No skipping validation**: Never push untested code. Never say "done" mid-plan.
- **Multi-step plans**: Enumerate steps, complete each fully, report "✓ Step N" after each.
- **Code review before commit**: Run `/simplify`, verify API correctness in docs, review diff for logic errors, check for duplication.
- **Dependency direction**: NotesDomain → NotesStorage → NotesSync → NotesFeatures → NotesUI → NotesApp. No upward imports.
- **Concurrency**: Swift 6 strict mode. Actors for storage, `@MainActor` for UI, `Sendable` for protocols. See `Docs/CONCURRENCY_ARCHITECTURE.md`.
- **Tombstones**: Soft-delete only (`deleted_at`). No hard deletes.
- **Pagination**: Offset-based (`LIMIT ? OFFSET ?`). Cursor-based is a future enhancement.
- **API stability**: SemVer. Deprecate with `@available` for 2 releases before removal. Breaking changes only in major bumps. See `Docs/Architecture.md`.

## Permissions & Autonomy

**Full autonomy granted** for all project delivery work:
- All bash/swift commands in this directory and `/tmp/` (no prompting required)
- File operations, git operations (commit, push, branch, PR, merge)
- Script execution (coverage, perf, lint gates)
- Code modifications, test additions, documentation updates

### GitHub API PR Review Workflow
For PR reviews, use GitHub API directly (not `gh pr view` summaries):
1. Fetch ALL comments: `gh api repos/OWNER/REPO/pulls/PR/reviews/REVIEW_ID/comments`
2. Reply to each: `gh api repos/.../comments/ID/replies -X POST -f "body=..."`
3. Resolve threads via GraphQL (replies alone don't resolve)
4. Track: code fix → reply → resolve thread → push

## Configuration

- **Swift tools version**: 6.0 (see `Package.swift`) | **Platforms**: macOS 26.0, iOS 26.0
- **Dependencies**: `swift-markdown` (parsing), `ViewInspector` (UI testing)
- **CI**: `.github/workflows/coverage-gates.yml` is advisory-only (all jobs use `continue-on-error: true` — reports status but does not block merge). CI runners may lag behind the local SDK/toolchain. **Local checks are the authoritative quality gates** — always run `run-lint.sh`, `run-coverage-gates.sh`, and `run-perf-gates.sh` locally before committing.

## Documentation Index

Load detailed docs as needed:

| Topic | File |
|-------|------|
| Repo structure | `Docs/project-map.md` |
| Architecture & API stability | `Docs/Architecture.md` |
| Concurrency | `Docs/CONCURRENCY_ARCHITECTURE.md` |
| Persistence (SQLite) | `Docs/persistence.md` |
| Sync engine | `Docs/sync.md` |
| UI patterns | `Docs/ui-patterns.md` |
| Testing & review protocol | `Docs/testing.md` |
| Performance & debugging | `Docs/debugging.md` |
| Linting config | `Docs/LINTING.md` |
| Accessibility testing | `Docs/ACCESSIBILITY_TESTING.md` |
| Liquid Glass discovery | `Docs/liquid-glass-discovery.md` |
| Historical decisions | `memory/decisions.md` |
| Known pitfalls | `memory/gotchas.md` |
| Release process | `Docs/ReleaseRunbook.md` |

## Known Limitations

1. Calendar recurrence exception editing not fully hardened
2. EventKit identifiers can drift — bindings store both `eventIdentifier` and `externalIdentifier`
3. iOS TestFlight/App Store distribution requires native Xcode app hosts (shared modules ready)
