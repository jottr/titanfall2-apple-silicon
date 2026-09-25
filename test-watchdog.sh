#!/usr/bin/env bash
# Self-check for the supervisor bootstrap.sh writes into the wrapper's
# StartupScript. Builds a fake bundle, generates the real script into it, then
# fakes lsof/ps (which "Wine processes" exist), sleep (fast polls) and wine
# (records the teardown). Run: ./test-watchdog.sh
set -euo pipefail
cd "$(dirname "$0")"

STEAM='C:\Program Files (x86)\Steam\steam.exe'
GAME='C:\Program Files (x86)\Steam\steamapps\common\Titanfall2\Titanfall2.exe'
IDLE='C:\windows\system32\services.exe' # an EA/Wine service: outlives Steam
TICK=0.05                               # what the fake sleep really waits
STEP=0.6                                # long enough for several polls

root=$(mktemp -d); trap 'rm -rf "$root"' EXIT
app="$root/Titanfall2.app"; state="$root/state"; torndown="$root/torndown"
mkdir -p "$app/Contents/Resources/Scripts" "$root/bin" \
         "$app/Contents/SharedSupport/wine/lib/wine/x86_64-windows" \
         "$app/Contents/SharedSupport/wine/bin" \
         "$app/Contents/SharedSupport/prefix/drive_c"
: > "$app/Contents/SharedSupport/wine/lib/wine/x86_64-windows/apisetschema.dll"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Program Name and Path</key><string></string>
<key>Program Flags</key><string></string>
</dict></plist>
PLIST

WRAPPER="$app" ./bootstrap.sh watchdog >/dev/null

# fakes: lsof reports "a session exists", ps reports what is in it
printf '#!/bin/sh\n[ -s "%s" ] && echo 1\n' "$state" > "$root/bin/lsof"
# (the supervisor pid check asks the real ps)
printf '#!/bin/sh\ncase "$*" in *command=*) exec /bin/ps "$@";; esac\ncat "%s"\n' \
  "$state" > "$root/bin/ps"
printf '#!/bin/sh\nexec /bin/sleep %s\n' "$TICK"     > "$root/bin/sleep"
printf '#!/bin/sh\necho "$*" > "%s"\n' "$torndown" \
  > "$app/Contents/SharedSupport/wine/bin/wine"
chmod +x "$root/bin"/* "$app/Contents/SharedSupport/wine/bin/wine"
export PATH="$root/bin:$PATH"

set_state() { printf '%s\n' "$@" > "$state"; }
start()     { rm -f "$torndown"; "$app/Contents/Resources/Scripts/StartupScript"; }
settle()    { /bin/sleep "$STEP"; }
ok()        { [ -f "$torndown" ] || { echo "FAIL: $1 — no teardown" >&2; exit 1; }
              grep -q 'wineboot -e -s' "$torndown" ||
                { echo "FAIL: $1 — teardown was '$(cat "$torndown")'" >&2; exit 1; }
              echo "ok: $1"; }
no()        { [ ! -f "$torndown" ] || { echo "FAIL: $1 — tore down early" >&2; exit 1; }
              echo "ok: $1"; }

# 1. the normal path: Steam boots, game runs, game quits -> session ends
set_state "$IDLE"; start; settle;              no  "cold start does not tear down"
set_state "$IDLE" "$STEAM"; settle;            no  "Steam alone does not tear down"
set_state "$IDLE" "$STEAM" "$GAME"; settle;    no  "game running does not tear down"
set_state "$IDLE" "$STEAM"; settle;            ok  "game exit tears down"

# 2. quitting at the EA login: Steam goes away before any game appears
set_state "$IDLE"; start; settle
set_state "$IDLE" "$STEAM"; settle;            no  "waiting for the game"
set_state "$IDLE"; settle;                     ok  "Steam exit tears down"

# 4. an EA self-update left the symlink dangling: launch repoints it to the newest
ea="$app/Contents/SharedSupport/prefix/drive_c/Program Files/Electronic Arts/EA Desktop"
mkdir -p "$ea/13.768.7-1" "$ea/13.768.7-2/EA Desktop" "$ea/13.778.0-1/EA Desktop"
: > "$ea/13.768.7-2/EA Desktop/EADesktop.exe"; : > "$ea/13.778.0-1/EA Desktop/EADesktop.exe"
ln -s "$ea/13.768.7-1/EA Desktop" "$ea/EA Desktop"
set_state "$IDLE"; start
[ "$(readlink "$ea/EA Desktop")" = "$ea/13.778.0-1/EA Desktop" ] ||
  { echo "FAIL: EA link is $(readlink "$ea/EA Desktop")" >&2; exit 1; }
echo "ok: dangling EA link repaired"
settle

# 6. EA breaks itself mid-session: the supervisor repairs it on its next poll
set_state "$IDLE" "$STEAM"; start; settle
mkdir -p "$ea/13.796.0-1/EA Desktop"; : > "$ea/13.796.0-1/EA Desktop/EADesktop.exe"
rm -rf "$ea/13.778.0-1/EA Desktop"; settle
[ "$(readlink "$ea/EA Desktop")" = "$ea/13.796.0-1/EA Desktop" ] ||
  { echo "FAIL: mid-session EA link is $(readlink "$ea/EA Desktop")" >&2; exit 1; }
grep -q 'reg add' "$torndown" || { echo "FAIL: link2ea handler not restored" >&2; exit 1; }
echo "ok: mid-session EA breakage repaired"
set_state "$IDLE"; settle

# 5. a second launch stops the first launch's supervisor
set_state "$IDLE"; start; first=$(cat "$app/Contents/SharedSupport/supervisor.pid")
start; settle
! kill -0 "$first" 2>/dev/null || { echo "FAIL: old supervisor still running" >&2; exit 1; }
echo "ok: relaunch replaces the old supervisor"
settle

# 3. a session that never starts is not a session to tear down
set_state "$IDLE"; start; /bin/sleep 8;        no  "give up quietly"

echo "all ok"
