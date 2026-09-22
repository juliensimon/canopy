#!/bin/bash
# Fails unless the Metal compiler can actually run.
#
# Xcode 26 and later do not bundle it -- it is a separately downloaded ~840 MB
# component. SwiftTerm (pinned exactly at 1.20.0) resource-processes
# Apple/Metal/Shaders.metal, so *both* `swift build` and `xcodebuild archive`
# shell out to `metal`. Without it they die deep in the build log with
# "cannot execute tool 'metal' due to missing Metal Toolchain".
#
# Sourced by the build entry points rather than copied into each, so the
# remedy text has one home.

set -euo pipefail

if xcrun metal --version >/dev/null 2>&1; then
    exit 0
fi

echo "ERROR: cannot run the Metal compiler -- SwiftTerm's Shaders.metal will not build." >&2
DEVELOPER_DIR_PATH=$(xcode-select -p 2>/dev/null || echo "")
if [[ "$DEVELOPER_DIR_PATH" != *.app/Contents/Developer ]]; then
    # xcrun also fails this way when the Command Line Tools are selected
    # instead of Xcode, where -downloadComponent is not the remedy.
    echo "       Command Line Tools are selected, not Xcode (${DEVELOPER_DIR_PATH:-none})." >&2
    echo "       Fix with: sudo xcode-select -s /Applications/Xcode.app" >&2
else
    echo "       Xcode 26+ ships the Metal toolchain separately." >&2
    echo "       Install it with: xcodebuild -downloadComponent MetalToolchain" >&2
fi
exit 1
