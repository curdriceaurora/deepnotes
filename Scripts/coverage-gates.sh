#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CODECOV_JSON="${1:-"$ROOT_DIR/.build/arm64-apple-macosx/debug/codecov/NotesEngine.json"}"

if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq is required to evaluate coverage gates." >&2
  exit 1
fi

if [[ ! -f "$CODECOV_JSON" ]]; then
  echo "error: coverage json not found at: $CODECOV_JSON" >&2
  echo "run: swift test --enable-code-coverage" >&2
  exit 1
fi

coverage_counts() {
  local selector="$1"
  jq -r --arg root "$ROOT_DIR" "$selector" "$CODECOV_JSON"
}

format_percent() {
  awk -v covered="$1" -v total="$2" 'BEGIN { if (total == 0) printf "0.00"; else printf "%.2f", (covered / total) * 100 }'
}

evaluate_gate() {
  local name="$1"
  local threshold="$2"
  local selector="$3"

  local counts covered total percent
  counts="$(coverage_counts "$selector")"
  covered="$(awk '{print $1}' <<<"$counts")"
  total="$(awk '{print $2}' <<<"$counts")"
  percent="$(format_percent "$covered" "$total")"

  local status="PASS"
  if ! awk -v p="$percent" -v t="$threshold" 'BEGIN { exit !(p + 0 >= t + 0) }'; then
    status="FAIL"
    GATE_FAILED=1
  fi

  printf "%-32s %7s%%  (%s/%s)  min=%s%%  [%s]\n" "$name" "$percent" "$covered" "$total" "$threshold" "$status"
}

GATE_FAILED=0

echo "Coverage gates (line coverage):"

evaluate_gate \
  "Functional Coverage" \
  "90" \
  '[.data[0].files[] | select(.filename | startswith($root + "/Sources/")) | .summary.lines] | [(map(.covered) | add), (map(.count) | add)] | @tsv'

evaluate_gate \
  "Integration Coverage" \
  "99" \
  '[.data[0].files[] | select((.filename | endswith("Sources/NotesSync/TwoWaySyncEngine.swift")) or (.filename | endswith("Sources/NotesSync/TaskCalendarMapper.swift"))) | .summary.lines] | [(map(.covered) | add), (map(.count) | add)] | @tsv'

evaluate_gate \
  "Error Description Assertions" \
  "99" \
  '[.data[0].files[] | select(.filename | endswith("Sources/NotesDomain/Errors.swift")) | .summary.lines] | [(map(.covered) | add), (map(.count) | add)] | @tsv'

evaluate_gate \
  "UI Interaction Coverage" \
  "95" \
  '[.data[0].files[] | select(.filename | endswith("Sources/NotesUI/AppViewModel.swift")) | .summary.lines] | [(map(.covered) | add), (map(.count) | add)] | @tsv'

evaluate_gate \
  "UI View Layer Coverage" \
  "85" \
  '[.data[0].files[] | select(.filename | endswith("Sources/NotesUI/Views.swift")) | .summary.lines] | [(map(.covered) | add), (map(.count) | add)] | @tsv'

if [[ "$GATE_FAILED" -ne 0 ]]; then
  echo "Coverage gates failed." >&2
  exit 1
fi

echo "All coverage gates passed."
