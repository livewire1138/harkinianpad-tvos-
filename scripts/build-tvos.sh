#!/usr/bin/env bash
# Fetch, patch, configure, and build the first controller-first tvOS port.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODE="${1:---device}"
case "$MODE" in --device|--simulator) ;; *) echo "Usage: scripts/build-tvos.sh [--device|--simulator]" >&2; exit 2;; esac
"$ROOT/scripts/clone-sources.sh"
"$ROOT/scripts/generate-port-archive.sh"
"$ROOT/scripts/configure-tvos.sh" "$MODE"
if [ "$MODE" = --simulator ]; then BUILD_DIR="$ROOT/build-tvos-soh-sim"; DEST="generic/platform=tvOS Simulator"; PRODUCT="Release-appletvsimulator"; else BUILD_DIR="$ROOT/build-tvos-soh"; DEST="generic/platform=tvOS"; PRODUCT="Release-appletvos"; fi
set -- cmake --build "$BUILD_DIR" --target soh --config Release -- -destination "$DEST"
if [ "$MODE" = --device ] && [ -z "${DEVELOPMENT_TEAM:-}" ]; then set -- "$@" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO; fi
"$@"
printf '\nHarkinianTV app:\n  %s/soh/%s/HarkinianTV.app\n' "$BUILD_DIR" "$PRODUCT"
