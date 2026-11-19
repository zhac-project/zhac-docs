# Changelog

All notable changes to **zhac-docs** are documented in this file.

## [Unreleased]

### Changed

- **`FIRST_20_MINUTES.md` follows today's flasher, for both boards**: the ESP32-S31 path next to the P4 + C6 one; on the P4, the one-time radio installer replaces the USB-serial wiring (by wire stays as the flasher's Advanced section), and the flasher picks the silicon family, so the manual revision check and the "v3.x will not boot" step are gone (v3.0 stays unsupported). The status note says what runs on hardware; Backups names the full backup.
- **Issues and Discussions move here from zhac-platform** (archived): `.github/ISSUE_TEMPLATE/` (bug, device request, board report; the dual-chip and single-chip choices dropped, the label commands now name this repo). Every "report a bug", "request a device" and Discussions link — zhac.org, the flasher, supported devices, `FIRST_20_MINUTES.md`, `TROUBLESHOOTING.md`, `HOME_ASSISTANT.md` — points here. Before the forms work: enable Discussions on this repo and create the labels (commands in `config.yml`).
- **The browser flasher no longer offers the dual-chip images** (`flash/index.html`, `flash/build-site.sh`): that build never shipped and is archived; its releases stay on GitHub.
- **README describes the one-board hub** (zhac-wired-core on the ESP32-S31 or the Guition P4 + C6): new architecture and repository sections, the archived repos listed as such, and the dual-chip wiring and build guide replaced by a pointer to zhac-wired-core's build guide. `FEATURES.md` lists the dual-chip and single-chip builds as archived; `CONTRIBUTING.md` and `SECURITY.md` point at the live repos.

### Added

- **Zigbee device firmware update** (`REST_API.md`, `openapi.yaml`, `FEATURES.md` WC11): `POST /api/device/ota`, `GET /api/device/ota` and `POST /api/device/ota/cancel` on the wired builds: the file check, one update at a time, no older versions, the states and reason codes, and that the hub now answers devices' OTA queries ("no image" while none is loaded).
- **Full backup and restore** (`REST_API.md`, `openapi.yaml`, `FEATURES.md` WC10): `POST /api/backup/full` and `POST /api/backup/restore` on the wired builds, the file's encryption, the restore's checks and error codes, and `tools/zhac_backup.py` for a computer or a USB restore.
- **Hub GPIO control** (`RULES_DSL.md`, `LUA_API.md`): the rule actions `gpio.set`, `gpio.toggle` and `pwm.set` (with an inputs-as-trigger example), and the Lua functions `zhac.gpio_write`, `zhac.gpio_toggle`, `zhac.gpio_read`, `zhac.pwm_write`, `zhac.adc_read` and `zhac.ws_write`. Only pins configured in Settings › I/O can be used.
- **`GPIO.md`**: configuring hub pins, the pins each board offers, the Hub I/O device, and wiring notes (3.3 V logic, current, relays, buttons, ADC range, WS2812 power and data level).
