# Pre-Release Smoke Checklist

Last updated: 2026-03-02

Validate each item manually on both macOS and iOS before marking a build as a release candidate.
Record the build number, device/OS version, and tester initials next to each pass.

---

## How to use this checklist

- Work through sections top to bottom.
- Mark each item `[PASS]`, `[FAIL]`, or `[SKIP]` (with reason).
- A build is blocked from release if **any** item is `[FAIL]`.
- `[SKIP]` is only allowed for items explicitly not applicable to that platform (noted inline).

---

## 1. App Launch and DB Initialization

- [ ] Fresh install: app launches to Notes tab with no crash.
- [ ] Notes list is empty; Tasks tab shows empty state; Board tab shows all columns with "No cards".
- [ ] Sync tab renders the Calendar Identifier field and "Run Two-Way Sync" button.
- [ ] Relaunch (with existing data): previously created notes and tasks appear without prompt.
- [ ] No "globalErrorBanner" visible at startup.

---

## 2. Notes Tab — Create and Edit

- [ ] Tap/click the `+` button (`newNoteButton`): new note appears in the list, title field is focused.
- [ ] Enter a title; title appears immediately in the list item.
- [ ] Type multi-line body content; editor scrolls correctly.
- [ ] Tap "Save" (`saveNoteButton`): note persists through relaunch.
- [ ] Edit the same note after relaunch: title and body match what was saved.
- [ ] Attempt to create a second note with the same title: an error is shown (duplicate title is rejected).

---

## 3. Notes Tab — Markdown Toolbar

- [ ] Click "Heading" (`insertHeadingButton`) or press ⌘⇧1: `## ` is inserted at cursor.
- [ ] Click "Bullet" (`insertBulletButton`) or press ⌘⇧8: `- ` is inserted at cursor.
- [ ] Click "Checkbox" (`insertCheckboxButton`) or press ⌘⇧X: `- [ ] ` is inserted at cursor.

---

## 4. Notes Tab — Search and Snippets

- [ ] Type a word present in a note body into the search field (`noteSearchField`): list filters to matching notes.
- [ ] Matching notes show a snippet below the title; the matching word is highlighted (bold, accent color).
- [ ] Clear the search field: full notes list is restored.
- [ ] Type a word that matches no notes: list is empty; no crash.

---

## 5. Notes Tab — Quick Open

- [ ] Press ⌘O or tap the search icon (`quickOpenButton`): Quick Open sheet appears.
- [ ] Quick Open search field (`quickOpenSearchField`) is focused and accepts keyboard input.
- [ ] Type a partial title: results list updates in real time.
- [ ] Select a result (`quickOpenRow_*`): sheet dismisses and that note is selected in the editor.
- [ ] Tap "Close" (`quickOpenCloseButton`): sheet dismisses with no note change.

---

## 6. Notes Tab — Wiki Links and Backlinks

- [ ] In note A's body, type `[[`: wiki link suggestions bar (`wikiSuggestionsBar`) appears.
- [ ] Suggestions include titles of other existing notes.
- [ ] Tap a suggestion (`wikiSuggestion_*`): the link text is inserted and the suggestions bar disappears.
- [ ] Open note B (the linked note): the Backlinks section lists note A.
- [ ] Delete the wiki link text from note A and save: note B no longer shows note A in backlinks.
- [ ] Note with no incoming links shows "No backlinks yet" (`backlinksEmptyState`).

---

## 7. Notes Tab — Quick Task Creation

- [ ] Select a note, type a title in the quick task field (`` `quickTaskField` ``), tap "Add Task" (`quickTaskButton`): task appears in Tasks tab.
- [ ] Created task has the linked note's ID set (visible via Tasks tab row or Kanban card).
- [ ] Quick task field is cleared after successful creation.

---

## 8. Tasks Tab — List and Filter

- [ ] Tasks tab shows all non-deleted tasks when filter is "All".
- [ ] Filter picker (`taskFilterPicker`) segments match: All, Today, Upcoming, Overdue, Completed.
- [ ] Selecting "Completed" filter shows only tasks with `.done` status.
- [ ] "Today" filter shows only tasks with a due date today; "Upcoming" shows future-dated tasks; "Overdue" shows past-due tasks.
- [ ] Filter selection persists within the session (no reset on tab switch).

---

## 9. Tasks Tab — Status Transitions and Completion

- [ ] Tap the circle button on a task: status toggles to Done; title gets strikethrough; button shows filled checkmark.
- [ ] Tap again: task reverts to active status.
- [ ] Status label and icon update immediately (no reload required).
- [ ] Due date label is visible when set; absent when not.

---

## 10. Tasks Tab — Delete (Tombstone)

- [ ] Tap trash icon on a task: task disappears from the list.
- [ ] Relaunch: deleted task is not present in any filter.
- [ ] Deleted task does not reappear after a sync run.

---

## 11. Kanban Board Tab — Column Layout

- [ ] Board shows all five columns: Backlog, Next, Doing, Waiting, Done.
- [ ] Each column header has the correct icon and title.
- [ ] Columns with no cards show "No cards" placeholder.
- [ ] Columns scroll vertically when cards overflow.

---

## 12. Kanban Board Tab — Card Actions

- [ ] Each card is rendered with identifier `kanbanCard_*` (where `*` is the task UUID).
- [ ] Cards display task title; due date shown when set.
- [ ] Left arrow button (`moveLeft_*`) is visible on all columns except Backlog.
- [ ] Right arrow button (`moveRight_*`) is visible on all columns except Done.
- [ ] Tap left arrow: card moves to the previous column immediately.
- [ ] Tap right arrow: card moves to the next column immediately.
- [ ] Moved card appears in the correct column after relaunch.
- [ ] Trash button (`deleteKanbanTask_*`) removes the card; card absent after relaunch.

---

## 13. Kanban Board Tab — Drag Reorder (macOS)

*Skip on iOS if drag-and-drop from kanban is not exposed in the iOS build.*

- [ ] Drag a card within the same column and drop it above another card: order updates immediately.
- [ ] Drag a card to a different column: card moves to that column.
- [ ] Drop target column highlights in accent color during drag.
- [ ] Relaunch: reordered positions are preserved.
- [ ] Drag two cards in sequence; both positions persist after relaunch.

---

## 14. Sync Tab — UI Rendering

- [ ] Calendar Identifier text field (`syncCalendarField`) accepts input.
- [ ] "Run Two-Way Sync" button (`runSyncButton`) is enabled when not syncing.
- [ ] Sync status label (`syncStatusText`) is visible.
- [ ] No sync report section is shown before first sync run.

---

## 15. Sync Tab — Sync Run

*Requires a real calendar ID from `list-calendars` CLI. Skip if no EventKit permission is granted.*

- [ ] Enter a valid calendar identifier; tap "Run Two-Way Sync": button label changes to "Syncing..." and is disabled.
- [ ] After sync completes, "Last Report" section appears with pushed/pulled/imported counts.
- [ ] Sync status label updates to a non-error state.
- [ ] Synced tasks appear in Tasks and Board tabs.

---

## 16. Sync Tab — Diagnostics Export

*Requires at least one completed sync run.*

- [ ] "Last Report" section is visible after sync.
- [ ] Tap "Export Diagnostics" (`exportSyncDiagnosticsButton`): no crash.
- [ ] Export path label (`syncDiagnosticsExportPath`) shows a file path after export.
- [ ] Exported file exists at the shown path and is non-empty JSON.

---

## 17. Sync Tab — Diagnostics Entries

- [ ] If the last sync run produced warnings/errors, the Diagnostics section lists entries with operation, severity icon, and message.
- [ ] A clean sync run shows "No diagnostics captured in last run" (`syncDiagnosticsEmptyState`).
- [ ] Entity/task/event IDs are shown per entry (or `-` if absent).

---

## 18. Recurrence UX

*Requires a recurring task synced from Calendar.*

- [ ] Edit a recurring task: "Recurring Task Edit" dialog appears with "This Occurrence" and "Entire Series" options.
- [ ] Choose "This Occurrence": only the selected occurrence is updated; sibling occurrences are unchanged.
- [ ] Choose "Entire Series": all occurrences reflect the change after next sync.
- [ ] Delete a recurring task: "Recurring Task Delete" dialog appears with "This Occurrence" and "Entire Series" options.
- [ ] Choose "This Occurrence": only that occurrence is deleted; others remain.
- [ ] Choose "Entire Series": all occurrences are removed after next sync.
- [ ] If a detached occurrence was edited externally, `recurrenceConflictBanner` appears in Sync tab.
- [ ] Tapping "Cancel" in either dialog leaves the task unchanged.

---

## 19. Error States

- [ ] Kill network / revoke EventKit permission mid-sync: `globalErrorBanner` appears at bottom of screen.
- [ ] Banner disappears or updates after the condition is resolved.
- [ ] App does not crash when banner is shown.

---

## 20. Data Integrity After Relaunch

- [ ] Create a note, a task, and a kanban reorder in one session; force-quit; relaunch: all three changes persist.
- [ ] Sync checkpoint (calendar token and cursors) survives relaunch — next sync run does not re-import all events from scratch.

---

## Sign-off

| Platform | OS Version | Build | Tester | Date | Result |
|----------|------------|-------|--------|------|--------|
| macOS    |            |       |        |      |        |
| iOS      |            |       |        |      |        |
