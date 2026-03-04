# ``NotesDomain``

Core domain models and protocols for a local-first notes and task management application.

## Overview

`NotesDomain` defines the fundamental entities and contracts that power the notes and task management system. It is layer-independent and contains no dependencies on storage, networking, or UI frameworks.

### Key Concepts

- **Notes**: Markdown-formatted documents supporting `[[wikilinks]]` for cross-references and `#tags` for categorization
- **Tasks**: Items with priority, due dates, subtasks, and calendar sync integration
- **Subtasks**: Child items of tasks with independent completion status and auto-completion logic
- **Kanban Columns**: Customizable task status columns with optional WIP limits and color coding
- **Calendar Binding**: Integration with Apple Calendar for two-way sync of tasks and events
- **Search Modes**: Smart, phrase, and prefix-based search for finding notes and tasks

## Topics

### Essentials

- <doc:Models>
- <doc:Errors>
- <doc:Protocols>

### Domain Entities

- ``Note``
- ``Task``
- ``Subtask``
- ``NoteTemplate``
- ``CalendarEvent``
- ``CalendarBinding``
- ``SyncCheckpoint``

### Task Management

- ``TaskStatus``
- ``TaskPriority``
- ``TaskSortOrder``
- ``TaskFilter``
- ``TaskLabel``
- ``KanbanColumn``

### Search and Discovery

- ``NoteSearchMode``
- ``GraphNode``
- ``GraphEdge``

### Protocols and Interfaces

- ``NoteStore``
- ``TaskStore``
- ``CalendarProvider``
- ``NoteTemplateStore``

### Error Handling

- ``NoteError``
- ``TaskError``
- ``SyncError``
- ``StorageError``
