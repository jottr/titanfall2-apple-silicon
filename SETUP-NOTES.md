# Setup log — M1 Pro, 16 GB, macOS 26.5.2 (2026-08-01 → 2026-08-06)

Record of the working path and what failed on the way. Companion to
`gptk-handoff.md` (original plan, superseded) and `steam-cpu-handoff.md`.

## Outcome

Titanfall 2 (Steam copy) campaign **running** under Sikarugir. EA login
smooth. Performance: first session choppy (shader warm-up + Steam CEF
contention); `-no-browser` flags applied, re-measure pending.

## Working stack

| Component | Version |
|---|---|
| Sikarugir | brew cask, installed 2026-08-01 |
| Engine | `WS12WineSikarugir10.0_6` (CrossOver-derived Wine 10) |
| Backend | D3DMetal (DXMT untried — no need yet) |
| Winetricks | `vcrun2010`, `vcrun2012`, `vcrun2022` |
| Steam | current Windows client, silent NSIS install |
| EA app | `13.759.2.6273` via MSI extract bypass (no installer run) |
| Launch | `steam.exe -no-browser -silent -applaunch 1237970` |

MSI: `EAapp-13.759.2.6273-14790298.msi`,
sha256 `c8f68016bd03c414a873d34b796cdc1f9b4ea6cdebb51720d3c429d95cb1ca94`.

## Failure signatures hit (for future searchers)

- `INST-14-1627` — EA installer, both the standalone stub and the pinned
  13.667 full installer. Root cause per burn log: MSI downloads + verifies
  fine, dies at "configure per-machine MSI package" `0x80070643`, rolls back.
  EA-side change ~2026-03-21; affects all CrossOver-lineage Wine (CrossOver
  26 included). Proton is unaffected — Linux fixes do not transfer.
- Steam "crash" after self-update — it's a self-restart Wine fails to respawn;
  relaunch works. Second symptom: window never maps while processes run
  healthy; full kill + relaunch fixed it.
- `wine` CLI vs running launcher: needs
  `DYLD_FALLBACK_LIBRARY_PATH=<wrapper>/Contents/Frameworks:<wrapper>/Contents/SharedSupport/wine/lib`,
  and mach-port conflicts mean CLI wine only works when the launcher's
  wineserver is dead.

## Paths not taken (and why)

- **GPTK from source** (original handoff): two-Homebrew mess, 45–90 min
  Rosetta compile, and GPTK's Wine has the fatal `bcryptgeneratesymmetrickey`
  bug with the EA app anyway.
- **Whisky**: dead (April 2025). **CrossOver**: paid, and hits the same
  INST-14-1627. **Heroic on macOS**: no EA store support. **UTM Windows VM as
  player**: no 3D acceleration (donor-only value, unneeded once msiextract
  worked). **Bundled-installer swap** (ProtonDB fix): Proton-only — the MSI
  configure step it relies on is exactly what's broken under CrossOver Wine.

## Open items

- [ ] Framerate at 1080p Low/High (campaign), `MTL_HUD_ENABLED=1`
- [ ] Post-`-no-browser` CPU/RSS re-measure (baseline: 160–240% / 1.9 GB idle
      — see `steam-cpu-handoff.md`; note its steam.exe mystery load was the
      TF2 download, not idle churn)
- [ ] Verify `-no-browser` actually suppressed steamwebhelper on current build
