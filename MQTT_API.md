# MQTT API

ZHAC can connect to an MQTT broker you run (Mosquitto, EMQX, the Home Assistant add-on, …). Every
build — wired (ESP32-S31 / ESP32-P4), single-chip S3 and dual-chip — uses the same topics.

What goes over MQTT:

- **Device state out**: every value a device reports.
- **Device commands in**: set any writable value.
- **Availability**: whether the hub, and each battery device, is reachable.
- **Your own messages** from rules and Lua scripts, in and out.

For Home Assistant, turn on discovery and follow [HOME_ASSISTANT.md](HOME_ASSISTANT.md) instead: HA
creates the entities by itself from the topics below.

---

## Setup

Web UI → **Settings → MQTT**:

| Setting | Meaning | Default |
|---|---|---|
| Broker URL | `mqtt://host:1883`, or `mqtt://user:password@host:1883` | — |
| Root topic | Prefix of every ZHAC topic, written `<root>` below | `zhac` |
| Client ID | MQTT client id | `zhac-` + last 4 hex digits of the MAC |
| Enable MQTT client | Connects when on | off |
| Home Assistant discovery | Publishes discovery configs and accepts `…/set` commands (see below) | off |

The hub shows whether it is connected on **Settings → MQTT** and in `GET /api/status`
(`mqtt_connected`).

Device addresses in topics are the IEEE address as **16 upper-case hex digits without `0x`**, e.g.
`70B3D52B600316B5`. The device page shows it.

---

## Topics at a glance

| Topic | Direction | Retained | When |
|---|---|---|---|
| `<root>/availability` | hub → broker | yes | always: `online` on connect, `offline` as the last will |
| `<root>/devices/<IEEE>/state` | hub → broker | no | always: one message per reported value |
| `<root>/devices/<IEEE>/<key>` | hub → broker | yes (except `action`) | discovery on |
| `<root>/devices/<IEEE>/availability` | hub → broker | yes | discovery on, battery devices |
| `<root>/devices/<IEEE>/<key>/set` | broker → hub | — | discovery on |
| `homeassistant/<component>/zhac_<ieee>_<key>/config` | hub → broker | yes | discovery on |
| anything else under `<root>/…` | broker → hub | — | always: goes to rules and Lua |

---

## Hub availability

`<root>/availability` is `online` while the hub is connected. The broker publishes `offline` (the
hub's last will) when the connection drops without a clean goodbye.

```sh
mosquitto_sub -h broker.local -t 'zhac/availability' -v
# zhac/availability online
```

## Device state

### `<root>/devices/<IEEE>/state` — always on

One JSON message per reported value, with or without Home Assistant discovery:

```json
{"ieee":"0x70B3D52B600316B5","attrs":{"temperature":21.4}}
```

Watch everything:

```sh
mosquitto_sub -h broker.local -t 'zhac/devices/+/state' -v
# zhac/devices/A4C138D750FECC83/state {"ieee":"0xA4C138D750FECC83","attrs":{"humidity":57.2}}
# zhac/devices/70B3D52B600316B5/state {"ieee":"0x70B3D52B600316B5","attrs":{"state":1}}
```

Values are JSON: numbers (`21.4`), booleans, or strings (`"high"`). Each message carries one key;
a device reporting three values sends three messages. The topic is not retained: a new subscriber
sees values as the devices report them, not the last known state. For the last known state use the
per-key topics below (discovery on) or the REST API.

### `<root>/devices/<IEEE>/<key>` — with discovery on

One topic per value, **retained**, with the bare value as payload:

```sh
mosquitto_sub -h broker.local -t 'zhac/devices/70B3D52B600316B5/#' -v
# zhac/devices/70B3D52B600316B5/state 1
# zhac/devices/70B3D52B600316B5/power 12.5
```

- On/off values are published as `1` / `0`, numbers as written, text without quotes.
- Button presses (`action`, e.g. `single`, `1_double`) are **not** retained, so a new subscriber does
  not replay an old press.

Careful: with discovery on, `<root>/devices/<IEEE>/state` can mean two things. It is the JSON
message above, and it is also the per-key topic of a value that happens to be called `state`
(switches, plugs, lights). Tell them apart by the payload: JSON object versus bare value.

### `<root>/devices/<IEEE>/availability` — with discovery on

For battery devices that report on their own schedule: `online`, or `offline` when the device has
been silent too long. Mains devices do not get this topic.

---

## Controlling devices

With **Home Assistant discovery on**, publish the new value to:

```
<root>/devices/<IEEE>/<key>/set
```

The payload is the bare value — not JSON:

| You want | Payload |
|---|---|
| on / off | `1` / `0`, or `true` / `false`, or `ON` / `OFF` for keys that take words |
| a number | `21.5` (`21.0` is sent as `21`) |
| a choice | the option text, e.g. `high`, `3` |

Examples:

```sh
# Switch a plug off
mosquitto_pub -h broker.local -t 'zhac/devices/70B3D52B600316B5/state/set' -m '0'

# Radiator valve setpoint
mosquitto_pub -h broker.local -t 'zhac/devices/EC1BBDFFFE2DAD79/current_heating_setpoint/set' -m '21.5'

# Alarm volume
mosquitto_pub -h broker.local -t 'zhac/devices/842E14FFFEDB8619/volume/set' -m 'high'
```

Rules for the topic: 16 hex digits (either case) for the address; the key only lower-case letters,
digits and `_`, and it must be a writable value of that device (the device page lists them, with
their allowed values). The hub publishes the new value on the state topics once the device confirms
it. Battery devices (valves, remotes) take it on their next wake-up; the hub holds the command until
then.

With discovery **off**, `…/set` topics are ignored: use a rule or a Lua script (below), or the
[REST/WebSocket API](REST_API.md) (`device.attr.set`).

---

## Your own messages: rules and Lua

The hub subscribes to **`<root>/#` only**. Every message under the root that is not a `…/set`
command and not one of its own `devices/…` topics is handed to rules (`Mqtt#` triggers) and to Lua
(`zhac.on_mqtt`). Messages outside the root never reach the hub, so **put your topics under the root**:
with the default root, `zhac/home/alarm`, not `home/alarm`.

A trigger names the **full** topic, root included, and matches it exactly (no `+` / `#` wildcards).

### Rule: MQTT message → device

```
ON Mqtt#zhac/home/alarm DO zigbee.set siren state 1 ENDON
```

```sh
mosquitto_pub -h broker.local -t 'zhac/home/alarm' -m 'go'
```

`%value%` is the message payload:

```
ON Mqtt#zhac/cmd/lamp DO zigbee.set lamp state %value% ENDON
```

```sh
mosquitto_pub -h broker.local -t 'zhac/cmd/lamp' -m '1'
```

### Rule: device → MQTT message

```
ON front door#contact=0 DO publish zhac/alerts/door opened ENDON
```

Rules may publish to any topic (inside or outside the root). Topic and payload are single tokens
(no spaces) or a `%value%` expression; topics up to 63 characters. See [RULES_DSL.md](RULES_DSL.md).

### Lua

A Lua handler receives **every** message the hub gets (topic, payload) and picks its topics itself:

```lua
local LIVING_ROOM = "70B3D52B600316B5"   -- device IEEE, from the device page

-- Incoming: react to a command
zhac.on_mqtt(function(topic, payload)
    if topic == "zhac/cmd/scene" and payload == "movie" then
        zhac.set_attr(LIVING_ROOM, "brightness", 40)
    end
end)

-- Outgoing: republish a value, retained
zhac.on_attr_change(function(ieee, key, value)
    if key == "occupancy" then
        zhac.publish("zhac/occupancy/" .. ieee, tostring(value), 0, true)
    end
end)
```

`zhac.publish(topic, payload [, qos [, retain]])` — qos default 0, retain default false; does nothing
while the hub is not connected. More in [LUA_API.md](LUA_API.md).

### Limits for incoming messages

Rules and Lua see at most **63 characters of topic and 31 bytes of payload**; longer ones are cut
short. Keep commands short (`movie`, `1`, `21.5`) and put structure in the topic, not in a JSON body.
`…/set` commands go to the device path and are not affected (values up to 63 characters).

---

## Home Assistant discovery

With discovery on, the hub also publishes a retained config for every value of every device on
`homeassistant/<component>/zhac_<ieee>_<key>/config` (prefix configurable), plus one for the hub's
own connection sensor. Removing a device clears its configs. Entity types, names and limitations:
[HOME_ASSISTANT.md](HOME_ASSISTANT.md).

---

## Quick test

```sh
# 1. See everything the hub sends
mosquitto_sub -h broker.local -t 'zhac/#' -v

# 2. Switch something (discovery on) — IEEE and key from the device page
mosquitto_pub -h broker.local -t 'zhac/devices/<IEEE>/state/set' -m '1'
```

If nothing arrives: **Settings → MQTT** shows the connection, `GET /api/status` has
`mqtt_connected`, and the broker log shows the client id (`zhac-xxxx`).
