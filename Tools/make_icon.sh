#!/bin/zsh
# Regenerates Resources/AppIcon.icns.
set -e
cd "$(dirname "$0")/.."
T=$(mktemp -d)
cp Tools/MakeIcon.swift $T/main.swift
swiftc -swift-version 5 $T/main.swift Sources/Mascot.swift -o $T/makeicon
$T/makeicon $T/AppIcon.iconset
iconutil -c icns $T/AppIcon.iconset -o Resources/AppIcon.icns
cp $T/AppIcon.iconset/icon_512x512@2x.png Resources/AppIcon-1024.png
rm -rf $T
echo "Resources/AppIcon.icns"
