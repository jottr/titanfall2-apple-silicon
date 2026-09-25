#!/usr/bin/env bash
# Titanfall 2 on Apple Silicon — free stack: Sikarugir (CrossOver-derived Wine
# + D3DMetal) + Windows Steam + a manual EA-app bypass that sidesteps EA's
# broken-under-Wine installer (INST-14-1627, since ~2026-03).
#
# Usage: ./bootstrap.sh [phase]    (no arg = run all phases in order)
# Phases: preflight deps wrapper steam ea-bypass saves watchdog status
#         stop — tear a running wrapper down (menubar icons included)
# Idempotent — re-run after completing each HUMAN step.
set -euo pipefail

# ---- config (override via env) ----------------------------------------------
WRAPPER="${WRAPPER:-$HOME/Applications/Sikarugir/Titanfall2.app}"
ENGINE="WS12WineSikarugir10.0_6" # newest Sikarugir engine at time of writing
EA_VERSION="${EA_VERSION:-13.759.2.6273}"
# NOTE: the numeric suffix is a build id that changes per version — see README
# "Bumping the EA version" for how to discover the current URL from a burn log.
EA_MSI="${EA_MSI:-EAapp-${EA_VERSION}-14790298.msi}"
EA_MSI_URL="https://origin-a.akamaihd.net/EA-Desktop-Client-Download/installer-releases/${EA_MSI}"
EA_MSI_SHA256="c8f68016bd03c414a873d34b796cdc1f9b4ea6cdebb51720d3c429d95cb1ca94" # for the pinned default only
STEAM_URL="https://cdn.akamai.steamstatic.com/client/installer/SteamSetup.exe"
# Save location. Anywhere outside ~/Documents, ~/Desktop and ~/Downloads works —
# those three need a macOS privacy grant the wrapper cannot ask for twice.
SAVES="${SAVES:-$HOME/Library/Application Support/Titanfall2}"
TF2_APPID=1237970
TMP="${TMPDIR:-/tmp}"

PREFIX="$WRAPPER/Contents/SharedSupport/prefix"
C="$PREFIX/drive_c"
# a DLL every Wine process of this wrapper maps — the only reliable way to tell
# this wrapper's processes apart from another prefix's (see wrapper_pids)
WINE_MARKER="$WRAPPER/Contents/SharedSupport/wine/lib/wine/x86_64-windows/apisetschema.dll"
STARTUP_SCRIPT="$WRAPPER/Contents/Resources/Scripts/StartupScript"
# EA installs each version into its own dir and points an unversioned symlink at
# the active one; everything else (registry, its own destager) resolves through
# that symlink. Stage into the versioned dir, then link it.
EA_ROOT="$C/Program Files/Electronic Arts/EA Desktop"
EA_BASE_WIN="C:\\Program Files\\Electronic Arts\\EA Desktop\\EA Desktop"
EA_STAGE="$EA_ROOT/${EA_VERSION}"
EA_LINK="$EA_ROOT/EA Desktop"

say()  { printf '\n\033[1m== %s\033[0m\n' "$*"; }
die()  { printf '\033[31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }
human(){ printf '\n\033[33mHUMAN STEP:\033[0m %s\nRe-run ./bootstrap.sh when done.\n' "$*"; exit 0; }

wine() { # run the wrapper's wine with the env it needs outside its launcher
  WINEPREFIX="$PREFIX" \
  DYLD_FALLBACK_LIBRARY_PATH="$WRAPPER/Contents/Frameworks:$WRAPPER/Contents/SharedSupport/wine/lib" \
  "$WRAPPER/Contents/SharedSupport/wine/bin/wine" "$@"
}
wineserver() { WINEPREFIX="$PREFIX" \
  DYLD_FALLBACK_LIBRARY_PATH="$WRAPPER/Contents/Frameworks:$WRAPPER/Contents/SharedSupport/wine/lib" \
  "$WRAPPER/Contents/SharedSupport/wine/bin/wineserver" "$@"; }
wine_wait() { wineserver -w; }

# Wine's "Windows" processes carry no trace of their wrapper in argv, so identify
# them by a DLL only this wrapper's engine maps — precise, and ~0.1s.
wrapper_pids() { lsof -t "$WINE_MARKER" 2>/dev/null; }
server_alive() { pgrep -qf "$WRAPPER/.*wineserver"; }
no_wine_running() { [ -z "$(wrapper_pids)" ]; }

# Wine processes ignore SIGTERM; a dead wineserver leaves them reachable only here.
kill_wrapper_pids() {
  local p; p=$(wrapper_pids)
  # shellcheck disable=SC2086  # deliberate split: $p is a list of pids
  [ -n "$p" ] && kill -9 $p 2>/dev/null
  return 0
}

# Tear the wrapper down, escalating only as far as needed. Steam and the EA app
# both persist state on exit, so start with the Windows end-session broadcast.
stop() {
  say stop
  if no_wine_running; then echo "nothing running"; return; fi
  if server_alive; then
    # only with a live server: against a dead prefix wineboot BOOTS it instead,
    # replaying the EA app's pending installers.
    wine wineboot -e -s >/dev/null 2>&1 || true
    for _ in $(seq 10); do
      if no_wine_running; then echo "wrapper stopped"; return; fi
      sleep 1
    done
    wineserver -k >/dev/null 2>&1 || true
    sleep 2
  fi
  if no_wine_running; then echo "wrapper stopped"; return; fi
  kill_wrapper_pids
  sleep 1
  no_wine_running || die "still running: $(wrapper_pids | tr '\n' ' ')"
  echo "wrapper stopped (forced)"
}

# ---- phases ------------------------------------------------------------------
preflight() {
  say preflight
  [ "$(uname -sm)" = "Darwin arm64" ] || die "needs an Apple Silicon Mac"
  [ "$(sw_vers -productVersion | cut -d. -f1)" -ge 15 ] || die "needs macOS 15+ (AVX under Rosetta)"
  # only gates the ~64 GB first install — re-runs repair an existing one, and
  # blocking those on free space makes the recovery path unusable when it matters
  if [ ! -d "$C/Program Files (x86)/Steam/steamapps/common/Titanfall2" ]; then
    local free; free=$(df -g /System/Volumes/Data | awk 'NR==2{print $4}')
    [ "$free" -ge 80 ] || die "need >=80 GB free for the install, have ${free} GB"
  fi
  pgrep -q oahd || softwareupdate --install-rosetta --agree-to-license
  command -v brew >/dev/null || die "Homebrew (arm64) required: https://brew.sh"
  echo "ok"
}

deps() {
  say deps
  brew list --cask sikarugir &>/dev/null || {
    brew tap-info Sikarugir-App/sikarugir &>/dev/null || brew trust Sikarugir-App/sikarugir 2>/dev/null || true
    brew install --cask Sikarugir-App/sikarugir/sikarugir
  }
  command -v msiextract >/dev/null || brew install msitools
  echo "ok"
}

wrapper() {
  say wrapper
  [ -d "$WRAPPER" ] && { echo "ok ($WRAPPER)"; return; }
  human "Create the wrapper in 'Sikarugir Creator' (/Applications) — engine
  ${ENGINE}, blank wrapper '$(basename "${WRAPPER%.app}")', D3DMetal, vcruns.
  Follow README.md > 'Wrapper creation, click by click'."
}

steam() {
  say steam
  local steam_dir="$C/Program Files (x86)/Steam"
  if [ ! -f "$steam_dir/steam.exe" ]; then
    [ -f "$TMP/SteamSetup.exe" ] || curl -fL -o "$TMP/SteamSetup.exe" "$STEAM_URL"
    echo "installing Steam silently into the prefix..."
    wine "$TMP/SteamSetup.exe" /S; wine_wait
  fi
  /usr/libexec/PlistBuddy -c 'Set "Program Name and Path" "/Program Files (x86)/Steam/steam.exe"' \
    "$WRAPPER/Contents/Info.plist"
  [ -d "$steam_dir/steamapps/common/Titanfall2" ] && { echo "ok (TF2 installed)"; return; }
  human "Launch $(basename "$WRAPPER"), log in to Steam, install Titanfall 2
  (default location — must stay on C:), then FULLY QUIT Steam (Steam menu > Exit)."
}

ea-bypass() {
  say ea-bypass
  no_wine_running || die "quit Steam/the wrapper first — registry edits need Wine stopped"

  # Any complete version will do: once EA self-updated past the pin, the repair
  # below only needs the symlink and registry, not a fresh MSI.
  if ! (ea_newest) >/dev/null 2>&1; then
    if [ ! -f "$TMP/$EA_MSI" ]; then curl -fL -o "$TMP/$EA_MSI" "$EA_MSI_URL"; fi
    if [ "$EA_MSI" = "EAapp-13.759.2.6273-14790298.msi" ]; then
      echo "$EA_MSI_SHA256  $TMP/$EA_MSI" | shasum -a 256 -c - || die "MSI checksum mismatch"
    else
      echo "WARN: non-default EA version — no pinned checksum, trusting TLS + EA host"
    fi

    local x="$TMP/ea-extract.$$"
    mkdir -p "$x"; (cd "$x" && msiextract "$TMP/$EA_MSI" >/dev/null)
    mkdir -p "$EA_STAGE" "$C/Program Files (x86)/Origin"
    cp -R "$x/Electronic Arts/EA Desktop/EA Desktop" "$EA_STAGE/"
    for shim in Origin.exe OriginClient.exe OriginClientService.exe; do
      cp "$x/Electronic Arts/EA Desktop/EA Desktop/OriginLegacyCompatibility.exe" \
         "$C/Program Files (x86)/Origin/$shim"
    done
    rm -rf "$x"
  fi

  # Point the symlink at the newest staged version. The EA app self-updates by
  # staging a new versioned dir and swapping this symlink — a step its destager
  # cannot do under Wine (destage code 21), after which it blanks the link2ea
  # handler and every path in the registry dangles. Re-running repairs that.
  if [ -d "$EA_LINK" ] && [ ! -L "$EA_LINK" ]; then
    echo "note: $EA_LINK is a real directory (EA destaged it itself) — leaving it"
  else
    ln -sfn "$(ea_newest)/EA Desktop" "$EA_LINK"
  fi

  local reg="$TMP/ea-bypass.$$.reg"
  ea_reg > "$reg"
  wine regedit /S "$reg"; wine_wait; rm -f "$reg"
  grep -q "EABackgroundService" "$PREFIX/system.reg" || die "registry import failed"
  echo "ok"
}

saves() {
  say saves
  # Titanfall 2 writes saves to the Windows "My Documents" folder, which Wine
  # maps to ~/Documents — behind a macOS privacy prompt. Denying that prompt
  # leaves EA unable to see any local save (ErrorCloudDataCorruptedNoLocal) and
  # it blocks the launch on a "Cloud data is corrupted" dialog. Point the folder
  # somewhere outside ~/Documents so the game needs no Documents grant at all.
  mkdir -p "$SAVES"
  local old="$HOME/Documents/Respawn"
  if [ -d "$old" ]; then
    if [ -e "$SAVES/Respawn" ]; then
      echo "WARN: saves in both $old and $SAVES/Respawn — leaving the old copy alone"
    else
      mv "$old" "$SAVES/Respawn"; echo "moved $old -> $SAVES/Respawn"
    fi
  fi

  no_wine_running || die "quit Steam/the wrapper first — registry edits need Wine stopped"
  local reg="$TMP/tf2-saves.$$.reg"
  saves_reg > "$reg"
  wine regedit /S "$reg"; wine_wait; rm -f "$reg"
  grep -qF "$(saves_win)" "$PREFIX/user.reg" || die "shell-folder pin failed"
  echo "ok ($SAVES)"
}

# The wrapper is NSBGOnly (no Dock icon, no Cmd-Q) and its launcher waits for the
# Wine session, not for the game — so quitting Titanfall left Steam and the EA
# services running as unclickable menubar icons. Give the session a supervisor
# that ends it when the game does.
#
# The supervisor runs on the macOS side. It used to be a C:\launch.cmd the
# wrapper booted instead of Steam, but a .cmd needs a console, and that console
# window opens on top of the EA activation window the game shows at launch —
# black screen, no visible way forward, game waiting on a dialog behind it.
# Nothing Windows-side is needed anyway: ps reports a Wine process under its
# Windows path, so the game is as visible from here as from tasklist.
watchdog() {
  say watchdog
  rm -f "$C/launch.cmd"

  cat > "$STARTUP_SCRIPT" <<'SH'
#!/bin/sh
# Generated by bootstrap.sh — edit there, not here.
cd "$(dirname "$0")/../../"
CONTENTSFOLD="$PWD"

marker="$CONTENTSFOLD/SharedSupport/wine/lib/wine/x86_64-windows/apisetschema.dll"
# A live session means the user double-clicked twice — leave it strictly alone.
pgrep -qf "$CONTENTSFOLD/.*wineserver" && exit 0
# Clear a previous session's leftovers. Only signals can reach those — their
# wineserver is gone, so they answer to nothing else, and their menubar icons
# never go away on their own.
stale=$(lsof -t "$marker" 2>/dev/null)
[ -n "$stale" ] && kill -9 $stale 2>/dev/null

wine() {
  WINEPREFIX="$CONTENTSFOLD/SharedSupport/prefix" \
  DYLD_FALLBACK_LIBRARY_PATH="$CONTENTSFOLD/Frameworks:$CONTENTSFOLD/SharedSupport/wine/lib" \
  "$CONTENTSFOLD/SharedSupport/wine/bin/wine" "$@"
}

# The EA app self-updates by staging a new versioned dir and swapping the
# "EA Desktop" symlink, a swap its destager cannot do under Wine. The link then
# dangles, EA blanks the link2ea handler, and Steam's launch of the game fails
# with "no Windows program configured". Repair both before Wine starts; this is
# what ./bootstrap.sh ea-bypass does, minus the MSI.
ea="$CONTENTSFOLD/SharedSupport/prefix/drive_c/Program Files/Electronic Arts/EA Desktop"
if [ -L "$ea/EA Desktop" ]; then
  new=$(ls -d "$ea"/*/"EA Desktop/EADesktop.exe" 2>/dev/null | sort -V | tail -1)
  [ -n "$new" ] && ln -sfn "$(dirname "$new")" "$ea/EA Desktop"
fi
grep -A2 -F '[Software\\Classes\\link2ea\\shell\\open\\command]' \
  "$CONTENTSFOLD/SharedSupport/prefix/system.reg" 2>/dev/null | grep -qx '@=""' &&
  wine reg add 'HKLM\Software\Classes\link2ea\shell\open\command' /ve /f \
    /d '"C:\Program Files\Electronic Arts\EA Desktop\EA Desktop\Link2EA.exe" "%1"' \
    >/dev/null 2>&1

# Supervise this session in the background; Wine has not started yet.
(
  steam='C:\Program Files (x86)\Steam\steam.exe'
  game='C:\Program Files (x86)\Steam\steamapps\common\Titanfall2\Titanfall2.exe'
  # scoped to this wrapper's processes: another prefix running the same paths
  # must not count, and after teardown nothing must match at all
  up() {
    pids=$(lsof -t "$marker" 2>/dev/null) || return 1
    [ -n "$pids" ] || return 1
    ps -p $pids -o comm= 2>/dev/null | grep -qxF "$1"
  }

  # Phase 1: wait for Steam to register. Until it has, "Steam is gone" below
  # cannot tell "not up yet" from "quit", and the cold-start race would tear the
  # session down seconds after launch. The game counts as progress too, so a
  # missed Steam match can never tear down a session that got as far as playing.
  # ~10 min, generous because Steam may update itself first.
  n=0
  until up "$steam" || up "$game"; do
    n=$((n + 1))
    [ "$n" -ge 120 ] && exit 0  # nothing came up — nothing to tear down
    sleep 5
  done

  # Phase 2: wait for the game. Steam vanishing now is a real exit (failed
  # launch, or quit during the EA login) — go straight to teardown.
  until up "$game"; do
    up "$steam" || break
    sleep 5
  done

  # Phase 3: game is up — poll until it exits.
  while up "$game"; do sleep 5; done

  # WM_QUERYENDSESSION/WM_ENDSESSION: Steam and EA save state and quit
  # themselves, their tray icons go with them, wineserver exits with the last
  # process. Signals are the fallback in ./bootstrap.sh stop, not the default.
  # Only against a live session — on a dead prefix wineboot BOOTS one instead,
  # replaying the EA app's pending installers.
  [ -n "$(lsof -t "$marker" 2>/dev/null)" ] || exit 0
  wine wineboot -e -s
) >/dev/null 2>&1 &

exit 0
SH
  chmod +x "$STARTUP_SCRIPT"

  /usr/libexec/PlistBuddy -c 'Set "Program Name and Path" "/Program Files (x86)/Steam/steam.exe"' \
    "$WRAPPER/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set \"Program Flags\" \"-no-browser -silent -applaunch $TF2_APPID\"" \
    "$WRAPPER/Contents/Info.plist"
  echo "ok — double-click $(basename "$WRAPPER") to play (first EA login is in-flow)"
  echo "     quitting the game now tears the whole session down"
}

status() {
  say status
  printf '%-28s %s\n' \
    "wrapper"        "$([ -d "$WRAPPER" ] && echo yes || echo no)" \
    "steam"          "$([ -f "$C/Program Files (x86)/Steam/steam.exe" ] && echo yes || echo no)" \
    "titanfall2"     "$([ -d "$C/Program Files (x86)/Steam/steamapps/common/Titanfall2" ] && echo yes || echo no)" \
    "ea bypass"      "$([ -f "$EA_LINK/EADesktop.exe" ] && echo "yes ($(basename "$(dirname "$(readlink "$EA_LINK")")"))" || echo no)" \
    "saves"          "$(grep -qF "$(saves_win)" "$PREFIX/user.reg" 2>/dev/null && echo "$SAVES" || echo "NOT pinned (~/Documents — needs a macOS grant)")" \
    "watchdog"       "$(grep -q 'Phase 3' "$STARTUP_SCRIPT" 2>/dev/null && [ -n "$(/usr/libexec/PlistBuddy -c 'Print "Program Flags"' "$WRAPPER/Contents/Info.plist" 2>/dev/null)" ] && echo yes || echo no)" \
    "running"        "$(no_wine_running && echo no || echo "yes ($(wrapper_pids | wc -l | tr -d ' ') procs, server $(server_alive && echo up || echo DEAD))")"
}

saves_win() { # $SAVES as a .reg-ready Windows path (Z: is Wine's view of /)
  # .reg string values need doubled backslashes; sed, because bash's ${//} eats
  # its own escaping and silently emits single ones
  printf '%s' "Z:${SAVES//\//\\}" | sed 's/\\/\\\\/g'
}

saves_reg() { # both keys — apps read either one
  cat <<EOF
Windows Registry Editor Version 5.00

[HKEY_CURRENT_USER\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Shell Folders]
"Personal"="$(saves_win)"

[HKEY_CURRENT_USER\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\User Shell Folders]
"Personal"="$(saves_win)"
EOF
}

ea_newest() { # newest complete versioned EA dir, ignoring the symlink itself
  local d best=""
  for d in "$EA_ROOT"/*/; do
    [ -L "${d%/}" ] && continue
    [ -f "$d/EA Desktop/EADesktop.exe" ] || continue
    best="$(printf '%s\n%s\n' "$best" "${d%/}" | sort -V | tail -1)"
  done
  [ -n "$best" ] || die "no staged EA Desktop under $EA_ROOT — re-run ea-bypass"
  printf '%s\n' "$best"
}

ea_reg() { # registry recipe (CodeWeavers forum, 2026-03) parametrized on version
  local base="${EA_BASE_WIN//\\/\\\\}" # .reg string values need doubled backslashes
  cat <<EOF
Windows Registry Editor Version 5.00

[HKEY_LOCAL_MACHINE\\Software\\Electronic Arts\\EA Desktop]
"InstallSuccessful"="true"
"IsUnavailable"=dword:00000000
"EaConnectLink2EAAppPath"="${base}\\\\Link2EA.exe"

[HKEY_LOCAL_MACHINE\\Software\\Wow6432Node\\Electronic Arts\\EA Desktop]
"InstallSuccessful"="true"
"IsUnavailable"=dword:00000000
"EaConnectLink2EAAppPath"="${base}\\\\Link2EA.exe"

[HKEY_LOCAL_MACHINE\\Software\\Electronic Arts\\EA Core]
"ClientPath"="${base}\\\\legacyPM\\\\OriginLegacyCLI.exe"
"ClientAccessDLLPath"="${base}\\\\legacyPM\\\\CmdPortalClient.dll"
"ClientVersion"="7.0.0.1"
"EADM6InstallDir"="${base}\\\\legacyPM"
"EADM6Version"="7.0.0.1"

[HKEY_LOCAL_MACHINE\\Software\\Wow6432Node\\Electronic Arts\\EA Core]
"ClientPath"="${base}\\\\legacyPM\\\\OriginLegacyCLI.exe"
"ClientAccessDLLPath"="${base}\\\\legacyPM\\\\CmdPortalClient.dll"
"ClientVersion"="7.0.0.1"
"EADM6InstallDir"="${base}\\\\legacyPM"
"EADM6Version"="7.0.0.1"

[HKEY_LOCAL_MACHINE\\Software\\Origin]
"ClientPath"="C:\\\\Program Files (x86)\\\\Origin\\\\Origin.exe"
"InstallDir"="C:\\\\Program Files (x86)\\\\Origin"

[HKEY_LOCAL_MACHINE\\Software\\Wow6432Node\\Origin]
"ClientPath"="C:\\\\Program Files (x86)\\\\Origin\\\\Origin.exe"
"InstallDir"="C:\\\\Program Files (x86)\\\\Origin"
"ClientVersion"="10.5.122.52971"

[HKEY_LOCAL_MACHINE\\Software\\Classes\\link2ea]
@="URL:link2ea Protocol"
"URL Protocol"=""

[HKEY_LOCAL_MACHINE\\Software\\Classes\\link2ea\\shell]

[HKEY_LOCAL_MACHINE\\Software\\Classes\\link2ea\\shell\\open]

[HKEY_LOCAL_MACHINE\\Software\\Classes\\link2ea\\shell\\open\\command]
@="\\"${base}\\\\Link2EA.exe\\" \\"%1\\""

[HKEY_LOCAL_MACHINE\\System\\CurrentControlSet\\Services\\EABackgroundService]
"Type"=dword:00000010
"Start"=dword:00000002
"ErrorControl"=dword:00000001
"ImagePath"="${base}\\\\EABackgroundService.exe"
"DisplayName"="EABackgroundService"
"ObjectName"="LocalSystem"
EOF
}

# ---- main --------------------------------------------------------------------
if [ $# -gt 0 ]; then "$1"; else
  preflight; deps; wrapper; steam; ea-bypass; saves; watchdog; status
fi
