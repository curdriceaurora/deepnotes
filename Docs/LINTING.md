# Code Style, Linting & Formatting

This project uses **SwiftLint**, **SwiftFormat**, **Periphery**, and **xcbeautify** to enforce consistent code style, quality standards, and identify dead code.

## Tools Overview

| Tool | Purpose | Config |
|---|---|---|
| **SwiftLint** | Enforces coding rules and standards | `.swiftlint.yml` |
| **SwiftFormat** | Formats code consistently (indentation, imports, etc.) | `.swiftformat` |
| **Periphery** | Detects and removes dead code | `.periphery.yml` |
| **xcbeautify** | Prettifies Xcode build output | (no config) |

## SwiftLint

### Configuration

SwiftLint configuration is in [`.swiftlint.yml`](../.swiftlint.yml) at the repository root.

#### Key Rules

- **Line length**: 140 characters max (160 error)
- **Cyclomatic complexity**: 15 warning / 20 error
- **Function parameters**: 6 warning / 8 error
- **File length**: 400 warning / 600 error
- **Type body length**: 250 warning / 350 error (500 error for tests)
- **Function body length**: 50 warning / 80 error
- **Identifier names**: 2+ characters (excluded: `id`, `db`, `vm`, `at`, `to`, `i`, `j`, `k`, `x`, `y`)

#### Opt-in rules enabled

- `sorted_imports` — Enforces alphabetical import order
- `closure_spacing` — Ensures consistent spacing around closures
- `contains_over_first_not_nil` — Prefers `contains()` over `first(where:) != nil`
- `empty_count` — Prefers `isEmpty` over `count == 0`
- `explicit_init` — Requires explicit `.init()` in some contexts
- `first_where` — Prefers `first(where:)` over filtering then getting first
- `modifier_order` — Enforces consistent modifier order (public static var, etc.)
- `override_in_extension` — Prevents overrides in extensions (compile-time safety)
- `prefer_self_type_over_type_of_self` — Prefers `Self` in protocols and classes

#### Disabled rules

- `todo` — Allows `// TODO:` and `// FIXME:` comments without warnings
- `trailing_comma` — Allows trailing commas in multi-line collections
- `multiple_closures_with_trailing_closure` — Allows multiple trailing closures

### Installation

```bash
# Homebrew (recommended)
brew install swiftlint

# Mint
mint install realm/swiftlint
```

### Usage

```bash
# Check all Swift files
swiftlint lint

# Check with strict mode (warnings = errors)
swiftlint lint --strict

# Check specific files or directories
swiftlint lint Sources/

# Auto-fix violations where possible
swiftlint lint --fix

# Verbose output
swiftlint lint --verbose
```

## SwiftFormat

### Configuration

SwiftFormat configuration is in [`.swiftformat`](../.swiftformat) at the repository root.

#### Key Settings

- **Line width**: 140 characters
- **Indentation**: 4 spaces
- **Imports**: Testable imports grouped at bottom
- **Trailing commas**: Always enabled
- **Semicolons**: Never allowed
- **Wrapping**: Before first argument/parameter/collection element

### Installation

```bash
# Homebrew
brew install swiftformat

# Mint
mint install nicklockwood/swiftformat/swiftformat
```

### Usage

```bash
# Check formatting without applying changes
swiftformat Sources/ Tests/ --lint --config .swiftformat

# Apply formatting
swiftformat Sources/ Tests/ --config .swiftformat

# Check specific file
swiftformat Sources/NotesUI/Views.swift --lint
```

## Periphery

### Configuration

Periphery configuration is in [`.periphery.yml`](../.periphery.yml) at the repository root.

#### Scope

Periphery scans these targets for dead code:
- NotesDomain
- NotesStorage
- NotesSync
- NotesFeatures
- NotesUI
- NotesApp
- NotesCLI
- NotesPerfHarness

Test targets are excluded from analysis.

### Installation

```bash
brew install periphery
```

### Usage

```bash
# Scan for dead code
periphery scan

# Output as JSON (for CI/CD pipelines)
periphery scan --output json

# Exclude specific files
periphery scan --exclude "Sources/Legacy/**"
```

### Suppressing False Positives

Add a comment above the declaration to suppress a specific warning:

```swift
// periphery:ignore
func internalHelperNeverUsedDirectly() {
    // ...
}

// Alternatively, for specific occurrences:
class MyClass {
    // periphery:ignore
    func conformanceMethodRequiredByProtocol() {
        // ...
    }
}
```

## xcbeautify

### Purpose

xcbeautify prettifies Xcode build output, making warnings and errors easier to read. It's not a linter but a build log formatter.

### Installation

```bash
brew install xcbeautify
```

### Usage

Pipe build or test commands through `xcbeautify`:

```bash
# Clean build output
swift build 2>&1 | xcbeautify

# Clean test output
swift test 2>&1 | xcbeautify

# With exit code preservation
swift build 2>&1 | xcbeautify && echo "✓ Build succeeded"
```

## Pre-commit Hooks

To automatically lint before commits, install the pre-commit hook:

```bash
./Scripts/install-git-hooks.sh
```

This will:
1. Check staged Swift files with SwiftFormat
2. Check staged files with SwiftLint

If either check fails, the commit is blocked. To bypass (not recommended):

```bash
git commit --no-verify
```

## Quick Scripts

The project provides helper scripts for common tasks:

```bash
# Run all lint checks (SwiftLint + SwiftFormat + Periphery)
./Scripts/run-lint.sh

# Apply SwiftFormat to entire codebase
./Scripts/run-format.sh

# Install pre-commit hooks
./Scripts/install-git-hooks.sh
```

## CI Integration

Lint checks run automatically on every PR and push to main:

- `.github/workflows/coverage-gates.yml` — Runs SwiftLint, SwiftFormat, Periphery, and builds with xcbeautify

See `.github/workflows/coverage-gates.yml` for the full CI configuration.

## Common Violations & How to Fix

### Force Unwrapping (`!`)

❌ **Bad:**
```swift
let value = dictionary["key"]!
```

✅ **Good:**
```swift
if let value = dictionary["key"] {
    // use value
}

guard let value = dictionary["key"] else { return }
```

### Unsorted Imports

❌ **Bad:**
```swift
import Foundation
import NotesDomain
@testable import NotesStorage
```

✅ **Good:**
```swift
import Foundation
@testable import NotesStorage
import NotesDomain
```

(Test imports group at bottom per `--importgrouping testable-bottom`)

### Line Length

❌ **Bad:**
```swift
let veryLongVariableName = someFunctionCall(withArgument: "this is a very long line that exceeds the 140 character limit")
```

✅ **Good:**
```swift
let veryLongVariableName = someFunctionCall(
    withArgument: "this line wraps properly"
)
```

### Cyclomatic Complexity

Functions with more than 15 conditions/branches are too complex.

❌ **Bad:**
```swift
func processInput(_ value: Int) {
    if value > 0 {
        if value < 10 {
            // ...
        } else if value < 20 {
            // ...
        } else if value < 30 {
            // ... (many more conditions)
        }
    }
}
```

✅ **Good:**
```swift
func processInput(_ value: Int) {
    guard value > 0 else { return }

    switch value {
    case 0..<10: handleSmall(value)
    case 10..<20: handleMedium(value)
    case 20..<30: handleLarge(value)
    default: handleExtra(value)
    }
}
```

## Disabling Rules for Specific Code

In rare cases, you can disable SwiftLint for a line or block:

```swift
// swiftlint:disable:next force_unwrapping
let value = dictionary["key"]!

// swiftlint:disable force_unwrapping
func riskyFunction() {
    let value = dictionary["key"]!
}
// swiftlint:enable force_unwrapping
```

**Use sparingly.** Understand why the rule exists before disabling it.

## Updating Configuration

To modify linting rules:

1. Edit `.swiftlint.yml`, `.swiftformat`, or `.periphery.yml`
2. Test locally:
   - `./Scripts/run-lint.sh` (check all)
   - `./Scripts/run-format.sh` (apply formatting)
3. Commit the configuration changes
4. Notify the team of any breaking changes

See [SwiftLint docs](https://github.com/realm/SwiftLint), [SwiftFormat docs](https://github.com/nicklockwood/SwiftFormat), and [Periphery docs](https://github.com/peripheryapp/periphery) for all available options.
