#!/usr/bin/env bash
set -euo pipefail
echo "==> Smoke tests"
swift test --filter testSmoke 2>&1 | tail -3
echo "✓ Smoke tests passed"
