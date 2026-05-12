# ZHAC WebSocket API Reference

**URL:** `ws://<device-ip>/ws`
**Transport:** single endpoint serves both the command-envelope RPC
and the unsolicited push-event stream. Text frames only. UTF-8 JSON.

The Preact SPA under `www-spa/` is the first-party consumer of this
API and speaks WebSocket only. REST (see [`REST_API.md`](REST_API.md))
is retained for scripts and third-party integrations; every command
below is byte-identical to its REST equivalent because both transports
call the same `api_*` handler in
`zhac-net-core/main/api_handlers.cpp`.

---

## Envelope format

### Request

```json
{ "id": 42, "cmd": "<name>", "args": { /* command-specific */ } }
```

- `id` — any JSON value (int, string, null). Echoed verbatim on the
  response so the client can correlate. Integers are the common case.
- `cmd` — command name; see the dispatch table below.
- `args` — optional object. Passed through to the handler as the
  same body it would receive from a REST POST/PUT.

### Response — success

```json
{ "id": 42, "ok": true, "data": { /* handler output */ } }
```

`data` is embedded verbatim, not re-serialised — the handler writes
JSON directly into the response buffer.

### Response — error

```json
{ "id": 42, "ok": false, "err": "<reason>" }
```

Possible `err` strings: `missing cmd`, `unknown cmd`, `bad request`,
`not found`, `method not allowed`, `alloc failed`, `response too large`,
`internal error`.

### Size limits

- Request body (`args` serialised): 2 KB stack buffer.
- Response body: 8 KB PSRAM buffer, **40 KB for `logs.get`**.
- Envelope overhead: 1 KB additional PSRAM.

Implementation: `dispatch_envelope` in
`zhac-net-core/main/ws_bridge.cpp`.

---

## Command dispatch table

The table below mirrors `kWsCmds[]` in `ws_bridge.cpp`. Each row maps
a command name to an `api_*` handler and the equivalent REST route.

### Status / system

| cmd | handler | REST equivalent |
|-----|---------|-----------------|
| `status.get` | `api_status_get` | `GET /api/status` |
| `alerts.get` | `api_alerts_get` | `GET /api/alerts` |
| `logs.get` | `api_logs_get` | `GET /api/logs` |
| `diagnostics.unhandled.get` | `api_diagnostics_unhandled_get` | `GET /api/diagnostics/unhandled` |
| `settings.set` | `api_settings_set` | `POST /api/settings` |

### WiFi

| cmd | handler | REST equivalent |
|-----|---------|-----------------|
| `wifi.status` | `api_wifi_status` | `GET /api/wifi/status` |
| `wifi.scan` | `api_wifi_scan` | `GET /api/wifi/scan` |
| `wifi.connect` | `api_wifi_connect` | `POST /api/wifi` |
| `wifi.disconnect` | `api_wifi_disconnect` | `DELETE /api/wifi` |

### OTA

| cmd | handler | REST equivalent |
|-----|---------|-----------------|
| `ota.s3` | `api_ota_s3` | `POST /api/ota` |
| `ota.p4` | `api_ota_p4` | `POST /api/p4-ota` |

### Zigbee control

| cmd | handler | REST equivalent |
|-----|---------|-----------------|
| `zigbee.permit_join` | `api_zigbee_permit_join` | `POST /api/permit_join` |
| `zigbee.reset` | `api_zigbee_reset` | `POST /api/zigbee/reset` |
| `zigbee.settings.set` | `api_zigbee_settings_set` | `POST /api/zigbee/settings` |

### Devices

| cmd | handler | REST equivalent |
|-----|---------|-----------------|
| `device.list` | `api_device_list` | `GET /api/devices` |
| `device.get` | `api_device_get` | `GET /api/devices/:ieee` — response includes the `exposes` array (see below) |
| `device.bind` | `api_device_bind` | `POST /api/devices/:ieee/bind` |
| `device.delete` | `api_device_delete` | `DELETE /api/devices/:ieee` |
| `device.rename` | `api_device_rename` | `PUT /api/devices/:ieee/attrs` (name field) |
| `device.reinterview` | `api_device_reinterview` | `POST /api/devices/:ieee/interview` |

`device.get` / `device.list` responses carry an `exposes` array with
`{name, type, access, unit, values}` entries, built on P4 by
`zhac_adapter_build_exposes_json` from the device's
`PreparedDefinition`. The SPA `StatesTab` uses the `access` bitmask
(bit 0 = STATE, bit 1 = SET, bit 2 = GET) to render read-only labels,
editable inputs, or enum dropdowns.

### Rules

| cmd | handler | REST equivalent |
|-----|---------|-----------------|
| `rule.list` | `api_rule_list` | `GET /api/rules` |
| `rule.create` | `api_rule_create` | `POST /api/rules` |
| `rule.delete` | `api_rule_delete` | `DELETE /api/rules` |
| `rule.enable` | `api_rule_enable` | `PUT /api/rules` |
| `rule.update` | `api_rule_update` | `PUT /api/rules/:id` |

### Scripts

| cmd | handler | REST equivalent |
|-----|---------|-----------------|
| `script.list` | `api_script_list` | `GET /api/scripts` |
| `script.read` | `api_script_read` | `GET /api/scripts/:name` |
| `script.write` | `api_script_write` | `POST /api/scripts/:name` |
| `script.delete` | `api_script_delete` | `DELETE /api/scripts/:name` |
| `script.run` | `api_script_run` | `POST /api/scripts/:name/run` |

`script.run` routes through HAP message `SCRIPT_RUN_REQ = 0x58` to the
P4, which calls `lua_engine_run_script(const char*)`.

### Groups

| cmd | handler | REST equivalent |
|-----|---------|-----------------|
| `group.list` | `api_group_list` | `GET /api/groups` |
| `group.create` | `api_group_create` | `POST /api/groups` |
| `group.get` | `api_group_get` | `GET /api/groups/:id` |
| `group.update` | `api_group_update` | `PUT /api/groups/:id` |
| `group.delete` | `api_group_delete` | `DELETE /api/groups/:id` |
| `group.cmd` | `api_group_cmd` | `POST /api/groups/:id/cmd` |

---

## Push events

Events are broadcast unsolicited to every connected client using the
envelope:

```json
{ "event": "<name>", "data": <payload> }
```

`data` is a JSON value of any shape — object, array, number, string.
No `id` field, no correlation — events are fire-and-forget.

Implementation: `ws_event_broadcast(name, payload_json, payload_len)`
in `zhac-net-core/main/ws_bridge.cpp`, fan-out protected by a
mutex over a 2 KB file-static scratch slab.

### Event catalogue

| event | emitted from | payload |
|-------|--------------|---------|
| `device.added` | `hap_bridge.cpp` on `DEVICE_JOINED` | `{ieee, ...device summary}` |
| `device.updated` | `hap_bridge.cpp` on identity / state change | `{ieee, ...device summary}` |
| `device.removed` | `hap_bridge.cpp` on `DEVICE_DELETED` | `{ieee}` |
| `device.list.snapshot` | `hap_bridge.cpp` after HAP resync | `[{...}, ...]` — full device array |
| `attr.bulk` | `hap_bridge.cpp` coalesced 100 ms window | `[{type:"device_update", ieee, attrs:{...}, lqi, last_seen}, ...]` |
| `alert.added` | `hap_bridge.cpp` on new persisted alert | `{code, ieee, msg, ts}` |
| `alert.fired` | `hap_bridge.cpp` on transient alert | `{code, ieee, msg, ts}` |

### `log.entry` — currently disabled

The log ring (`zhac-net-core/main/log_ring.cpp`) is capable of
emitting a `log.entry` event per log line, but `s_ws_enabled` is
force-initialised to `false`. Per-line broadcast caused httpd
back-pressure and a feedback storm through `log_vprintf_hook`
during bootstrap. The SPA Logs page polls `logs.get` every 5 s as
a stopgap. Re-enabling needs a dedicated TaskLogStream — see
[`TODO.md`](TODO.md) "Follow-ups from 2026-04-22".

---

## Connection lifecycle

1. Client opens `ws://<host>/ws`. `ws_server` handles the HTTP
   upgrade.
2. `WsRxCallback(int fd, payload, len)` is invoked for every text
   frame; non-JSON frames are rejected with `err: "bad request"`.
3. `ws_server_reply(fd, ...)` sends the envelope back on the
   originating socket. Push events go to every connected socket.
4. LRU purge (`cfg.lru_purge_enable = true` in `ws_server_init`)
   evicts the oldest idle socket when `max_open_sockets` is hit —
   keeps mobile browsers with 6 speculative connections from
   exhausting `accept()`.

Authentication: the bearer token accepted on REST also gates `/ws`;
see [`REST_API.md`](REST_API.md) "Authentication" and the open
follow-up in [`TODO.md`](TODO.md) for the planned session cookie.

---

## See also

- [`REST_API.md`](REST_API.md) — per-endpoint request / response shapes (same schema on both transports).
- [`LUA_API.md`](LUA_API.md) §8–§9 — Scripts REST + WS surface.
- `zhac-net-core/main/ws_bridge.cpp` — dispatcher source of truth.
- `zhac-net-core/main/api_handlers.{h,cpp}` — every `api_*` called by the table above.
