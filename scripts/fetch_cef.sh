#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CEFZIG_DIR="${CEFZIG_DIR:-$HOME/code/cefzig}"
CEF_VERSION="${CEF_VERSION:-142.5.0+142.0.17}"
CEF_BASE_URL="${CEF_BASE_URL:-https://cef-builds.spotifycdn.com}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/Libraries/CEF}"

if [[ ! -d "$CEFZIG_DIR" ]]; then
  echo "cefzig not found at $CEFZIG_DIR"
  echo "Set CEFZIG_DIR or clone https://github.com/mitchellh/cefzig"
  exit 1
fi

echo "Fetching CEF $CEF_VERSION via cefzig..."
pushd "$CEFZIG_DIR/examples/cef-client" >/dev/null
zig build -Dcef-version="$CEF_VERSION" -Dcef-base-url="$CEF_BASE_URL"

CEF_CACHE_DIR="$(ls -d .zig-cache/cef-cache/cef_macos_* 2>/dev/null | head -n 1 || true)"
if [[ -z "$CEF_CACHE_DIR" ]]; then
  CEF_CACHE_DIR="$(ls -d zig-cache/cef-cache/cef_macos_* 2>/dev/null | head -n 1 || true)"
fi
if [[ -z "$CEF_CACHE_DIR" ]]; then
  echo "CEF cache not found under cefzig examples."
  exit 1
fi

rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"
rsync -a "$CEF_CACHE_DIR/" "$OUTPUT_DIR/"
popd >/dev/null

echo "CEF extracted to $OUTPUT_DIR"
