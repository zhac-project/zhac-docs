# ZHAC REST API Reference

**Base URL:** `http://<device-ip>/api`  
**Content-Type:** `application/json` (all requests and responses)

---

## Authentication

Protected endpoints require the header:

```
X-Api-Key: <token>
```

The token is a 32-character hex string generated on first boot and printed to the serial console:

```
W (1234) main: *** NEW API TOKEN (save this): a1b2c3d4e5f6... ***
```

The token persists in NVS across reboots. Endpoints marked **Auth required** return `401` if the header is missing or wrong.

---

## Relationship to the WebSocket API and the SPA

Every endpoint below is a thin wrapper over a shared
transport-agnostic handler in
`firmware/s3_core/main/api_handlers.cpp` (the `api_*` family). The
same handler is called from the WebSocket envelope dispatcher
(`firmware/s3_core/main/ws_bridge.cpp`, 35-entry table), so request
and response bodies are byte-identical on the two transports.

The first-party web UI (`www-spa/`, Preact SPA) speaks **WebSocket
only** using the envelope
`{id, cmd, args}` ↔ `{id, ok, data|err}` — see
[`WS_API.md`](WS_API.md) for the command list and push-event
catalogue. The REST surface is intended for scripts / third-party
integrations.

---

## Endpoints

### System

#### `GET /api/status`
Returns S3 and P4 health metrics. No auth required. The P4-side values
are populated from the periodic HAP heartbeat (`HapHeartbeat` — 14
fields as of 2026-04-22).

**Response:**
```json
{
  "heap":        123456,
  "heap_min":    100000,
  "int_free":     48000,
  "int_min":      32000,
  "int_blk":      16000,
  "psram_free": 4000000,
  "psram_min":  3800000,
  "psram_blk":  2000000,
  "psram_total":8000000,
  "stack_hwm":     1024,
  "uptime":        3600,
  "cpu_c0":          12,
  "cpu_c1":           4,
  "ip":    "192.168.1.100",
  "mac":   "AA:BB:CC:DD:EE:FF",
  "wifi":           true,
  "mqtt_connected": true,
  "ws_clients":        2,
  "synced":         true,
  "metrics_enabled":false,
  "auth_enabled":   true,
  "api_token":      "",
  "p4": {
    "devices":         12,
    "uptime":        3598,
    "fw":          "1.0.0",
    "heap":        123456,
    "heap_min":    100000,
    "int_free":     48000,
    "int_min":      32000,
    "int_blk":      16000,
    "psram_free": 2000000,
    "psram_min":  1800000,
    "psram_blk":   900000,
    "psram_total":4000000,
    "stack_hwm":      512,
    "cpu_c0":           9,
    "cpu_c1":           3,
    "proto_mask":       1,
    "synced":        true
  }
}
```

| Field | Meaning |
|-------|---------|
| `heap` / `heap_min` | Current and all-time-low free bytes across the full default heap |
| `int_free` / `int_min` / `int_blk` | Internal-RAM free / low-water / largest free block |
| `psram_free` / `psram_min` / `psram_blk` / `psram_total` | PSRAM equivalents |
| `stack_hwm` | Smallest high-water-mark remaining across the chip's task table, in bytes |
| `cpu_c0` / `cpu_c1` | Per-core CPU utilisation, percent |
| `proto_mask` (P4 only) | Bitmask of live `DeviceBackend`s; bit 0 = Zigbee |
| `api_token` | Echoes the token only when auth is disabled (first-boot helper) |

#### `GET /api/alerts`
Returns recent system alerts (battery low, script crash, rule errors). **Auth required.**

**Response:** Array, oldest first:
```json
[
  {
    "code": 1,
    "ieee": "0x001234567890ABCD",
    "msg": "battery low: 15%",
    "ts": 1712345678
  }
]
```

Alert codes: `1` = battery low, `2` = script crash, `3` = rule error.

---

### WiFi

#### `GET /api/wifi/status`
Returns current WiFi mode and connection info. **No auth required** (must work in AP mode before token is known).

**Response (AP mode):**
```json
{"mode": "ap", "ssid": "ZHAC-A1B2", "ip": "192.168.4.1", "sta_ssid": null, "rssi": null}
```

**Response (STA mode):**
```json
{"mode": "sta", "ssid": "MyNetwork", "ip": "192.168.1.100", "rssi": -42}
```

#### `GET /api/wifi/scan`
Scans for nearby WiFi networks. **Auth required.** Rate limited: 1 scan per 10 seconds.

**Response:**
```json
{
  "networks": [
    {"ssid": "MyNetwork", "rssi": -45, "auth": "wpa2"},
    {"ssid": "Neighbor", "rssi": -72, "auth": "wpa2"},
    {"ssid": "OpenNet", "rssi": -80, "auth": "open"}
  ]
}
```

Auth types: `open`, `wep`, `wpa`, `wpa2`, `wpa3`, `enterprise`.

#### `POST /api/wifi`
Save WiFi credentials and reboot into STA mode. **Auth required.** Rate limited: 1 per 30 seconds.

**Body:** `{"ssid": "MyNetwork", "pass": "secret"}`

**Response:** `{"ok": true}` — device reboots after 1 second.

#### `DELETE /api/wifi`
Erase WiFi credentials and reboot into AP mode. **Auth required.**

**Response:** `{"ok": true}` — device reboots after 500ms.

---

### Devices

#### `GET /api/devices`
Returns all devices from P4 (all protocols). No auth required.

**Response:** Raw P4 JSON — array of device objects:
```json
[
  {
    "ieee": "0x001234567890ABCD",
    "proto": "zb",
    "nwk": "0x1234",
    "name": "Living Room Bulb",
    "eps": [1, 2],
    "clusters": { "1": [6, 8, 768] },
    "exposes": [
      { "type": "binary", "name": "state", "access": 7 },
      { "type": "numeric", "name": "brightness", "min": 0, "max": 254, "access": 7 }
    ]
  }
]
```

#### `GET /api/devices/:ieee`
Returns a single device. `:ieee` = `0x001234567890ABCD`. No auth required.

**Response:** Same shape as one item from `GET /api/devices`.

**Errors:** `500` on P4 timeout.

#### `PUT /api/devices/:ieee/attrs`
Send a ZCL attribute write or command to a device. **Auth required.**

**Request:**
```json
{
  "key": "state",
  "val": 1,
  "ep": 1,
  "cluster": 0,
  "attr": 0
}
```

- `key` — required. Well-known keys: `state`, `brightness`, `color_temp`, `hue`, `saturation`.
- `val` — required. Integer value.
- `ep`, `cluster`, `attr` — optional, default `0`. P4 resolves cluster/attr from `key` when `0`.

**Response:**
```json
{ "ok": true }
```

**Errors:** `500` on P4 timeout (3 s).

#### `DELETE /api/devices/:ieee`
Remove a device: sends ZDO leave request, removes from NVS, broadcasts `device_deleted` WebSocket event. **Auth required.**

**Response:** `{"ok": true}` or `{"ok": false}` on P4 timeout (5 s).

#### `GET /api/devices/:ieee/options`
Read per-device options blob from S3 NVS. No auth required.

**Response:** Free-form JSON object (returns `{}` if none saved).

#### `POST /api/devices/:ieee/options`
Save per-device options blob to S3 NVS. **Auth required.**

**Request:** Any JSON object — replaces the stored blob entirely.

**Response:** `{"ok": true}`

> **Sub-route dispatch:** `POST /api/devices/*/bind`,
> `/unbind`, and `/interview` are all served by a single wildcard
> handler (`handle_post_device_subroute` in `rest_devices.cpp`) that
> parses the suffix and delegates — ESP-IDF httpd only supports the
> trailing-segment `*` wildcard, so separate registrations can't
> coexist with `/api/devices/*`.

#### `POST /api/devices/:ieee/bind`
Issue a ZDO bind request. **Auth required.**

**Request:**
```json
{
  "src_ep": 1,
  "cluster": 6,
  "dst_ieee": "0x00124B0009D12345",
  "dst_ep": 1
}
```

**Response:** `{"ok": true}` — confirmed by BIND_ACK from P4 (5 s timeout).

#### `POST /api/devices/:ieee/unbind`
Same as `/bind` but removes the binding. **Auth required.**

#### `POST /api/devices/:ieee/interview`
Trigger a fresh interview on the target device (useful after a
stalled join or when the ZHC definition has been updated).
**Auth required.**

**Response:** `{"ok": true}` when the interview task has accepted
the request; the interview itself runs asynchronously and emits
`device.updated` events as identity / support state changes.

---

### Groups

#### `GET /api/groups`
Returns all groups. No auth required.

**Response:**
```json
{
  "groups": [
    {
      "id": 1,
      "name": "Living Room",
      "members": [
        { "ieee": "0x001234567890ABCD", "ep": 1 }
      ]
    }
  ]
}
```

#### `POST /api/groups`
Create a group. **Auth required.**

**Request:**
```json
{
  "name": "Living Room",
  "members": [
    { "ieee": "0x001234567890ABCD", "ep": 1 }
  ]
}
```

**Response:** Created group object (same shape as one item from `GET /api/groups`).

#### `GET /api/groups/:id`
Returns a single group by numeric ID. No auth required.

**Errors:** `404` if not found.

#### `PUT /api/groups/:id`
Update group name and/or members. **Auth required.**

**Request:** Same shape as `POST /api/groups` — fields are optional; omitting `name` or `members` leaves them unchanged.

**Response:** Updated group object.

#### `DELETE /api/groups/:id`
Delete a group. **Auth required.**

**Response:** `{"ok": true}` or `{"ok": false}`.

#### `POST /api/groups/:id/cmd`
Fan-out a command to all group members. **Auth required.**

**Request:**
```json
{ "key": "state", "val": 1 }
```

**Response:**
```json
{ "ok": true, "sent": 3 }
```

`sent` = number of members the command was dispatched to.

---

### Rules

#### `GET /api/rules`
Returns all automation rules from P4. No auth required.

**Response:** P4 JSON — array of rule objects.

#### `POST /api/rules`
Create a new rule. **Auth required.**

**Request:**
```json
{ "dsl": "on 0x001234567890ABCD.state == 1 do set 0xAABBCCDDEEFF0011.state 0" }
```

**Response:** `201 Created` + created rule object.

#### `DELETE /api/rules`
Delete a rule by ID. **Auth required.**

**Request:**
```json
{ "id": 3 }
```

**Response:** P4 acknowledgement JSON.

#### `PUT /api/rules`
Toggle a rule enabled/disabled. **Auth required.**

**Request:**
```json
{ "id": 3, "enabled": false }
```

**Response:** P4 acknowledgement JSON.

#### `PUT /api/rules/:id`
Replace rule DSL source. **Auth required.**

**Request body:** Raw DSL string (plain text, not JSON).

**Response:** `{"ok": true}` or `{"ok": false}`.

---

### Scripts (Lua)

Lua scripts are stored on the P4 SPIFFS partition at `/scripts/<name>.lua`. See `docs/LUA_API.md` for the scripting API reference.

Name validation: `[a-z][a-z0-9_-]{0,23}` (up to 24 characters, lowercase alphanumeric + `_` + `-`).
Source cap: 16 KB per script. Soft limit: 16 distinct files.

#### `GET /api/scripts`
List all Lua scripts. **Auth required.** Returns an empty list if the P4 script cache isn't initialised yet — failed `SCRIPT_LIST_REQ` round-trips do not fail the endpoint.

**Response:**
```json
{ "scripts": [ { "name": "motion", "size": 256 } ] }
```

#### `GET /api/scripts/:name`
Get one Lua script's source. **Auth required.**

**Response:**
```json
{ "name": "motion", "src": "zhac.log('hi')\n" }
```

**Errors:** `400` on invalid name, `500` on P4 timeout.

#### `POST /api/scripts/:name`
Create or overwrite a Lua script. **Auth required.**

**Request body:** Raw Lua source text (Content-Type `text/plain`; body up to 16 KB). No JSON wrapper.

**Response:** `201 Created` + `{"ok":true}`. On busy channel returns `429`; on P4 timeout returns `500`.

#### `POST /api/scripts`
Bulk-upload multiple Lua scripts in a single HAP round-trip. **Auth required.**

**Request:**
```json
[
  { "name": "motion",   "src": "..." },
  { "name": "schedule", "src": "..." }
]
```

**Response:**
```json
{ "ok": true, "written": 2, "failed": 0 }
```

A busy channel returns `429` for the entire batch; callers must retry the full array.

#### `DELETE /api/scripts/:name`
Delete a Lua script. **Auth required.**

**Response:** `{"ok": true}`. Deleting a non-existent script is idempotent and returns success.

---

### Network & System Config

#### `POST /api/wifi`
Update WiFi credentials and reboot. **Auth required.**

**Request:**
```json
{ "ssid": "MyNetwork", "pass": "secret" }
```

**Response:** `{"status": "ok", "reboot": true}` — device reboots ~1 s later.

#### `POST /api/settings`
Update MQTT broker URL. **Auth required.**

**Request:**
```json
{ "broker_url": "mqtt://192.168.1.10:1883" }
```

**Response:** `{"ok": true}` — takes effect immediately without reboot.

---

### OTA (Firmware Update)

#### `POST /api/ota`
Trigger S3 OTA update. **Auth required.**

**Request:**
```json
{ "url": "http://192.168.1.5:8080/s3_core.bin" }
```

**Response:** `202 Accepted` + `{"status": "queued"}` — download runs in background task.

#### `POST /api/p4-ota`
Trigger P4 OTA update over HAP. **Auth required.**

**Request:**
```json
{ "url": "http://192.168.1.5:8080/p4_core.bin" }
```

**Response:** `202 Accepted` + `{"status": "queued"}`.

---

### Permit Join

#### `POST /api/permit_join`
Open the Zigbee network for new device joins. **Auth required.**

**Request:**
```json
{ "duration": 254 }
```

`duration` — seconds (1–254). `254` = open indefinitely. Default: `254`.

**Response:** `{"ok": true}` — fire-and-forget, no join confirmation.

---

## WebSocket

**URL:** `ws://<device-ip>/ws`

The `/ws` endpoint serves two roles:

1. **Command envelope** — `{id, cmd, args}` ↔ `{id, ok, data|err}`.
   Every command calls the same `api_*` handler as the REST
   endpoint above; response bodies are byte-identical.
2. **Push events** — `{"event":"<name>","data":<payload>}` frames
   broadcast unsolicited when the underlying state changes
   (`device.added`, `device.updated`, `device.removed`,
   `attr.bulk`, `alert.added`, `alert.fired`).

Full envelope format, the 35-entry command table, and the
push-event catalogue live in **[`WS_API.md`](WS_API.md)**.

---

## Error Responses

| HTTP | Meaning |
|------|---------|
| `400` | Bad request — missing or invalid field; message in body |
| `401` | Missing or wrong `X-Api-Key` |
| `404` | Resource not found |
| `500` | P4 timeout (5 s) or internal error |
