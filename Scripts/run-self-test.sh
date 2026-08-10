#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
MODULE_CACHE="$PROJECT_DIR/.build/module-cache"
COMPATIBLE_SDK="$("$PROJECT_DIR/Scripts/swift-sdk-path.sh")"

mkdir -p "$MODULE_CACHE"
SDKROOT="$COMPATIBLE_SDK" \
CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" \
SWIFTPM_MODULECACHE_OVERRIDE="$MODULE_CACHE" \
swift run \
    --disable-sandbox \
    --triple arm64-apple-macosx13.0 \
    --package-path "$PROJECT_DIR" \
    ClipFlowSelfTest
