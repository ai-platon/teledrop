#!/bin/zsh
# Visual test of the setup window: opens each page and screenshots the window.
cd "$(dirname "$0")"
mkdir -p shots
[[ -x "${TMPDIR:-/tmp}/teledrop-winid" ]] || swiftc -O winid.swift -o "${TMPDIR:-/tmp}/teledrop-winid"
steps=(create token start done settings); (( $# )) && steps=("$@")
for s in $steps; do
  osascript -l JavaScript -e "ObjC.import('Foundation'); \$.NSDistributedNotificationCenter.defaultCenter.postNotificationNameObjectUserInfoDeliverImmediately('app.teledrop.TeleDrop.test', 'setup:$s', \$(), true)" >/dev/null
  sleep 1.3
  id=$("${TMPDIR:-/tmp}/teledrop-winid")
  [[ -n "$id" ]] && screencapture -x -o -l $id shots/setup-$s.png && echo shots/setup-$s.png
done
