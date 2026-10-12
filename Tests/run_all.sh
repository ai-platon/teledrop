#!/bin/zsh
# Runs every TeleDrop test: build checks, logic tests, visual tests (both themes, all languages,
# every island state, every setup page, positions next to Coucou), and a CPU check.
# Restores the user's language/theme settings at the end. Results: Tests/shots/*.png + summary.
cd "$(dirname "$0")/.."
ROOT=$PWD
SHOTS=Tests/shots/all
rm -rf $SHOTS; mkdir -p $SHOTS
DOMAIN=app.teledrop.TeleDrop
TMP=${TMPDIR:-/tmp}
PASS=0; FAIL=0
ok()   { print "  ✅ $1"; PASS=$((PASS+1)); }
bad()  { print "  ❌ $1"; FAIL=$((FAIL+1)); }
post() { osascript -l JavaScript -e "ObjC.import('Foundation'); \$.NSDistributedNotificationCenter.defaultCenter.postNotificationNameObjectUserInfoDeliverImmediately('$DOMAIN.test', '$1', \$(), true)" >/dev/null; }
relaunch() { pkill -x TeleDrop; sleep 1; open /Applications/TeleDrop.app; sleep 3; }
W=$(osascript -l JavaScript -e "ObjC.import('AppKit'); \$.NSScreen.mainScreen.frame.size.width")

# Remember the user's settings
OLD_LANG=$(defaults read $DOMAIN language 2>/dev/null || echo en)
OLD_HW=$(defaults read $DOMAIN halloween 2>/dev/null || echo "")

print "1. Build"
./build.sh >/dev/null 2>&1 && ok "app builds and installs" || bad "build failed"
lipo -archs /Applications/TeleDrop.app/Contents/MacOS/TeleDrop | grep -q "x86_64 arm64" && ok "universal binary (Intel + Apple Silicon)" || bad "not universal"
codesign --verify --deep /Applications/TeleDrop.app 2>/dev/null && ok "code signature is valid" || bad "signature invalid"
[[ $(ls /Applications/TeleDrop.app/Contents/Resources/Sounds/*.wav | wc -l) -ge 19 ]] && ok "all sounds are bundled" || bad "sounds missing"
for w in platonious claude bobr; do
  strings -a /Applications/TeleDrop.app/Contents/MacOS/TeleDrop | grep -qi $w && bad "binary contains '$w'" || ok "binary has no '$w'"
done

print "2. Logic"
mkdir -p $TMP/teledrop-logic-src && cp Tests/LogicTests.swift $TMP/teledrop-logic-src/main.swift
swiftc -swift-version 5 $TMP/teledrop-logic-src/main.swift Sources/Telegram.swift Sources/Settings.swift Sources/Lang.swift \
  Sources/Log.swift Sources/Mascot.swift Sources/Layout.swift -o $TMP/teledrop-logic 2>/dev/null && $TMP/teledrop-logic \
  && ok "logic tests" || bad "logic tests"

print "3. Island — every state, both themes, all languages"
swiftc -O Tests/winid.swift -o $TMP/teledrop-winid 2>/dev/null
swiftc -O Tests/contact.swift -o $TMP/teledrop-contact 2>/dev/null
SHEET=()
for theme in classic halloween; do
  defaults write $DOMAIN halloween -bool $([[ $theme == halloween ]] && echo true || echo false)
  for lang in en uk ru; do
    defaults write $DOMAIN language -string $lang
    relaunch
    states=(peek hover compact sending done error)
    [[ $lang != en ]] && states=(hover done)
    for st in $states; do
      post $st; sleep 1.3
      f=$SHOTS/island-$theme-$lang-$st.png
      screencapture -x -R "$(( W / 2 - 340 )),0,980,200" $f && SHEET+=("$theme $lang $st=$f")
    done
    post hidden; sleep 0.5
    # setup window pages
    pages=(create token start done settings)
    [[ $lang != en ]] && pages=(settings)
    for pg in $pages; do
      post "setup:$pg"; sleep 1.3
      id=$($TMP/teledrop-winid) && screencapture -x -o -l $id $SHOTS/setup-$theme-$lang-$pg.png && SHEET+=("setup $theme $lang $pg=$SHOTS/setup-$theme-$lang-$pg.png")
    done
    osascript -e 'tell application "System Events" to keystroke "w" using command down' 2>/dev/null
  done
done
grep -q "phase hidden → peek" ~/Library/Logs/TeleDrop.log && ok "island state changes are logged"

print "4. Positions"
defaults write $DOMAIN halloween -bool false; defaults write $DOMAIN language -string en; relaunch
if pgrep -x Coucou >/dev/null; then
  post peek; sleep 2; screencapture -x -R 0,0,$W,110 $SHOTS/pos-coucou.png; post hidden
  SHEET+=("next to Coucou=$SHOTS/pos-coucou.png")
  grep -q "coucou edges" ~/Library/Logs/TeleDrop.log && ok "Coucou's edges are measured" || bad "Coucou not measured"
  osascript -e 'quit app "Coucou"'; sleep 2
  post peek; sleep 2; screencapture -x -R 0,0,$W,110 $SHOTS/pos-centered.png; post hidden
  SHEET+=("no Coucou (centered)=$SHOTS/pos-centered.png")
  open -a Coucou; sleep 3
  pgrep -x Coucou >/dev/null && ok "Coucou relaunched" || bad "Coucou did not relaunch"
else
  post peek; sleep 2; screencapture -x -R 0,0,$W,110 $SHOTS/pos-centered.png; post hidden
  SHEET+=("no Coucou (centered)=$SHOTS/pos-centered.png")
fi

print "5. Performance (demo)"
post demo; sleep 0.5
CPU=$(top -l 3 -s 1 -stats command,cpu -pid $(pgrep -x WindowServer) | awk '/WindowServer/ {v=$2} END {print int(v)}')
(( CPU < 70 )) && ok "WindowServer during demo: ${CPU}% (< 70%)" || bad "WindowServer during demo: ${CPU}%"
sleep 3

# Restore the user's settings
defaults write $DOMAIN language -string $OLD_LANG
[[ -n $OLD_HW ]] && defaults write $DOMAIN halloween -bool $([[ $OLD_HW == 1 ]] && echo true || echo false) || defaults delete $DOMAIN halloween 2>/dev/null
relaunch

$TMP/teledrop-contact Tests/shots/all-island.png 2 "${(@)SHEET:#setup*}" >/dev/null
$TMP/teledrop-contact Tests/shots/all-setup.png 4 "${(@M)SHEET:#setup*}" >/dev/null
print "\nPassed: $PASS   Failed: $FAIL"
print "Sheets: Tests/shots/all-island.png, Tests/shots/all-setup.png"
