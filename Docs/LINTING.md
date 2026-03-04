# Code Style & Linting

This project uses **SwiftLint** to enforce consistent code style and quality standards.

## Configuration

SwiftLint configuration is in [`.swiftlint.yml`](../.swiftlint.yml) at the repository root.

### Key rules:

- **Indentation**: 4 spaces (matches project convention)
- **Line length**: 140 characters max
- **Cyclomatic complexity**: 15 warning / 20 error
- **Function parameters**: 6 warning / 8 error
- **File length**: 500 lines warning / 750 lines error
- **Type body length**: 300 warning / 500 error
- **Force unwrapping**: Warning (use optionals properly)
- **Strict access control**: Explicit public/private required

## Installation

### Homebrew (recommended)

```bash
brew install swiftlint
```

### Mint

```bash
mint install realm/swiftlint
```

### From source

```bash
git clone https://github.com/realm/SwiftLint.git
cd SwiftLint
make install
```

## Usage

### Run checks

```bash
# Check all Swift files
swiftlint lint

# Check specific files or directories
swiftlint lint Sources/

# Show detailed output
swiftlint lint --verbose
```

### Auto-fix violations

```bash
# Automatically fix violations where possible
swiftlint lint --fix

# Fix specific files
swiftlint lint --fix Sources/NotesUI/Views.swift
```

### Strict mode (fail on warnings)

```bash
# Treat warnings as errors (useful for CI)
swiftlint lint --strict
```

## Pre-commit Integration

To automatically lint before commits:

### Setup pre-commit framework

```bash
# Install pre-commit
brew install pre-commit

# Install git hooks
pre-commit install

# Run hooks on all files
pre-commit run --all-files
```

### Manual pre-commit check

```bash
# Check only staged files
swiftlint lint --strict
```

## CI Integration

SwiftLint checks should be run in CI pipelines:

```yaml
# Example GitHub Actions workflow
- name: SwiftLint
  run: swiftlint lint --strict
```

## Common Violations & Fixes

### Force unwrapping (`!`)

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

### Trailing whitespace

❌ **Bad:**
```swift
func example() {    // trailing spaces after {
    // code
}
```

✅ **Good:**
```swift
func example() {
    // code
}
```

### Nesting depth

❌ **Bad:**
```swift
if condition1 {
    if condition2 {
        if condition3 {
            if condition4 {
                // too deeply nested
            }
        }
    }
}
```

✅ **Good:**
```swift
guard condition1 else { return }
guard condition2 else { return }
guard condition3 else { return }
// continue with logic
```

## Disabling rules for specific code

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

Note: Use sparingly. Understand why the rule exists before disabling.

## Updating configuration

To modify SwiftLint rules:

1. Edit `.swiftlint.yml`
2. Test with `swiftlint lint --verbose`
3. Commit the updated configuration
4. Notify the team of any breaking changes

See [SwiftLint documentation](https://github.com/realm/SwiftLint) for all available rules.
