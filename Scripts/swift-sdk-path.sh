#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
PROBE_CACHE="$PROJECT_DIR/.build/sdk-probe-cache"
mkdir -p "$PROBE_CACHE"

typeset -a candidates
typeset -a checked

if [[ -n "${SDKROOT:-}" ]]; then
    candidates+=("$SDKROOT")
fi

DEFAULT_SDK="$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)"
if [[ -n "$DEFAULT_SDK" ]]; then
    candidates+=("$DEFAULT_SDK")
fi

candidates+=(
    /Applications/Xcode*.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX*.sdk(N)
    /Library/Developer/CommandLineTools/SDKs/MacOSX*.sdk(N)
)

for candidate in "${candidates[@]}"; do
    [[ -d "$candidate" ]] || continue
    RESOLVED_SDK="${candidate:A}"
    if (( ${checked[(Ie)$RESOLVED_SDK]} )); then
        continue
    fi
    checked+=("$RESOLVED_SDK")

    if CLANG_MODULE_CACHE_PATH="$PROBE_CACHE" \
        swiftc \
        -typecheck \
        -sdk "$RESOLVED_SDK" \
        -target arm64-apple-macosx13.0 \
        - <<< 'import Foundation' >/dev/null 2>&1; then
        print -r -- "$RESOLVED_SDK"
        exit 0
    fi
done

print -u2 -- "找不到与当前 Swift 编译器兼容的 macOS SDK。请通过系统设置更新 Command Line Tools，或安装匹配版本的 Xcode。"
exit 1
