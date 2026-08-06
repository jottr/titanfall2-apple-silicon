#!/usr/bin/env bash
# Titanfall 2 on Apple Silicon — free stack: Sikarugir (CrossOver-derived Wine
# + D3DMetal) + Windows Steam + a manual EA-app bypass that sidesteps EA's
# broken-under-Wine installer (INST-14-1627, since ~2026-03).
#
# Usage: ./bootstrap.sh [phase]    (no arg = run all phases in order)
# Phases: preflight deps wrapper steam ea-bypass launch-flags status
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
TF2_APPID=1237970
TMP="${TMPDIR:-/tmp}"

PREFIX="$WRAPPER/Contents/SharedSupport/prefix"
C="$PREFIX/drive_c"
EA_BASE_WIN="C:\\Program Files\\Electronic Arts\\EA Desktop\\${EA_VERSION}\\EA Desktop"
EA_BASE="$C/Program Files/Electronic Arts/EA Desktop/${EA_VERSION}"

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
  local free; free=$(df -g /System/Volumes/Data | awk 'NR==2{print $4}')
  [ "$free" -ge 80 ] || die "need >=80 GB free, have ${free} GB"
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
  human "In 'Sikarugir Creator' (/Applications):
  1. Install engine ${ENGINE} + latest wrapper version when prompted
  2. Create New Blank Wrapper named '$(basename "${WRAPPER%.app}")'
  3. Open the wrapper's Configure window:
     - tick 'Direct3D to Metal translation layer - (D3DMetal)'
     - Winetricks: install vcrun2010, vcrun2012, vcrun2022 (Silent on, then Run)"
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
  [ -f "$EA_BASE/EA Desktop/EADesktop.exe" ] && { echo "ok (already staged)"; return; }
  no_wine_running || die "quit Steam/the wrapper first — registry edits need Wine stopped"

  if [ ! -f "$TMP/$EA_MSI" ]; then curl -fL -o "$TMP/$EA_MSI" "$EA_MSI_URL"; fi
  if [ "$EA_MSI" = "EAapp-13.759.2.6273-14790298.msi" ]; then
    echo "$EA_MSI_SHA256  $TMP/$EA_MSI" | shasum -a 256 -c - || die "MSI checksum mismatch"
  else
    echo "WARN: non-default EA version — no pinned checksum, trusting TLS + EA host"
  fi

  local x="$TMP/ea-extract.$$"
  mkdir -p "$x"; (cd "$x" && msiextract "$TMP/$EA_MSI" >/dev/null)
  mkdir -p "$EA_BASE" "$C/Program Files (x86)/Origin"
  cp -R "$x/Electronic Arts/EA Desktop/EA Desktop" "$EA_BASE/"
  for shim in Origin.exe OriginClient.exe OriginClientService.exe; do
    cp "$x/Electronic Arts/EA Desktop/EA Desktop/OriginLegacyCompatibility.exe" \
       "$C/Program Files (x86)/Origin/$shim"
  done
  rm -rf "$x"

  local reg="$TMP/ea-bypass.$$.reg"
  ea_reg > "$reg"
  wine regedit /S "$reg"; wine_wait; rm -f "$reg"
  grep -q "EABackgroundService" "$PREFIX/system.reg" || die "registry import failed"
  echo "ok"
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
    "ea bypass"      "$([ -f "$EA_BASE/EA Desktop/EADesktop.exe" ] && echo yes || echo no)" \
    "launch flags"   "$(/usr/libexec/PlistBuddy -c 'Print "Program Flags"' "$WRAPPER/Contents/Info.plist" 2>/dev/null || echo unset)"
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
  preflight; deps; wrapper; steam; ea-bypass; launch-flags; status
fi
