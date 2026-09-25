# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `watchdog` phase. The wrapper now runs a supervisor alongside Steam: it waits
  for the game, and ends the Windows session when the game exits — so quitting
  the game also quits Steam and the EA services, menubar icons included. It runs
  on the macOS side; a Windows batch file would need a console, and that console
  window lands on top of the EA activation window the game shows at launch.
  Replaces the `launch-flags` phase, which only set the Steam arguments the
  wrapper now passes itself.
- `./test-watchdog.sh` self-check for the supervisor.
- `stop` phase. It ends a running session politely (`wineboot -e -s`), and
  signals only the processes that do not answer. It is also the recovery path
  for a session whose wineserver died: those processes ignore SIGTERM and hold
  their menubar icons until something kills them.
- The wrapper clears such leftovers at launch too, before Wine starts. It also
  ends a session that is still live, and that session's supervisor, so a stuck
  session cannot block the next launch. A second double-click during a game
  ends that game.
- `status` reports whether a session is running, and whether its wineserver is
  alive.

### Fixed

- After an EA self-update, Steam showed "There is no Windows program configured
  to open this type of file" and the game did not start. The update left the
  `EA Desktop` symlink dangling and the `link2ea` handler blank. The wrapper now
  repairs both at each launch, before Wine starts.
- `ea-bypass` downloaded the pinned EA MSI again when the EA app had already
  updated past it. It now uses any complete staged version.

## [0.2.0] - 2026-08-20

### Added

- `saves` phase. It points the Windows "My Documents" folder at
  `~/Library/Application Support/Titanfall2`, and moves an existing
  `~/Documents/Respawn` there. macOS then asks for no privacy grant.
  Set `SAVES=` to choose a different path.
- `status` reports the save location, and the staged EA app version.

### Fixed

- The game stopped launching after the EA app updated itself. Steam reported
  `Failed running GameID … (OS Error 0)`. EA's updater expects the active
  client at an unversioned symlink, which it cannot create under Wine.
  `ea-bypass` now creates that symlink, and repairs the registry damage.
  Re-run it after any EA update.
- Denying the macOS Documents prompt stopped the launch on a "Cloud data is
  corrupted" dialog. The `saves` phase removes the need for that permission.
- `ea-bypass` skipped its registry import when the EA files were already in
  place. An EA update damages the registry but keeps the files, so the phase
  could not repair the most common breakage.
- The 80 GB free-space check blocked every run on a full disk. It now gates
  only the first install, so repair runs still work.

## [0.1.0] - 2026-08-06

### Added

- `bootstrap.sh`. It installs the dependencies, installs Steam into the
  wrapper, applies the EA-app bypass, and configures the launch flags.
- EA-app installer bypass. It extracts the vendor MSI with `msitools`, and
  writes the registry state a successful install produces. This avoids the
  `INST-14-1627` installer failure.
- README with a quickstart, a click-by-click wrapper walkthrough, EA version
  bump instructions, and a troubleshooting table.
- MIT license.

[0.2.0]: https://github.com/jottr/titanfall2-apple-silicon/releases/tag/v0.2.0
[0.1.0]: https://github.com/jottr/titanfall2-apple-silicon/releases/tag/v0.1.0
