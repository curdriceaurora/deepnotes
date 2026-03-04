#!/usr/bin/env bash
set -euo pipefail
git config core.hooksPath hooks
chmod +x hooks/pre-commit
echo "✓ Git hooks installed (hooks/pre-commit)"
