# ZHAC Rules DSL Reference

The Rules DSL lets you define event-driven automations without writing a Lua script. Rules are stored on P4 and evaluated in real-time as device attributes change, cron timers fire, or custom events arrive. When declarative rules aren't enough, a rule can invoke a named Lua script via the `script.run` action — see `docs/LUA_API.md` for the scripting reference.

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

Fires when a Zigbee device reports an attribute value. `device_ref` is either a friendly name or an IEEE address string (`0x001234567890ABCD`).

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
ON kitchen switch#action=single DO zigbee.set kitchen_light state 1 ENDON
ON 0x001234567890ABCD#temperature>2500 DO publish home/alert hot ENDON
ON door sensor#contact DO event motion ENDON
```

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
[LUA_API.md](LUA_API.md#triggers) for the exact shape.

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

Fires when a message is received on the given MQTT topic.

```
ON Mqtt#home/alarm DO zigbee.set siren state 1 ENDON
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
- `value`: integer literal, `%value%` (the trigger value), or a `%value%` expression — see
  [Value substitution & expressions](#value-substitution--expressions)

```
zigbee.set kitchen_light state 1
zigbee.set 0x001234567890ABCD brightness 128
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
ON kitchen switch#action=single DO zigbee.toggle kitchen_light state ENDON
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

## Complete Examples

### Motion sensor → lights on for 5 minutes

```
ON motion sensor#occupancy=1 DO zigbee.set hallway_light state 1 ; timer 1 300000 ENDON
ON Rules#Timer=1 DO zigbee.set hallway_light state 0 ENDON
```

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
ON kitchen switch#action=double DO event all_lights_off ENDON
ON Event#all_lights_off DO zigbee.set kitchen state 0 ; zigbee.set living_room state 0 ENDON
```

---

## Constraints

| Limit | Value |
|-------|-------|
| Actions per rule | 4 |
| Device ref length | 63 characters |
| Attribute key length | 31 characters |
| Cron expression length | 63 characters |
| Event name length | 31 characters |
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
