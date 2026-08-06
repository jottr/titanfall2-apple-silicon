# Handoff: Titanfall 2 via Apple Game Porting Toolkit on Apple Silicon

## Objective

Get Titanfall 2 (Steam or EA App copy) running on macOS under Apple's Game Porting Toolkit 3.0.
Target: singleplayer campaign at 1080p, playable framerate. Multiplayer via Northstar is a
follow-on step, not in scope for the first pass.

## Machine

- MacBook Pro, M1 Pro, 16 GB RAM
- Existing arm64 Homebrew at `/opt/homebrew` — **do not modify, do not tap into, do not install
  anything x86 into it**
- GPTK requires a **separate x86_64 Homebrew** at `/usr/local/homebrew`
- Shell is zsh

## Hard constraints

- Do not install or suggest CrossOver (the CodeWeavers product). GPTK's Wine is CrossOver-derived
  source; that is fine and expected. The commercial app is out of scope.
- Do not `sudo` anything except the Rosetta install.
- Do not touch `/opt/homebrew` or the user's existing brew state.
- Anything requiring a GUI click, an Apple Developer login, or an EA account login is a **human
  step**. Stop and hand back with explicit instructions rather than trying to automate it.

## Background the agent needs

GPTK = old Wine fork + D3DMetal (DirectX→Metal translation dylibs). Titanfall 2 is D3D11, so
the rendering path is not the risk.

**The risk is the EA App.** Titanfall 2 mandates it even when bought on Steam. Apple's Wine
snapshot lags CodeWeavers' launcher-compatibility work. The documented failure mode is:

```
Engine Error: 0xc0000002 bcryptgeneratesymmetrickey
```

i.e. the game launches then dies on a bcrypt gap. GPTK 3.0 (released Dec 2025) is on a newer
base than the 22.1.1 sources that first exhibited this, so it may be fixed. Unverified either
way. This is the go/no-go checkpoint.

## Plan

### Phase 0 — preflight

1. Confirm macOS version (`sw_vers`). Need Sonoma+; Sequoia (15.x) or later preferred — AVX/AVX2
   under Rosetta only landed in macOS 15.
2. Confirm free disk ≥ 80 GB (game ~50 GB, EA App, prefix, build artifacts).
3. `softwareupdate --install-rosetta --agree-to-license` if not present.

### Phase 1 — x86 Homebrew + GPTK

```sh
arch -x86_64 zsh
mkdir -p /usr/local/homebrew
curl -L https://github.com/Homebrew/brew/tarball/master | tar xz --strip 1 -C /usr/local/homebrew
/usr/local/homebrew/bin/brew tap apple/apple https://github.com/apple/homebrew-apple
/usr/local/homebrew/bin/brew install apple/apple/game-porting-toolkit
```

Compiles Wine under Rosetta. Budget 45–90 min. Run it under `caffeinate`. If it fails, capture
`~/Library/Logs/Homebrew/game-porting-toolkit/` before retrying — Xcode CLT version mismatches
are the usual cause.

### Phase 2 — D3DMetal dylibs (HUMAN STEP)

The agent cannot do this; it needs an Apple ID.

1. Human downloads `Game_Porting_Toolkit_3.0.dmg` from developer.apple.com (free account).
2. Mount it, open the inner `Evaluation environment for Windows games 3.0.dmg`, accept the licence.
3. Agent then copies `redist/lib/external` and `redist/lib/wine` over
   `$(/usr/local/homebrew/bin/brew --prefix game-porting-toolkit)/lib/`.

Verify afterwards that `external/` and `wine/` both landed and that the D3DMetal dylibs are present.

### Phase 3 — prefix

```sh
export WINEPREFIX=~/tf2
export GPTK=$(/usr/local/homebrew/bin/brew --prefix game-porting-toolkit)
$GPTK/bin/wine64 winecfg     # set Windows 10
```

Install VC++ redists into the prefix — 2010, 2012 and current x64 are all reported as needed:

```sh
$GPTK/bin/wine64 vc_redist.x64.exe
```

### Phase 4 — EA App + game (HUMAN LOGIN)

Install EA App into the prefix, launch it, human logs in, human installs Titanfall 2.

```sh
MTL_HUD_ENABLED=1 WINEESYNC=1 \
  arch -x86_64 gameportingtoolkit ~/tf2 \
  'C:\Program Files\Electronic Arts\EA Desktop\EA Desktop\EADesktop.exe'
```

**Known gotcha:** if the game is bought on Steam, launching via Steam often loops on the EA
launcher. Launch the EA App directly instead.

**Known gotcha:** Titanfall 2 cannot write saves to a drive other than the one it is installed
on. Keep everything on `C:` inside the prefix.

### Phase 5 — verify

Launch the game. Success criteria, in order:

1. EA App opens and authenticates → if not, this is the wall (see Fallback).
2. Game reaches main menu without `0xc0000002`.
3. Campaign loads, Metal HUD shows D3DMetal / Game Porting Toolkit 3.0 active.
4. Note framerate at 1080p Low and 1080p High. Report both.

If `Titanfall2.exe` refuses to launch, try Windows 8 compatibility mode on the exe — this is a
documented fix in VM setups and may apply here.

## Fallback (invoke without asking if Phase 5 step 1 or 2 fails)

Do **not** spend more than two debugging attempts on the EA App under stock GPTK Wine. The
structural fix is newer Wine underneath the same D3DMetal, not a different renderer.

Switch to Sikarugir (Kegworks successor, free):

```sh
softwareupdate --install-rosetta --agree-to-license
brew update && brew trust Sikarugir-App/sikarugir
brew install --cask --no-quarantine Sikarugir-App/sikarugir/sikarugir
```

Build a wrapper on the **CX24.0.7** engine, enable the **D3DMetal** or **DXMT** toggle, install
VC++ 2010 + 2012, then EA App, then the game. Same D3DMetal renderer, Wine that knows about the
EA App. This install goes through the arm64 brew and is safe alongside the x86 one.

## Out of scope for pass 1

- Northstar client (community multiplayer). Drop-in once vanilla works: copy the release zip into
  the `Titanfall2` folder, run `NorthstarLauncher.exe`. Still requires EA App for auth.
- Tuning (esync/msync, shader cache warming, MetalFX).

## Reporting

At the end, write a short log to `~/tf2/SETUP-NOTES.md`: what path succeeded, which GPTK/engine
version, VC++ components installed, exact failure signatures hit, and measured framerates.
