# Changelog

## Unreleased

- Support the ROG Ally X (2024, RC72LA, codec subsystem 1043:1EB3) with its own
  ASUS package (Dolby Atmos driver V9.816.706.24).
- Per-device package registry in `defaults/fallback-sources.json`: display name,
  ASUS API query and pinned fallback package per lowercase codec subsystem id.
- Compare codec subsystem ids in lowercase everywhere.
- If the newest package from the ASUS API has no tuning for the codec, setup
  downloads the pinned package and tries again.
- "Try anyway" on an unknown device tries every pinned package.
- Generic device names in the unit description and the plugin metadata.

## 0.1.4 (2026-09-20)

- Restart Steam automatically after an in-app update so the new UI loads
  (Maintenance toggle, default on); manual restart button when the UI is stale.

## 0.1.3 (2026-09-19)

- Update @types/react and @types/react-dom to 19.3.0 (Dependabot).

## 0.1.2 (2026-09-19)

- Keep unit and runtime data when Decky replaces the plugin during an update
  (Decky calls `_uninstall` in that path); real uninstalls still clean up.
- Restore the active preset and unit on startup; re-run setup if data is missing.
- Show a hint when Steam still runs an older cached UI bundle.

## 0.1.1 (2026-09-19)

- Remove the Custom 1–3 presets (Dolby's neutral personalize profiles).
- English-only UI.
- Await background tasks on unload.

## 0.1.0 (2026-09-19)

First release.

- Setup wizard: hardware check, ASUS "Dolby Atmos driver" download with SHA-256
  verification, DAX3 tuning extraction, converter venv, conversion of all
  profiles, activation.
- PipeWire filter chain (convolver, LSP parametric EQ, multiband compressor,
  autogain, limiter) as WirePlumber smart filter in a systemd user unit.
- Presets Game/Dynamic/Movie/Music/Voice × Balanced/Detailed/Warm, global or
  per game; headphone pause; extras (leveler, dialog, regulator, pre-gain).
- Diagnostics page and text report.
- Signed self-update from GitHub Releases, installed via Decky Loader.
