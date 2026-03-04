#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPORT_FILE="${1:-$ROOT_DIR/perf-artifacts/perf-report.txt}"
BASELINE_FILE="${2:-$ROOT_DIR/Docs/perf-baseline.env}"

if [[ ! -f "$REPORT_FILE" ]]; then
  echo "error: perf report not found at $REPORT_FILE" >&2
  echo "run: ./Scripts/run-perf-gates.sh" >&2
  exit 1
fi

metric() {
  local key="$1"
  local value
  value="$(awk -F= -v key="$key" '$1 == key { value=$2 } END { print value }' "$REPORT_FILE")"
  if [[ -z "$value" ]]; then
    echo "error: metric '$key' missing from $REPORT_FILE" >&2
    exit 1
  fi
  echo "$value"
}

baseline_metric() {
  local key="$1"
  local value
  value="$(awk -F= -v key="$key" '$1 == key { value=$2 } END { print value }' "$BASELINE_FILE")"
  if [[ -z "$value" ]]; then
    echo "error: baseline metric '$key' missing from $BASELINE_FILE" >&2
    exit 1
  fi
  echo "$value"
}

format_float() {
  awk -v value="$1" 'BEGIN { printf "%.3f", value + 0 }'
}

assert_le() {
  local label="$1"
  local actual="$2"
  local expected_max="$3"

  if awk -v a="$actual" -v e="$expected_max" 'BEGIN { exit !(a <= e) }'; then
    printf "%-36s actual=%8s  limit=%8s  [PASS]\n" "$label" "$(format_float "$actual")" "$(format_float "$expected_max")"
  else
    printf "%-36s actual=%8s  limit=%8s  [FAIL]\n" "$label" "$(format_float "$actual")" "$(format_float "$expected_max")" >&2
    GATE_FAILED=1
  fi
}

assert_ge() {
  local label="$1"
  local actual="$2"
  local expected_min="$3"

  if awk -v a="$actual" -v e="$expected_min" 'BEGIN { exit !(a >= e) }'; then
    printf "%-36s actual=%8s  limit=%8s  [PASS]\n" "$label" "$(format_float "$actual")" "$(format_float "$expected_min")"
  else
    printf "%-36s actual=%8s  limit=%8s  [FAIL]\n" "$label" "$(format_float "$actual")" "$(format_float "$expected_min")" >&2
    GATE_FAILED=1
  fi
}

if [[ ! -f "$BASELINE_FILE" ]]; then
  echo "error: baseline file not found at $BASELINE_FILE" >&2
  exit 1
fi

status="$(metric status)"
if [[ "$status" != "ok" ]]; then
  echo "error: harness status is '$status'" >&2
  awk -F= '$1 == "failure" { print " - " $2 }' "$REPORT_FILE" >&2 || true
  exit 1
fi

create_note_p95="$(metric create_note_p95_ms)"
create_note_slo="$(metric create_note_p95_slo_ms)"
launch_p95="$(metric launch_to_interactive_p95_ms)"
launch_slo="$(metric launch_to_interactive_p95_slo_ms)"
open_note_p95="$(metric open_note_p95_ms)"
open_note_slo="$(metric open_note_p95_slo_ms)"
save_note_p95="$(metric save_note_edit_p95_ms)"
save_note_slo="$(metric save_note_edit_p95_slo_ms)"
wikilink_backlinks_p95="$(metric wikilink_backlinks_refresh_p95_ms)"
wikilink_backlinks_slo="$(metric wikilink_backlinks_refresh_p95_slo_ms)"
search_50k_p95="$(metric search_50k_p95_ms)"
search_50k_slo="$(metric search_50k_p95_slo_ms)"
kanban_drag_commit_p95="$(metric kanban_drag_commit_p95_ms)"
kanban_drag_commit_slo="$(metric kanban_drag_commit_p95_slo_ms)"
kanban_p95="$(metric kanban_render_frame_p95_ms)"
kanban_slo="$(metric kanban_render_frame_p95_slo_ms)"
kanban_fps_p95="$(metric kanban_render_fps_p95)"
kanban_target_fps="$(metric kanban_target_fps)"

sync_push_p95="$(metric sync_push_p95_ms)"
sync_push_slo="$(metric sync_push_p95_slo_ms)"
sync_pull_p95="$(metric sync_pull_p95_ms)"
sync_pull_slo="$(metric sync_pull_p95_slo_ms)"
sync_roundtrip_p95="$(metric sync_roundtrip_p95_ms)"
sync_roundtrip_slo="$(metric sync_roundtrip_p95_slo_ms)"
sync_conflict_p95="$(metric sync_conflict_p95_ms)"
sync_conflict_slo="$(metric sync_conflict_p95_slo_ms)"

baseline_create_note_p95="$(baseline_metric create_note_p95_ms)"
baseline_launch_p95="$(baseline_metric launch_to_interactive_p95_ms)"
baseline_open_note_p95="$(baseline_metric open_note_p95_ms)"
baseline_save_note_p95="$(baseline_metric save_note_edit_p95_ms)"
baseline_wikilink_backlinks_p95="$(baseline_metric wikilink_backlinks_refresh_p95_ms)"
baseline_search_50k_p95="$(baseline_metric search_50k_p95_ms)"
baseline_kanban_drag_commit_p95="$(baseline_metric kanban_drag_commit_p95_ms)"
baseline_kanban_p95="$(baseline_metric kanban_render_frame_p95_ms)"

allowed_create_note_regression="$(awk -v b="$baseline_create_note_p95" 'BEGIN { printf "%.6f", b * 1.10 }')"
allowed_launch_regression="$(awk -v b="$baseline_launch_p95" 'BEGIN { printf "%.6f", b * 1.10 }')"
allowed_open_note_regression="$(awk -v b="$baseline_open_note_p95" 'BEGIN { printf "%.6f", b * 1.10 }')"
allowed_save_note_regression="$(awk -v b="$baseline_save_note_p95" 'BEGIN { printf "%.6f", b * 1.10 }')"
allowed_wikilink_backlinks_regression="$(awk -v b="$baseline_wikilink_backlinks_p95" 'BEGIN { printf "%.6f", b * 1.10 }')"
allowed_search_50k_regression="$(awk -v b="$baseline_search_50k_p95" 'BEGIN { printf "%.6f", b * 1.10 }')"
allowed_kanban_drag_commit_regression="$(awk -v b="$baseline_kanban_drag_commit_p95" 'BEGIN { printf "%.6f", b * 1.10 }')"
allowed_kanban_regression="$(awk -v b="$baseline_kanban_p95" 'BEGIN { printf "%.6f", b * 1.10 }')"

baseline_sync_push_p95="$(baseline_metric sync_push_p95_ms)"
baseline_sync_pull_p95="$(baseline_metric sync_pull_p95_ms)"
baseline_sync_roundtrip_p95="$(baseline_metric sync_roundtrip_p95_ms)"
baseline_sync_conflict_p95="$(baseline_metric sync_conflict_p95_ms)"

allowed_sync_push_regression="$(awk -v b="$baseline_sync_push_p95" 'BEGIN { printf "%.6f", b * 1.10 }')"
allowed_sync_pull_regression="$(awk -v b="$baseline_sync_pull_p95" 'BEGIN { printf "%.6f", b * 1.10 }')"
allowed_sync_roundtrip_regression="$(awk -v b="$baseline_sync_roundtrip_p95" 'BEGIN { printf "%.6f", b * 1.10 }')"
allowed_sync_conflict_regression="$(awk -v b="$baseline_sync_conflict_p95" 'BEGIN { printf "%.6f", b * 1.10 }')"

GATE_FAILED=0

echo "Performance gates:"
assert_le "Launch p95 SLO" "$launch_p95" "$launch_slo"
assert_le "Open note p95 SLO" "$open_note_p95" "$open_note_slo"
assert_le "Save note p95 SLO" "$save_note_p95" "$save_note_slo"
assert_le "Wiki/backlinks p95 SLO" "$wikilink_backlinks_p95" "$wikilink_backlinks_slo"
assert_le "Create note p95 SLO" "$create_note_p95" "$create_note_slo"
assert_le "Search@50k p95 SLO" "$search_50k_p95" "$search_50k_slo"
assert_le "Kanban drag commit p95 SLO" "$kanban_drag_commit_p95" "$kanban_drag_commit_slo"
assert_le "Kanban render p95 SLO" "$kanban_p95" "$kanban_slo"
assert_ge "Kanban render p95 FPS" "$kanban_fps_p95" "$kanban_target_fps"
assert_le "Launch p95 regression" "$launch_p95" "$allowed_launch_regression"
assert_le "Open note p95 regression" "$open_note_p95" "$allowed_open_note_regression"
assert_le "Save note p95 regression" "$save_note_p95" "$allowed_save_note_regression"
assert_le "Wiki/backlinks p95 regression" "$wikilink_backlinks_p95" "$allowed_wikilink_backlinks_regression"
assert_le "Create note p95 regression" "$create_note_p95" "$allowed_create_note_regression"
assert_le "Search@50k p95 regression" "$search_50k_p95" "$allowed_search_50k_regression"
assert_le "Kanban drag p95 regression" "$kanban_drag_commit_p95" "$allowed_kanban_drag_commit_regression"
assert_le "Kanban render p95 regression" "$kanban_p95" "$allowed_kanban_regression"
assert_le "Sync push p95 SLO" "$sync_push_p95" "$sync_push_slo"
assert_le "Sync pull p95 SLO" "$sync_pull_p95" "$sync_pull_slo"
assert_le "Sync round-trip p95 SLO" "$sync_roundtrip_p95" "$sync_roundtrip_slo"
assert_le "Sync conflict p95 SLO" "$sync_conflict_p95" "$sync_conflict_slo"
assert_le "Sync push p95 regression" "$sync_push_p95" "$allowed_sync_push_regression"
assert_le "Sync pull p95 regression" "$sync_pull_p95" "$allowed_sync_pull_regression"
assert_le "Sync round-trip p95 regression" "$sync_roundtrip_p95" "$allowed_sync_roundtrip_regression"
assert_le "Sync conflict p95 regression" "$sync_conflict_p95" "$allowed_sync_conflict_regression"

if [[ "$GATE_FAILED" -ne 0 ]]; then
  echo "Performance gates failed." >&2
  exit 1
fi

echo "All performance gates passed."
