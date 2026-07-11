# ZHAC Automation Cookbook

Real-world automations for ZHAC, from one-liners to small state machines,
using both automation surfaces:

- **Rules DSL** — declarative `ON … DO … ENDON` rules, evaluated on the P4 as
  events arrive. No code. Reference: [`RULES_DSL.md`](RULES_DSL.md).
- **Lua scripts** — event-driven scripts on TaskLua for logic the DSL can't
  express (timers you can cancel, per-device state, loops, math). Reference:
  [`LUA_API.md`](LUA_API.md).

Every example below is grounded in those two references. Replace the friendly
names (`kitchen_motion`, `hallway_light`, …) and IEEE addresses
(`0x00158D0001020304`) with your own devices.

> **Rules or Lua?** Reach for a **rule** first — it's simpler, survives reboots
> in NVS, and is visible in the Web UI. Drop to **Lua** when you need to hold
> state between events, cancel a pending action, loop, or do non-trivial math.
> The two compose: a rule can `event` a name that a script handles, a script can
> `zhac.event()` a name a rule handles, and a rule can call a script with
> `script.run`.

---

## 1. Rules DSL

### 1.1 Beginner

**Turn a light on with motion.**

```
ON kitchen_motion#occupancy=1 DO zigbee.set kitchen_light state 1 ENDON
```

**All lights off at 22:30** (cron is 6-field: `sec min hour dom mon dow`):

```
ON Time#Cron=0 30 22 * * * DO zigbee.set all_lights state 0 ENDON
```

**Reset a scene on boot.**

```
ON System#Boot DO zigbee.set all_lights state 0 ; zigbee.set siren state 0 ENDON
```

**Raise an MQTT alert when it gets hot** (temperature is stored ×100, so
`2500` = 25.00 °C):

```
ON greenhouse_probe#temperature>2500 DO publish home/alert/greenhouse hot ENDON
```

### 1.2 Intermediate — one rule instead of two with `%value%`

The `%value%` token is the trigger's value. It replaces the classic
"one rule for on, one for off" pattern with a single rule.

**Mirror occupancy onto a light** (motion → on, no-motion → off, one rule):

```
ON hall_motion#occupancy DO zigbee.set hall_light state %value% ENDON
```

**Invert a contact sensor onto a lamp** (door open → lamp off):

```
ON front_door#contact DO zigbee.set porch_lamp state !%value% ENDON
```

**Scale a 0–1000 dial onto 0–254 brightness** (integer expression, C
precedence, parens allowed):

```
ON living_dial#level DO zigbee.set living_light brightness (%value%*254)/1000 ENDON
```

**Publish a temperature in whole units** (the shadow keeps ×100; divide in the
action, never in the sensor):

```
ON greenhouse_probe#temperature DO publish home/temp/greenhouse %value%/100 ENDON
```

**Toggle on a button single-press.**

```
ON bedroom_button#action=single DO zigbee.toggle bedroom_light state ENDON
```

### 1.3 Intermediate — timers (auto-off, delayed action)

Timers are indices `1`–`8`, armed with `timer <n> <ms>` and fired by
`ON Rules#Timer=<n>`.

**Motion light with a 30 s auto-off** — arming the timer on each motion event
keeps the light on while there's activity, and only the last timer fires:

```
ON stairs_motion#occupancy=1 DO zigbee.set stairs_light state 1 ; timer 1 30000 ENDON
ON Rules#Timer=1            DO zigbee.set stairs_light state 0                    ENDON
```

**Bathroom fan that runs 5 minutes after the light goes off.**

```
ON bath_light#state=0 DO timer 2 300000 ENDON
ON Rules#Timer=2      DO zigbee.set bath_fan state 0 ENDON
ON bath_light#state=1 DO zigbee.set bath_fan state 1 ENDON
```

### 1.4 Advanced — chaining, events, hand-off to Lua

**Fan out one trigger to several actions** (actions run left to right, split by
`;`):

```
ON goodnight_button#action=hold DO zigbee.set all_lights state 0 ; zigbee.set thermostat setpoint 1800 ; publish home/mode night ENDON
```

**Decouple a sensor from consumers with a named event.** One rule fires the
event; any number of rules (or a Lua `zhac.on_*`) react to it:

```
ON motion_any#occupancy=1 DO event presence ENDON
ON Event#presence         DO zigbee.set hallway_light state 1 ENDON
ON Event#presence         DO publish home/presence 1           ENDON
```

**React to an MQTT command from another system.**

```
ON Mqtt#home/cmd/alloff DO zigbee.set all_lights state 0 ENDON
```

**Hand off to Lua when the logic outgrows the DSL** — the script receives the
full event context in one table:

```
ON front_door#contact=1 DO script.run "arrival" ENDON
```

> **Rule gotchas** (see `RULES_DSL.md` for the full list):
> - In **actions**, a device reference is a single space-delimited token and
>   quotes are **not** stripped — use `zigbee.set hall_light …`, never
>   `zigbee.set "hall light" …`. **Trigger** references may contain spaces
>   (they're split at `#`): `ON kitchen switch#action=single` is fine.
> - Binary attributes compare with `=1` / `=0` (`ON x#occupancy=1`), not
>   `="true"`.
> - Floats (temperature, humidity) live in the shadow as integer ×100. Compare
>   and scale accordingly (`temperature>2500`, `%value%/100`).
> - `script.run` names are quoted: `script.run "arrival"`.

---

## 2. Lua scripts

Scripts register `on_*` handlers at load; each handler runs as its own
coroutine on TaskLua when its event arrives. `zhac.sleep(ms)` is the only yield
point — use it freely, it doesn't block other events.

### 2.1 Beginner

**Log on boot.**

```lua
zhac.on_boot(function()
    zhac.log("I", "automations loaded")
end)
```

**Mirror one sensor onto one actuator** (`value` is bool/int/string per the
attribute):

```lua
zhac.on_attr_change("0x00158D0001020304", "occupancy", function(ieee, key, value)
    zhac.set_attr("0x00158D0009080706", "state", value)
end)
```

**A nightly chime** (cron handler, no coroutine gymnastics needed):

```lua
zhac.on_cron("0 0 22 * * *", function()
    zhac.log("I", "22:00")
    zhac.set_attr("0x00158D0009080706", "state", false)
end)
```

### 2.2 Intermediate — timeouts you can cancel

The DSL timer auto-off (§1.3) re-arms on every motion, but it can't be
*cancelled* when occupancy clears early. Lua can, with a generation counter:
each new motion invalidates any pending off.

```lua
local MOTION = "0x00158D0001020304"   -- occupancy sensor
local LIGHT  = "0x00158D0009080706"   -- light
local gen    = 0                       -- bumped on every occupancy=1

zhac.on_attr_change(MOTION, "occupancy", function(_, _, occupied)
    if occupied then
        gen = gen + 1
        local mine = gen
        zhac.set_attr(LIGHT, "state", true)
        zhac.sleep(30000)              -- 30 s hold; yields, doesn't block
        if mine == gen then            -- no newer motion arrived → turn off
            zhac.set_attr(LIGHT, "state", false)
        end
    end
end)
```

**Read-modify-write with `zhac.get_attr`** — nudge brightness up on a button:

```lua
zhac.on_attr_change("0x00158D0001111111", "action", function(_, _, action)
    if action == "up" then
        local b = zhac.get_attr("0x00158D0009080706", "brightness") or 0
        zhac.set_attr("0x00158D0009080706", "brightness", math.min(254, b + 25))
    end
end)
```

**Debounce a chatty leak sensor** — only alert if it's still wet after 5 s:

```lua
local LEAK = "0x00158D0002020202"
zhac.on_attr_change(LEAK, "water_leak", function(_, _, wet)
    if wet then
        zhac.sleep(5000)
        if zhac.get_attr(LEAK, "water_leak") then
            zhac.publish("home/alert/leak", "confirmed", 1, true)  -- qos1, retained
            zhac.set_attr("0x00158D0003030303", "state", true)     -- siren
        end
    end
end)
```

### 2.3 Advanced

**Multi-press button → semantic events** (the script turns raw actions into
named events that *rules* can consume — see §3):

```lua
local BTN = "0x00158D0001111111"
local last, count = 0, 0

zhac.on_attr_change(BTN, "action", function(_, _, action)
    if action ~= "single" then return end
    local now = zhac.millis()
    count = (now - last < 400) and (count + 1) or 1
    last  = now
    zhac.sleep(400)                    -- wait out the multi-press window
    if zhac.millis() - last >= 400 then
        if     count == 1 then zhac.event("scene_day")
        elseif count == 2 then zhac.event("scene_evening")
        else                    zhac.event("scene_night") end
        count = 0
    end
end)
```

**Adaptive thermostat setback** — every half hour, ease the setpoint toward a
target while nobody's home (`get_attr`/`set_attr`, plain math, cron):

```lua
local STAT   = "0x00158D0004040404"
local TARGET = 1700                     -- 17.00 °C, shadow ×100

zhac.on_cron("0 */30 * * * *", function()
    if zhac.get_attr("0x00158D0001020304", "occupancy") then return end
    local sp = zhac.get_attr(STAT, "setpoint") or TARGET
    if sp > TARGET then
        zhac.set_attr(STAT, "setpoint", math.max(TARGET, sp - 50))  -- -0.5 °C
        zhac.log("I", string.format("setback → %.1f", (sp - 50) / 100))
    end
end)
```

**Bridge a raw IAS Zone frame to MQTT** (for a device with no ZHC decoder):

```lua
zhac.on_zcl_raw(function(ev)
    if ev.cluster == 0x0500 then        -- ssIasZone
        zhac.publish("zhac/raw/ias/" .. ev.ieee, ev.hex)
    end
end)
```

**MQTT-commanded scene** — accept a command from Home Assistant / Node-RED:

```lua
zhac.on_mqtt("home/cmd/scene", function(topic, payload)
    if payload == "movie" then
        zhac.set_attr("0x00158D0009080706", "brightness", 40)
        zhac.set_attr("0x00158D000A0B0C0D", "state", false)
    elseif payload == "bright" then
        zhac.set_attr("0x00158D0009080706", "brightness", 254)
    end
end)
```

---

## 3. MQTT bridge patterns

ZHAC's MQTT gateway (S3) speaks to a broker so Home Assistant, Node-RED, or
anything else can see and drive your devices.

- **Root topic** defaults to `zhac/` (configurable in **Settings → MQTT**). All
  examples below assume it.
- **Availability** is automatic: the gateway publishes `zhac/availability`
  (`online` / `offline` via the MQTT LWT). Use it as the bridge's availability
  topic in Home Assistant.
- **Device state is *not* auto-published per attribute** — you publish what you
  want, on the topics you want (below). That keeps the broker traffic to what
  you actually consume.
- **Inbound** topics (`ON Mqtt#…` / `zhac.on_mqtt`) only fire for topics inside
  the gateway's configured **subscription filter** — set that filter to cover
  the command topics you use (e.g. `zhac/#`).
- The DSL `publish` payload is a single token with **no qos/retain**. For
  **retained** state (so a reconnecting consumer sees the last value) use Lua's
  `zhac.publish(topic, payload, qos, retain)`.

**A. State out — one attribute, one topic (rule).** Temperature is ×100 in the
shadow, so scale it:

```
ON living_temp#temperature DO publish zhac/living/temperature %value%/100 ENDON
ON front_door#contact      DO publish zhac/front_door/contact  %value%      ENDON
```

**B. State out, retained (Lua)** — survives a broker restart / HA reconnect:

```lua
zhac.on_attr_change("0x00158D0001020304", "temperature", function(_, _, t)
    zhac.publish("zhac/living/temperature", string.format("%.2f", t / 100), 0, true)  -- retain=true
end)
```

**C. Command in — MQTT drives a device (rule).** For a `Mqtt#` trigger, `%value%`
is the message payload:

```
ON Mqtt#zhac/living/light/set DO zigbee.set living_light state %value% ENDON
```

Lua when you need to parse the payload:

```lua
zhac.on_mqtt("zhac/living/light/set", function(_, payload)
    zhac.set_attr("0x00158D0009080706", "state", payload == "on" or payload == "1")
end)
```

**D. Full round-trip for one device** — the "MQTT switch" wiring HA expects
(state topic + set topic):

```
ON kitchen_plug#state         DO publish zhac/kitchen_plug/state %value% ENDON
ON Mqtt#zhac/kitchen_plug/set DO zigbee.set kitchen_plug state %value%   ENDON
```

**E. Aggregate a multi-sensor into one JSON payload (Lua).** Read the sibling
attributes with `zhac.get_attr` and publish one retained document:

```lua
local AQ = "0x00158D000A0A0A0A"          -- air-quality monitor
zhac.on_attr_change(AQ, "co2", function()
    local j = string.format(
        '{"temp":%.1f,"hum":%.0f,"co2":%d,"pm25":%d,"voc":%d}',
        (zhac.get_attr(AQ, "temperature") or 0) / 100,
        (zhac.get_attr(AQ, "humidity")    or 0) / 100,
         zhac.get_attr(AQ, "co2")  or 0,
         zhac.get_attr(AQ, "pm25") or 0,
         zhac.get_attr(AQ, "voc")  or 0)
    zhac.publish("zhac/air_quality", j, 0, true)
end)
```

**F. Per-device presence** (the LWT covers only the gateway itself):

```lua
zhac.on_attr_change("0x00158D0001020304", "occupancy", function(_, _, occ)
    zhac.publish("zhac/presence/hallway", occ and "1" or "0", 0, true)
end)
```

**G. Bridge FROM another system's topic.** Have Node-RED / HA publish to a
topic inside your subscription filter, then react:

```lua
zhac.on_mqtt("home/cmd/scene", function(_, payload)
    if     payload == "movie" then zhac.set_attr("0x…", "brightness", 40)
    elseif payload == "bright" then zhac.set_attr("0x…", "brightness", 254) end
end)
```

> A device can also be re-interviewed over MQTT by publishing to
> `zhac/devices/<ieee>/interview` — handy for onboarding tooling.

---

## 4. More device recipes

Accurate attribute keys per device class (from the ZHC exposes). Enum values
(e.g. `system_mode`) are device-specific — check the device's expose in the Web
UI. Numeric temperatures/setpoints are stored ×100.

**Cover / blinds** (`position` 0–100, `state`):

```
ON Time#Cron=0 0 7 * * 1-5 DO zigbee.set bedroom_blind position 100 ENDON   # open, weekdays 07:00
ON Time#Cron=0 30 21 * * *  DO zigbee.set bedroom_blind position 0   ENDON   # close 21:30
ON goodnight#action=hold    DO zigbee.set bedroom_blind position 0   ENDON
```

**RGB / CCT light** (`state`, `brightness` 0–254, `color_temp` mireds):

```
ON wake#action=single DO zigbee.set bedroom_light state 1 ; zigbee.set bedroom_light brightness 60 ; zigbee.set bedroom_light color_temp 370 ENDON
```

Lua sunrise ramp (a slow fade the DSL can't express):

```lua
local LIGHT = "0x00158D0009080706"
zhac.on_cron("0 0 6 * * *", function()
    zhac.set_attr(LIGHT, "state", true)
    for b = 1, 254, 12 do
        zhac.set_attr(LIGHT, "brightness", b)
        zhac.sleep(20000)              -- ≈ 7 min to full
    end
end)
```

**Thermostat / TRV** (`setpoint` ×100, `local_temperature` ×100, `system_mode`):

```
ON Time#Cron=0 0 6 * * *  DO zigbee.set living_trv setpoint 2100 ENDON   # 21.00 °C morning
ON Time#Cron=0 0 23 * * * DO zigbee.set living_trv setpoint 1700 ENDON   # 17.00 °C night
ON balcony_door#contact=1 DO zigbee.set living_trv system_mode 0 ENDON   # window open → off (check enum)
```

**Metering plug** (`state`, `power` W, `energy` kWh) — "washer done" from power:

```
ON washer_plug#power>5 DO publish zhac/washer running ENDON
ON washer_plug#power<2 DO event washer_done            ENDON
ON Event#washer_done   DO publish zhac/washer done ; publish home/notify washer_done ENDON
```

Lua overload trip (payloads with spaces aren't possible in the DSL):

```lua
local PLUG = "0x00158D000B0B0B0B"
zhac.on_attr_change(PLUG, "power", function(_, _, w)
    if w > 3000 then
        zhac.set_attr(PLUG, "state", false)                    -- cut power
        zhac.publish("zhac/alert/overload", tostring(w), 1, true)
    end
end)
```

**Door lock** (`lock_state` / `state`):

```
ON front_lock#lock_state=1 DO publish zhac/front_door locked ; event arrived_home ENDON
ON Time#Cron=0 0 23 * * *  DO zigbee.set front_lock state 1 ENDON            # auto-lock 23:00
```

**Water-leak safety** (`water_leak`) → close the valve, sound the siren, alert
— one rule, several actuators:

```
ON kitchen_leak#water_leak=1 DO zigbee.set main_valve state 0 ; zigbee.set siren state 1 ; publish zhac/alert/leak kitchen ENDON
```

**Smoke / CO** (`smoke`) — lights up, siren, notify:

```
ON hall_smoke#smoke=1 DO zigbee.set all_lights state 1 ; zigbee.set siren state 1 ; publish home/alert smoke ENDON
```

**Vibration / tilt** (`vibration`) — e.g. a mailbox sensor:

```lua
zhac.on_attr_change("0x00158D000C0C0C0C", "vibration", function(_, _, v)
    if v then zhac.publish("home/notify", "mail_arrived", 1, false) end
end)
```

**Button / dimmer** (`action` — string values like `on`, `off`, `single`,
`brightness_step_up`):

```
ON dimmer#action=on  DO zigbee.set lounge state 1 ENDON
ON dimmer#action=off DO zigbee.set lounge state 0 ENDON
```

Hold-to-dim needs current state → Lua:

```lua
local DIMMER, LOUNGE = "0x00158D000D0D0D0D", "0x00158D000E0E0E0E"
zhac.on_attr_change(DIMMER, "action", function(_, _, a)
    local b = zhac.get_attr(LOUNGE, "brightness") or 128
    if     a == "brightness_step_up"   then zhac.set_attr(LOUNGE, "brightness", math.min(254, b + 25))
    elseif a == "brightness_step_down" then zhac.set_attr(LOUNGE, "brightness", math.max(1,   b - 25)) end
end)
```

**Low-battery sweep** (`battery` %, on any battery device) — nag once a day:

```
ON any_sensor#battery<15 DO publish zhac/alert/battery low ENDON
```

```lua
zhac.on_cron("0 0 9 * * *", function()      -- 09:00 daily
    for _, d in ipairs({ "0x00158D0001020304", "0x00158D0002020202" }) do
        local b = zhac.get_attr(d, "battery")
        if b and b < 15 then zhac.publish("zhac/alert/battery/" .. d, tostring(b), 0, true) end
    end
end)
```

---

## 5. Rules ↔ Lua together

The named-event bus is the seam. Use each side for what it's best at: a script
for the tricky detection, rules for the easy fan-out.

**Script detects, rules act.** The multi-press script in §2.3 fires
`scene_day` / `scene_evening` / `scene_night`; keep the *scenes* as readable
rules:

```
ON Event#scene_day     DO zigbee.set living_light brightness 254 ENDON
ON Event#scene_evening DO zigbee.set living_light brightness 90  ENDON
ON Event#scene_night   DO zigbee.set living_light state 0 ; zigbee.set porch_lamp state 1 ENDON
```

**Rule detects, script acts.** A rule calls a named script with `script.run`;
the script runs a sequence staggered with `sleep` (which a rule can't do). This
is the supported rule→Lua path — Lua's `on_*` handlers subscribe to device /
cron / MQTT / boot / raw events, *not* to rule-fired `event` names, so route
rule→Lua through `script.run`, not `event`:

```
ON front_door#contact=1 DO script.run "arrival" ENDON
```

```lua
-- arrival.lua — its top-level body runs each time the rule fires
zhac.log("I", "arrival: welcome sequence")
zhac.set_attr("0x00158D000A0B0C0D", "state", true)     -- porch on now
zhac.sleep(2000)
zhac.set_attr("0x00158D0009080706", "brightness", 120) -- hall fades up after 2 s
```

---

## 6. Quick reference

| Need | Rule | Lua |
|------|------|-----|
| Sensor → actuator, 1:1 | `ON s#k=v DO zigbee.set a k2 v2 ENDON` | `zhac.on_attr_change(s,k,fn)` |
| Same value passthrough | `zigbee.set a k %value%` | `zhac.set_attr(a,k,value)` |
| Invert / scale | `!%value%`, `(%value%*10)/3` | plain Lua math |
| Time-of-day | `ON Time#Cron=…` | `zhac.on_cron(expr,fn)` |
| Auto-off (re-arm) | `timer n ms` + `ON Rules#Timer=n` | — |
| Auto-off (cancellable) | — | `sleep` + generation counter (§2.2) |
| Read current state | — | `zhac.get_attr(ieee,key)` |
| Fire / react to a name | `event n` / `ON Event#n` | `zhac.event(n)` |
| MQTT out / in | `publish t p` / `ON Mqtt#t` | `zhac.publish` / `zhac.on_mqtt` |
| Hold between events | — | module-scope locals |

See [`RULES_DSL.md`](RULES_DSL.md) and [`LUA_API.md`](LUA_API.md) for the
authoritative syntax, operators, error behaviour, and per-function contracts.
