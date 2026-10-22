#!/bin/bash
# usage: sign.sh DiskLens.app "Developer ID Application: ..."  — signs Sparkle's helpers inside-out, then the app.
set -euo pipefail
APP=$1; ID=$2; F="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
C=(codesign --force --options runtime --timestamp -s "$ID")
for x in "$F"/XPCServices/*.xpc "$F/Autoupdate" "$F/Updater.app" "$APP/Contents/Frameworks/Sparkle.framework"; do "${C[@]}" "$x"; done
"${C[@]}" "$APP"
codesign --verify --deep --strict "$APP"
