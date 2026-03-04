# API Documentation

The NotesEngine project provides comprehensive API documentation via **DocC** (Documentation Compiler), Apple's official documentation framework for Swift packages.

## Building Documentation

### Prerequisites

- **macOS**: Xcode 15.0+ (includes DocC command-line tool)
- **Linux**: Swift 5.9+ (DocC available via `swift build` with plugin)

### Generate Documentation

#### Option 1: Using Swift Package Build (Recommended)

```bash
# Build documentation and open in default browser
swift package generate-documentation --target NotesDomain --derive-swift-ui-symbols

# Or build for all targets
swift package generate-documentation --derive-swift-ui-symbols
```

The documentation will be generated to `.build/documentation/`.

#### Option 2: Using Xcode

1. Open the project in Xcode
2. Select **Product** → **Build Documentation** (or `Cmd+Ctrl+D`)
3. Browse documentation in the Documentation window

#### Option 3: Command-Line Tool (Xcode)

```bash
# Xcode must be installed
xcrun docc build \
  --base-url https://notes-engine.example.com/docs \
  --output-path ./docs \
  Sources/NotesDomain/NotesDomain.docc
```

## Viewing Documentation

### Locally

1. Build documentation (see above)
2. Open the `.build/documentation/index.html` file in your browser
3. Or use Xcode's Documentation window

### Online (GitHub Pages)

Documentation is automatically deployed to GitHub Pages on each release:
- **URL**: `https://curdriceaurora.github.io/notes-placeholder/documentation/notesdomain/`

## Documentation Structure

The documentation is organized as follows:

```
Sources/NotesDomain/NotesDomain.docc/
├── NotesDomain.md              # Main catalog and navigation
├── Models.md                   # Core domain entities
├── Errors.md                   # Error types and handling
├── Protocols.md                # Interfaces and contracts
└── Resources/                  # Images, diagrams, etc.
```

### Main Sections

1. **NotesDomain** (`NotesDomain.md`)
   - Overview and key concepts
   - Topic organization
   - Links to detailed sections

2. **Models** (`Models.md`)
   - Core entity types: Note, Task, Subtask
   - Calendar integration: CalendarEvent, CalendarBinding
   - Customization: NoteTemplate, TaskLabel, KanbanColumn
   - Search: GraphNode, GraphEdge

3. **Error Handling** (`Errors.md`)
   - Typed errors: NoteError, TaskError, SyncError, StorageError
   - Best practices for error handling
   - Sync diagnostics

4. **Protocols** (`Protocols.md`)
   - Store protocols: NoteStore, TaskStore, NoteTemplateStore
   - Calendar integration: CalendarProvider
   - Testing interfaces: WorkspaceServiceSpy, MockWorkspaceService

## Documenting Your Code

### Doc Comments

Every public API should have a doc comment using `///`:

```swift
/// Creates a new note with the provided title and body.
///
/// - Parameters:
///   - title: The note title (non-empty)
///   - body: The note body in Markdown format (may be empty)
///   - tags: Optional array of tags to assign (default: empty)
/// - Throws: `NoteError.invalidTitle` if title is empty
/// - Returns: The created Note with UUID, timestamps, and version
///
/// - SeeAlso: ``updateNote(_:)``
public func createNote(
    title: String,
    body: String,
    tags: [String] = []
) throws -> Note {
    // ...
}
```

### Documentation Markup

DocC supports rich Markdown with extensions:

| Element | Syntax |
|---------|--------|
| Parameter | `- Parameters:` followed by parameter list |
| Return | `- Returns:` description |
| Throws | `- Throws:` error types |
| See also | `- SeeAlso:` related symbols |
| Discussion | Multi-paragraph text after description |
| Code | ````swift` code blocks with syntax highlighting |
| Links | `` ``SymbolName`` `` or `[text](link)` |

### Best Practices

✅ **Do:**
- Document all public types, methods, and properties
- Include usage examples in complex APIs
- Explain error cases and recovery strategies
- Link to related types and methods
- Keep descriptions concise and scannable

❌ **Don't:**
- Document implementation details (private APIs)
- Leave generic placeholders like `TODO` or `Implement me`
- Write documentation that duplicates the code
- Skip error documentation

## Deployment to GitHub Pages

### Automatic Deployment (CI/CD)

Documentation is built and deployed automatically on release:

1. **GitHub Actions workflow** generates documentation
2. **Publish to GitHub Pages** via `gh-pages` branch
3. **Deployed to**: `https://curdriceaurora.github.io/notes-placeholder/`

See `.github/workflows/` for CI configuration.

### Manual Deployment

If needed, deploy documentation manually:

```bash
# Build documentation
swift package generate-documentation \
  --target NotesDomain \
  --derive-swift-ui-symbols \
  --output-path ./docs

# Commit and push to gh-pages branch
git checkout -b gh-pages
git add docs/
git commit -m "docs: publish API documentation"
git push origin gh-pages

# Switch back to main
git checkout main
```

## Accessing Documentation

- **Latest (development)**: `https://curdriceaurora.github.io/notes-placeholder/docs/`
- **Stable (releases)**: Tagged versions are available via GitHub Releases

## Troubleshooting

### Documentation not generating

1. Verify doc comments are in place (use `swift build` to check for warnings)
2. Check for syntax errors in `.docc/` files (validate YAML/Markdown)
3. Ensure all referenced symbols exist (``SymbolName``)
4. Try cleaning build artifacts: `rm -rf .build/ && swift build`

### Broken links in documentation

- Use full symbol paths: `` ``NotesDomain.Note`` `` (not just `Note`)
- Check that all referenced symbols are public
- Use `swift package diagnose-api-changes` to find undocumented symbols

### Deployment issues

- Verify GitHub Pages is enabled in repository settings
- Check GitHub Actions workflow logs for build failures
- Ensure `gh-pages` branch exists and is set as publication branch

## Related Documentation

- **[CONTRIBUTING.md](../CONTRIBUTING.md)** — Code standards including documentation requirements
- **[Docs/](../)** — Architecture, design decisions, and technical guides
- **[Swift DocC Docs](https://www.apple.com/swift/documentation/)** — Official DocC documentation

## Questions?

- Check the [DocC tutorials](https://www.apple.com/swift/documentation/) for markup examples
- Open an issue if documentation is unclear or missing
- Refer to doc comments in source files for inline examples

---

**Last Updated**: 2026-03-03
**Status**: Active (automatically deployed from main branch)
