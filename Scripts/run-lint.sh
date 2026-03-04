#!/usr/bin/env bash
set -euo pipefail

echo "==> SwiftLint"
swiftlint lint --strict --config .swiftlint.yml

echo "==> SwiftFormat (check only)"
swiftformat Sources/ Tests/ --lint --config .swiftformat

echo "==> Periphery"
periphery scan

echo "✓ All lint checks passed"
