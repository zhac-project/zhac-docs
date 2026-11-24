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

Stage 1 is the hub only. The ZHAC Cloud app, the HomeTiles tile, a Home Assistant alarm panel and
the keypad feedback come later.

## How it works

The panel runs on the hub. Guarding, the sirens and your own rules work without the internet; only
the notifications need it, and they wait for it (see [Notifications](#notifications)). The panel
does the core job: the states, the delays, the sirens and the notifications. It reports every
change through the Alarm device and named events. Anything else you want (lights, a scene, a
message of your own) goes in rules or Lua that react to them.

```
 sensor and keypad reports ──────────┐
 hub page: Arm, Disarm ──────────────┼──► state machine ──► on each change, in this order:
 alarm_state set by a rule, Lua,     │    (exit delay,       1. saves the state in flash
 MQTT, Home Assistant, the cloud ────┘     entry delay,      2. queues the notifications
                                           siren time)       3. sets the Alarm device's alarm_state, alarm_sensor
                                                             4. fires Event#alarm_<state>
                                                             5. switches the sirens on or off
                                                             6. tells the open hub pages
```

- **What goes in.** The hub decodes every Zigbee report as usual. The panel looks only at the
  devices on the Security page: a sensor's `contact`, `occupancy`, `presence` or `vibration`, and a
  keypad's `action`. Arming and disarming come from the hub page, or as a new value of the Alarm
  device's `alarm_state`. Rules, Lua, MQTT, Home Assistant and ZHAC Cloud scenes all go that way,
  so they behave the same.
- **The decision.** A small state machine decides what each input means in the current state and
  mode (see [States](#states) and [What sets it off](#what-sets-it-off)). Before arming, it checks
  the mode's contacts against their last report, so an open door blocks the arm. A contact counts
  only when it changes to open. At start-up the panel takes each contact's last known state, so a
  door left open across a restart is not a new opening.
- **The clock.** The panel keeps the exit delay, the entry delay and the siren time itself, and
  checks them every second while one of them runs.
- **What comes out.** The panel's own task does the slow work of each change, in the order above.
  The sirens come late in it, because a siren can take a few seconds to answer over Zigbee.
- **A restart.** The settings and the state are kept in flash. After a restart the panel comes back
  in the state it was in, or, if the alarm was on, in the state before the alarm.

In the firmware (`zhac-wired-core`): `main/alarm_core.cpp` is the state machine (plain C++,
host-tested), `main/alarm.cpp` the task with the sirens, the notifications, the flash records and
the Alarm device, and `main/ws_bridge.cpp` the `alarm.*` commands of
[WS_API.md](WS_API.md#security-mode).

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

A keypad, a button, a rule, Lua, MQTT or Home Assistant cannot force. When an arm from one of
them is refused, the hub tells you, because otherwise you would leave thinking the house is
guarded: a notification ("Not armed (away): Bathroom window is open") and the event
`Event#alarm_arm_failed`.

## Sirens

Each siren has a kind, which depends on what the device offers:

| Kind | For | On alarm |
|---|---|---|
| `warning` | IAS WD sirens (Heiman, Develco, Bitron, AduroSmart, …) | sends `warning` with the chosen mode (`burglar`, `fire`, `emergency`, `police_panic`, `fire_panic`, `emergency_panic`), level (`low` … `very_high`) and strobe, lasting the siren time |
| `alarm` | Tuya-style sirens that expose an `alarm` switch | sets the tone (`melody` / `ringtone`) and `volume` you chose, the device's own `duration` (the siren time, within the device's range), then `alarm` on |
| `state` | any switch or plug | `state` on |

The sirens stop when the siren time ends or when you disarm. Saving the settings checks that each
siren's device has something to set for its kind: a smoke sensor's `alarm` is only a reading, and
is refused as a siren of kind `alarm`.

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
- **No feedback yet (planned for stage 2).** The hub does not answer the keypad, so its own lights
  and beeps may not show the panel's state; some keypads may beep an error or repeat the command.
  The arm or disarm still works.

## Notifications

- **The alarm goes off:**
  - the ZHAC Cloud app gets a critical push plus an inbox entry, when the hub is linked;
  - Telegram gets a message, when it is set up;
  - the text names the sensor and the mode ("Front door (armed away)"), or the keypad for a panic
    ("Panic button on Hall keypad").
- **An arm refused for open doors or windows** (see above): "Not armed (away): Bathroom window is
  open".
- **Notify on arm and disarm** (a setting): also "Armed (away)" and "Disarmed". The return to the
  armed state after the siren time sends nothing.
- Each message ends with the time it happened ("… at 02:13") once the hub's clock is set.
- **The hub restarts during `pending` or `triggered`:** it comes back to the state it was in
  before the alarm (armed, or disarmed after a panic from a disarmed panel) and, a minute later,
  sends "The hub restarted during an alarm" and switches the sirens off (unless a new alarm
  sounds them by then).
- **The network is down when a notification is due** (an internet outage, a router still
  booting after a power cut): the cloud notification waits on the hub and goes out when the
  cloud link is back, and Telegram is tried again every 30 s for 10 minutes. A restart in the
  meantime loses what is still waiting.

## Your own reactions

Rules and Lua see the Alarm device like any other device. On every state change the hub also fires
the named event `alarm_<state>`, for example `Event#alarm_triggered` or `Event#alarm_disarmed`, and
`Event#alarm_arm_failed` when an arm is refused for open doors or windows (not from the hub page).

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

# Blink the hall light when the button could not arm
ON Event#alarm_arm_failed DO zigbee.set hall_light effect blink ENDON
```

A rule's value is at most 19 characters: `fire,very_high,1,60` fits, `police_panic,high,1,60` does
not. For a longer signal, add the siren in the Security settings.

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
- ZHAC Cloud, through a scene. For example, an "Arm away" scene sets the Alarm device's
  `alarm_state` to `armed_away`, and a "Disarm" scene sets it to `disarmed`. The cloud's device
  card shows `alarm_state` but has no control for it yet.

**None of these ask for a code.** Anyone who can publish to your MQTT broker, control the device
from Home Assistant or run scenes in your ZHAC Cloud account can disarm the panel. Secure those
the way you would secure the door. Forcing past open sensors is only on the hub page.

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
