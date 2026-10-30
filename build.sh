#!/bin/zsh
set -e
cd "$(dirname "$0")"
APP="The Miracle and the Sleeper.app"
BUILD=.build
rm -rf "$APP" $BUILD
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" $BUILD
swiftc -O -parse-as-library -target arm64-apple-macos13.0 SleepTimer.swift -o "$APP/Contents/MacOS/MiracleSleeper"
swiftc -O MakeIcon.swift -o $BUILD/makeicon
$BUILD/makeicon $BUILD/AppIcon.iconset
iconutil -c icns $BUILD/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
cp Info.plist "$APP/Contents/"
codesign --force --sign - "$APP"
echo "Built $PWD/$APP"
