#!/usr/bin/env bash
# Configure the first HarkinianTV device or Simulator Xcode project.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/sources/Shipwright"
MODE="${1:---device}"
case "$MODE" in --device|--simulator) ;; *) echo "Usage: scripts/configure-tvos.sh [--device|--simulator]" >&2; exit 2;; esac
[ -d "$SRC" ] || { echo "sources/Shipwright not found — run scripts/clone-sources.sh first." >&2; exit 1; }
[ -f "$SRC/soh/soh.o2r" ] || { echo "Run scripts/generate-port-archive.sh first." >&2; exit 1; }
DEPLOYMENT_TARGET="${DEPLOYMENT_TARGET:-14.0}"
BUNDLE_ID="${BUNDLE_ID:-com.chrissotraidis.harkiniantv}"
VERSION="${HARKINIANPAD_VERSION:-0.1.0}"
BUILD_NUMBER="${HARKINIANPAD_BUILD_NUMBER:-1}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "HARKINIANPAD_VERSION must use numeric major.minor.patch form." >&2; exit 2; }
[[ "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]] || { echo "HARKINIANPAD_BUILD_NUMBER must be a positive integer." >&2; exit 2; }
if [ "$MODE" = --simulator ]; then PLATFORM="SIMULATOR_TVOS"; BUILD_DIR="$ROOT/build-tvos-soh-sim"; DESTINATION="generic/platform=tvOS Simulator"; else PLATFORM="TVOS"; BUILD_DIR="$ROOT/build-tvos-soh"; DESTINATION="generic/platform=tvOS"; fi
set -- cmake -Wno-unused-cli -S "$SRC" -B "$BUILD_DIR" -GXcode \
  -DCMAKE_SYSTEM_NAME=tvOS -DCMAKE_SYSTEM_VERSION="$DEPLOYMENT_TARGET" \
  -DDEPLOYMENT_TARGET="$DEPLOYMENT_TARGET" -DCMAKE_OSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET" \
  -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_BUILD_TYPE=Release -DENABLE_SCRIPTING=OFF \
  -DPLATFORM="$PLATFORM" -DBUNDLE_ID="$BUNDLE_ID" \
  -DHARKINIANPAD_VERSION="$VERSION" -DHARKINIANPAD_BUILD_NUMBER="$BUILD_NUMBER"
if [ -n "${DEVELOPMENT_TEAM:-}" ]; then set -- "$@" "-DCMAKE_XCODE_ATTRIBUTE_DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM" -DSIGN_LIBRARY=ON; fi
"$@"
printf '\nConfigured: %s\nBuild destination: %s\n' "$BUILD_DIR" "$DESTINATION"
