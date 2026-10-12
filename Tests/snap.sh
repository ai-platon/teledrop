#!/bin/zsh
# Visual test: puts TeleDrop into each state and screenshots the notch area.
# Usage: Tests/snap.sh [state ...]   (default: all states)   Output: Tests/shots/<state>.png
cd "$(dirname "$0")"
mkdir -p shots
states=(peek hover sending done error hidden); (( $# )) && states=("$@")

post() {
  osascript -l JavaScript -e "ObjC.import('Foundation'); \$.NSDistributedNotificationCenter.defaultCenter.postNotificationNameObjectUserInfoDeliverImmediately('app.teledrop.TeleDrop.test', '$1', \$(), true)" >/dev/null
}

# Notch-area rectangle in points: from just left of the notch to well right of it.
read W < <(osascript -l JavaScript -e "ObjC.import('AppKit'); \$.NSScreen.mainScreen.frame.size.width")
X=$(( W / 2 - 140 )); RECT="$X,0,720,170"

pgrep -x TeleDrop >/dev/null || { open ~/Applications/TeleDrop.app; sleep 2; }
for s in $states; do
  post "$s"; sleep 1.1
  screencapture -x -R "$RECT" "shots/$s.png" && echo "shots/$s.png"
done
post hidden
