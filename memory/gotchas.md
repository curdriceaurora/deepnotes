# Gotchas & Technical Pitfalls

## ViewInspector Cannot Find Accessibility Identifiers

**Problem**: `find(viewWithAccessibilityIdentifier:)` throws "Search did not find a match" even when identifiers ARE set in Views.swift.

**Root Cause**: ViewInspector's hierarchy traversal doesn't see the same modifier chain that SwiftUI renders at runtime. Accessibility identifiers are applied as modifiers that ViewInspector can't reliably locate.

**Solution**:
- Convert identifier-validation tests to `XCTSkip()` with clear reason
- Move identifier validation to UI/XCUI tests (full app context)
- Focus unit tests on: view rendering, state management, event handling
- Keep semantic attributes (labels, hints) in Views.swift for build-time verification

**Affected tests**: 19 total across NotesAccessibilityTests (8), NotesViewsTests §20 (14), UICoverageGapTests (5).

---

## SwiftFormat Rules That Strip `await`

Two rules cause `await` stripping in autoclosure/async contexts:
1. **`redundantSelf`** — strips `await` in async closures (actor isolation)
2. **`hoistAwait`** — strips `await` inside `XCTAssertThrowsErrorAsync` autoclosure args

**Fix**: Disable both in `.swiftformat`: `--disable redundantSelf,hoistAwait`
**Always**: `swift build` after any SwiftFormat run to catch missing `await`.

---

## SwiftFormat vs SwiftLint Import Sorting Conflict

SwiftFormat's `--importgrouping testable-bottom` conflicts with SwiftLint's `sorted_imports`.
**Fix**: Remove `sorted_imports` from SwiftLint `opt_in_rules`. SwiftFormat is the authority for import ordering.

---

## SwiftLint `opening_brace` vs SwiftFormat Wrapping

When SwiftFormat wraps long declarations, it puts `{` on a new line. SwiftLint's `opening_brace` wants same-line braces.
**Fix**: Disable `opening_brace` in SwiftLint. SwiftFormat owns brace placement.

---

## Line Width: Match Error Threshold

SwiftFormat `--maxwidth` should match SwiftLint's **error** threshold (160), not warning (140). Otherwise SwiftFormat hard-wraps at 140, creating artifacts that SwiftLint then warns about.

---

## EventKit Identifier Drift

EventKit identifiers can change under certain conditions. Calendar bindings store both `eventIdentifier` and `externalIdentifier` to handle drift. Always look up bindings by `stableID` (immutable) rather than EventKit identifiers.

---

## CI PIPESTATUS Pattern

In GitHub Actions (non-pipefail shell), `cmd | xcbeautify && exit ${PIPESTATUS[0]}` does NOT work — `&&` resets PIPESTATUS. Use semicolon:
```bash
swift build 2>&1 | xcbeautify; exit ${PIPESTATUS[0]}
```

---

## Periphery Needs Build Index First

Periphery's `--index-store-path` requires a built index store. In CI, `swift build` must run BEFORE `periphery scan`.

---

## Calendar Recurrence Exception Editing

Not fully hardened. Edge cases with recurrence exceptions may produce unexpected behavior during sync.
