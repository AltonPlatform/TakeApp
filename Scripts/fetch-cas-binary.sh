#!/usr/bin/env bash
# Downloads CleverAdsSolutions and extracts only the xcframework (SPM-safe layout).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/Vendor/CASBase"
VERSION="${CAS_VERSION:-4.8.0}"
URL="https://github.com/cleveradssolutions/CAS-iOS/releases/download/${VERSION}/CleverAdsSolutions-${VERSION}.zip"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "fetch-cas-binary: downloading ${URL}"
curl -fsSL "$URL" -o "$TMP/cas.zip"
unzip -q "$TMP/cas.zip" -d "$TMP/extracted"

if [[ ! -d "$TMP/extracted/CleverAdsSolutions.xcframework" ]]; then
  echo "fetch-cas-binary: CleverAdsSolutions.xcframework missing from zip" >&2
  exit 1
fi

rm -rf "$DEST/CleverAdsSolutions.xcframework"
cp -R "$TMP/extracted/CleverAdsSolutions.xcframework" "$DEST/"
# Optional companion resources from the same release (not required by SPM binaryTarget).
if [[ -d "$TMP/extracted/CASBaseResources.bundle" ]]; then
  rm -rf "$DEST/CASBaseResources.bundle"
  cp -R "$TMP/extracted/CASBaseResources.bundle" "$DEST/"
fi

echo "fetch-cas-binary: installed → $DEST/CleverAdsSolutions.xcframework"
