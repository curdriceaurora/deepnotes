#!/usr/bin/env bash
set -euo pipefail

echo "==> SwiftFormat (apply)"
swiftformat Sources/ Tests/ --config .swiftformat
echo "✓ Formatting applied"
