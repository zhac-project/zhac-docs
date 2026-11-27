<!--
SPDX-FileCopyrightText: 2025-2026 Evgenij Cjura and project contributors
SPDX-License-Identifier: AGPL-3.0-or-later
-->

# Safety: alarm profiles

The wired hub (`zhac-wired-core`, ESP32-S31 and ESP32-P4 boards) has an alarm built in, close to
Alarmo in Home Assistant. A **profile** is one guard with its own sensors, delays and outputs. A
door and window profile, a flood profile, a fire profile and a gas profile all work the same way:
you arm it, a sensor goes off, the outputs act (a siren sounds, a valve closes) and the hub sends
you a notification. You set it all up on the hub page under **Safety**. Then you arm and disarm
each profile from that page, a keypad, a button, a rule or a Lua script. Anything else that should
happen goes in your own rules or scripts.

Up to 8 profiles. Each has a **class**: `intrusion`, `fire`, `water`, `gas` or `other`. Intrusion
profiles replace each other (one is armed at a time, like the away, home and night modes of
v2026112401). Every other profile runs beside them, on its own.

The alarm shows up as a device named **Alarm** that lives on the hub itself, like Hub I/O. It has
no radio, and its IEEE address is always `0x025A484143414C00`. Its attributes:

| Attribute | Values | You can set |
|---|---|---|
| one per profile, named by the profile's `id` (for example `away`, `flood`) | `disarmed`, `arming`, `armed`, `pending`, `triggered` | `armed`, `disarmed` |
| `alarm_state` | `disarmed`, `arming`, `armed_<id>` for each intrusion profile, `pending`, `triggered` | `armed_<id>`, `disarmed` |
| `alarm_sensor` | the name of the sensor or keypad that started `pending` or `triggered` of an intrusion profile, else empty | no |

- `alarm_state` and `alarm_sensor` are the summary of the **intrusion** profiles, as in
  v2026112401. A flood or fire alarm does not touch either of them. Read a flood or fire profile
  from its own attribute.
- Switching from one intrusion profile to another takes `alarm_state` straight to the new value. It
  does not pass through `disarmed`.
- The attribute list follows the profiles. When you add or delete a profile the hub announces the
  Alarm device again, the way it does for Hub I/O, and a deleted profile's attribute disappears.

The ZHAC Cloud app panel, the HomeTiles tile, a Home Assistant alarm panel and the keypad feedback
come later. For now Safety is the hub only.

## How it works

The alarm runs on the hub. Guarding, the outputs and your own rules work without the internet; only
the notifications need it, and they wait for it (see [Notifications](#notifications)). The hub does
the core job: the states, the delays, the outputs and the notifications. It reports every change
through the Alarm device and named events. Anything else you want (lights, a scene, a message of
your own) goes in rules or Lua that react to them.

```
 sensor and keypad reports ─────────────┐
 hub page: Arm, Disarm, Silence ────────┼──► one state machine ──► on each change of any profile,
 a profile's attribute or alarm_state   │    per profile             in this order:
 set by a rule, Lua, MQTT, Home         │    (arm delay,             1. saves the states in flash
 Assistant, the cloud ──────────────────┘     trigger delay,         2. queues the notifications
                                              alarm time)            3. sets the Alarm device's attributes
                                                                     4. fires Event#alarm_<state>_<id>, ...
                                                                     5. switches the outputs
                                                                     6. tells the open hub pages
```

- **What goes in.** The hub decodes every Zigbee report as usual. The alarm looks only at the
  devices on the Safety page: a sensor's `contact`, `occupancy`, `presence`, `vibration`,
  `water_leak`, `smoke`, `gas` or `carbon_monoxide`, and a keypad's `action`. Arming and disarming
  come from the hub page, or as a new value of an attribute of the Alarm device. Rules, Lua, MQTT,
  Home Assistant and ZHAC Cloud scenes all go that way, so they behave the same, but for one thing:
  from ZHAC Cloud a disarm, and an arm that would stop another profile, need "Allow the cloud to
  disarm the alarm" on the hub's own page ([WS_API.md](WS_API.md#the-alarm-switch)).
- **The decision.** One small state machine per profile decides what each input means in the
  profile's current state (see [States](#states) and [What sets it off](#what-sets-it-off)). Before
  arming, it checks the profile's contacts against their last report, so an open door blocks the
  arm. At start-up, and for a sensor you add to a profile, the hub takes the last known value, so a
  door left open or a sensor that is already wet is not a new event.
- **The clock.** The hub keeps the arm delays, the trigger delays and the alarm times itself, and
  checks them every second while one of them runs.
- **What comes out.** The alarm's own task does the slow work of each change, in the order above.
  The outputs come late in it, because a siren can take a few seconds to answer over Zigbee.
- **Under load.** The task keeps no queue of changes. Each pass it asks which profiles differ from
  what it acted on last. When changes pile up (many sensors at once while an output waits on a slow
  device) it may skip the steps in between, but every profile's last state is saved, shown and acted
  on, and every alarm is notified. A profile that was disarmed and armed again between two looks, and
  ends in the state it was seen in, sends no "Disarmed" or "Armed" notification and fires no event.
- **A restart.** The settings and the state of every profile are kept in flash. A save writes the
  states of every profile, a new one too, straight after the settings, so a power cut right after a
  save brings each profile back as it rested at the save. After a restart each profile comes back
  in the state it rested in: armed stays armed, disarmed stays disarmed, and
  a profile that was in an alarm comes back in the state before the alarm. Nothing is armed again
  by itself. A state that cannot be written is logged and the change still takes effect; a restart
  then comes back to the state written last.

In the firmware (`zhac-wired-core`): `main/alarm_core.cpp` is the state machine and the config
(plain C++, host-tested), `main/alarm.cpp` the task with the outputs, the notifications, the flash
records and the Alarm device, and `main/ws_bridge.cpp` the `alarm.*` commands of
[WS_API.md](WS_API.md#safety).

## Profiles

A profile has these fields:

| Field | Values | Notes |
|---|---|---|
| `id` | `a-z`, `0-9`, `_`; starts with a letter; 1 to 13 characters | Unique. Fixed once saved: rules, MQTT and Home Assistant refer to it. Not one of these ten, which are the hub's own: `alarm_state`, `alarm_sensor`, `armed`, `disarmed`, `arming`, `pending`, `triggered`, `pin_code`, `action_code`, `color_hex`. |
| `name` | text, 1 to 24 bytes of UTF-8, no control characters | Shown on the page and in notifications. Free to change. |
| `class` | `intrusion`, `fire`, `water`, `gas`, `other` | Fixed once saved, like the id. |
| `role` | `away`, `home`, `night` or none | Intrusion only. The keypad button that arms this profile. Each role at most once. The page calls it "Keypad button". |
| `arm_delay` | 0 to 300 s (default 0) | Time in `arming` before `armed`. The old exit delay. |
| `trigger_delay` | 0 to 300 s (default 0) | Time in `pending` before `triggered`, for sensors marked delayed. The old entry delay. |
| `siren_time` | 10 to 1800 s (default 180) | The alarm time: how long `triggered` lasts. The page calls it "Alarm time". |
| `notify_arm` | true, false | Also notify when this profile is armed or disarmed. |
| `sensors` | list of `{ieee, entry}` | `entry` means delayed: the sensor starts `pending` instead of the alarm. The page calls it "delayed". A sensor is listed once in a profile. |
| `outputs` | list, see [Outputs](#outputs) | Driven in the order listed. |

What the class does:

- **Intrusion profiles replace each other.** Arming one disarms the armed one. Only they have a
  role.
- **Disarm.** The page's main Disarm button, a keypad's disarm and `alarm_state = disarmed` disarm the
  intrusion profiles, and only **silence** the others (see
  [Arming, disarming, silencing](#arming-disarming-silencing)).
- **Outputs.** When one device is an output of two sounding profiles, the class decides which
  signal it plays: fire first, then gas, water, other, intrusion.
- **The page** uses the class for the icon and for the default tone of a new IAS siren: `fire` for a
  fire profile, `burglar` for intrusion, `emergency` for the rest.
- **The class cannot change.** To use another class, delete the profile and add a new one. A save
  that changes the class of a saved profile is refused.

Limits: 8 profiles; 48 different sensors, each in any number of profiles; 8 outputs in a profile and
32 in all; 8 keypads; 8 codes. Every config of v2026112401 fits (its largest is 48 sensors in three
modes and 8 sirens, which become 24 outputs). The whole list is under [Limits](#limits).

### Add and edit a profile on the page

- **+ Add profile** offers templates: Away, Home and Night (while their keypad button is free),
  Vacation (intrusion, no keypad button), Flood (water), Fire and smoke (fire), Gas and CO (gas),
  and an empty profile (class other). A template is only a filled-in form: Away has a 30 s arm delay
  and a 30 s trigger delay, Home and Night a 30 s trigger delay, the alarm time is 180 s, and the
  Flood, Fire and Gas templates tick "Notify when it is armed or disarmed". A second profile from
  the same template gets the first free name: "Night 2", "Night 3", and so on.
- The **Id** is proposed from the name, never one that is reserved or that another profile has. The
  id and the class can be set until the first save; after it they are shown, not edited. Save is
  refused for a duplicate id or a reserved one (the ten are in the table above).
- The sensor picker lists the sensors that suit the class first, but any sensor can go into any
  profile. The output picker lists the devices that can act as an output.
- While an alarm is running the page says why Save is off. Delete profile asks first, and rules that
  name the profile's id stop working.
- **Save** sends the whole config. The page edits the config as the hub has it when you press Save,
  so the last save wins: a profile added or deleted in another browser tab shows only after a
  reload, and saving an edit to a profile that was deleted elsewhere adds it again.

The config as a whole:

- **The config cannot be saved while any profile is arming, pending or triggered.** The hub refuses
  the save ("an alarm is running: disarm or wait, then save"), so no edit meets a running timer or
  a sounding output.
- **A new profile** of a class other than intrusion is armed right after the save, like any arm
  without force: the arm delay runs, and an open contact leaves it disarmed. A new intrusion profile
  starts disarmed.
- A disarmed profile that is not intrusion shows "Not guarding" on its card: nothing re-arms it for
  you.

## States

Each profile has the same life:

| State | What it means | What comes next |
|---|---|---|
| `disarmed` | The profile guards nothing. | Arming. |
| `arming` | The arm delay runs so you can leave. Its sensors are not counted yet. | `armed` when the delay ends. |
| `armed` | The profile's sensors are guarded. | `pending` or `triggered`. |
| `pending` | A delayed sensor went off. The trigger delay runs so you can disarm. The page calls it "Entry delay". | `triggered` when the delay ends. Another, not delayed sensor: `triggered` at once. |
| `triggered` | The alarm is on. The outputs act for the alarm time. | Back to its resting state when the time ends: `armed`, or `disarmed` after a panic from disarmed. |

- An arm delay of 0 arms at once.
- A second sensor during `triggered` of the same profile changes nothing.
- **No automatic re-arming.** A disarmed profile stays disarmed until someone arms it.
- **Switching intrusion profiles:** you can go from one armed intrusion profile straight to another.
- **Arming a profile that is already armed or arming** does nothing.
- **During `pending` or `triggered`** arming is refused: disarm first. For an intrusion profile this
  holds while any intrusion profile is pending or triggered.

## Arming, disarming, silencing

- **Arm a profile.**
  - Already armed or arming: nothing happens.
  - The profile is pending or triggered: refused ("an alarm is on: disarm first").
  - An intrusion profile, while another intrusion profile is pending or triggered: refused.
  - A contact sensor of the profile is open: refused, with the list of open sensors. The hub page
    offers **Arm anyway**; the open devices are then ignored in this profile (all their reports)
    until it is disarmed. A restart also clears that list. Nothing else can force.
  - Otherwise: `arming` if the arm delay is not 0, else `armed`. For an intrusion profile the armed
    intrusion profile is disarmed in the same step.
- **When an arm ends in `armed`** (a profile armed from disarmed, also a new one), each of its
  hazard sensors (water leak, smoke, gas, carbon monoxide) that is still active counts as going off
  now. Motion, presence and vibration are ignored. This check runs only then: not when an alarm ends,
  not after a silence and not at start-up. One corner: a keypad panic during the arm delay sounds the
  alarm before the profile has reached `armed`. That arm is not over, so when the panic's alarm ends
  (by its time or by a silence) the profile ends in `armed` and the check runs then.
- **Disarm a profile:** from any state to `disarmed`. Its outputs stop, except those you marked
  "leave it so".
- **Disarm with no profile named** (the page's main Disarm button, a keypad, `alarm_state =
  disarmed`): every intrusion profile is disarmed, and every other profile that is pending or
  triggered is silenced. A flood or fire profile stays armed.
- **Silence a profile:** pending or triggered ends now. The profile goes where it would go when the
  alarm time ends: back to `armed`, or to `disarmed` after a panic from disarmed. The page's card
  has a **Silence** button while a profile is pending or triggered.
- **A refused arm** that did not come from the hub page is told to you, because otherwise you would
  leave thinking the house is guarded: a notification and an event (see
  [Notifications](#notifications) and [Your own reactions](#your-own-reactions)).

Who can do what:

| From | Arm | Disarm one | Disarm all / silence | Force |
|---|---|---|---|---|
| Hub page | yes | yes | yes, and silence one | yes |
| Rules, Lua, MQTT, Home Assistant (the Alarm device) | yes | yes | `alarm_state = disarmed` | no |
| ZHAC Cloud (scenes, the app: the Alarm device) | yes | only with "Allow the cloud to disarm the alarm" on the hub page, off by default | only with the same switch | no |
| Keypad | the profile with the button's role | no | disarm, with a code or from a trusted keypad | no |

None of them but the keypad asks for a code. A keypad arms without a code too.

## What sets it off

A sensor counts only in the profiles you put it in, and a sensor can be in any number of profiles.
For example, the window contacts might count in away, home and night, the indoor motion sensors in
away only, and a leak sensor in Flood.

| Sensor | Counts when | At arming |
|---|---|---|
| contact (door, window) | it **opens**. A repeated "open" report is not a new opening. | open: the arm is refused |
| occupancy, presence, vibration | it reports motion, presence or vibration (every such report) | ignored |
| water leak, smoke, gas, carbon monoxide | it changes to **true** (wet, smoke, gas, CO). A repeated "true" is not a new event. | still true: the alarm, once armed |

- **Delayed sensor** (the front door, say): starts the trigger delay (`pending`). Every other sensor
  triggers at once, also while `pending` runs.
- **The class does not filter keys.** Any sensor can be in any profile: a smoke sensor in an
  intrusion profile triggers it.
- **Panic, emergency or fire on a keypad** triggers an intrusion profile from any state, also
  disarmed (see [Keypads](#keypads)). When the alarm time ends, the profile goes back to the state it
  was in before.
- While a profile is `arming` its sensors are not counted. A hazard sensor that is active when the
  arm ends counts then (see above).

### Open doors and windows

Arming is refused while a contact sensor of that profile is open. The hub page lists the open ones
on the profile's card and offers **Arm anyway**. A forced arm ignores those devices until you
disarm. A restart also clears the list, so the profile comes back with every sensor guarded.

A keypad, a button, a rule, Lua, MQTT or Home Assistant cannot force. When an arm from one of them
is refused, the hub tells you: a notification ("Not armed (Away): Bathroom window is open") and the
event `Event#alarm_arm_failed_<id>` (also `Event#alarm_arm_failed`).

### A sensor that stays active

A contact or hazard sensor that is still open or active when its alarm ends does not start a new
one, however the alarm ended: by its time, by a silence, by a restart (bar the one corner at the end
of this section). It counts again once it has closed or cleared. A fire that still burns when the
alarm time ends therefore does not sound again; the alarm time is your setting. Only arming from
disarmed checks hazard sensors anew. The one corner: when a keypad panic sounds during the arm
delay, that arm has not yet reached `armed`, so the check runs when the panic's alarm ends, and a
hazard sensor still active then counts as going off (see
[Arming, disarming, silencing](#arming-disarming-silencing)).

## Outputs

Each output has a kind, which depends on what the device offers:

| Kind | For | On alarm | Stops |
|---|---|---|---|
| `warning` | IAS WD sirens (Heiman, Develco, Bitron, AduroSmart, ...) | sends `warning` with the chosen mode (`burglar`, `fire`, `emergency`, `police_panic`, `fire_panic`, `emergency_panic`), level (`low`, `medium`, `high`, `very_high`) and strobe, lasting the alarm time left | `warning` off |
| `alarm` | Tuya-style sirens that expose an `alarm` switch | sets the tone (`melody` / `ringtone`) and `volume` you chose, the device's own `duration` (the alarm time left, within the device's range), then `alarm` on | `alarm` off |
| `state` | any switch, plug or valve | sets `state` to the value you chose, on or off | the opposite value, unless "leave it so" |

- **Melody and volume are plain text** of up to 23 bytes of UTF-8, no control characters. The page
  offers the siren's own values.
- **The hub's own speaker.** On a board with a speaker, the device **Hub Sound** appears in the
  Safety page's output list as an output of kind `warning`, like an IAS siren
  ([SOUND.md](SOUND.md#the-hub-sound-device)). It plays looped sounds: mode `burglar` the `alarm`
  sound, `fire` and `fire_panic` the `fire` sound, `emergency`, `police_panic` and `emergency_panic`
  the `siren` sound. The level gives the volume (`low` 25, `medium` 40, `high` 55, `very_high` 70, never
  above 70), and the strobe is ignored. It stops when the alarm ends, or after 10 minutes at the most.
  These are urgent sounds, so a muted hub still sounds the alarm. To keep the speaker out of the alarm,
  leave Hub Sound out of the outputs.
- **Leave it so** (kind `state` only): the output is set once and left so. A valve closed by a leak
  stays closed until you open it. The hub never sends the opposite value to such a device: not when
  an alarm ends, not when you disarm or silence, not when another profile's alarm ends, not after a
  restart, also when you save in the minute after it (see [Notifications](#notifications)). The page
  ticks it by default for a switch set to off.
- **A "leave it so" output is set on every alarm**, even one that is silenced or ends at once: a
  valve closes for every leak alarm, however short. It follows the settings the alarm went off
  under: a save made before the hub has acted on a short alarm still closes a valve that the save
  removes, and does not close one that the save adds, for that earlier alarm.
- **One device as a `state` output in several profiles** must have the same value and the same
  "leave it so" in all of them. A save that breaks this is refused, so no profile can reopen a valve
  another one closed. A device can be listed once in a profile.
- **Order.** A profile's outputs are driven in the order listed, so a valve can come before the
  sirens.
- **One device in several sounding profiles.** After every change of any profile the hub works out
  each output device anew. It follows the triggered profile that lists it; with several, the class
  order (fire, gas, water, other, intrusion), then the profile order. When that profile's alarm
  ends, the next one takes the device over for the time it has left. With none, the device is
  stopped, unless it is left so. An intrusion alarm that ends does not silence a fire alarm that
  still sounds.
- Saving the settings checks that each output's device has something to set for its kind: a smoke
  sensor's `alarm` is only a reading, and is refused as an output of kind `alarm`.

## Keypads

The hub understands IAS ACE keypads and arm/disarm keyfobs: devices whose `action` reports
`arm_all_zones`, `arm_day_zones`, `arm_night_zones`, `disarm`, `panic`, `emergency` or `fire`. Add
them under **Keypads and codes** on the Safety page.

| Keypad | Does |
|---|---|
| arm all zones | arms the intrusion profile with the keypad button `away` |
| arm day zones | arms the intrusion profile with the keypad button `home` |
| arm night zones | arms the intrusion profile with the keypad button `night` |
| disarm | disarms every intrusion profile and silences every other profile that sounds, if the code matches one of the codes (or the keypad is trusted) |
| panic / emergency / fire | triggers the intrusion profile that is not disarmed (arming, armed or pending); it returns to `armed` afterwards. With every intrusion profile disarmed, it triggers the first one in the list, which returns to `disarmed` |

- With no profile for a button, or no intrusion profile for a panic, the press is ignored and
  logged. A keypad's arm is refused for an open door like any other arm, and you are told.
- A keypad's disarm does not switch a flood or fire profile off: it silences it, and the profile
  stays armed.
- **Codes:** up to 8 codes of 4-8 digits. A keypad's code is checked on the hub. It shows in the hub
  page's live view of the keypad, but it never goes to the cloud.
- **Trusted keypads** disarm without a code. Use this for a keyfob that has no keypad.
- **No feedback yet (planned for stage 2).** The hub does not answer the keypad, so its own lights
  and beeps may not show the alarm's state; some keypads may beep an error or repeat the command.
  The arm or disarm still works.

## Notifications

- **A profile is triggered:**
  - the ZHAC Cloud app gets a critical push plus an inbox entry, when the hub is linked;
  - Telegram gets a message, when it is set up;
  - the text names the sensor and the profile ("Front door (Away)", "Kitchen leak sensor (Flood)"),
    or the keypad for a panic ("Panic button on Hall keypad").
  - An alarm always notifies; it does not depend on "Notify when it is armed or disarmed".
- **An arm refused for open doors or windows** (see above): "Not armed (Away): Bathroom window is
  open", or "Not armed (Away): Bathroom window and 2 more are open".
- **Armed and disarmed**, for a profile that has "Notify when it is armed or disarmed" ticked:
  "Armed (Night)" when the profile reaches armed (after the arm delay, if there is one), and
  "Disarmed (Fire)" when a disarm really changed the state. The return to `armed` after the alarm
  time sends nothing. When one intrusion profile replaces another, only the "Armed" message goes
  out.
- Each message ends with the time it happened ("... at 02:13") once the hub's clock is set.
- **Two profiles, one sensor.** A trigger alert is keyed by its sensor, as in v2026112401, so when
  one sensor triggers two profiles within the cloud's repeat window the phone gets one push. The
  armed and disarmed alerts carry the profile's id, so two profiles never hide each other.
- **Two pushes for a leak or smoke event.** The cloud already announces smoke, water leak, gas and
  carbon monoxide for every device by itself, and the hub's alert for a profile is a second push.
  The hub keeps sending its own: it is the one that survives an outage. A later cloud update should
  drop the duplicate.
- **The hub restarts during `pending` or `triggered`:** each profile comes back to the state it was
  in before the alarm (armed, or disarmed after a panic from a disarmed profile) and, a minute
  later, the hub sends "The hub restarted during an alarm" and switches off the outputs that were
  sounding (unless a new alarm sounds them by then). Those left so get their value once more
  instead: the restart may have come before the hub sent it, and a valve must still close.
  - **Which outputs.** Those of the settings in force at the restart. A save in that minute that
    changes the profile's outputs does not change what is switched off, except for a switch that
    the settings in force then leave so: it never gets the opposite of the value they leave it at.
    A switch the save leaves so at on is not switched off, and one it leaves so at off (a closed
    valve) is not switched on.
  - **A disarm in that minute** switches those outputs off at once (an output left so gets its
    value again instead), without waiting for the minute. Any accepted disarm does it, of any
    profile: from the hub page, the Alarm device (a rule, Lua, MQTT, Home Assistant, a cloud scene)
    or a keypad. The notice still comes at the minute, and nothing is switched off twice.
  - **A second restart in that minute** still switches them off. The hub keeps the job in flash
    until it is done, in a record `bt` of its own in its `alarm` storage.
- **The network is down when a notification is due** (an internet outage, a router still booting
  after a power cut): the cloud notification waits on the hub and goes out when the cloud link is
  back, and Telegram is tried again every 30 s for 10 minutes. A restart in the meantime loses what
  is still waiting.

## Your own reactions

Rules and Lua see the Alarm device like any other device: each profile's attribute and `alarm_state`
change on `Alarm#...`. On every change of every profile the hub also fires a named event
`alarm_<state>_<id>`, state first, so no two ids can give the same name:

- `Event#alarm_armed_night`, `Event#alarm_arming_away`, `Event#alarm_pending_away`,
  `Event#alarm_disarmed_fire`: the profile moved to that state.
- `Event#alarm_triggered_flood`: an alarm of that profile started, also when it is over again by the
  time the hub looks.
- `Event#alarm_arm_failed_<id>` and `Event#alarm_arm_failed`: an arm of that profile was refused for
  open doors or windows (not from the hub page).

The names of v2026112401 still work: `Event#alarm_<alarm_state value>` (`alarm_triggered`,
`alarm_disarmed`, `alarm_arming`, `alarm_pending`, `alarm_armed_away`, ...) follows the intrusion
summary, and `alarm_triggered` fires for an intrusion alarm only. `alarm_armed_<id>` is the same
event in both lists and fires once. A rule written against `alarm_state`, `alarm_sensor` or one of
these events keeps working.

```
# Lights on and an RGB strip blinking when the intrusion alarm goes off
ON Alarm#alarm_state="triggered" DO zigbee.set hall_light state 1; zigbee.set led_strip effect blink ENDON

# The flood profile has its own attribute
ON Alarm#flood="triggered" DO zigbee.set hall_light effect blink ENDON
ON Event#alarm_triggered_night DO zigbee.set bedroom_light state 1 ENDON

# A siren with its own signal, from a rule
ON Event#alarm_triggered_fire DO zigbee.set garden_siren warning fire,very_high,1,60 ENDON

# Arm and disarm with a button
ON hall_button#action="single" DO zigbee.set Alarm night armed ENDON
ON hall_button#action="double" DO zigbee.set Alarm alarm_state disarmed ENDON
ON hall_button#action="hold" DO zigbee.set Alarm fire disarmed ENDON

# A message of your own when it arms
ON Event#alarm_armed_night DO publish home/alarm night ENDON

# Blink the hall light when the button could not arm
ON Event#alarm_arm_failed DO zigbee.set hall_light effect blink ENDON
```

A rule's value is at most 19 characters: `fire,very_high,1,60` fits, `police_panic,high,1,60`
does not. For a longer signal, add the siren as an output of the profile.

On a board with a speaker, rules can also play sounds: exit and entry beeps for a profile are in
[SOUND.md](SOUND.md#exit-and-entry-beeps-for-an-alarm-profile).

Rules refer to the device by its name. If you rename the Alarm device, use the new name or its IEEE
address. The **Safety** page builds the two common rules for you (**Add a reaction**, **Arm with a
button**) in its **Rule shortcuts** card; they are ordinary rules you can change on the Rules page.

- **Devices.** A rule built there names a device by its name when the name reads as one word in a
  rule and no other device has that exact name; the hub's rules take the first match, skipping
  removed devices. Otherwise it uses the device's IEEE address.
- **Names.** A reaction is named `Alarm <id> <state>` ("Alarm flood triggered"). A button's rule is
  `Button arms <id>` or `Button disarms <id>`; a button for every profile is `Button disarms`. A
  name is at most 23 bytes, and the page never cuts one. When the long form does not fit, its first
  word goes: a 13-character id gives `abcdefghijklm triggered` and `arms abcdefghijklm`. A different
  profile, state or button target always gives a different name.

```lua
local ALARM = "0x025A484143414C00"

zhac.on_attr_change(ALARM, "flood", function(_, _, state)
  if state == "triggered" then
    zhac.set_attr("0x00158D0001020304", "state", true)
  end
end)

zhac.set_attr(ALARM, "night", "armed")                -- one profile
zhac.set_attr(ALARM, "alarm_state", "armed_night")    -- the intrusion summary: same thing here
```

## Arming and disarming from outside

You can set the Alarm device's attributes from all of these:

- the hub page;
- rules and Lua: a profile's attribute (`armed`, `disarmed`) or `alarm_state` (`armed_<id>` of an
  intrusion profile, `disarmed`);
- MQTT, with discovery on (`<root>/devices/025A484143414C00/<id>/set` with `armed` or `disarmed`,
  or `<root>/devices/025A484143414C00/alarm_state/set` with `armed_<id>` or `disarmed`);
- Home Assistant, where each profile's attribute and `alarm_state` show up as a select. The select
  lists all five states, of which only the ones above can be set. A proper alarm panel entity for
  Home Assistant comes later;
- ZHAC Cloud, through a scene. For example, an "Arm night" scene sets the Alarm device's `night`
  attribute to `armed`. A "Disarm" scene (`alarm_state` set to `disarmed`) works only while
  **Allow the cloud to disarm the alarm** is on (Settings → Remote on the hub page). The cloud's
  device card has no control for these attributes yet.

**No code is asked for any of these.** Anyone who can publish to your MQTT broker or control the device
from Home Assistant can disarm the alarm, and that now includes the flood and fire profiles. Secure
those the way you would secure the door. Forcing past open sensors is only on the hub page.

**The cloud is held back by a switch.** Settings → Remote has **Allow the cloud to disarm the
alarm**, off on every hub (and after a storage reset). Off: the cloud and the app can arm the alarm
while no other profile is armed, but not disarm it; the hub refuses a disarm, an arm that would stop
another profile (Night in place of Away), any other change to the Alarm device, and a rule saved,
run or enabled from the cloud whose actions write to the Alarm device, with `alarm_off`, and the app says to turn
the switch on at the hub. A rule that only reads the Alarm device (a trigger or a condition) still saves.
On: anyone who can control the alarm through your cloud account can disarm it, so the same care as for
the door applies to who is a member of the hub. Either way, every change to the Alarm device that the
cloud makes and the hub accepts raises a hub alert (to ZHAC Cloud, Telegram and the hub log, with the
account that made it), and so does every rule the cloud saves, runs or enables whose actions write to
the Alarm device. The switch comes on top of **Cloud control**: the cloud
needs at least the *Devices* level to write to any device. See
[`WS_API.md`](WS_API.md#the-alarm-switch).

## Updating from v2026112401

v2026112401 had three modes: away, home and night. A hub updated from it keeps its config, its armed
state and every rule written against `alarm_state`, `alarm_sensor` and `Event#alarm_*`. The page that
was called Security is now Safety, and an old `#/security` link still opens it.

What becomes what, when the hub reads the old config:

| In v2026112401 | In Safety |
|---|---|
| The modes away, home, night | Three intrusion profiles with the ids `away`, `home`, `night`, the keypad buttons of the same names and the names Away, Home, Night |
| The exit delay (away only) | `away`'s arm delay. `home` and `night`: 0 |
| The entry delay, the siren time, "notify on arm" | The same values in all three profiles |
| Each siren | An output of all three profiles (8 sirens become 24 outputs) |
| Each sensor, with its modes and entry flag | A sensor of the profiles of its modes, delayed in each of them when it was an entry sensor |
| Keypads, trusted keypads and codes | Unchanged |
| The armed mode | That profile armed. "Restarted during an alarm" still works |

A hub that never had a config starts with the same three empty profiles, so the page looks as it
did. A full backup made on v2026112401 loads too: the old records are read whenever they are met.

- The old config record is read, never changed. The Safety config is a new record, first written
  when you save on the Safety page. Until then the hub reads the old record at every start.
- The wording of a notification changes: "Front door (armed away)" becomes "Front door (Away)".

**Going back keeps the old config.** If you fall back to v2026112401, by itself after a bad update
or by hand, the hub is still armed in the mode it was in, with the sensors, sirens and delays it
had when you updated. The hub keeps the old state record current while it runs this firmware: an
intrusion profile shows there as its mode (`away`, `home` and `night` as themselves, another
profile as the mode of its keypad button, else as away). Edits made on the Safety page are not seen
by the old firmware, and flood, fire and gas profiles do nothing there: v2026112401 has no such
profiles.

**Updating again after a fall back:**

- **The armed state is carried.** If you armed or disarmed on v2026112401, the intrusion profiles
  come back as that says. The other profiles come back as they were.
- **A mode armed on v2026112401 comes back on the intrusion profile with that id (away, home,
  night), else on the one with that keypad button.** A new name changes nothing. Only when that
  profile was deleted before the fall back and no other profile has its keypad button do the
  intrusion profiles come back disarmed. The page shows the state.
- **The config is carried until the Safety page has saved.** The Safety config record is written
  only by a save on the Safety page. Before the first save the hub converts the old record again at
  every start, so a config you changed on v2026112401 during the fall back is taken over. Once the
  Safety page has saved, its config is used, and a change made on v2026112401 is not: a sensor you
  added there is unguarded until you add it on the Safety page again.
- **A fall back in the minute after a restart during an alarm** can leave the `bt` record (see
  [Notifications](#notifications)) in flash, because the older firmware does not know it. The next
  update to this firmware then sends one more "The hub restarted during an alarm" and switches
  those outputs off once more.

## Limits

| | |
|---|---|
| Profiles | 8 |
| Sensors | 48 different devices, each in any number of profiles |
| Outputs | 8 in a profile, 32 in all |
| Keypads | 8 |
| Codes | 8, each 4-8 digits |
| Arm delay and trigger delay | 0-300 s |
| Alarm time | 10-1800 s (default 180) |
| Profile id | 1-13 characters of `a-z`, `0-9`, `_`, starting with a letter |
| Profile name | 1-24 bytes of UTF-8 |
| Roles | `away`, `home`, `night`, each once, intrusion only |
| Melody, volume | up to 23 bytes of UTF-8, plain text |
| A WebSocket frame to the hub | 32 KB. The largest config the limits allow is about 22 KB as JSON |
| The config in flash | 8 KB. The stored form is packed so the largest config the limits allow fits; a save that does not fit is refused ("could not save the config") |

The config and the state of every profile are kept in the hub's flash. They survive restarts and
updates. For the WebSocket commands behind the page, see [WS_API.md](WS_API.md#safety). Three of
their rules matter to a script of your own:

- `alarm.config.set` needs `profiles` as a list (`[]` for none). The v2026112401 form is refused
  there ("profiles must be a list"); the hub converts it only from its own stored record, at start.
- A profile's `id` must be text that is not empty. Only leaving `id` out names no profile (for
  `alarm.disarm`: all of them), so an `id` of `null` or `""` is answered "no such profile" and
  changes nothing.
- `alarm.get` answers the error `oom` when the hub has no memory for the whole answer: it never
  sends part of the config as if it were all of it.
