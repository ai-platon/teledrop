#!/bin/zsh
# Builds dist/TeleDrop.dmg: the app, a shortcut to /Applications and install notes.
set -e
cd "$(dirname "$0")"
./build.sh --no-install
STAGE=$(mktemp -d)/TeleDrop
mkdir -p $STAGE
ditto build/TeleDrop.app $STAGE/TeleDrop.app
ln -s /Applications $STAGE/Applications
cp "How to install.txt" $STAGE/
mkdir -p dist
rm -f dist/TeleDrop.dmg
hdiutil create -volname TeleDrop -srcfolder $STAGE -fs HFS+ -format UDZO -ov dist/TeleDrop.dmg >/dev/null
rm -rf $(dirname $STAGE)
echo "dist/TeleDrop.dmg ($(du -h dist/TeleDrop.dmg | cut -f1))"
