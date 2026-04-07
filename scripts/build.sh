#!/bin/bash
# Quick debug build and run.
# Usage: scripts/build.sh [--open]

set -euo pipefail

cd "$(dirname "$0")/.."

echo "Building debug..."
swift build 2>&1

if [[ "${1:-}" == "--open" ]]; then
    echo "Launching..."
    open .build/debug/Canopy
fi

echo "Done."
