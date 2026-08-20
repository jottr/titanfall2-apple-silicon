# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 0.2.0 - 2026-08-20

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

## 0.1.0 - 2026-08-06

### Added

- `bootstrap.sh`. It installs the dependencies, installs Steam into the
  wrapper, applies the EA-app bypass, and configures the launch flags.
- EA-app installer bypass. It extracts the vendor MSI with `msitools`, and
  writes the registry state a successful install produces. This avoids the
  `INST-14-1627` installer failure.
- README with a quickstart, a click-by-click wrapper walkthrough, EA version
  bump instructions, and a troubleshooting table.
- MIT license.
