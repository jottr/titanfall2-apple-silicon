# Titanfall 2 on Apple Silicon — free, no CrossOver

Run the Titanfall 2 singleplayer campaign on an M-series Mac using only free
components: [Sikarugir](https://sikarugir.com/) (CrossOver-derived Wine +
Apple's D3DMetal), the Windows Steam client, and a scripted bypass for the EA
app's installer, which has been broken under Wine since ~March 2026
(`INST-14-1627`).

Nothing is redistributed here. The script downloads every component from its
vendor (Sikarugir via Homebrew, Steam from Valve's CDN, the EA app from EA's
CDN, with a pinned SHA-256). You need your own purchased copy of Titanfall 2
on Steam and your own EA account.

## Requirements

- Apple Silicon Mac, macOS 15+ (tested: M1 Pro / 16 GB / macOS 26)
- ~80 GB free disk
- arm64 Homebrew
- Titanfall 2 in your Steam library

## Usage

```sh
./bootstrap.sh
```

Run it repeatedly: each run advances as far as it can, then prints the next
**HUMAN STEP** and exits. The human steps, in order:

1. **Wrapper creation** (~6 clicks in Sikarugir Creator: engine download, blank
   wrapper, D3DMetal toggle, three winetricks runtimes)
2. **Steam login + Titanfall 2 install** (your credentials, ~64 GB download)
3. First launch: **EA account login** (once; the session persists)

Everything else — dependency installs, silent Steam setup, the EA bypass
(download, verify, extract, file placement, registry, service), launch
configuration — is automated. `./bootstrap.sh status` shows progress.

When it finishes, double-clicking the wrapper launches the game directly:
Steam runs headless (`-no-browser`), and the EA app auto-authenticates in the
background.

## How the EA bypass works

Titanfall 2 requires EA-app authentication at every launch, but the EA app's
installer dies under CrossOver-lineage Wine at its per-machine MSI configure
step (`0x80070643`, surfaced as `INST-14-1627`) — an EA-side change from
~2026-03-21 that no free Wine build fixes. The runtime is fine; only the
installer is broken.

So the script never runs the installer. It downloads the same MSI the
installer would fetch, extracts it natively with `msitools`, places the
payload at the path a real install uses, and writes the registry state +
`EABackgroundService` service definition a successful install would have
produced (recipe from a March 2026 CodeWeavers forum report, parametrized).
The game's bundled EA stub then sees a healthy install and proceeds to login.

## Bumping the EA version

An EA-app update may eventually demand a newer version than the pinned
`13.759.2.6273`. To find the current MSI URL: let the game's EA stub attempt
(and fail) an install once, then grep the burn log for the payload URL:

```sh
grep -ho 'https://[^ "]*\.msi' \
  "<wrapper>/Contents/SharedSupport/prefix/drive_c/users/"*/AppData/Local/Temp/EA_app_*.log
```

Then re-run with the discovered name (the build-id suffix is not derivable):

```sh
EA_MSI="EAapp-<version>-<buildid>.msi" ./bootstrap.sh ea-bypass
```

## Troubleshooting

| Symptom | Fix |
|---|---|
| `INST-14-1627` at game launch | Bypass not applied or EA version bumped — see above |
| EA login window blank/white | In the wrapper config, switch D3DMetal → DXMT; add `d3dcompiler_47` via winetricks |
| Choppy first session | Shader compilation warm-up — play 10–15 min, it settles |
| Steam window never appears | Post-update silent restart; quit fully and relaunch the wrapper |
| Game won't save | Keep the game on `C:` (it can't save across drives) |

## Known limitations

- Singleplayer focus. Multiplayer via [Northstar](https://northstar.tf/) is
  untested here (it also requires EA auth; drop the release zip into the
  `Titanfall2` folder and run `NorthstarLauncher.exe`).
- An EA-side update can re-break the bypass until the version is bumped.
- The wrapper-creation clicks resist automation (GUI-only in Sikarugir today).
