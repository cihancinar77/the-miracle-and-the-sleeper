#!/bin/zsh
set -e
cd "$(dirname "$0")"
FINAL="The Miracle and the Sleeper.app"
BUILD=.build
APP="$BUILD/$FINAL"  # assemble here, move into place when complete
rm -rf $BUILD
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" $BUILD
for arch in arm64 x86_64; do
  swiftc -O -parse-as-library -target $arch-apple-macos13.0 SleepTimer.swift -o $BUILD/MiracleSleeper-$arch
done
lipo -create $BUILD/MiracleSleeper-arm64 $BUILD/MiracleSleeper-x86_64 -output "$APP/Contents/MacOS/MiracleSleeper"
swiftc -O MakeIcon.swift -o $BUILD/makeicon
$BUILD/makeicon $BUILD/AppIcon.iconset
iconutil -c icns $BUILD/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
cp Info.plist "$APP/Contents/"
codesign --force --sign - "$APP"
rm -rf "$FINAL"
mv "$APP" "$FINAL"
echo "Built $PWD/$FINAL"
