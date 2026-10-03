#!/usr/bin/env bash
# Archives AltonApp (AppStore config) and uploads to App Store Connect.
#
# uploadSymbols is DISABLED (see ExportOptions/AppStore.plist): Google's binary
# SPM frameworks (GoogleAdsOnDeviceConversion, GoogleAppMeasurement,
# GoogleAppMeasurementIdentitySupport) ship without dSYMs, so Apple's symbol
# upload fails with "Upload Symbols Failed" warnings. Firebase Crashlytics
# handles crash symbolication via its own "Upload Crashlytics dSYMs" build
# phase, so uploading symbols to Apple is redundant.
#
# Usage:
#   Scripts/distribute-appstore.sh              # archive + upload to App Store Connect
#   Scripts/distribute-appstore.sh --export     # archive + export IPA (no upload)
#   Scripts/distribute-appstore.sh --archive-only
#
# Requires: Xcode command line tools (xcodebuild). xcpretty is used if present.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXPORT_OPTIONS_SRC="$ROOT/ExportOptions/AppStore.plist"
PROJECT="$ROOT/AltonApp.xcodeproj"
SCHEME="AltonApp AppStore"
CONFIG="AppStore"
DERIVED_DATA="$ROOT/.derivedData"
BUILD_DIR="$ROOT/build"
TEAM_ID="X6GV877JLH"

MODE="upload"
case "${1:-}" in
  --export)       MODE="export" ;;
  --archive-only) MODE="archive-only" ;;
  "")             MODE="upload" ;;
  *) echo "distribute-appstore: unknown flag '$1'" >&2
     echo "usage: $0 [--export|--archive-only]" >&2
     exit 2 ;;
esac

if [[ ! -f "$EXPORT_OPTIONS_SRC" ]]; then
  echo "distribute-appstore: missing $EXPORT_OPTIONS_SRC" >&2
  exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
ARCHIVE_PATH="$DERIVED_DATA/Archives/AltonApp-$STAMP.xcarchive"
mkdir -p "$(dirname "$ARCHIVE_PATH")"

# For --export we switch destination to "export" so xcodebuild writes an IPA
# instead of uploading. Mutate a temp copy, never the source plist.
EFFECTIVE_OPTIONS="$EXPORT_OPTIONS_SRC"
if [[ "$MODE" == "export" ]]; then
  EFFECTIVE_OPTIONS="$(mktemp -d)/ExportOptions.plist"
  cp "$EXPORT_OPTIONS_SRC" "$EFFECTIVE_OPTIONS"
  /usr/libexec/PlistBuddy -c "Set :destination export" "$EFFECTIVE_OPTIONS"
  trap 'rm -rf "$(dirname "$EFFECTIVE_OPTIONS")"' EXIT
fi

# Pipe through xcpretty when available, otherwise pass output through.
pipe_xcpretty() {
  if command -v xcpretty >/dev/null 2>&1; then
    xcpretty
  else
    cat
  fi
}

echo "==> archive scheme='$SCHEME' config='$CONFIG' -> $ARCHIVE_PATH"
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -archivePath "$ARCHIVE_PATH" \
  -derivedDataPath "$DERIVED_DATA" \
  -destination "generic/platform=iOS" \
  CODE_SIGN_STYLE=Automatic \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  2>&1 | pipe_xcpretty

if [[ "$MODE" == "archive-only" ]]; then
  echo "==> archive-only complete: $ARCHIVE_PATH"
  exit 0
fi

EXPORT_DIR="$BUILD_DIR/Export/$STAMP"
mkdir -p "$EXPORT_DIR"

echo "==> exportArchive mode=$MODE options=$EFFECTIVE_OPTIONS -> $EXPORT_DIR"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportOptionsPlist "$EFFECTIVE_OPTIONS" \
  -exportPath "$EXPORT_DIR" \
  2>&1 | pipe_xcpretty

if [[ "$MODE" == "upload" ]]; then
  echo "==> uploaded to App Store Connect (symbols NOT sent to Apple — Crashlytics handles crash reports)"
else
  echo "==> IPA exported to: $EXPORT_DIR"
fi
