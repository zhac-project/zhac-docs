<!--
SPDX-FileCopyrightText: 2025-2026 Evgenij Cjura and project contributors
SPDX-License-Identifier: AGPL-3.0-or-later
-->

# Security mode (alarm panel)

The wired hub (`zhac-wired-core`, ESP32-S31 and ESP32-P4 boards) has an alarm panel built in, close
to Alarmo in Home Assistant. You pick the sensors, sirens and keypads on the hub page under
**Security**. Then you arm and disarm the panel from that page, a keypad, a button, a rule or a Lua
script. When the alarm goes off, the hub sounds the sirens and sends you a notification. Anything
else that should happen goes in your own rules or scripts.

The panel shows up as a device named **Alarm** that lives on the hub itself, like Hub I/O. It has
no radio, and its IEEE address is always `0x025A484143414C00`. It has two attributes:

| Attribute | Values |
|---|---|
| `alarm_state` | `disarmed`, `arming`, `armed_away`, `armed_home`, `armed_night`, `pending`, `triggered`; settable |
| `alarm_sensor` | the name of the sensor or keypad that started `pending` or `triggered`, else empty |

Stage 1 is the hub only. The ZHAC Cloud app, the HomeTiles tile and a Home Assistant alarm panel
come later.

## States

| State | What it means | What comes next |
|---|---|---|
| `disarmed` | Nothing is guarded. | Arming. |
| `arming` | Away only: the exit delay runs so you can leave. | `armed_away` when the delay ends. |
| `armed_away` / `armed_home` / `armed_night` | The sensors of that mode are guarded. | `pending` or `triggered`. |
| `pending` | An entry sensor went off. The entry delay runs so you can disarm. | `triggered` when the delay ends. |
| `triggered` | The alarm is on. The sirens sound for the siren time. | Back to the armed state when the siren time ends, or `disarmed`. |

- **Home and night** arm at once. Only away has an exit delay.
- **Switching modes:** you can go from one armed mode straight to another.
- **Arming the mode it is already in** does nothing.
- **During `pending` or `triggered`** arming is refused: disarm first.

## What sets it off

A sensor counts only in the modes you put it in. For example, the window contacts might count in
away, home and night, and the indoor motion sensors in away only.

| Sensor | Counts when |
|---|---|
| contact (door, window) | it **opens**. A repeated "open" report is not a new opening. |
| occupancy, presence | it reports motion or presence (every report of it) |
| vibration | it reports vibration (every report of it) |

- **Entry sensor** (the front door, say): starts the entry delay (`pending`). Every other sensor
  triggers at once, also while `pending` runs.
- **Panic or emergency on a keypad** triggers from any state, also `disarmed`. When the siren time
  ends, the panel goes back to the state it was in before.

### Open doors and windows

Arming is refused while a contact sensor of that mode is open. The hub page lists the open ones
and offers **Arm anyway**. A forced arm ignores those sensors until you disarm. A restart also
clears the list, so the panel comes back with every sensor guarded.

## Sirens

Each siren has a kind, which depends on what the device offers:

| Kind | For | On alarm |
|---|---|---|
| `warning` | IAS WD sirens (Heiman, Develco, Bitron, AduroSmart, …) | sends `warning` with the chosen mode (`burglar`, `fire`, `emergency`, `police_panic`, `fire_panic`, `emergency_panic`), level (`low` … `very_high`) and strobe, lasting the siren time |
| `alarm` | Tuya-style sirens that expose an `alarm` switch | sets the tone (`melody` / `ringtone`) and `volume` you chose, the device's own `duration` (the siren time, within the device's range), then `alarm` on |
| `state` | any switch or plug | `state` on |

The sirens go off when the siren time ends or when you disarm.

## Keypads

The hub understands IAS ACE keypads and arm/disarm keyfobs: devices whose `action` reports
`arm_all_zones`, `arm_day_zones`, `arm_night_zones`, `disarm`, `panic` or `emergency`.

| Keypad | Does |
|---|---|
| arm all zones | arm away |
| arm day zones | arm home |
| arm night zones | arm night |
| disarm | disarm, if the code matches one of the panel's codes |
| panic / emergency | trigger the alarm |

- **Codes:** up to 8 codes of 4–8 digits.
- **Trusted keypads** disarm without a code. Use this for a keyfob that has no keypad.
- **No feedback in stage 1.** The hub does not answer the keypad yet, so its own lights and beeps
  may not show the panel's state.

## Notifications

- **The alarm goes off:**
  - the ZHAC Cloud app gets a critical push plus an inbox entry, when the hub is linked;
  - Telegram gets a message, when it is set up;
  - the text names the sensor and the mode ("Front door (armed away)"), or the keypad for a panic
    ("Panic button on Hall keypad").
- **Notify on arm and disarm** (a setting): also "Armed (away)" and "Disarmed". The return to the
  armed state after the siren time sends nothing.
- **The hub restarts during `pending` or `triggered`:** it comes back armed and, a minute later,
  sends "The hub restarted during an alarm" and switches the sirens off (unless a new alarm
  sounds them by then).
- **The cloud link is down when the alarm goes off:** that cloud notification is lost. Telegram
  still goes out when it is set up and the network is up.

## Your own reactions

Rules and Lua see the Alarm device like any other device. On every state change the hub also fires
the named event `alarm_<state>`, for example `Event#alarm_triggered` or `Event#alarm_disarmed`.

```
# Lights on and an RGB strip blinking when the alarm goes off
ON Alarm#alarm_state="triggered" DO zigbee.set hall_light state 1; zigbee.set led_strip effect blink ENDON

# A siren with its own signal, from a rule
ON Event#alarm_triggered DO zigbee.set garden_siren warning fire,very_high,1,60 ENDON

# Arm and disarm with a button
ON hall_button#action="single" DO zigbee.set Alarm alarm_state armed_away ENDON
ON hall_button#action="double" DO zigbee.set Alarm alarm_state disarmed ENDON

# A message of your own when it arms
ON Event#alarm_armed_night DO publish home/alarm night ENDON
```

Rules refer to the device by its name. If you rename the Alarm device, use the new name or its
IEEE address. The **Security** page builds the two common rules for you (**Add a reaction**,
**Arm with a button**).

```lua
local ALARM = "0x025A484143414C00"

zhac.on_attr_change(ALARM, "alarm_state", function(_, _, state)
  if state == "triggered" then
    zhac.set_attr("0x00158D0001020304", "state", true)
  end
end)

zhac.set_attr(ALARM, "alarm_state", "armed_night")
```

## Arming and disarming from outside

You can set the Alarm device's `alarm_state` from all of these:

- the hub page;
- rules and Lua;
- MQTT, with discovery on (`<root>/devices/025A484143414C00/alarm_state/set` with `armed_away`,
  `disarmed`, …);
- Home Assistant, where it shows up as a select;
- the ZHAC Cloud device card.

**None of these ask for a code.** Anyone who can publish to your MQTT broker or control the device
from Home Assistant can disarm the panel. Secure those the way you would secure the door. Forcing
past open sensors is only on the hub page.

A keypad's code is checked on the hub. It shows in the hub page's live view of the keypad, but it
never goes to the cloud.

## Limits

| | |
|---|---|
| Sensors | 48 |
| Sirens | 8 |
| Keypads | 8 |
| Codes | 8, each 4–8 digits |
| Exit and entry delay | 0–300 s (default 30) |
| Siren time | 10–1800 s (default 180) |

The settings and the panel's state are kept in the hub's flash. They survive restarts and updates.
For the WebSocket commands behind the page, see [WS_API.md](WS_API.md#security-mode).
