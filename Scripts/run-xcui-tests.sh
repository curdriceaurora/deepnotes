#!/usr/bin/env bash
# Run XCUI tests against the Deep Notes app.
# Requires: xcodegen (brew install xcodegen)
#
# Usage: ./Scripts/run-xcui-tests.sh [test-filter]
# Example: ./Scripts/run-xcui-tests.sh NotesEditorXCUITests/testNoteBodyEditorAcceptsText
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

# Regenerate Xcode project if project.yml changed
if [ ! -d "NotesEngine.xcodeproj" ] || [ "project.yml" -nt "NotesEngine.xcodeproj/project.pbxproj" ]; then
    echo "==> Generating Xcode project..."
    xcodegen generate
fi

FILTER="${1:-}"
EXTRA_ARGS=()
if [ -n "$FILTER" ]; then
    EXTRA_ARGS+=(-only-testing "NotesUIXCTests/$FILTER")
fi

echo "==> Building and running XCUI tests..."
xcodebuild test \
    -project NotesEngine.xcodeproj \
    -scheme "XCUIHost" \
    -destination "platform=macOS" \
    "${EXTRA_ARGS[@]}" \
    2>&1 | xcbeautify || {
        echo "XCUI tests failed."
        exit 1
    }

echo "==> XCUI tests passed."
