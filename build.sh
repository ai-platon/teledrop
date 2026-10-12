#!/bin/zsh
# Builds a universal TeleDrop.app (Apple Silicon + Intel) and installs it into /Applications.
set -e
cd "$(dirname "$0")"
APP=build/TeleDrop.app
rm -rf build
mkdir -p $APP/Contents/MacOS $APP/Contents/Resources
for arch in arm64 x86_64; do
  swiftc -O -swift-version 5 -target $arch-apple-macos14.0 -file-prefix-map "$PWD=." Sources/*.swift -o build/TeleDrop-$arch
done
lipo -create build/TeleDrop-arm64 build/TeleDrop-x86_64 -output $APP/Contents/MacOS/TeleDrop
cp Info.plist $APP/Contents/
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns $APP/Contents/Resources/
cp -R Resources/Sounds $APP/Contents/Resources/
# Stable self-signed identity keeps macOS permissions across rebuilds; falls back to ad-hoc.
ID=$(security find-identity -p codesigning | awk "/TeleDrop Dev/ {print \$2; exit}")
codesign --force --sign "${ID:--}" $APP
[[ "$1" == "--no-install" ]] && exit 0
true
pkill -x TeleDrop || true
rm -rf /Applications/TeleDrop.app
ditto $APP /Applications/TeleDrop.app
echo "Installed /Applications/TeleDrop.app"
