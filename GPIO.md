<!--
SPDX-FileCopyrightText: 2025-2026 Evgenij Cjura and project contributors
SPDX-License-Identifier: AGPL-3.0-or-later
-->

# Hub pins (GPIO)

The wired hub (`zhac-wired-core`, ESP32-S31 and ESP32-P4 boards) can drive and read its own free pins:
switch a relay, dim an LED with PWM, read a button or a voltage, and light a WS2812 strip.

A pin does nothing until you configure it on the hub page, under **Settings › I/O**. Rules, Lua
scripts, the cloud and Home Assistant can use configured pins only, and only in the configured
mode. A cloud-pushed rule or script cannot touch any other pin.

## Configure a pin

Each row in **Settings › I/O** is one pin (16 at most):

| Field | Values | Default | Used by |
|---|---|---|---|
| GPIO | a pin from the list the editor offers | — | all |
| Mode | `out` on/off, `pwm` duty 0–100 %, `in` on/off input, `adc` voltage, `strip` WS2812 | — | all |
| Name | starts with a letter, then up to 14 of `a-z 0-9 _` (`relay`, `door_btn`) | — | all: the attribute name on the Hub I/O device |
| Invert | on = low level / inverted duty; for inputs, low reads as on | off | out, pwm, in |
| Pull | `none`, `up`, `down` | none | in |
| At boot | `off`, `on` (100 % for pwm), `last` (the level before the restart) | off | out, pwm |
| Frequency | 1–40000 Hz | 1000 | pwm |
| Interval | 0–3600 s; 0 = read from Lua only, never published | 5 | adc |
| Delta | 0–4095: publish only when the reading moved this much | 50 | adc |
| LEDs | 1–1024 | 30 | strip |

Saving applies at once. A pin you remove is released and left undriven (no pull resistor).
The configuration is kept in the hub's flash and survives updates.

## Which pins

The editor lists only pins that are free on your build. A pin used by Ethernet, the Zigbee radio,
the status LED, the Wi-Fi co-processor or the flash/PSRAM is never offered.

| Build | Pins offered |
|---|---|
| ESP32-P4 (Guition / Waveshare P4) | 2, 3, 4, 5, 20, 21, 22, 23, 26, 27, 32, 33, 45, 46, 47, 48, 53 |
| ESP32-P4 with Wi-Fi co-processor | 21, 22, 23, 26, 27, 45, 46, 47, 48, 53 |
| ESP32-S31 Function-CoreBoard | 2, 3, 4, 20–25, 35–40, 42–49 |
| ESP32-S31 with Wi-Fi co-processor | 2, 3, 4, 35–40, 42–46, 48, 49 |

`adc` works only on pins with an ADC channel; the editor offers those for `adc` and `GET /api/io`
lists them as `adc_pins`. Readings are millivolts on the P4 (calibrated) and raw counts
(0–4095) on the S31, whose IDF release has no ADC calibration yet; `adc_unit` says which.

Limits: 8 PWM pins at most, using at most 4 different frequencies. Each strip takes one RMT
channel (the S31 status LED takes one too); a strip that finds none shows the error on its row.

## The Hub I/O device

While at least one pin is configured, the device list shows **Hub I/O** (model `ZHAC-IO`). Its
attributes are the pin names:

| Mode | Attribute | Control |
|---|---|---|
| out | on/off | switch, writable |
| pwm | 0–100 % | slider, writable |
| in | on/off | read-only, updated on every change (debounced, ~40 ms) |
| adc | mV or raw | read-only, published every `interval` seconds when it moved by `delta` |
| strip | — | Lua only |

It works like any device: rename it, put it in dashboards, read it from MQTT/Home Assistant and
the cloud, and use inputs as rule triggers:

```
ON Hub I/O#door_btn=1 DO gpio.toggle relay ENDON
ON Hub I/O#light_level<800 DO pwm.set lamp 60 ENDON
```

It has no radio, so bind, reconfigure, re-interview, groups and remove do not apply. To remove it,
delete its pins in Settings › I/O.

## Rules and Lua

Rules: `gpio.set <pin> on|off`, `gpio.toggle <pin>`, `pwm.set <pin> <0-100>`; see
[RULES_DSL.md](RULES_DSL.md). Lua: `zhac.gpio_write`, `gpio_toggle`, `gpio_read`, `pwm_write`,
`adc_read`, `ws_write`; see [LUA_API.md](LUA_API.md). `<pin>` is the name or the GPIO number.

## Wiring

- **3.3 V logic.** Never put more than 3.3 V on a pin. A 5 V signal needs a divider or a level shifter.
- **Current.** Keep each pin under ~20 mA. That is one indicator LED with a resistor, not a lamp,
  a motor or a relay coil.
- **Relays.** Drive the coil through a transistor/MOSFET with a flyback diode, or use a relay
  module with its own driver. Modules that switch on a low input: set *Invert*.
- **Buttons.** Wire the button between the pin and GND and set *Pull* = `up` and *Invert* on,
  so pressed reads as on.
- **ADC.** Up to ~3.1 V on the P4. On the S31 the range is much lower (0 dB attenuation only),
  so divide the voltage down first.
- **WS2812 strips.** Power the strip from its own 5 V supply sized for it (up to 60 mA per LED at
  full white), connect the grounds, and feed the data line through a 3.3→5 V level shifter
  (74AHCT125 or similar) for strips that miss 3.3 V data. Colours are `0xRRGGBB`, sent in GRB order.
- **Boot.** Pins float until the hub has started (a second or two). Give relay drivers a pull resistor
  that keeps them off while the hub boots.
