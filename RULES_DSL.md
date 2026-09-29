# ZHAC Rules DSL Reference

The Rules DSL lets you define event-driven automations without writing a Lua script. Rules are stored on P4 and evaluated in real-time as device attributes change, cron timers fire, or custom events arrive. When declarative rules aren't enough, a rule can invoke a named Lua script via the `script.run` action — see `docs/LUA_API.md` for the scripting reference.

> **What changed for existing rules (2026-09).** A device-attribute rule now fires when the value
> **changes**, not on every report. `ON door#contact=1 DO …` runs when the door opens, and no
> longer again each time the sensor repeats "open" as a heartbeat (a Tuya contact sensor does so
> about every 4 hours, and used to switch a socket on by itself). A reboot, saving or editing a
> rule, or renaming a device no longer fires anything either. Buttons and other event-like
> attributes (`action`, `click`, `event`, `scene`) still fire on every press, and time, event,
> timer, MQTT and boot triggers work as before. Check the rules that relied on repeats:
>
> - A motion rule that restarts a timer (`ON sensor#occupancy=1 DO … ; timer 1 300000 ENDON`)
>   now starts it when motion **begins**: a sensor repeating `occupancy=1` while you stay in the
>   room no longer extends it. `ON sensor#occupancy DO zigbee.set light state %value% ENDON`
>   follows the sensor instead.
> - A sensor that never reports "no motion" itself (the Aqara RTCGQ11LM family) stays at
>   `occupancy=1`, so `#occupancy=1` fires only once. Set its **occupancy timeout** (the
>   device's options) so the hub reports `occupancy=0` after that many seconds without motion.
> - A threshold rule such as `#temperature>2800 DO publish …` publishes once when the
>   temperature crosses 28.00, not with every report above it. Use a bare `#temperature`
>   trigger to act on every change of value.
>
> See [When device rules fire](#when-device-rules-fire) for the exact rules and
> [Rule status and "Run now"](#rule-status-and-run-now) for how to check what a rule did.

---

## Syntax

```
ON <trigger> DO <action> [; <action> ...] ENDON
```

- Everything between `ON` and `DO` is the **trigger**.
- Everything between `DO` and `ENDON` is one or more **actions**, separated by `;`.
- Maximum **4 actions** per rule.
- Whitespace around tokens is ignored.

---

## Triggers

### Device attribute change

```
ON <device_ref>#<attr>[<op><value>] DO ... ENDON
```

Fires when a Zigbee device's attribute **changes** — see
[When device rules fire](#when-device-rules-fire). `device_ref` is either a friendly name or an IEEE address string (`0x001234567890ABCD`).

The value after the operator is a number (`=1`, `>2500`) or, for text values such as a
button's `action` or a thermostat's `system_mode`, a string in **double quotes**
(`#action="single"`). An unquoted word is read as a number and the rule is rejected with
`invalid numeric literal`.

| Operator | Meaning |
|----------|---------|
| `=` | equal |
| `!=` | not equal |
| `<` | less than |
| `>` | greater than |
| `<=` | less than or equal |
| `>=` | greater than or equal |
| *(none)* | any value change |

```
ON kitchen switch#action="single" DO zigbee.set kitchen_light state 1 ENDON
ON 0x001234567890ABCD#temperature>2500 DO publish home/alert hot ENDON
ON door sensor#contact DO event motion ENDON
```

#### When device rules fire

The hub remembers, per rule, the last value of the trigger attribute and whether the comparison
held for it. A report that changes nothing does not fire the rule.

| Trigger | Fires when |
|---------|------------|
| `#attr` with a comparison (`=`, `!=`, `>`, `<`, `>=`, `<=`) | the comparison goes from not holding to holding. It does not fire again while it keeps holding, and fires again after it stopped holding in between (`>2500`: 2400 no, 2600 **yes**, 2700 no, 2400 no, 2600 **yes**). |
| bare `#attr` (no comparison) | the value differs from the last one (`contact` 1 **yes**, 1 no, 0 **yes**, 0 no, 1 **yes**). `%value%` is the new value. |
| `#action`, `#click`, `#event`, `#scene`, with or without a comparison | **every** report that matches: these attributes are events (a button press, a cube shake), not state. `ON cube#action="shake"` fires on every shake. |
| bare `ON <device>` (wildcard, below) | every report of any attribute, as before. |

Where the memory comes from:

- **An attribute with no known value is "unknown"**: the first report that matches fires. This
  is the case for a new rule on a device that has never reported that attribute.
- **Boot.** The hub restores each device's last reported values when it starts (the values the
  web UI shows), and every rule starts from them. The first report after a reboot that repeats
  the stored value does not fire; a real change does. (The single-chip S3 build restores no
  values, so there every rule starts unknown after a reboot.)
- **Saving, editing, enabling, renaming.** Whenever rules are (re)loaded (a rule saved, edited or
  enabled again, or every rule after a device rename), each rule starts again from the device's
  current value. Saving a rule while the door is open does not fire it; neither does an unrelated
  edit or a rename. When the hub has no stored value for the attribute (a device with more than
  32 attributes), an edited or reloaded rule keeps what it already knew.
- The memory is RAM only: nothing is written to flash on a report.

#### Wildcard: any attribute on a device

Omit the `#<attr>` suffix entirely to match **every** attribute change on
that device. Intended for handing off routing to a script:

```
ON kitchen_motion DO script.run "kitchen_motion" ENDON
ON 0x001234567890ABCD DO script.run "router" ENDON
```

The Lua handler receives the full event context in its single table
argument (`ev.key`, `ev.value`, `ev.int_val`, `ev.cluster`, `ev.attr_id`,
`ev.ieee`, etc.) and can dispatch however it wants — see
[LUA_API.md](LUA_API.md#triggers) for the exact shape. The wildcard fires on
**every** report, repeats included: the script decides what counts as a change.

### System boot

```
ON System#Boot DO ... ENDON
```

Fires once when P4 starts up.

```
ON System#Boot DO zigbee.set all_lights state 0 ENDON
```

### Cron timer

```
ON Time#Cron=<expr> DO ... ENDON
```

`<expr>` is a cron expression: `sec min hour mday month wday`

Fields support: single values, `*` (any), and comma-separated lists.

```
ON Time#Cron=0 0 7 * * 1-5 DO zigbee.set bedroom_blinds position 100 ENDON
ON Time#Cron=0 30 22 * * * DO zigbee.set all_lights state 0 ENDON
```

Schedules follow the hub's clock, and no ZHAC board has a battery-backed one: the hub sets it
from the internet (`pool.ntp.org`) after it gets an address. Until then, scheduled rules and
Lua cron handlers wait rather than fire at the wrong time, and the Rules page says so. A hub
with no internet access can be pointed at a time server on that network (Settings, Time), which
is the only way its clock returns after a power cut on its own; otherwise it takes the time
from the browser that opens its web UI, and needs that again after every power cut. All other
triggers work without the clock.

### Named event

```
ON Event#<name> DO ... ENDON
```

Reacts to an event fired by `zhac.event(name)` from a Lua script or another rule's `event` action.

```
ON Event#motion_detected DO zigbee.set hallway_light state 1 ENDON
```

### Timer

```
ON Rules#Timer=<n> DO ... ENDON
```

Fires when timer `n` expires (set via the `timer` action). `n` is a timer index (1–8).

```
ON Rules#Timer=1 DO zigbee.set hallway_light state 0 ENDON
```

### MQTT topic

```
ON Mqtt#<topic> DO ... ENDON
```

Fires when a message is received on the given MQTT topic. The topic is matched exactly, root
included, and the hub only receives topics under its root (`zhac/…` by default) — see
[MQTT_API.md](MQTT_API.md#your-own-messages-rules-and-lua).

```
ON Mqtt#zhac/home/alarm DO zigbee.set siren state 1 ENDON
```

---

## Actions

Multiple actions are separated by `;`. Maximum 4 per rule.

### `zigbee.set <device_ref> <key> <value>`

Set a device attribute by semantic key name.

- `device_ref`: friendly name or IEEE address string. **Single token, no quotes** — action
  arguments split on spaces and quotes are not stripped, so a name containing spaces cannot
  be used here; rename the device (e.g. `kitchen_light`) or use its IEEE address. (Trigger
  device names before `#` *may* contain spaces.)
- `key`: `state`, `brightness`, `color_temp`, `hue`, `saturation`, or any registered attribute name
  (up to 31 characters; a longer key is rejected at save time with "attr key too long")
- `value`: integer literal, a decimal literal such as `21.5` (the device's converter scales
  it — a thermostat setpoint goes out as 2150, a Tuya datapoint with divisor 10 as 215; a
  converter that only takes integers refuses it and the log says "no tz converter"),
  `%value%` (the trigger value), or a `%value%` expression — see
  [Value substitution & expressions](#value-substitution--expressions). Note that
  `%value%` of a decimal attribute is the raw ×100 integer, so `zigbee.set valve
  current_heating_setpoint 21.5` is what you write by hand, not `2150`.

```
zigbee.set kitchen_light state 1
zigbee.set 0x001234567890ABCD brightness 128
zigbee.set radiator_valve current_heating_setpoint 21.5
```

### `zigbee.toggle <device_ref> <key>`

Read the current shadow value for `key` on the named device and send the inverted binary value. Only meaningful for binary attributes (e.g. `state`, `on_off`): if the shadow value is `0` it sends `1`, and vice versa. If the attribute is absent from the shadow cache, or its value is not `0` or `1`, the action logs a warning and no-ops rather than guessing.

- `device_ref`: friendly name or IEEE address string — same rule as `zigbee.set`:
  single token, no quotes
- `key`: binary attribute name (e.g. `state`)

```
zigbee.toggle kitchen_light state
zigbee.toggle 0x001234567890ABCD on_off
```

```
ON kitchen switch#action="single" DO zigbee.toggle kitchen_light state ENDON
```

### `publish <topic> <payload>`

Publish to MQTT. `topic` and `payload` are space-delimited tokens (no spaces within each);
the payload may also be a `%value%` expression (spaces allowed inside the expression) — see
[Value substitution & expressions](#value-substitution--expressions).

```
publish home/status online
publish home/temp 22
publish home/temp/c %value%/100
```

### Value substitution & expressions

The `<value>` of `zigbee.set` and the `<payload>` of `publish` accept, besides a literal:

- **`%value%`** — the raw trigger value, passed through. For a `Mqtt#` trigger this is the
  message payload; for a device trigger it is the reported value as an integer.
- **An integer expression over `%value%`** — evaluated when the rule fires:

```
ON motion#occupancy   DO zigbee.set lamp state %value%            ENDON   # passthrough
ON door#contact       DO zigbee.set lamp state !%value%           ENDON   # invert: open=1 → off
ON sensor#illuminance DO zigbee.set lamp brightness %value%/4     ENDON   # scale
ON sensor#lux         DO zigbee.set lamp brightness (%value%*10)/3+5 ENDON
ON room#temperature   DO publish home/temp/c %value%/100          ENDON   # ×100 float → whole units
```

Expression rules:

- Operators `+ - * / %` (integer, C precedence), parentheses, unary `-` and `!`
  (`!` maps `0 → 1`, anything else `→ 0`). One variable: `%value%`. Spaces are allowed.
- All arithmetic is 32-bit integer; overflow clamps, division truncates. Float attributes
  (e.g. `temperature`) reach rules as the value ×100, so `%value%/100` yields whole units.
- Limits (rule is rejected on save if exceeded): expression ≤ 48 characters,
  ≤ 12 operations, parentheses ≤ 6 deep. Division by a literal `0` is rejected on save.
- If the divisor evaluates to `0` at fire time, or the trigger value is not numeric
  (a string attribute), the action is **skipped** with a warning — nothing is sent.
- Expressions are compiled once when the rule is saved; evaluation per fire is a few
  integer operations.

### `event <name>`

Fire a named event on the internal bus. Triggers rules with `ON Event#<name>`.

```
event lights_off
```

### `timer <index> <ms>`

Set a countdown timer. When it expires, fires `ON Rules#Timer=<index>`.

```
timer 1 30000
```

Fires `ON Rules#Timer=1` after 30 seconds.

### `log <message>`

Write a message to the serial log (ESP-IDF INFO level).

```
log rule triggered OK
```

### `script.run <name>`

Invoke a stored Lua script by filename (no extension). The script is loaded from SPIFFS at `/scripts/<name>.lua`, run on the Lua `TaskLua` coroutine scheduler, and receives a single event table with `{value, key, ieee, cluster, attr_id, val_type, int_val, str_val}` — for attribute triggers the backend fills every field from the ZCL event; for non-attribute triggers (`System#Boot`, `Event#…`, `Rules#Timer=…`, `Time#Cron=…`) most fields are empty. See `docs/LUA_API.md` §4 for the full event shape.

- `<name>`: alphanumeric + `_` + `-`, up to 24 characters. Must match an uploaded script (see `docs/LUA_API.md`).

```
ON motion sensor#occupancy=1 DO script.run motion_hallway ENDON
```

Fire-and-forget: the rule action returns as soon as the run request is queued on `TaskLua`. A dropped request (queue full) logs a warning but does not fail the rule. See `docs/LUA_API.md` for the `zhac.*` API available inside scripts.

---

## Rule status and "Run now"

The hub keeps, per rule, in RAM (reset on reboot):

- **Last ran**: when the rule last ran, as epoch seconds once the hub's clock is set, else as
  seconds since boot;
- **Runs**: how many times it ran since boot;
- **Last skip**: why it last did not run, or which action failed when it ran:
  `unchanged` (a report of its trigger changed nothing), `condition_false` (a report did not
  match the comparison) or `action_error:<action>` (for example `action_error:zigbee.set`: the
  device was not found or the command was not sent; `action_error:publish`: MQTT is off or not
  connected). A clean run clears it.

The Rules page shows them next to each rule and refreshes them every 5 seconds while it is
open. Its **Run now** button runs a rule's actions at once, as if the trigger had fired: the
comparison is not checked, a disabled rule runs too, and `%value%` is the trigger attribute's
current value (empty for a trigger that is not a device attribute). Run now counts as a run and
leaves the rule's memory alone, so the next real change still fires it.

Every run writes one line to the log (INFO), which the Logs page shows:

```
I (…) simple_rules: rule 'door open' fired (tuya_contact#contact=1)
I (…) simple_rules: rule 'printer' fired (Time#Cron)
I (…) simple_rules: rule 'door open' run now (tuya_contact#contact=1)
```

For clients: the WebSocket commands are `rules.status` (reply data
`[{"id", "last_fired", "runs", "last_skip", "ago"}]`, `ago` = seconds since the last run, present
when `runs` > 0) and `rule.run` `{"id"}` — see [WS_API.md](WS_API.md#rules). They exist on the
wired (S31, P4 + C6) firmware; the rule objects from `rule.list`, `GET /api/rules` and the
`rule.*` pushes carry none of these fields.

---

## Complete Examples

### Motion sensor → lights on for 5 minutes

```
ON motion sensor#occupancy=1 DO zigbee.set hallway_light state 1 ; timer 1 300000 ENDON
ON Rules#Timer=1 DO zigbee.set hallway_light state 0 ENDON
```

The timer starts when motion begins (`occupancy` goes from 0 to 1); a repeated `occupancy=1`
does not restart it.

### Door contact → MQTT alert

```
ON front door#contact=0 DO publish home/door opened ; log door opened ENDON
```

### Night mode at 22:00

```
ON Time#Cron=0 0 22 * * * DO zigbee.set living_room state 0 ; zigbee.set bedroom brightness 30 ENDON
```

### Chained events

```
ON kitchen switch#action="double" DO event all_lights_off ENDON
ON Event#all_lights_off DO zigbee.set kitchen state 0 ; zigbee.set living_room state 0 ENDON
```

---

## Constraints

| Limit | Value |
|-------|-------|
| Actions per rule | 4 |
| Device name length | 29 characters, the longest name a device can have |
| Attribute key length | 27 characters |
| Cron expression length | 63 characters |
| Event name length | 63 characters |
| MQTT topic length | 63 characters |
| Timer indices | 1–8 |
| Rule DSL source length | 499 bytes |

---

## Error Codes

When `POST /api/rules` fails, the response contains a parse error. Common causes:

| Error | Cause |
|-------|-------|
| `ERR_NO_ON` | DSL does not start with `ON ` |
| `ERR_NO_DO` | Missing ` DO ` keyword |
| `ERR_NO_ENDON` | Missing `ENDON` at end |
| `ERR_BAD_TRIGGER` | Trigger string not recognized |
| `ERR_BAD_ACTION` | Action verb not recognized or malformed |
| `ERR_TOO_MANY_ACTIONS` | More than 4 actions separated by `;` |
