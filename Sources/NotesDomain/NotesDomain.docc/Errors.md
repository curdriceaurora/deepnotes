# Error Handling

Typed errors for domain-specific failures across the system.

## Overview

The domain layer uses typed errors (enums) instead of generic exceptions. This provides compile-time safety and allows callers to handle specific failure modes gracefully.

## Note Errors

``NoteError`` is thrown by note-related operations:

- **notFound(id: UUID)** — Requested note does not exist
- **invalidTitle(title: String)** — Title is empty or contains invalid characters
- **invalidBody(reason: String)** — Body fails validation (e.g., exceeds size limits)
- **linkNotFound(title: String)** — A referenced `[[wikilink]]` target does not exist

**Usage:**
```swift
do {
    let note = try workspace.note(withID: uuid)
} catch NoteError.notFound(let id) {
    print("Note \(id) not found")
} catch {
    print("Other error: \(error)")
}
```

## Task Errors

``TaskError`` is thrown by task operations:

- **notFound(id: UUID)** — Requested task does not exist
- **invalidPriority(value: Int)** — Priority outside valid range (0-5)
- **invalidStatus(status: String)** — Status is not a valid TaskStatus
- **invalidDueDate(reason: String)** — Due date is in the past or invalid
- **subtaskNotFound(id: UUID, in: UUID)** — Subtask does not exist on parent
- **statusTransitionInvalid(from: TaskStatus, to: TaskStatus)** — Invalid state transition

**Usage:**
```swift
do {
    let task = try Task(
        id: UUID(),
        stableID: "task-1",
        title: "Important",
        priority: 10,  // Invalid: must be 0-5
        updatedAt: Date()
    )
} catch DomainValidationError.invalidPriority(let value) {
    print("Invalid priority value: \(value); must be 0-5")
}
```

## Sync Errors

``SyncError`` is thrown during two-way calendar sync:

- **operationFailed(operation: String, details: String)** — Sync operation failed (pull, push, or resolve)
- **providerError(provider: String, underlyingError: Error)** — Calendar provider (EventKit) returned an error
- **conflictUnresolvable(IDs: [String], reason: String)** — Conflict resolution logic failed
- **checkpointCorrupted(reason: String)** — Sync checkpoint is invalid or unreadable

**Usage:**
```swift
do {
    try workspace.runSync(with: calendarProvider)
} catch SyncError.operationFailed(let op, let details) {
    print("Sync \(op) failed: \(details)")
}
```

## Storage Errors

``StorageError`` is thrown by persistence operations:

- **connectionFailed(reason: String)** — Cannot connect to database
- **queryFailed(query: String, reason: String)** — SQL query execution failed
- **migrationFailed(version: Int, reason: String)** — Database migration failed
- **constraintViolated(constraint: String)** — Database constraint violated (e.g., uniqueness)

**Usage:**
```swift
do {
    try store.initialize()
} catch StorageError.migrationFailed(let version, let reason) {
    print("Migration to version \(version) failed: \(reason)")
}
```

## Error Handling Best Practices

### Be Specific
```swift
// ✅ Good: Handle specific errors
do {
    try workspace.linkNote(from: sourceID, to: targetID)
} catch NoteError.notFound {
    // Handle missing note
} catch NoteError.linkNotFound {
    // Handle missing link target
}

// ❌ Avoid: Catch-all error handling
do {
    try workspace.linkNote(from: sourceID, to: targetID)
} catch {
    print("Error: \(error)")
}
```

### Log Diagnostic Context
```swift
// ✅ Good: Include context in logs
do {
    try store.updateTask(id, with: changes)
} catch SyncError.operationFailed(let op, let details) {
    logger.error("Sync \(op) failed", metadata: [
        "details": "\(details)",
        "taskID": "\(id)",
        "timestamp": "\(Date())"
    ])
}
```

### Recover Gracefully
```swift
// ✅ Good: Provide fallback behavior
let notes: [Note]
do {
    notes = try workspace.allNotes()
} catch StorageError.connectionFailed {
    notes = [] // Empty cache, user sees empty list
    scheduleRetry()
}
```

## Sync Diagnostics

When sync errors occur, a ``SyncDiagnostic`` record is created with:
- **operation**: The failing operation (pull, push, resolve)
- **taskIDs / eventIDs**: Affected entity IDs
- **providerError**: Calendar provider error (if applicable)
- **timestamp**: When the error occurred
- **recoveryHint**: Suggested user action

Users can review these in the **Sync Diagnostics** tab to understand what went wrong and retry if needed.
