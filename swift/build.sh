#!/bin/bash
# Builds M4BtoMP3 and packages it as a proper macOS .app bundle.
# SwiftUI apps require an app bundle to get a window server connection —
# running the raw binary directly from the terminal produces no window.

set -e

BINARY="M4BtoMP3"
APP="${BINARY}.app"

echo "Building ${BINARY}..."
swift build -c release

echo "Packaging ${APP}..."
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS"
mkdir -p "${APP}/Contents/Resources"

cp ".build/release/${BINARY}" "${APP}/Contents/MacOS/${BINARY}"
cp "Info.plist"                "${APP}/Contents/Info.plist"
cp "AppIcon.icns"              "${APP}/Contents/Resources/AppIcon.icns"

echo ""
echo "Done. Launch with:"
echo "  open ${APP}"
