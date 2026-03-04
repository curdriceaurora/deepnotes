#!/usr/bin/env bash
set -euo pipefail
git config core.hooksPath hooks
chmod +x hooks/pre-commit
chmod +x hooks/pre-push
echo "✓ Git hooks installed (hooks/pre-commit, hooks/pre-push)"
