#!/usr/bin/env bash
# Formats all Swift files in place.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

find App Sources Tests -name '*.swift' -print0 | \
    xargs -0 xcrun swift-format format --configuration .swift-format --in-place

echo "Formatted all Swift files."
