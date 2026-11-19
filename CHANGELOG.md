# Changelog

All notable changes to **zhac-docs** are documented in this file.

## [Unreleased]

### Added

- **Zigbee device firmware update** (`REST_API.md`, `openapi.yaml`, `FEATURES.md` WC11): `POST /api/device/ota`, `GET /api/device/ota` and `POST /api/device/ota/cancel` on the wired builds: the file check, one update at a time, the states and reason codes, and that the hub now answers devices' OTA queries ("no image" while none is loaded).
- **Full backup and restore** (`REST_API.md`, `openapi.yaml`, `FEATURES.md` WC10): `POST /api/backup/full` and `POST /api/backup/restore` on the wired builds, the file's encryption, the restore's checks and error codes, and `tools/zhac_backup.py` for a computer or a USB restore.
- **Hub GPIO control** (`RULES_DSL.md`, `LUA_API.md`): the rule actions `gpio.set`, `gpio.toggle` and `pwm.set` (with an inputs-as-trigger example), and the Lua functions `zhac.gpio_write`, `zhac.gpio_toggle`, `zhac.gpio_read`, `zhac.pwm_write`, `zhac.adc_read` and `zhac.ws_write`. Only pins configured in Settings › I/O can be used.
- **`GPIO.md`**: configuring hub pins, the pins each board offers, the Hub I/O device, and wiring notes (3.3 V logic, current, relays, buttons, ADC range, WS2812 power and data level).
