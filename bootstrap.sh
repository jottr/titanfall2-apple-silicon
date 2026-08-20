#!/usr/bin/env bash
# Titanfall 2 on Apple Silicon — free stack: Sikarugir (CrossOver-derived Wine
# + D3DMetal) + Windows Steam + a manual EA-app bypass that sidesteps EA's
# broken-under-Wine installer (INST-14-1627, since ~2026-03).
#
# Usage: ./bootstrap.sh [phase]    (no arg = run all phases in order)
# Phases: preflight deps wrapper steam ea-bypass saves launch-flags status
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
wine_wait() { WINEPREFIX="$PREFIX" \
  DYLD_FALLBACK_LIBRARY_PATH="$WRAPPER/Contents/Frameworks:$WRAPPER/Contents/SharedSupport/wine/lib" \
  "$WRAPPER/Contents/SharedSupport/wine/bin/wineserver" -w; }

no_wine_running() {
  ! pgrep -qf "$WRAPPER/Contents/SharedSupport/wine" &&
  ! pgrep -qf 'steamwebhelper|steam\.exe|EADesktop|EABackgroundService'
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

  if [ ! -f "$EA_STAGE/EA Desktop/EADesktop.exe" ]; then
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

launch-flags() {
  say launch-flags
  /usr/libexec/PlistBuddy -c "Set \"Program Flags\" \"-no-browser -silent -applaunch $TF2_APPID\"" \
    "$WRAPPER/Contents/Info.plist"
  echo "ok — double-click $(basename "$WRAPPER") to play (first EA login is in-flow)"
}

status() {
  say status
  printf '%-28s %s\n' \
    "wrapper"        "$([ -d "$WRAPPER" ] && echo yes || echo no)" \
    "steam"          "$([ -f "$C/Program Files (x86)/Steam/steam.exe" ] && echo yes || echo no)" \
    "titanfall2"     "$([ -d "$C/Program Files (x86)/Steam/steamapps/common/Titanfall2" ] && echo yes || echo no)" \
    "ea bypass"      "$([ -f "$EA_LINK/EADesktop.exe" ] && echo "yes ($(basename "$(dirname "$(readlink "$EA_LINK")")"))" || echo no)" \
    "saves"          "$(grep -qF "$(saves_win)" "$PREFIX/user.reg" 2>/dev/null && echo "$SAVES" || echo "NOT pinned (~/Documents — needs a macOS grant)")" \
    "launch flags"   "$(/usr/libexec/PlistBuddy -c 'Print "Program Flags"' "$WRAPPER/Contents/Info.plist" 2>/dev/null || echo unset)"
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
  preflight; deps; wrapper; steam; ea-bypass; saves; launch-flags; status
fi
