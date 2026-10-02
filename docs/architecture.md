# Architecture

Ally DSP is a Decky Loader plugin with a Python backend (`py_modules/allydsp`),
a React frontend (`src/`) and one audio runtime process. It runs without root
and writes only below the user's home directory.

```
Decky Loader (root) ── plugin backend "Ally DSP" (runs as deck)
                         ├─ setup_flow    hardware check → ASUS package → DAX3 XML → venv → presets → activate
                         ├─ dsp_runtime   ~/.config/systemd/user/ally-dsp.service, active preset
                         ├─ settings      global / per-app preset, extras, update state
                         ├─ jackwatch     pause the chain while headphones are plugged in
                         ├─ updater       GitHub Releases, minisign verification
                         └─ diagnostics   text report
Frontend (QAM) ── get_state / set_* callables, events setup_progress, dsp_state, convert_progress, update_state
               ── SteamClient.GameSessions.RegisterForAppLifetimeNotifications → on_running_app_changed

ally-dsp.service: /usr/bin/pipewire -c ~/homebrew/data/Ally DSP/active/chain.conf
  LV2_PATH=~/homebrew/plugins/Ally DSP/bin/lv2:/usr/lib/lv2
  filter chain: convolver → LSP PEQ → LSP multiband compressor → [LSP autogain] → LSP limiter
  smart filter targeting alsa_output.pci-…analog-stereo
```

## Files on the device

| Path | Content |
|---|---|
| `~/homebrew/plugins/Ally DSP/` | plugin code, `bin/lv2/lsp-plugins.lv2`, `defaults/converter` |
| `~/homebrew/settings/Ally DSP/settings.json` | settings, see below |
| `~/homebrew/data/Ally DSP/dax3/` | tuning XML, INF, `provenance.json` |
| `~/homebrew/data/Ally DSP/venv/` | Python venv with numpy/scipy for the converter (`meta.json` records the Python version) |
| `~/homebrew/data/Ally DSP/presets/<profile>/<voicing>/` | `chain.conf`, `ir.irs`, `converter.conf`, `meta.json` |
| `~/homebrew/data/Ally DSP/active/` | copy of the active preset the unit reads |
| `~/.config/systemd/user/ally-dsp.service` | unit, rendered from `defaults/ally-dsp.service.tmpl` |
| `~/homebrew/logs/Ally DSP/` | backend log, `diagnostics.txt` |

## Setup

`setup_flow.run_setup` runs in a worker thread and reports progress events.

1. `hardware`: Realtek codec and subsystem id from `/proc/asound`, speaker sink
   from `pw-dump`, tools (`7z`, `curl`), bundled LV2 plugins via `lv2ls`.
2. `resolve`: `devices.lookup(ssid)` gives the entry for the detected codec
   subsystem id (lowercase). Its ASUS support API query (`GetPDDrivers`) returns
   the driver list. Setup uses the newest "Dolby Atmos driver" entry with URL
   and SHA-256. If the API is unreachable, setup uses the pinned package of the entry.
3. `download`: `curl` with resume, progress by file size, SHA-256 check.
4. `extract`: find the 7z signature in the installer, slice the payload, `7z l`
   then `7z e` for `DEV_<dev>_SUBSYS_<ssid>*.xml` and `dax3_ext_rtk.inf`,
   validate the XML (root, security key, profiles), write `provenance.json`.
   If the API package has no XML for this codec, steps 3 and 4 run again with
   the pinned package. With "try anyway" on an unknown device, every pinned
   package is tried in turn.
5. `venv`: `/usr/bin/python3 -m venv`, `pip install -r converter-requirements.txt`
   (fallback unpinned), import check. Rebuilt when the system Python changes.
6. `convert`: for every profile × voicing run
   `dolby_to_pipewire.py <xml> --profile P --variant V --target-sink S --no-activate ...`
   with `LV2_PATH` set, then `confgen.finalize` rewrites the drop-in into a
   standalone config: base modules, fixed node names (`effect_input.ally_dsp`,
   `effect_output.ally_dsp`), smart-filter name and target, IR path.
7. `activate`: write the resolved preset to `active/`, install and start the
   unit, verify the node in `pw-dump`, enable autostart.

Steps 3–4 and 6 are skipped when provenance and preset metadata already match.

## Device registry

`defaults/fallback-sources.json` holds one entry per supported device, keyed by
the lowercase codec subsystem id:

```json
{
  "asus_cdn": "https://dlcdnets.asus.com",
  "devices": {
    "10431eb3": {
      "name": "ROG Ally X (RC72LA)",
      "asus_api": "https://www.asus.com/support/webapi/ProductV2/GetPDDrivers?...&cpu=RC72LA&osid=52",
      "package": {"title": "Dolby Atmos driver", "version": "V9.816.706.24", "release_date": "2024/09/13",
                  "url": "https://dlcdnets.asus.com/pub/ASUS/.../..._V9.816.706.24_16152_3.exe",
                  "sha256": "…", "size": 8807856}
    }
  }
}
```

`devices.load_registry` reads the file and normalizes the keys. An entry
without `asus_api` or `package` inherits the top-level keys of the same name
(the format before the registry). The file stores only URLs and hashes. The
tuning itself is never part of the repository (see `THIRD_PARTY_LICENSES.md`).

The RC72LA query needs `cpu=RC72LA`. Without it, the API answers with a
parameter error. The RC73YA shares the RC73XA query and package, because that
package contains the tuning for both codecs.

## Runtime

- Preset switch: copy `chain.conf` and `ir.irs` to `active/`, apply pre-gain to
  the limiter input gain, `systemctl --user restart ally-dsp.service`, verify.
- The unit has `ConditionPathExists` on the active config, `BindsTo=pipewire.service`
  and `Restart=on-failure`.
- Per-game presets: the frontend reports the running app id; the backend
  resolves `perApp[appId]` or the global preset and restarts only on change.
- Headphones: `jackwatch` polls the active output route every 3 s and stops the
  unit while `analog-output-headphones` is active.
- Extras: leveler, dialog and regulator switches trigger a reconversion of all
  presets; pre-gain only re-applies the active preset. Virtual bass is offered
  only when Calf LV2 is installed system-wide.

## Settings

```json
{
  "enabled": true,
  "global": {"profile": "game", "voicing": "balanced"},
  "perApp": {"1245620": {"profile": "movie", "voicing": "warm", "enabled": true, "name": "Elden Ring"}},
  "extras": {"autogain": true, "dialog": true, "regulator": true, "virtualBass": false, "preGainDb": 0.0},
  "update": {"channel": "stable", "lastCheck": 0, "latest": null, "autoCheck": true},
  "setup": {"done": true, "xmlSha256": "…", "packageVersion": "V11.130.1340.46", "converterVersion": "bde5653",
            "completedAt": "…", "extrasSignature": "…", "targetSink": "alsa_output.pci-0000_64_00.6.analog-stereo"}
}
```

## Updates

1. `updater.check` reads `releases/latest` (cached for six hours).
2. `updater.verify_release` downloads `SHA256SUMS` and `SHA256SUMS.minisig`,
   verifies the signature with the pinned `minisign.pub` and returns the zip URL
   and its SHA-256.
3. The frontend calls Decky's `utilities/install_plugin` with that data; Decky
   confirms with the user, downloads, checks the hash, replaces the plugin and
   reloads it. Decky calls `_uninstall` while replacing the plugin, so
   `prepare_update` writes `data/.update-pending` and `_uninstall` leaves unit and
   runtime data alone while that marker is fresh. `_startup` re-creates the unit
   and active preset, or re-runs setup when data is missing. Steam keeps the old UI
   bundle until it restarts, so the frontend restarts Steam
   (`SteamClient.User.StartRestart(false)`) when Decky reports
   `loader/plugin_download_finish` for the plugin or the new backend emits
   `update_installed` on its first start; the Maintenance toggle
   `autoRestartSteam` (default on) controls this, and a stale-UI row offers a
   manual restart.

First install: `install.sh` (sudo) downloads the latest release, verifies
`SHA256SUMS` and the signature, installs into `~/homebrew/plugins/Ally DSP` and
restarts Decky.

## Release pipeline

`release.yml` runs on tags `v*`: build and typecheck the frontend, `pytest`,
assemble the converter from the submodule, fetch and trim the LSP LV2 bundle
(`scripts/fetch-lsp.sh`), package `ally-dsp-<version>.zip`, sign `SHA256SUMS`
with the `MINISIGN_SEED` secret (`python3 -m allydsp.minisign sign`), verify the
signature against the committed key and create the release. The tag must equal
the `package.json` version.

## Compatibility notes

- Decky runs plugin backends in its bundled Python 3.11 (PyInstaller). It lacks
  `xml.etree` and may lack other stdlib modules; the backend only uses `re`,
  `json`, `os`, `subprocess`, `shutil`, `hashlib`, `base64`, `time`, `asyncio`.
- Backends do not inherit `XDG_RUNTIME_DIR` or the session bus address;
  `util.user_env` sets them from the uid.
- The CLI (`python3 -m allydsp.cli`) uses the system Python and the same paths.

## Open items

- Listening test and QAM handling by the maintainer; suspend/resume behaviour.
- End-to-end test of the in-app update with a second release.
- Optional pre-release channel via GitHub pre-releases.
- Upstream: a `hardware-profile` for the RC73XA in Bazzite or `steamdeck-dsp`.
