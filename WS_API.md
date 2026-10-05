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
| `time.set` | `api_time_set` | none (WS only) |
| `alerts.get` | `api_alerts_get` | `GET /api/alerts` |
| `logs.get` | `api_logs_get` | `GET /api/logs` |
| `diagnostics.unhandled.get` | `api_diagnostics_unhandled_get` | `GET /api/diagnostics/unhandled` |
| `settings.set` | `api_settings_set` | `POST /api/settings` |

`time.set` `{"epoch": <Unix seconds>}` hands a hub the time when it has none. No ZHAC board
has a battery-backed clock, so a hub without internet access (no NTP) starts every boot at
1970, and its scheduled rules wait. The hub takes the time only while its own clock is unset:
the reply `{"set": true}` means it did, `{"set": false}` that its clock was already set and was
left alone. `status.get` reports `clock_set`, and the web UI sends `time.set` by itself when that
is `false`. An epoch before 2020 or after 2099 is an error.

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
| `diag.tasks` | — (wired and single-chip builds) | — |
| `device.reinterview` | `api_device_reinterview` | `POST /api/devices/:ieee/interview` |

Rename, delete and permit join share one implementation with REST (`device_cmd` in
zhac-components): `device.rename` refuses names over 29 bytes or with quotes, backslashes or
control characters; `device.delete` with `hard: false` (default) asks the device to leave and
hides it, `hard: true` also wipes its stored row, shadow and converter caches;
`zigbee.permit_join` takes `duration` 0–254 (255 is clamped to 254 on the radio) and
`zigbee.permit_join.status` reads the same deadline the REST route set. `diag.tasks` answers
`{"cores":2,"tasks":[{"name","core","cpu","prio","stack_free"}, …]}`: every FreeRTOS task with
its CPU share since the previous call (per-task 0–100, so the sum may reach 100 × cores), the core
it is pinned to (−1 = any), priority and stack headroom; the Diag page polls it every 5 s. The `rule.added` /
`rule.updated` / `rule.deleted` pushes are emitted for every change, whichever door made it
(WebSocket, REST, backup restore), on the wired and mono builds.

`device.get` / `device.list` responses carry an `exposes` array with
`{name, type, access, unit, values}` entries, built on P4 by
`zhac_adapter_build_exposes_json` from the device's
`PreparedDefinition`. The SPA `StatesTab` uses the `access` bitmask
(bit 0 = STATE, bit 1 = SET, bit 2 = GET) to render read-only labels,
editable inputs, or enum dropdowns.

On the wired build, `device.get` of a motion sensor that reports motion but never "no motion"
(its definition has zigbee2mqtt's `occupancy_timeout` option) also carries
`occupancy_timeout_default` (the definition's default, seconds: 90, or 62 / 32 for some Aqara
models) and `occupancy_timeout` (the interval in force: the user's choice once saved, else the
default; 0 = never). The hub reports `occupancy = false` that long after the last motion.
`device.options.set {"ieee", "occupancy_timeout": N}` saves the user's choice (0–65535; out of
range is refused). Devices without the option carry neither field.

### Rules

| cmd | handler | REST equivalent |
|-----|---------|-----------------|
| `rule.list` | `api_rule_list` | `GET /api/rules` |
| `rule.create` | `api_rule_create` | `POST /api/rules` |
| `rule.delete` | `api_rule_delete` | `DELETE /api/rules` |
| `rule.enable` | `api_rule_enable` | `PUT /api/rules` |
| `rule.update` | `api_rule_update` | `PUT /api/rules/:id` |
| `rule.check` | — (wired build) | — |
| `rules.status` | — (wired build) | — |
| `rule.run` | — (wired build) | — |

On the wired build:

- `rule.list {"cursor": "0"}` answers one page, `{"items": [{id, enabled, trigger_type, rule_type, name, dsl}, …], "next_cursor": "<last id>"}`: rows sorted by id, after the cursor, at most 6,144 bytes of rows; the last page has no `next_cursor`. Without `cursor` it answers the bare array, as before.
- `rule.create` answers `{"id": <new id>}`.
- `rule.update {id, name, dsl, base}`: with `base` (the lowercase hex SHA-256 of the rule text the editor opened), the hub answers `changed` and saves nothing when the stored text is different. A rule deleted on the hub in the meantime answers `changed` too; a reload then shows it gone.
- `rule.check {dsl}` answers `{"ok": bool, "err": "<parser message>"}` and saves nothing.

`rules.status` answers `[{"id","last_fired","runs","last_skip","ago"}, …]`, one entry per active
rule: runs since boot, the last run as epoch seconds (seconds since boot while the clock is unset),
`ago` = seconds since it (present when `runs` > 0), and why the rule last did not run or which
action failed (`""`, `unchanged`, `condition_false`, `action_error:<action>`). RAM only, reset on
reboot. `rule.run` `{"id"}` ("Run now") runs a rule's actions at once with `%value%` = the trigger
attribute's current value; the reply comes after they ran. Both are separate from `rule.list` and
the `rule.*` pushes on purpose: the cloud mirrors the rule objects, and volatile fields there would
churn every sync. Firmware without them answers `unknown cmd`; the Rules page then hides the status.
See [RULES_DSL.md](RULES_DSL.md#rule-status-and-run-now).

### Scripts

| cmd | handler | REST equivalent |
|-----|---------|-----------------|
| `script.list` | `api_script_list` | `GET /api/scripts` |
| `script.read` | `api_script_read` | `GET /api/scripts/:name` |
| `script.write` | `api_script_write` (wired: WebSocket too) | `POST /api/scripts/:name` |
| `script.part` | — (wired build) | — |
| `script.check` | — | `POST /api/scripts/:name/check` |
| `script.delete` | `api_script_delete` | `DELETE /api/scripts/:name` |
| `script.run` | `api_script_run` | `POST /api/scripts/:name/run` |
| `script.reload` | — (wired build) | — |

`script.run` routes through HAP message `SCRIPT_RUN_REQ = 0x58` to the
P4, which calls `lua_engine_run_script(const char*)`.

On the wired build (one request frame from the cloud must fit 8,192 bytes, so a long text travels in parts):

- `script.list` items carry `mtime` (epoch seconds) when the hub's clock was set at the save.
- `script.read {name, offset}` answers one page `{src, offset, size, fp, next_offset?}`: at most 6,144 bytes of JSON-encoded text, whole characters only; `size` and `fp` (the lowercase hex SHA-256 of the whole file) repeat on every page. Without `offset` it answers `{src}`, the whole file (up to 16,384 bytes).
- `script.part {xfer, part, parts, src}` stages part `part` (0-based) of `parts` (2–16) of transfer `xfer` (1–16 of `[A-Za-z0-9]`), in order, and answers `{xfer, received}`. Part 0 opens the hub's one staging slot and drops any other transfer; nothing reaches flash before `script.write`. Errors: `bad_part` (another xfer, an index other than the next, a changed count), `too_large` (over 16,384 bytes), `oom`. The slot is dropped 30 s after its last use.
- `script.write {name, src}` or `{name, xfer, size, fp}` (the staged text, whose byte count and fingerprint must match), with optional `base`: `""` = the name must be free (`exists`), a fingerprint = the stored file must still have it (`changed`). The hub checks the syntax first (`check:<line>:<message>`) and answers `{name, size, fp}`. Other errors: `bad_name`, `too_large`, `too_many` (16 scripts), `no_xfer`, `bad_part`, `write_failed`, `missing src` (neither `src` nor `xfer`), and `oom` (no memory to read a staged `xfer`). Only a successful save uses the staged text up: after any error it stays until it expires (30 s after its last use) or a new part 0 replaces it, so the sender can correct `name`, `base`, `size` or `fp` and send `script.write` again.
- `script.check {name?, src}` or `{name?, xfer}` answers `{ok, err, line}`; a staged text stays staged. Errors: `missing src` (neither `src` nor `xfer`), `no_xfer`, `oom`.
- `script.reload` restarts the Lua engine without a reboot (the hub page's Apply): every stored script is loaded again and `on_boot` handlers do not run again. It answers `{loaded, total}`, or `{"queued": true}` when the pass takes longer than 5 s (it still finishes), or the error `lua queue full` when the Lua task's queue has no room (ask again).
- A REST save over 16,384 bytes is answered 413.

### Remote editing from ZHAC Cloud (wired build)

The cloud relay runs the same commands as this socket, with these limits:

- **Allow script changes from the cloud** (Settings → Remote; `settings.set {"remote_scripts": true|false}`; `status.get` reports `remote_scripts`) is off by default and after a storage reset. While it is off, the relay answers `script.write`, `script.run`, `script.reload` and `system.restart` with `scripts_off`. Only the hub's own page can change it: the relay answers `settings.set` carrying `remote_scripts` with `local_only`.
- The relay passes `rule.check`, `script.part` and every rule command.
- Every rule change (`rule.create`, `rule.update`, `rule.enable`, `rule.delete`, `rule.run`), every script change (`script.write`, `script.delete`, `script.run`, `script.reload`) and `system.restart` that the relay passes is written to the hub's log with the tag `cloud`, before it runs, e.g. `I (812345) cloud: script.write by <account id> name=heating`; the line adds `id=<n>` or `name=<name>` when the command has one. No other command the relay passes is logged.
- Firmware with these commands says so when it connects: `caps: ["rules.v1", "scripts.v1"]` and `remote_scripts`.

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
| `script.added` / `script.updated` | wired: a script was saved (REST or WebSocket) | `{name, size, fp, mtime?}` |
| `script.deleted` | wired: a script was deleted | `{name}` |
| `script.error` | wired: a script failed to compile at load, reload or run, or raised an error while running; at most one per script per 10 s | `{name, line, message}` (`message` at most 120 bytes; `name` only when it is `[A-Za-z0-9_-]{1,24}`, else `""`) |
| `hub.caps` | wired: "Allow script changes from the cloud" changed | `{caps, remote_scripts}` |

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
