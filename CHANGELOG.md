# Changelog

All notable changes to **zhac-docs** are documented in this file.

## [Unreleased]

### Added

- **Hub GPIO control** (`RULES_DSL.md`, `LUA_API.md`): the rule actions `gpio.set`, `gpio.toggle` and `pwm.set` (with an inputs-as-trigger example), and the Lua functions `zhac.gpio_write`, `zhac.gpio_toggle`, `zhac.gpio_read`, `zhac.pwm_write`, `zhac.adc_read` and `zhac.ws_write`. Only pins configured in Settings › I/O can be used.
- **`GPIO.md`**: configuring hub pins, the pins each board offers, the Hub I/O device, and wiring notes (3.3 V logic, current, relays, buttons, ADC range, WS2812 power and data level).
