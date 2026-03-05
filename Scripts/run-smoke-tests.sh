#!/usr/bin/env bash
set -euo pipefail
echo "==> Smoke tests"
swift test --filter testSmoke
echo "✓ Smoke tests passed"
