<!--
SPDX-FileCopyrightText: 2025-2026 Evgenij Cjura and project contributors
SPDX-License-Identifier: AGPL-3.0-or-later
-->

# Home Assistant

ZHAC shows up in Home Assistant through MQTT discovery: turn it on, and every paired device
appears with its sensors, switches and controls, grouped under one device per Zigbee device.
No custom integration, no YAML. Home Assistant keeps doing automations and dashboards; ZHAC
keeps the Zigbee network, and its own rules keep working if Home Assistant is down.

> **Status.** Built and unit-tested; not yet run against a live Home Assistant by the
> maintainers. Reports welcome — [open an issue](https://github.com/zhac-project/zhac-platform/issues/new?template=bug.yml).

## Set it up (5 minutes)

1. In Home Assistant, install an MQTT broker (the Mosquitto add-on is the usual choice) and
   the **MQTT** integration. Discovery is on by default there.
2. In ZHAC, open **Settings → MQTT**:
   - **Broker URL**: `mqtt://user:password@homeassistant.local:1883` (your broker's address
     and the user you created for ZHAC),
   - **Root topic**: `zhac` unless you run several hubs on one broker — then give each its own,
   - press **Save**, then turn on **Enable MQTT client**,
   - turn on **Home Assistant discovery**.
3. Within a few seconds Home Assistant lists a **ZHAC hub** device and one device per paired
   Zigbee device, under *Settings → Devices & services → MQTT*.

New devices appear when they finish pairing. Renaming a device in ZHAC renames it in Home
Assistant. Removing it in ZHAC removes it there. Turning discovery off removes them all.

## What each device becomes

| ZHAC exposes | Home Assistant entity |
|---|---|
| writable `state` + `brightness` (+ `color_temp`) | one **light**, named after the device |
| writable `state` | a **switch**, named after the device |
| other writable on/off values (`child_lock`, …) | **switch** |
| read-only on/off values | **binary sensor** — `contact` is a door, `occupancy`, `water_leak`, `smoke`, `tamper`, `battery_low`, … get their device class |
| writable numbers (setpoints, calibration) | **number**, with the device's range and step |
| read-only numbers | **sensor**, with unit, device class and state class where Home Assistant knows them (temperature, humidity, power, energy, battery, …) |
| writable choices (`system_mode`, `power_outage_memory`) | **select** |
| read-only choices and text (`action`, …) | **sensor** |

Values marked *diagnostic* or *config* in the device definition land in those entity
categories. Write-only commands (such as `identify`) are not exposed; they stay on the
device's **Commands** tab in the ZHAC web UI.

## Topics

With the default root `zhac` and prefix `homeassistant`:

| Topic | Direction | Content |
|---|---|---|
| `homeassistant/<component>/zhac_<ieee>_<key>/config` | ZHAC → HA | discovery config, retained |
| `zhac/devices/<IEEE>/<key>` | ZHAC → HA | the value, retained — `1`/`0` for on/off, numbers as numbers, text as text |
| `zhac/devices/<IEEE>/<key>/set` | HA → ZHAC | a new value, same format |
| `zhac/availability` | ZHAC → HA | `online`, or `offline` when the hub drops off the broker |
| `zhac/devices/<IEEE>/state` | ZHAC → any | dual-chip only: every update as one JSON object |

`<ieee>` is the 16-digit address in lower case, `<IEEE>` in upper case. Anything can use the
per-attribute topics — Node-RED, scripts — not only Home Assistant.

## Limits

- **Availability is per hub, not per device.** If the hub goes offline, all its entities do.
  A battery sensor that stops reporting keeps its last value.
- **`action` is a sensor**, not a device trigger. Automations can use its state changes.
- **Choices on the dual-chip build** need both chips on a release that has this feature: the
  P4 now receives the option name (`sval`) instead of a number.
- The single-chip ESP32-S3 build (`zhac-mono-core`) does not have discovery yet.
