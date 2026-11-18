#!/usr/bin/env bash
#
# Put the Rust core where the project expects it (Core/, gitignored):
#
#   Core/veltrioFFI.xcframework   (iOS + tvOS slices)
#   Core/Bindings/veltrio.swift
#
# Downloads `veltrio-core-apple-mobile-tvos.zip` from the veltrio-core release named in
# core.version (needs `gh` signed in with access to VeltrioApp/veltrio-core,
# or GH_TOKEN in CI). VELTRIO_CORE_DIR=../veltrio-core builds it from a
# local checkout instead.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/Core"
VERSION="$(tr -d '[:space:]' < "$ROOT/core.version")"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if [ -n "${VELTRIO_CORE_DIR:-}" ]; then
  CORE="$(cd "$VELTRIO_CORE_DIR" && pwd)"
  echo "==> Building the core from $CORE"
  VELTRIO_TVOS=1 "$CORE/scripts/package-ios.sh"
  cp "$CORE/dist/veltrio-core-apple-mobile.zip" "$TMP/veltrio-core-apple-mobile-tvos.zip"
else
  echo "==> veltrio-core $VERSION"
  gh release download "$VERSION" --repo VeltrioApp/veltrio-core --pattern veltrio-core-apple-mobile-tvos.zip --dir "$TMP"
fi

rm -rf "$OUT" && mkdir -p "$OUT"
unzip -q "$TMP/veltrio-core-apple-mobile-tvos.zip" -d "$OUT"
echo "==> Core/ ready"
