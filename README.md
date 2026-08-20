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

## Quickstart

```sh
# 1. arm64 Homebrew (skip if `brew --prefix` already prints /opt/homebrew)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# 2. this repo
git clone https://github.com/jottr/titanfall2-apple-silicon.git && cd titanfall2-apple-silicon

# 3. run — repeat after each HUMAN STEP it prints
./bootstrap.sh
```

The first HUMAN STEP is wrapper creation, which is GUI-only — follow
[Wrapper creation, click by click](#wrapper-creation-click-by-click) when the
script stops there. The other two are Steam login/install and the one-time EA
login; see [Usage](#usage) for the full list.

The script installs the two casks/formulae it needs itself, so these are
informational — run them by hand only if you want them ahead of time:

```sh
brew install --cask Sikarugir-App/sikarugir/sikarugir   # Wine + D3DMetal
brew install msitools                                   # msiextract, for the EA MSI
```

Rosetta is installed automatically by the preflight phase if missing.

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

1. **Wrapper creation** — GUI only; see the click-by-click walkthrough below
2. **Steam login + Titanfall 2 install** (your credentials, ~64 GB download)
3. First launch: **EA account login** (once; the session persists)

Everything else — dependency installs, silent Steam setup, the EA bypass
(download, verify, extract, file placement, registry, service), save location,
launch configuration — is automated. `./bootstrap.sh status` shows progress.

Every phase is idempotent, so re-run the script any time something breaks. It
repairs an existing install rather than reinstalling it.

### Wrapper creation, click by click

Sikarugir has no CLI for this part, so it's done once in its GUI:

1. Open **Sikarugir Creator** from `/Applications` (installed by the script).
2. On first run it offers engines and wrapper versions to download. Install:
   - the latest **Wrapper** version, and
   - the engine **`WS12WineSikarugir10.0_6`** (top of the list; ignore the
     `CX`/`GPTK`/`WhiskyWine`/`WS11` entries — the GPTK engine in particular
     crashes on this game's EA auth).
3. Click **Create New Blank Wrapper**, name it exactly **`Titanfall2`**
   (the script expects `~/Applications/Sikarugir/Titanfall2.app`; if you pick
   another name, run the script with `WRAPPER=... ` set). Wrapper creation
   takes a minute; ignore any "Support Ending for Intel-based Apps" macOS
   notification — Wine engines are x86 by nature and run via Rosetta.
4. When it's done, the wrapper is at `~/Applications/Sikarugir/`. Double-click
   it — since no Windows app is set yet, its **Configure** window opens.
5. In the Configuration tab, tick
   **"Direct3D to Metal translation layer - (D3DMetal)"**.
   Leave DXMT and DXVK unticked.
6. Click **Winetricks** (bottom row). In the search field type `vcrun`, then
   tick **`vcrun2010`**, **`vcrun2012`**, and **`vcrun2022`**. Keep **Silent**
   checked and press **Run**. Microsoft installer windows may flash by;
   wait until the spinner settles — all three must finish.
7. Close the Winetricks and Configure windows, and re-run `./bootstrap.sh`.

When it finishes, double-clicking the wrapper launches the game directly:
Steam runs headless (`-no-browser`), and the EA app auto-authenticates in the
background.

### Getting back into the wrapper's settings

Once the wrapper is configured to boot the game, double-clicking no longer
opens its Configure window. The side door: right-click `Titanfall2.app` →
**Show Package Contents** → `Contents/` → double-click **`Configure.app`**.
That reopens the Configure window (backend toggles, Winetricks, launch
field, env vars like `MTL_HUD_ENABLED=1` for an FPS overlay).

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

### Surviving EA's self-updates

The EA app updates itself, and its updater expects the active client at an
unversioned symlink, `EA Desktop\EA Desktop`. It stages the new version into a
versioned folder next to that symlink, then swaps the symlink over. Under Wine
the swap fails (`destage code[21]`). The updater then points every registry
path at the now-missing symlink and blanks the `link2ea` protocol handler, so
Steam's launch dies with `OS Error 0` before the EA app starts.

So `ea-bypass` creates that symlink itself and aims it at the newest staged
version. Re-run it after any EA update to repair the damage:

```sh
./bootstrap.sh ea-bypass
```

## Where saves live

Titanfall 2 writes saves to the Windows "My Documents" folder, which Wine maps
to `~/Documents`. macOS guards that folder with a privacy prompt. If you deny
the prompt, the EA app sees no local save, and it stops the launch on a "Cloud
data is corrupted" dialog.

The `saves` phase avoids the prompt. It points the Windows folder at
`~/Library/Application Support/Titanfall2`, which needs no grant, and moves any
existing `~/Documents/Respawn` there. Override with `SAVES=...` — any path
outside `~/Documents`, `~/Desktop` and `~/Downloads` works.

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
| Worked before, now Steam says `Failed running GameID … (OS Error 0)` | The EA app self-updated and broke its own install — run `./bootstrap.sh ea-bypass` |
| `Cloud data is corrupted` dialog, launch stops there | Saves are unreachable — run `./bootstrap.sh saves` |
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
