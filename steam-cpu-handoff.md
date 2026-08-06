# Handoff: Steam client CPU load under Sikarugir

Companion to `gptk-handoff.md`. That doc lists tuning as out of scope for pass 1; this is a
tuning item found after the fact. Fold in whenever the setup work reaches a stable point.

Written from a separate session on 2026-08-06 by measuring the running prefix. Nothing here
has been changed — this is diagnosis plus proposed fixes to test, not applied work.

## Symptom

The Steam client inside the Sikarugir prefix burns 2+ CPU cores **with no game running**.
Measured via `top -l 4` on the live prefix (M1 Pro, 16 GB):

| PID   | Process                          | CPU %  | RSS  |
|-------|----------------------------------|--------|------|
| 67169 | `steam.exe`                      | 72–99  | 513M |
| 67211 | `steamwebhelper.exe` (CEF)       | 43–67  | 590M |
| 67303 | `steamwebhelper.exe` (renderer)  | 28–46  | 846M |
| 67083 | `wineserver`                     | 16–30  |  34M |

Combined: **~160–240% sustained at idle.** Also ~1.9 GB RSS, which matters on a 16 GB machine
that is already swapping.

## Root cause

`steamwebhelper.exe` is Steam's embedded Chromium (CEF) — the store, library, friends and
overlay UI. Its actual argv in the running prefix contains:

```
--in-process-gpu --disable-gpu --no-sandbox --valve-enable-site-isolation
--valve-initial-threadpool-size=6 --enable-smooth-scrolling
```

`--disable-gpu` means all Chromium compositing is on the CPU. Under Sikarugir that CPU work is
x86_64 being translated to arm64 by Rosetta. Software rasterisation and Rosetta translation
multiply: a UI that would be near-free on a GPU becomes a permanent 2-core tax.

`--enable-smooth-scrolling` and the 6-thread pool make it worse — both spend CPU on animation
frames for a window that is usually not even visible.

`steam.exe` itself at 72–99% is a **separate, unexplained load** and is not obviously CEF.
Worth isolating rather than assuming the web helper explains everything (see Step 3).

## Fixes to try, cheapest first

### 1. Kill the web UI — `-no-browser`

Highest expected win. Drops the CEF process tree entirely; Steam falls back to a minimal UI.
Should reclaim the ~110% spent across the two `steamwebhelper` PIDs.

```sh
# wherever the prefix launches steam.exe, append:
steam.exe -no-browser -silent
```

Cost: no store, no library art, no friends list. For a launcher whose only job is starting
Titanfall 2, that is the right trade.

Unverified caveat: recent Steam builds have been progressively less tolerant of `-no-browser`
and may fall back to loading CEF anyway. Confirm by re-checking for `steamwebhelper` PIDs after
launch — if they are still there, it did not take, go to option 2.

### 2. Don't run Steam at all

`gptk-handoff.md:100` already flags that launching TF2 via Steam loops on the EA launcher, and
recommends launching the EA App directly. That advice also solves this problem — Steam is not
required at runtime for a Titanfall 2 campaign session.

If the current wrapper starts Steam as a side effect, point it straight at the game or the EA
App instead. This takes the number to zero rather than reducing it.

Relevant to the Northstar follow-on too: `NorthstarLauncher.exe` does not need the Steam client
running either, only EA auth.

### 3. Isolate the `steam.exe` 72–99%

Do this before declaring victory — it is roughly a full core on its own and options 1 and 2 may
not touch it. Likely candidates, in order:

- content/update scan or a stuck download → check Steam's download page and `logs/content_log.txt`
- shader pre-caching → Settings ▸ Downloads ▸ *Enable Shader Pre-caching*, turn off; on a
  translated Wine stack it is doing work that will not be reused
- cloud sync retry loop → `logs/cloud_log.txt`
- broken auto-update retry → `logs/stderr.txt`

`C:\Program Files (x86)\Steam\logs\` inside the prefix has all of these.

### 4. If CEF must stay

Settings ▸ Interface ▸ enable **Small Mode**, disable animated avatars, and set the startup page
to Library rather than Store. Also drop `--enable-smooth-scrolling` if the wrapper controls argv.
Partial mitigation only — expect to still pay tens of percent.

## Do not bother with

- Re-enabling GPU for CEF (removing `--disable-gpu`). D3DMetal targets the game's D3D11 path, not
  Chromium's GPU backend; Steam's own launcher sets `--disable-gpu` deliberately under Wine
  because the accelerated path is unstable there. Expect crashes, not speedups.
- Renicing the processes. Moves the heat around, does not reduce it.

## How to verify a fix

Launch, leave idle 60 s with no game, then:

```sh
top -l 4 -n 30 -o cpu -stats pid,cpu,mem,command | grep -iE "steam|wine"
```

Baseline to beat: ~160–240% combined, ~1.9 GB RSS. Re-measure **during** a campaign session too —
the idle number is the floor, and CEF contention while the game is running is the thing that
actually costs framerate.

Worth adding the before/after to `~/tf2/SETUP-NOTES.md` alongside the framerate figures that
`gptk-handoff.md:113` already asks for.
