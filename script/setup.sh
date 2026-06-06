#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOKS_DIR="${REPO_ROOT}/.git/hooks"

echo "Installing pre-commit hook..."
cp "${REPO_ROOT}/script/hooks/pre-commit" "${HOOKS_DIR}/pre-commit"
chmod +x "${HOOKS_DIR}/pre-commit"
echo "Done. Pre-commit hook installed at ${HOOKS_DIR}/pre-commit"
