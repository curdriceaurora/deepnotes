# Previously Fixed Bugs

## GitHub Actions Promise Handling (PR #26, 2026-03-04)

**Issue**: Copilot review automation ran successfully but never requested Copilot as reviewer.

**Root Cause**: `.catch()` pattern in `actions/github-script@v7` didn't reliably execute. The promise chain completed before the API call was fully processed.

**Fix**: Replace `.catch()` with explicit `try/catch` block. The script must fully `await` completion before the action finishes.

**Lesson**: Promise handling in GitHub Actions requires explicit async/await with try/catch, not chain-based .catch() patterns.

---

## Copilot Bot Identifier Discovery (2026-03-04)

**Problem**: `reviewers: ['copilot']` silently fails — not a valid GitHub user/bot.

**Correct identifier**: `copilot-pull-request-reviewer[bot]` (case-sensitive, includes `[bot]`).

**Discovery method**: Reverse-engineered from actual Copilot review comments on PRs. Not prominently documented in GitHub docs.

**Works with**:
- REST API `requestReviewers` endpoint
- GitHub CLI: `gh pr edit --add-reviewer copilot-pull-request-reviewer[bot]`

**Fallback**: If direct reviewer request fails, post comment mentioning `@github-copilot review`.

---

## PR Title/Description Mismatch (PR #24, 2026-03-04)

**Issue**: Created PR with title/description that didn't match actual contents. Copilot caught the discrepancy.

**Root Cause**: Skipped reviewing `git log` before creating PR.

**Fix**: Always run `git log main...HEAD` before `gh pr create` to verify all commits match the PR description.
