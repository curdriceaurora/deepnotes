## Summary

<!-- Brief description of what this PR does and why -->


## Related Issues

<!-- Link to issues this PR fixes or relates to -->
Closes #___
Fixes #___
Related to #___

## Changes

<!-- Describe the changes in this PR -->
-
-
-

## Test Plan

<!-- How did you verify these changes work? -->

- [ ] Unit tests added/updated
- [ ] Integration tests added/updated
- [ ] Manual testing completed
- [ ] All tests passing: `swift test`
- [ ] Coverage gates passing: `./Scripts/run-coverage-gates.sh`
- [ ] Performance gates passing: `./Scripts/run-perf-gates.sh`
- [ ] SwiftLint checks passing: `swiftlint lint`

### Specific Testing

<!-- Document any special testing steps needed -->

## Checklist

- [ ] Code follows style guidelines (SwiftLint passes)
- [ ] Changes are documented (public APIs have doc comments)
- [ ] No breaking changes to public APIs
- [ ] Related test targets have corresponding tests
- [ ] Commit message is clear and follows conventions
- [ ] CHANGELOG.md updated (if user-facing change)
- [ ] Performance impact considered and acceptable
- [ ] Accessibility considered (if UI changes)

## Performance Impact

<!-- Document any performance changes -->

Expected impact: None / Slight improvement / Trade-off

Measured:
- Launch-to-interactive: ___ms (budget: 900ms)
- Search at 50k notes: ___ms (budget: 80ms)
- Kanban render: ___ms (budget: 8.333ms)

## Breaking Changes

<!-- List any breaking API changes -->

None / See "API Changes" section below

### API Changes

**Deprecated:**
- `oldAPI()` → Use `newAPI()` instead (will be removed in v2.0)

**Removed:**
- `removedAPI()` (deprecated in v1.1)

## Screenshots (if applicable)

<!-- Add screenshots or GIFs for UI changes -->

---

🤖 Generated with [Claude Code](https://claude.com/claude-code)
