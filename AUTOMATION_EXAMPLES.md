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

**H. Home Assistant MQTT auto-discovery.** Publish a **retained** JSON config to
`homeassistant/<component>/zhac/<object>/config` and HA creates the entity
automatically, wired to the `zhac/…` state/command topics from the patterns
above. Do it from `on_boot` (retained, so it survives reconnects). Two
prerequisites: HA's discovery prefix is the default `homeassistant`, and the
gateway's **subscription filter** must cover both your `.../set` command topics
and `homeassistant/status` (the HA birth/last-will topic).

A tiny helper + a shared `device` block so all entities group under one "ZHAC"
device in HA:

```lua
-- component = sensor | binary_sensor | switch | light | cover | lock | climate
local function ha_discover(component, object, cfg)
    zhac.publish("homeassistant/" .. component .. "/zhac/" .. object .. "/config",
                 cfg, 0, true)              -- retained
end

local function announce_all()
    -- binary_sensor: motion
    ha_discover("binary_sensor", "hall_motion", [[{
      "name":"Hall Motion","unique_id":"zhac_hall_motion",
      "state_topic":"zhac/hall_motion/occupancy",
      "payload_on":"1","payload_off":"0","device_class":"motion",
      "availability_topic":"zhac/availability",
      "device":{"identifiers":["zhac_bridge"],"name":"ZHAC","manufacturer":"ZHAC"}
    }]])

    -- sensor: temperature (state published as whole units by the rule below)
    ha_discover("sensor", "living_temp", [[{
      "name":"Living Temperature","unique_id":"zhac_living_temp",
      "state_topic":"zhac/living/temperature","unit_of_measurement":"°C",
      "device_class":"temperature","state_class":"measurement",
      "availability_topic":"zhac/availability",
      "device":{"identifiers":["zhac_bridge"],"name":"ZHAC"}
    }]])

    -- switch: metering plug
    ha_discover("switch", "kitchen_plug", [[{
      "name":"Kitchen Plug","unique_id":"zhac_kitchen_plug",
      "state_topic":"zhac/kitchen_plug/state","command_topic":"zhac/kitchen_plug/set",
      "payload_on":"1","payload_off":"0",
      "availability_topic":"zhac/availability",
      "device":{"identifiers":["zhac_bridge"],"name":"ZHAC"}
    }]])

    -- cover: blind by position (0–100)
    ha_discover("cover", "bedroom_blind", [[{
      "name":"Bedroom Blind","unique_id":"zhac_bedroom_blind",
      "position_topic":"zhac/bedroom_blind/position",
      "set_position_topic":"zhac/bedroom_blind/set_position",
      "position_open":100,"position_closed":0,
      "availability_topic":"zhac/availability",
      "device":{"identifiers":["zhac_bridge"],"name":"ZHAC"}
    }]])

    -- light: on/off + brightness + colour temperature (default schema)
    ha_discover("light", "bedroom_light", [[{
      "name":"Bedroom Light","unique_id":"zhac_bedroom_light",
      "state_topic":"zhac/bedroom_light/state","command_topic":"zhac/bedroom_light/set",
      "payload_on":"1","payload_off":"0",
      "brightness_state_topic":"zhac/bedroom_light/brightness",
      "brightness_command_topic":"zhac/bedroom_light/brightness/set","brightness_scale":254,
      "color_temp_state_topic":"zhac/bedroom_light/color_temp",
      "color_temp_command_topic":"zhac/bedroom_light/color_temp/set",
      "availability_topic":"zhac/availability",
      "device":{"identifiers":["zhac_bridge"],"name":"ZHAC"}
    }]])
end

zhac.on_boot(announce_all)

-- HA republishes a birth message on restart; re-announce so entities survive it.
zhac.on_mqtt("homeassistant/status", function(_, payload)
    if payload == "online" then announce_all() end
end)
```

Each discovered entity needs its state (and, if controllable, command) topics
fed — the rules from §3 do exactly that. For the discovery set above:

```
# ── state OUT ──
ON hall_motion#occupancy    DO publish zhac/hall_motion/occupancy %value%   ENDON
ON living_temp#temperature  DO publish zhac/living/temperature %value%/100  ENDON
ON kitchen_plug#state       DO publish zhac/kitchen_plug/state %value%      ENDON
ON bedroom_blind#position   DO publish zhac/bedroom_blind/position %value%  ENDON
ON bedroom_light#state      DO publish zhac/bedroom_light/state %value%     ENDON
ON bedroom_light#brightness DO publish zhac/bedroom_light/brightness %value% ENDON
ON bedroom_light#color_temp DO publish zhac/bedroom_light/color_temp %value% ENDON

# ── command IN (HA → device) ──
ON Mqtt#zhac/kitchen_plug/set             DO zigbee.set kitchen_plug state %value%       ENDON
ON Mqtt#zhac/bedroom_blind/set_position   DO zigbee.set bedroom_blind position %value%   ENDON
ON Mqtt#zhac/bedroom_light/set            DO zigbee.set bedroom_light state %value%      ENDON
ON Mqtt#zhac/bedroom_light/brightness/set DO zigbee.set bedroom_light brightness %value% ENDON
ON Mqtt#zhac/bedroom_light/color_temp/set DO zigbee.set bedroom_light color_temp %value% ENDON
```

**Climate / thermostat** is the one HA component best done entirely in **Lua** —
its setpoint and current temperature are floats (`21.5 °C`), but the shadow keeps
them as integer ×100, and the DSL's `%value%/100` is *integer* division (it would
drop the `.5`). Modes (`system_mode`) and HVAC action (`running_state`) are also
device-specific enums that need mapping to HA's `off`/`heat` and
`heating`/`idle` strings. So format the floats and map the enums in Lua:

```lua
local TRV = "0x00158D0004040404"

-- system_mode enum ↔ HA mode. Enum values are DEVICE-SPECIFIC — check the
-- expose in the Web UI; this maps a common off=0 / heat=1 TRV.
local MODE_TO_HA = { [0] = "off", [1] = "heat" }
local HA_TO_MODE = { off = 0, heat = 1 }

local function announce_trv()
    ha_discover("climate", "living_trv", [[{
      "name":"Living TRV","unique_id":"zhac_living_trv",
      "modes":["off","heat"],
      "mode_state_topic":"zhac/living_trv/mode",
      "mode_command_topic":"zhac/living_trv/mode/set",
      "temperature_state_topic":"zhac/living_trv/setpoint",
      "temperature_command_topic":"zhac/living_trv/setpoint/set",
      "current_temperature_topic":"zhac/living_trv/temperature",
      "action_topic":"zhac/living_trv/action",
      "temp_step":0.5,"min_temp":5,"max_temp":30,"temperature_unit":"C",
      "availability_topic":"zhac/availability",
      "device":{"identifiers":["zhac_bridge"],"name":"ZHAC"}
    }]])
end
zhac.on_boot(announce_trv)

-- State OUT — float-formatted (integer /100 in the DSL would drop the .5).
zhac.on_attr_change(TRV, "setpoint", function(_, _, v)
    zhac.publish("zhac/living_trv/setpoint", string.format("%.1f", v / 100), 0, true)
end)
zhac.on_attr_change(TRV, "local_temperature", function(_, _, v)
    zhac.publish("zhac/living_trv/temperature", string.format("%.1f", v / 100), 0, true)
end)
zhac.on_attr_change(TRV, "system_mode", function(_, _, m)
    zhac.publish("zhac/living_trv/mode", MODE_TO_HA[m] or "off", 0, true)
end)
zhac.on_attr_change(TRV, "running_state", function(_, _, r)
    -- HA hvac_action wants "heating" | "idle" | "off"; running_state is a
    -- string ("heat"/"idle"), bool, or int depending on the device — normalise.
    local heating = (r == "heat" or r == 1 or r == true)
    zhac.publish("zhac/living_trv/action", heating and "heating" or "idle", 0, true)
end)

-- Command IN — HA sends a float setpoint and a mode string.
zhac.on_mqtt("zhac/living_trv/setpoint/set", function(_, payload)
    local c = tonumber(payload)
    if c then zhac.set_attr(TRV, "setpoint", math.floor(c * 100 + 0.5)) end   -- 21.5 → 2150
end)
zhac.on_mqtt("zhac/living_trv/mode/set", function(_, payload)
    local m = HA_TO_MODE[payload]
    if m ~= nil then zhac.set_attr(TRV, "system_mode", m) end
end)
```

Add `announce_trv()` to `announce_all()` (and the `homeassistant/status`
re-announce) so the thermostat comes back after an HA restart too.

**Fan** maps a `fan_mode` string enum (`low`/`medium`/`high`/`auto`) onto HA's
`preset_modes`, plus on/off — so it can stay mostly in the DSL (a bare `%value%`
passes the mode string through). Discovery:

```lua
ha_discover("fan", "ceiling_fan", [[{
  "name":"Ceiling Fan","unique_id":"zhac_ceiling_fan",
  "state_topic":"zhac/fan/state","command_topic":"zhac/fan/set",
  "payload_on":"1","payload_off":"0",
  "preset_mode_state_topic":"zhac/fan/mode",
  "preset_mode_command_topic":"zhac/fan/mode/set",
  "preset_modes":["low","medium","high","auto"],
  "availability_topic":"zhac/availability",
  "device":{"identifiers":["zhac_bridge"],"name":"ZHAC"}
}]])
```

```
# state OUT — bare %value% passes the fan_mode string ("low", …) straight through
ON ceiling_fan#state    DO publish zhac/fan/state %value% ENDON
ON ceiling_fan#fan_mode DO publish zhac/fan/mode  %value% ENDON
# command IN
ON Mqtt#zhac/fan/set      DO zigbee.set ceiling_fan state %value%    ENDON
ON Mqtt#zhac/fan/mode/set DO zigbee.set ceiling_fan fan_mode %value% ENDON
```

> The device's `fan_mode` values must match `preset_modes` — check the expose. If
> they differ (or the fan exposes a numeric `fan_speed`/`speed` instead), drop to
> Lua: map the strings, or use HA's percentage topics
> (`percentage_state_topic` / `percentage_command_topic` + `speed_range_min/max`)
> and publish the number.

**Humidifier** needs **Lua**: `target_humidity` and `humidity` are stored ×100
in the shadow (whole-percent for HA), and the on/off is a separate `state`
attribute. Discovery + wiring:

```lua
local HUM = "0x00158D000F0F0F0F"

ha_discover("humidifier", "bedroom_humidifier", [[{
  "name":"Bedroom Humidifier","unique_id":"zhac_bedroom_humidifier",
  "state_topic":"zhac/humidifier/state","command_topic":"zhac/humidifier/set",
  "payload_on":"1","payload_off":"0",
  "target_humidity_state_topic":"zhac/humidifier/target",
  "target_humidity_command_topic":"zhac/humidifier/target/set",
  "current_humidity_topic":"zhac/humidifier/current",
  "min_humidity":30,"max_humidity":80,"device_class":"humidifier",
  "availability_topic":"zhac/availability",
  "device":{"identifiers":["zhac_bridge"],"name":"ZHAC"}
}]])

-- state OUT (÷100 → whole percent)
zhac.on_attr_change(HUM, "state", function(_, _, on)
    zhac.publish("zhac/humidifier/state", on and "1" or "0", 0, true)
end)
zhac.on_attr_change(HUM, "target_humidity", function(_, _, v)
    zhac.publish("zhac/humidifier/target", tostring(math.floor(v / 100)), 0, true)   -- 5000 → 50
end)
zhac.on_attr_change(HUM, "humidity", function(_, _, v)
    zhac.publish("zhac/humidifier/current", tostring(math.floor(v / 100)), 0, true)
end)

-- command IN (whole percent → ×100)
zhac.on_mqtt("zhac/humidifier/set", function(_, payload)
    zhac.set_attr(HUM, "state", payload == "1" or payload == "on")
end)
zhac.on_mqtt("zhac/humidifier/target/set", function(_, payload)
    local pct = tonumber(payload)
    if pct then zhac.set_attr(HUM, "target_humidity", math.floor(pct) * 100) end     -- 50 → 5000
end)
```

Fold `announce_fan()` / the humidifier `ha_discover` into `announce_all()` (and
the `homeassistant/status` re-announce) so they return after an HA restart.

**Cover with tilt** (venetian blind — `position` *and* `tilt`, both whole-number
percentages, so plain DSL). Add the tilt topics to the `cover` config:

```lua
ha_discover("cover", "living_venetian", [[{
  "name":"Living Venetian","unique_id":"zhac_living_venetian",
  "position_topic":"zhac/venetian/position",
  "set_position_topic":"zhac/venetian/set_position",
  "position_open":100,"position_closed":0,
  "tilt_status_topic":"zhac/venetian/tilt",
  "tilt_command_topic":"zhac/venetian/set_tilt",
  "tilt_min":0,"tilt_max":100,
  "availability_topic":"zhac/availability",
  "device":{"identifiers":["zhac_bridge"],"name":"ZHAC"}
}]])
```

```
# state OUT
ON living_venetian#position DO publish zhac/venetian/position %value% ENDON
ON living_venetian#tilt     DO publish zhac/venetian/tilt     %value% ENDON
# command IN
ON Mqtt#zhac/venetian/set_position DO zigbee.set living_venetian position %value% ENDON
ON Mqtt#zhac/venetian/set_tilt     DO zigbee.set living_venetian tilt     %value% ENDON
```

**Lock.** `lock_state` is a binary (`1` = locked, `0` = unlocked). Instead of
mapping to HA's default `LOCK`/`UNLOCK`/`LOCKED`/`UNLOCKED` strings, tell HA to
use `1`/`0` directly — then it stays in the DSL:

```lua
ha_discover("lock", "front_lock", [[{
  "name":"Front Lock","unique_id":"zhac_front_lock",
  "state_topic":"zhac/lock/state","command_topic":"zhac/lock/set",
  "state_locked":"1","state_unlocked":"0",
  "payload_lock":"1","payload_unlock":"0",
  "availability_topic":"zhac/availability",
  "device":{"identifiers":["zhac_bridge"],"name":"ZHAC"}
}]])
```

```
ON front_lock#lock_state DO publish zhac/lock/state %value%       ENDON
ON Mqtt#zhac/lock/set    DO zigbee.set front_lock lock_state %value% ENDON
```

> Some locks expose the state as a string or under `state` instead of a binary
> `lock_state` — check the expose and adjust the mapped values (or keep HA's
> defaults and map the strings in Lua).

**Scene controller / multi-button remote.** A remote exposes a single `action`
attribute whose value is a string per button + press-type (e.g. `on`, `off`,
`up_hold`, `button_1_single` — device-specific, check the expose). Two ways to
surface it in HA; pick one.

*Approach A — an HA `event` entity (recommended for multi-button).* One entity,
all button actions as `event_types`. Publish `{"event_type": …}` per press
(transient, so **not** retained):

```lua
local REMOTE = "0x00158D00E1E1E1E1"

zhac.on_attr_change(REMOTE, "action", function(_, _, a)
    zhac.publish("zhac/remote/event", string.format('{"event_type":"%s"}', a), 0, false)
end)

zhac.on_boot(function()
    zhac.publish("homeassistant/event/zhac/remote/config", [[{
      "name":"Living Remote","unique_id":"zhac_living_remote",
      "state_topic":"zhac/remote/event",
      "event_types":["on","off","up","down","up_hold","down_hold"],
      "device_class":"button",
      "availability_topic":"zhac/availability",
      "device":{"identifiers":["zhac_bridge"],"name":"ZHAC"}
    }]], 0, true)
end)
```

In HA the entity fires with `event_type` = the button action — trigger
automations on it (`platform: mqtt`/state → `event_type`).

*Approach B — HA device-automation triggers (classic, shows in the device
picker).* Publish the raw action string, then one **retained** trigger config per
button/press; HA renders them as "Button 1 – Short Press" etc. in the automation
UI. `type`/`subtype` are the labels HA shows (use its conventional
`button_short_press` / `button_long_press` / `button_double_press`):

```lua
zhac.on_attr_change(REMOTE, "action", function(_, _, a)
    zhac.publish("zhac/remote/action", a, 0, false)     -- raw action string
end)

zhac.on_boot(function()
    -- trigger(config-id, action-payload, type, subtype)
    local function trigger(id, payload, typ, subtype)
        zhac.publish("homeassistant/device_automation/zhac/" .. id .. "/config",
            string.format([[{
              "automation_type":"trigger","topic":"zhac/remote/action","payload":"%s",
              "type":"%s","subtype":"%s",
              "device":{"identifiers":["zhac_bridge"],"name":"ZHAC"}
            }]], payload, typ, subtype), 0, true)
    end
    trigger("b1_press", "on",       "button_short_press", "button_1")
    trigger("b1_hold",  "up_hold",  "button_long_press",  "button_1")
    trigger("b2_press", "off",      "button_short_press", "button_2")
    trigger("b2_hold",  "down_hold","button_long_press",  "button_2")
    -- … one per button + press-type your remote emits
end)
```

> You don't need MQTT at all to *act* on a remote — a rule (`ON remote#action=on
> DO …`, §4) or a Lua handler (§2.3, multi-press → scenes) runs the scene on the
> hub directly. Use the discovery above when you specifically want the buttons to
> drive **Home Assistant** automations.

**Removing an entity:** publish an empty retained payload to its config topic —
`zhac.publish("homeassistant/sensor/zhac/living_temp/config", "", 0, true)`.

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

**Occupancy → light, with a custom off-delay.** Keep a light on while a room is
occupied, then switch it off a configurable time *after* occupancy clears. Two
ways — use **one**, not both:

*Simplest — let the firmware clear occupancy.* Every occupancy sensor has an
`occupancy_timeout` (seconds) in its **Options** tab (or `device.options.set
{ieee, occupancy_timeout}`). Set it to your off-delay; the device then
synthesises `occupancy=0` that long after the last motion, and one rule mirrors
occupancy onto the light — on when motion starts, off when the timeout elapses:

```
ON office_motion#occupancy DO zigbee.set office_light state %value% ENDON
```

*Configurable from Home Assistant (Lua).* When you want to change the delay live
(or the PIR reports `occupancy=0` immediately), run the timer yourself and expose
it as an HA `number`. A generation counter cancels the pending off if motion
returns:

```lua
local MOTION = "0x00158D00D1D1D1D1"
local LIGHT  = "0x00158D0009080706"
local off_ms = 120000            -- default 2 min; HA can change it (below)
local gen    = 0

zhac.on_attr_change(MOTION, "occupancy", function(_, _, occupied)
    gen = gen + 1                -- any occupancy change cancels a pending off
    if occupied then
        zhac.set_attr(LIGHT, "state", true)
    else
        local mine = gen
        zhac.sleep(off_ms)       -- wait the custom delay …
        if mine == gen then      -- … off only if no motion since
            zhac.set_attr(LIGHT, "state", false)
        end
    end
end)

-- HA number entity drives the delay (seconds).
zhac.on_mqtt("zhac/office/off_delay/set", function(_, payload)
    local s = tonumber(payload)
    if s and s > 0 then
        off_ms = math.floor(s) * 1000
        zhac.publish("zhac/office/off_delay", tostring(math.floor(s)), 0, true)
    end
end)
zhac.on_boot(function()
    zhac.publish("zhac/office/off_delay", tostring(math.floor(off_ms / 1000)), 0, true)
    zhac.publish("homeassistant/number/zhac/office_off_delay/config", [[{
      "name":"Office Light Off-Delay","unique_id":"zhac_office_off_delay",
      "state_topic":"zhac/office/off_delay","command_topic":"zhac/office/off_delay/set",
      "min":10,"max":1800,"step":10,"unit_of_measurement":"s","mode":"box",
      "availability_topic":"zhac/availability",
      "device":{"identifiers":["zhac_bridge"],"name":"ZHAC"}
    }]], 0, true)
end)
```

---

## 5. Whole-home scenarios

Multi-device, stateful automations. These hold state across events, so they're
Lua — with HA discovery + control where it helps.

### 5.1 Water-leak alarm with valve shut-off

Any of several leak sensors → **close the main water valve**, sound the siren,
alert. Critically, it **latches**: a sensor going dry does *not* reopen the valve
(a cleared sensor doesn't mean the leak is fixed) — reopening is a deliberate
reset only.

```lua
local VALVE = "0x00158D0001010101"   -- motorised main valve (state: 1 = open)
local SIREN = "0x00158D0002020202"
local LEAKS = { "0x00158D00A1A1A1A1", "0x00158D00A2A2A2A2", "0x00158D00A3A3A3A3" }
local tripped = false

local function trip(where)
    if tripped then return end
    tripped = true
    zhac.set_attr(VALVE, "state", false)          -- CLOSE the valve (check polarity!)
    zhac.set_attr(SIREN, "state", true)
    zhac.publish("zhac/alarm/leak", "TRIPPED", 1, true)   -- retained → HA sees it on connect
    zhac.publish("home/notify", "water_leak_" .. where, 1, false)
    zhac.log("E", "WATER LEAK (" .. where .. ") — valve closed")
end

for i, ieee in ipairs(LEAKS) do
    zhac.on_attr_change(ieee, "water_leak", function(_, _, wet)
        if wet then trip("zone" .. i) end
    end)
end

-- Reset is manual only — reopen the valve after you've physically checked.
-- HA exposes this as a button (discovery below) publishing to the reset topic.
zhac.on_mqtt("zhac/alarm/leak/reset", function()
    tripped = false
    zhac.set_attr(SIREN, "state", false)
    zhac.set_attr(VALVE, "state", true)           -- reopen ONLY on explicit reset
    zhac.publish("zhac/alarm/leak", "OK", 1, true)
    zhac.log("I", "leak alarm reset — valve reopened")
end)

-- HA discovery: a leak binary_sensor + a reset button.
zhac.on_boot(function()
    zhac.publish("homeassistant/binary_sensor/zhac/leak/config", [[{
      "name":"Water Leak","unique_id":"zhac_leak","state_topic":"zhac/alarm/leak",
      "payload_on":"TRIPPED","payload_off":"OK","device_class":"moisture",
      "availability_topic":"zhac/availability",
      "device":{"identifiers":["zhac_bridge"],"name":"ZHAC"}
    }]], 0, true)
    zhac.publish("homeassistant/button/zhac/leak_reset/config", [[{
      "name":"Leak Alarm Reset","unique_id":"zhac_leak_reset",
      "command_topic":"zhac/alarm/leak/reset","payload_press":"reset",
      "availability_topic":"zhac/availability",
      "device":{"identifiers":["zhac_bridge"],"name":"ZHAC"}
    }]], 0, true)
end)
```

> **Check valve polarity.** On some valves `state=1` is *open*, on others *closed*.
> Verify in the Web UI before trusting this with your plumbing.

### 5.2 Security system (motion + door/window + siren)

A small alarm panel: `disarmed` → `armed_home` / `armed_away` → `pending` (entry
delay) → `triggered`. Perimeter contacts always trip when armed; interior motion
trips only when *armed away* (so you can move around when home). Arm/disarm and
state are wired to an HA **alarm_control_panel**.

```lua
local SIREN    = "0x00158D0002020202"
local CONTACTS = { "0x00158D00C1C1C1C1", "0x00158D00C2C2C2C2" }  -- doors / windows
local MOTION   = { "0x00158D00D1D1D1D1", "0x00158D00D2D2D2D2" }  -- PIRs
local EXIT_DELAY, ENTRY_DELAY = 30000, 30000

local state = "disarmed"   -- disarmed|arming|armed_home|armed_away|pending|triggered
local gen   = 0            -- bumped on every state change to cancel pending sleeps

local function set_state(s)
    gen = gen + 1
    state = s
    zhac.publish("zhac/alarm/state", s, 1, true)   -- HA reads this
    zhac.log("I", "alarm → " .. s)
end

local function trigger(zone)
    set_state("triggered")
    zhac.set_attr(SIREN, "state", true)
    zhac.publish("home/notify", "alarm_breach_" .. zone, 1, false)
end

-- Start the entry countdown; a disarm (or any state change) during it cancels.
local function entry_countdown(zone)
    if state ~= "armed_home" and state ~= "armed_away" then return end
    local mine = gen
    set_state("pending")
    local was = gen        -- set_state bumped gen; remember this pending's id
    zhac.sleep(ENTRY_DELAY)
    if state == "pending" and gen == was then trigger(zone) end
end

for _, ieee in ipairs(CONTACTS) do
    zhac.on_attr_change(ieee, "contact", function(_, _, contact)
        -- 'contact' polarity varies: many sensors report false/0 when OPENED.
        -- Treat the "opened" edge as the breach — adjust for your sensor.
        local opened = (contact == false or contact == 0)
        if opened and (state == "armed_home" or state == "armed_away") then
            entry_countdown("perimeter")
        end
    end)
end
for _, ieee in ipairs(MOTION) do
    zhac.on_attr_change(ieee, "occupancy", function(_, _, occ)
        if occ and state == "armed_away" then      -- interior motion ignored when home
            entry_countdown("interior")
        end
    end)
end

-- HA alarm_control_panel sends DISARM / ARM_HOME / ARM_AWAY to the command topic.
zhac.on_mqtt("zhac/alarm/set", function(_, cmd)
    if cmd == "DISARM" then
        zhac.set_attr(SIREN, "state", false)
        set_state("disarmed")
    elseif cmd == "ARM_HOME" then
        set_state("armed_home")
    elseif cmd == "ARM_AWAY" then
        set_state("arming")                        -- exit delay
        local was = gen
        zhac.sleep(EXIT_DELAY)
        if state == "arming" and gen == was then set_state("armed_away") end
    end
end)

zhac.on_boot(function()
    zhac.publish("homeassistant/alarm_control_panel/zhac/house/config", [[{
      "name":"House Alarm","unique_id":"zhac_house_alarm",
      "state_topic":"zhac/alarm/state","command_topic":"zhac/alarm/set",
      "supported_features":["arm_home","arm_away"],
      "availability_topic":"zhac/availability",
      "device":{"identifiers":["zhac_bridge"],"name":"ZHAC"}
    }]], 0, true)
end)
```

> This is a starting point, not a certified alarm: it has no tamper handling,
> battery-fail supervision, or duress code. Keep life-safety (smoke/CO/leak) as
> its own always-on rule (§4), independent of the arm state.

---

## 6. Rules ↔ Lua together

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

## 7. Quick reference

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
