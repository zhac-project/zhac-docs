# ZHAC WebSocket API Reference

**URL:** `ws://<hub>/ws`
**Transport:** one endpoint carries both the command-envelope RPC and the unsolicited push
events. Text frames only, UTF-8 JSON.

The web UI (`www-spa/`) is the first-party client and speaks WebSocket only; the ZHAC Cloud
relay runs the same commands (see [Remote editing from ZHAC Cloud](#remote-editing-from-zhac-cloud)).
REST ([`REST_API.md`](REST_API.md)) is there for scripts and other integrations. The two are
separate handlers in the firmware: WebSocket commands in `zhac-wired-core/main/ws_bridge.cpp`,
REST routes in `zhac-wired-core/main/api_*.cpp`. Many of them call the same code underneath (the
device commands in `device_cmd`, settings, collections, the cloud link), but each transport reads
its own arguments and frames its own reply: the shapes below are the WebSocket ones, a REST
route's are in `REST_API.md`.

---

## Envelope format

### Request

```json
{ "id": 42, "cmd": "<name>", "args": { /* command-specific */ } }
```

- `id` — an unsigned 32-bit integer, echoed on the reply so the client can match the two.
  Anything else (a string, a negative or fractional number, no `id`) is answered with `id` 0.
- `cmd` — command name; see the tables below.
- `args` — optional object, read by the command.

### Response — success

```json
{ "id": 42, "ok": true, "data": { /* command output */ } }
```

`data` is an object or an array, depending on the command. A command with nothing to report
answers `{"id": 42, "ok": true}`. `ping` is the one exception: `{"id", "ok": true, "pong": true,
"uptime_s"}`, with no `data`.

### Response — error

```json
{ "id": 42, "ok": false, "err": "<reason>" }
```

`err` is a short English message. The envelope's own are `bad json` (the frame is not JSON;
answered with `id` 0), `missing cmd`, `unknown cmd`, `auth required` and `auth failed`. Every
other belongs to its command; common ones are `missing ieee`, `bad ieee`, `device not found` and
`oom`.

### Signing in

While the hub's sign-in is on, a new socket must send `{"cmd": "auth", "args": {"token": "…"}}`
before anything else: every other command is answered `auth required` until then, and a socket
that has not signed in within 5 seconds is closed (a full table closes the oldest such socket to
make room for a new one). The token rides a frame, never the URL; see
[`REST_API.md`](REST_API.md#authentication) for the tokens. A socket opened while sign-in is off
starts signed in, and `auth` on a signed-in socket just answers `ok`.

### Size limits

- Inbound frame: at most 32,768 bytes (the cloud relay's limit stays 8,192, see
  [Remote editing from ZHAC Cloud](#remote-editing-from-zhac-cloud)). A longer frame closes the
  session (the hub cannot answer a request it did not read); send a long script in parts
  (`script.part`, below) or with
  `POST /api/scripts/<name>`, and check it with `POST /api/scripts/<name>/check`.
- Inbound frame time: each frame, PING and CLOSE included, must arrive within 8 seconds of the
  start of its read (at most 11 s: the check comes before each read, which can wait 3 s); a slower
  one closes the session (one frame held the hub's web server while it trickled in). The hub
  answers a PING with a PONG and a CLOSE with a CLOSE.
- Replies: each command sizes its own. `logs.get` answers at most 32 KB of log lines; long lists
  come in pages when asked: `device.list` and `rule.list` with `cursor`, `script.read` with
  `offset` (below).

Implementation: `dispatch_envelope` in `zhac-wired-core/main/ws_bridge.cpp`; frames, sign-in and
deadlines in `zhac-components/components/ws_server/`.

---

## Commands

"REST route" names the route that does the same thing over HTTP, where there is one.

### Status / system

| cmd | REST route |
|-----|------------|
| `auth` | — (see [Signing in](#signing-in)) |
| `ping` | — |
| `status` / `status.get` | `GET /api/status` |
| `time.set` | — |
| `alerts.get` | — |
| `logs.get` | `GET /api/logs` |
| `diagnostics.unhandled` / `diagnostics.unhandled.get` | `GET /api/diagnostics/unhandled` |
| `diag.tasks` | — |
| `settings.set` | `POST /api/settings` |
| `token.rotate` | `POST /api/token/rotate` |
| `system.restart` | — |
| `system.storage_reset` | — |

- `status` and `status.get` answer the snapshot `GET /api/status` returns; both fill it with the
  same code (`api_status_fill`).
- `time.set` `{"epoch": <Unix seconds>}` hands a hub the time when it has none. No ZHAC board
  has a battery-backed clock, so a hub without internet access (no NTP) starts every boot at
  1970, and its scheduled rules wait. The hub takes the time only while its own clock is unset:
  the reply `{"set": true}` means it did, `{"set": false}` that its clock was already set and was
  left alone. `status.get` reports `clock_set`, and the web UI sends `time.set` by itself when that
  is `false`. An epoch before 2020 or after 2099 is an error.
- `alerts.get` answers an empty list, `[]`: the hub keeps no alerts.
- `logs.get` answers `{"logs": [...]}`, the hub's recent log lines.
- `diagnostics.unhandled` answers the Zigbee messages no device definition handled (the Diag
  page's list), filled by the same code as `GET /api/diagnostics/unhandled`.
- `diag.tasks` answers `{"cores":2,"tasks":[{"name","core","cpu","prio","stack_free"}, …]}`: every
  FreeRTOS task with its CPU share since the previous call (per-task 0–100, so the sum may reach
  100 × cores), the core it is pinned to (−1 = any), priority and stack headroom; the Diag page
  polls it every 5 s.
- `settings.set` takes the same object as `POST /api/settings` (one code path,
  `system_apply_settings`), at most 511 bytes of JSON here, and answers `ok` or `bad settings`.
  What the cloud relay may not change is under [Remote editing](#remote-editing-from-zhac-cloud).
- `token.rotate` replaces the hub's API token and answers the new one, `{"token": "…"}`.
- `system.restart` answers, then restarts the hub.
- `system.storage_reset` erases the device store and the settings (partitions `zhac_data` and
  `nvs`) and restarts the hub. The Zigbee network (`zb_storage`), the coordinator's address and
  the scripts stay.

### Network

| cmd | REST route |
|-----|------------|
| `net.status` | `GET /api/net/status` |
| `uplink.get` | — |
| `wifi.status` | `GET /api/wifi/status` |
| `wifi.scan` | `GET /api/wifi/scan` |
| `wifi.connect` | `POST /api/wifi/connect` |
| `wifi.disconnect` | `POST /api/wifi/disconnect` |

`net.status` answers the Ethernet link: `{transport: "ethernet", link_up, has_ip, ip, netmask,
gateway, mac, speed_mbps, duplex, hostname}`. The hub has no Wi-Fi: `wifi.status` reports
`mode: "eth"` with an empty `ssid` and `rssi` 0, `wifi.scan` an empty `networks` list, and
`wifi.connect` / `wifi.disconnect` the error `wifi unsupported: zhac-wired-core is Ethernet-only`.
`uplink.get` answers `{"uplink": "none"}`. (A test build with an ESP32-C5 Wi-Fi co-processor, not
released, answers the `wifi.*` commands from the co-processor.)

### Firmware update

| cmd | REST route |
|-----|------------|
| `ota.update` | — |

`ota.update` `{"url": "https://…-ota.bin", "allow_older": false}` updates the hub; it answers at
once and reports `ota.start`, `ota.progress` and `ota.complete` (target `self`). The hub installs
only an image of its own firmware (the same `project_name`), and a release older than the running
one only with `allow_older: true`; otherwise `ota.complete` carries `ok: false` and the reason.
A pre-release `vYYYYMMDDVV-rcN` comes just before its release (`-rc1` before `-rc2` before the
release); a developer build (`git describe` with commits on top) is never older and calls nothing
older. A download the server redirects again after the hub resolved its address ends the attempt:
`ota.complete` says so and the hub restarts, with nothing written. Zigbee devices' own firmware
goes over REST: [Device firmware update](REST_API.md#device-firmware-update).

### Zigbee network

| cmd | REST route |
|-----|------------|
| `zigbee.permit_join` | `POST /api/permit_join` |
| `zigbee.permit_join.status` | — |
| `zigbee.reset` | — |
| `zigbee.settings.set` | — |
| `net.map.scan` | — |
| `net.map.get` | — |

- `zigbee.permit_join` takes `duration` 0–254 (255 is clamped to 254 on the radio);
  `zigbee.permit_join.status` answers `{open, remaining_sec}`, reading the same deadline the REST
  route sets.
- `zigbee.reset` marks the Zigbee network for erasure at the next boot, forgets every device and
  restarts the hub, which then forms a new network: every device has to pair again.
- `zigbee.settings.set` always answers the error `channel and network key settings are not
  available on this hub yet -- nothing was saved`.
- `net.map.scan` starts a network-map scan and replies `{started: true}`; errors `busy`,
  `not_ready`, `oom`. `net.map.get` answers `{scanning, progress: {done, total, current}, map}`;
  `map` is `null` before the first scan.

### Devices

| cmd | REST route |
|-----|------------|
| `device.list` | `GET /api/devices` |
| `device.get` | — |
| `device.rename` | — |
| `device.delete` | — |
| `device.attr.set` | `POST /api/device/attr/set` |
| `device.options.set` | `POST /api/device/options/set` |
| `device.reinterview` | `POST /api/device/reinterview` |
| `device.configure` | `POST /api/device/configure` |
| `device.bind` | — |
| `device.groups.list` / `device.groups.add` / `device.groups.remove` / `device.groups.refresh` | — |

`device.list` without arguments answers the bare array of every device: `{ieee, nwk, friendly,
name, model, manufacturer, vendor, model_id, known, last_seen, lqi, battery, ep_count, …}`, with
`offline: true` on a device that left its availability ping unanswered and `local: true` on the
Hub I/O device (UIs hide its Zigbee buttons). With `{"cursor": "0"}` it answers pages,
`{items: [...], next_cursor}`, the cursor being the last IEEE address of the page; the last page
has no `next_cursor`. The cloud relay always gets pages.

`device.get` answers one device with its endpoints, clusters, stored values and, when a device
definition matches, an `exposes` array of `{name, type, access, unit, values}` entries, built by
`zhac_adapter_build_exposes_json` from the definition (`PreparedDefinition`). The web UI's States
tab uses the `access` bitmask (bit 0 = STATE, bit 1 = SET, bit 2 = GET) to render read-only
labels, editable inputs or enum dropdowns.

- `device.attr.set {ieee, key, value}` writes one value to the device (what its States tab
  writes) and answers `ok` or the reason it could not.
- `device.configure {ieee}` runs the device's bindings, reporting setup and first reads again,
  as after pairing (for a device paired before its definition gained them); error `device unknown
  or never interviewed`.
- `device.groups.list {ieee}` answers the native ZCL groups the device is in (the device page's
  Groups tab). `device.groups.add` / `device.groups.remove {ieee, gid, ep}` put an endpoint
  (default 1) into group `gid` (1–65535) or take it out; `device.groups.refresh {ieee, ep}` reads
  the device's own list again.
- `device.bind` and `device.groups.add` / `remove` / `refresh` answer when the device did, up to
  about 10 seconds later; the hub keeps serving other requests meanwhile. They go out one at a
  time. With one running and four waiting, another is answered at once with
  `busy -- another radio command is still running, try again`. Commands relayed from the cloud
  still run on the cloud link's own task and are not queued. The Hub I/O device refuses the
  Zigbee-only commands (`device.bind`, `device.reinterview`, `device.configure`,
  `device.groups.add` / `remove` / `refresh`).

Rename, delete and permit join share one implementation with REST (`device_cmd` in
zhac-components): `device.rename` refuses names over 29 bytes or with quotes, backslashes or
control characters; `device.delete` with `hard: false` (default) asks the device to leave and
hides it, `hard: true` also wipes its stored row, shadow and converter caches.

`device.get` of a motion sensor that reports motion but never "no motion" (its definition has
zigbee2mqtt's `occupancy_timeout` option) also carries `occupancy_timeout_default` (the
definition's default, seconds: 90, or 62 / 32 for some Aqara models) and `occupancy_timeout` (the
interval in force: the user's choice once saved, else the default; 0 = never). The hub reports
`occupancy = false` that long after the last motion. `device.options.set {"ieee",
"occupancy_timeout": N}` saves the user's choice (0–65535; out of range is refused). Devices
without the option carry neither field.

`device.get` also carries `no_occupancy_since` (seconds, 0 = off), zigbee2mqtt's `no_occupancy_since` option with one interval, for any motion sensor. Once the device reports `occupancy = false` (or the hub's no motion interval does) and that many seconds pass without motion, the hub sets the device value `no_occupancy_since` to N; the next motion sets it back to 0, so an edge-triggered rule fires once per quiet period. A repeated "no motion" report does not restart a running count, and after a hub restart counting starts again at the next motion change. `device.options.set {"ieee", "no_occupancy_since": N}` saves it (0–65535; out of range is refused). `device.options.set` merges each call into the device's stored options.

### Rules

| cmd | REST route |
|-----|------------|
| `rule.list` | `GET /api/rules` |
| `rule.create` | `POST /api/rules` |
| `rule.update` | `PUT /api/rules/<id>` |
| `rule.delete` | `DELETE /api/rules/<id>` |
| `rule.enable` | `POST /api/rules/<id>/enable` |
| `rule.check` | — |
| `rules.status` | — |
| `rule.run` | — |

- `rule.list {"cursor": "0"}` answers one page, `{"items": [{id, enabled, trigger_type, rule_type, name, dsl}, …], "next_cursor": "<last id>"}`: rows sorted by id, after the cursor, at most 6,144 bytes of rows; the last page has no `next_cursor`. Without `cursor` it answers the bare array.
- `rule.create {name, dsl, enabled}` answers `{"id": <new id>, "enabled": <bool>}`. `enabled` false creates the rule Off in one step, so it never runs before it is switched on; absent or `null` means On, and anything but a boolean is refused (`enabled must be true or false`). The echo, and the capability `rules.v2` below, tell a caller such as the cloud that the hub knows the argument. Older firmware answers without `enabled` and creates the rule On.
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

| cmd | REST route |
|-----|------------|
| `script.list` | `GET /api/scripts` |
| `script.read` | `GET /api/scripts/<name>` |
| `script.write` | `PUT` or `POST /api/scripts/<name>` |
| `script.part` | — |
| `script.check` | `POST /api/scripts/<name>/check` |
| `script.delete` | `DELETE /api/scripts/<name>` |
| `script.run` | `POST /api/scripts/<name>/run` |
| `script.reload` | — |

`script.run {name}` queues the script on the Lua task (`lua_engine_run_script`) and answers at
once; error `queue saturated or missing`.

One request frame from the cloud must fit 8,192 bytes, so a long text travels in parts:

- `script.list` items carry `mtime` (epoch seconds) when the hub's clock was set at the save.
- `script.read {name, offset}` answers one page `{src, offset, size, fp, next_offset?}`: at most 6,144 bytes of JSON-encoded text, whole characters only; `size` and `fp` (the lowercase hex SHA-256 of the whole file) repeat on every page. Without `offset` it answers `{src}`, the whole file (up to 16,384 bytes).
- `script.part {xfer, part, parts, src}` stages part `part` (0-based) of `parts` (2–16) of transfer `xfer` (1–16 of `[A-Za-z0-9]`), in order, and answers `{xfer, received}`. Part 0 opens the hub's one staging slot and drops any other transfer; nothing reaches flash before `script.write`. Errors: `bad_part` (another xfer, an index other than the next, a changed count), `too_large` (over 16,384 bytes), `oom`. The slot is dropped 30 s after its last use.
- `script.write {name, src}` or `{name, xfer, size, fp}` (the staged text, whose byte count and fingerprint must match), with optional `base`: `""` = the name must be free (`exists`), a fingerprint = the stored file must still have it (`changed`). The hub checks the syntax first (`check:<line>:<message>`) and answers `{name, size, fp}`. Other errors: `bad_name`, `too_large`, `too_many` (16 scripts), `no_xfer`, `bad_part`, `write_failed`, `missing src` (neither `src` nor `xfer`), and `oom` (no memory to read a staged `xfer`). Only a successful save uses the staged text up: after any error it stays until it expires (30 s after its last use) or a new part 0 replaces it, so the sender can correct `name`, `base`, `size` or `fp` and send `script.write` again.
- `script.check {name?, src}` or `{name?, xfer}` answers `{ok, err, line}`; a staged text stays staged. Errors: `missing src` (neither `src` nor `xfer`), `no_xfer`, `oom`.
- `script.reload` restarts the Lua engine without a reboot (the hub page's Apply): every stored script is loaded again and `on_boot` handlers do not run again. It answers `{loaded, total}`, or `{"queued": true}` when the pass takes longer than 5 s (it still finishes), or the error `lua queue full` when the Lua task's queue has no room (ask again).
- A REST save over 16,384 bytes is answered 413, and a chunked one (`Transfer-Encoding` without `Content-Length`, which the hub's HTTP server cannot read) 411; the stored script is kept either way.
- If the hub restarted twice in a row while its scripts were starting (a load at boot or Apply, or the minute after it), it holds them: the next boot does not start them, a rule's `script.run` action is skipped, `script.run` (and REST `POST /api/scripts/<name>/run`, 500) answers `scripts are held: the hub restarted twice while scripts were starting; Apply starts them again`, `status.get` and every `status.tick` carry `scripts_held` (the script that was loading at the last crash, `""` when unknown; a tick without it means the hold ended), and `script.error` repeats the reason once a minute. A `script.reload` that completes, or a clean boot, ends the hold.

### Cloud link

| cmd | REST route |
|-----|------------|
| `remote.status` | `GET /api/remote/status` |
| `remote.connect` | `POST /api/remote/connect` |
| `remote.disconnect` | `POST /api/remote/disconnect` |

`remote.status` answers the link's state: `{enabled, state, connected_since, last_event_at,
rtt_ms, tx_drops, auth_fails, log_sent, log_dropped}`. `remote.connect {url, token, device_id}`
stores the cloud's address and the hub's token and connects (`url + token required`; an empty
`device_id` keeps the stored one). `remote.disconnect` drops the link; with `{"forget": true}` it
also erases the stored address and token.

### Remote editing from ZHAC Cloud

The cloud relay runs the same commands as this socket, with these limits:

- **Allow script changes from the cloud** (Settings → Remote; `settings.set {"remote_scripts": true|false}`; `status.get` reports `remote_scripts`) is off by default and after a storage reset. While it is off, the relay answers `script.write`, `script.run`, `script.reload` and `system.restart` with `scripts_off`, and so a `rule.create` or `rule.update` whose text has a `script.run` action: the cloud cannot run Lua through a rule it adds either. Rules already on the hub keep running their scripts, `rule.run` included. Only the hub's own page can change it: the relay answers `settings.set` carrying `remote_scripts` with `local_only`.
- **Log to cloud** (Settings → Remote; `settings.set {"log_to_cloud": "off" | "errors" | "warnings" | "everything"}`; `status.get` reports `log_to_cloud`; `remote.status` reports `log_sent` and `log_dropped` since the hub started) is off by default and after a storage reset. Errors sends errors; Warnings sends warnings and errors; Everything adds the information lines. Only the hub's own page can change it: the relay answers `settings.set` carrying `log_to_cloud` with `local_only`. While it is on, the hub sends `log.batch` events (below) and, once per run, `log.tail`. The cloud link's own lines (`remote_client`, `websocket_client`, `transport*`, `esp-tls*`) never enter the backlog (`log.batch`); the restart tail may include them.
- The relay passes `rule.check`, `script.part` and every rule command.
- Every rule change (`rule.create`, `rule.update`, `rule.enable`, `rule.delete`, `rule.run`), every script change (`script.write`, `script.delete`, `script.run`, `script.reload`) and `system.restart` that the relay passes is written to the hub's log with the tag `cloud`, before it runs, e.g. `I (812345) cloud: script.write by <account id> name=heating`; the line adds `id=<n>` when the command carries a numeric `id`, and `name=<name>` when its `name` fits `[A-Za-z0-9_-]{1,24}` (every script name, and a rule name of that shape such as `porch_light`); any other name is left out. No other command the relay passes is logged.
- Firmware with these commands says so when it connects: `caps: ["rules.v1", "rules.v2", "scripts.v1", "logs.v1"]`, `remote_scripts` and `log_to_cloud`.
  `rules.v2` (since review 2026-10-28): `rule.create` takes `enabled` and echoes it.
- Every frame the hub sends to the cloud or to its own page is valid UTF-8: a byte that is not (a REST-uploaded script, a log line) goes out as `?`. The hub does this where frames leave it, so the JSON keeps its shape and length.

### Collections and native groups

| cmd | REST route |
|-----|------------|
| `group.list` | `GET /api/groups` |
| `group.create` | `POST /api/groups` |
| `group.get` | `POST /api/group/get` |
| `group.update` | `POST /api/group/update` |
| `group.delete` | `POST /api/group/delete` |
| `group.cmd` | `POST /api/group/cmd` |
| `groups.all` | — |

`group.*` are the hub's collections; each command and its REST route run the same code
(`zhac-wired-core/main/api_groups.cpp`), so they take and answer the same JSON. `groups.all`
answers every native ZCL group the hub knows, with its member devices (the global Groups tab);
see `device.groups.*` above for one device's groups.

`group.cmd` sends the command to every member of the collection. On, Off and Toggle
(`{cluster:6, cmd:0|1|2}`, or `key` `state` with `val` `ON` / `OFF` / `TOGGLE`) go out as one ZCL groupcast
when a native ZCL group (the device page's Groups tab) holds exactly the collection's members, at
least two, none of them asleep, and each with the Groups and On/Off (genOnOff) server clusters on its
endpoint, so they switch together. A Tuya data-point switch, whose on/off is a data-point write, keeps
the collection on one command per member. Otherwise, or when the hub has sent 4 broadcasts in the
last 9 seconds, each member gets its own command. The reply is the same either way.

---

### Safety

The hub's alarm profiles ([ALARM.md](ALARM.md)). Hub page only: the cloud link does not accept these
commands. The cloud can still arm and disarm through the Alarm device's attributes (a profile's
attribute, or `alarm_state`). The commands keep their `alarm.*` names and the device stays `Alarm`.

| cmd | args | answers |
|-----|------|---------|
| `alarm.get` | none | the status (below) plus `config`; the error `oom` when the hub has no memory for the whole answer (it never answers part of the config) |
| `alarm.arm` | `{id, force?: bool}` (`mode` is still read as `id`) | `{armed: true}`, or `{armed: false, open: [{ieee, name?}]}` while contacts of that profile are open (send again with `force: true` to arm past them); the error `an alarm is on: disarm first` while that profile (or, for an intrusion profile, any intrusion profile) is pending or triggered; `no such profile` |
| `alarm.disarm` | `{id?}` | ok. With `id`, that profile is disarmed. Without it every intrusion profile is disarmed and every other profile that is pending or triggered is silenced. `no such profile` for an unknown id |
| `alarm.silence` | `{id}` | ok: that profile's pending or triggered ends now, back to its resting state (`armed`, or `disarmed` after a panic from disarmed). `no such profile` for an unknown id |
| `alarm.config.set` | `{config}` | ok, or the first problem as the error (`profiles[1].sensors[2]: 0x... is not a device on this hub`, `profiles[0]: id armed is reserved`); nothing is changed then |

`id` names a profile only as text that is not empty. Leaving `id` out is the only way to give none (for
`alarm.disarm`: every profile; for `alarm.arm`: `mode` is read instead). An `id` that is `null`, `""`, a
number or anything else that is not text is answered `no such profile`, and nothing is armed, disarmed or
silenced.

The status: `{state, sensor?, profiles: [{id, name, class, state, since, left?, cause?, sensor?, bypassed}]}`:
- `state` is the summary of the intrusion profiles, the `alarm_state` value: `disarmed`, `arming`,
  `armed_<id>`, `pending` or `triggered`. A flood or fire profile never moves it.
- `sensor` is the name of the sensor or keypad behind the summary's `pending` or `triggered`.
- `profiles` has one entry per profile, in config order:
  - `state` is one of `disarmed`, `arming`, `armed`, `pending`, `triggered`;
  - `since` is the epoch seconds of the profile's last change, 0 while the clock is unset;
  - `left` is the seconds to the next step (arm delay, trigger delay or alarm time), during `arming`,
    `pending` and `triggered` only;
  - `cause` (an IEEE) and `sensor` (its name) say what started `pending` or `triggered`;
  - `bypassed` lists the open sensors a forced arm ignores until disarm.

The config:

```json
{"profiles": [
   {"id": "flood", "name": "Flood", "class": "water", "arm_delay": 0, "trigger_delay": 0, "siren_time": 180,
    "notify_arm": true,
    "sensors": [{"ieee": "0x00158D0001020304", "entry": false}],
    "outputs": [{"ieee": "0x00158D0005060708", "kind": "state", "value": "off", "keep": true},
                {"ieee": "0x00158D00090A0B0C", "kind": "warning", "mode": "emergency", "level": "high", "strobe": true},
                {"ieee": "0x00158D00112233FF", "kind": "alarm", "melody": "5", "volume": "high"}]},
   {"id": "night", "name": "Night", "class": "intrusion", "role": "night", "arm_delay": 0, "trigger_delay": 30,
    "siren_time": 180, "notify_arm": false, "sensors": [], "outputs": []}],
 "keypads": [{"ieee": "0x00158D0001AABBCC", "trusted": false}],
 "codes": ["1234"]}
```

- `alarm.config.set` replaces the whole config; a field left out takes its default (delays 0, `siren_time`
  180, `notify_arm` false, no `role`).
- `profiles` is required and must be a list (`[]` for none): a config without it, or with `"profiles": null`
  or an object there, is refused with `profiles must be a list`. The config of v2026112401 (`exit_delay`,
  `entry_delay`, `sensors` with `modes`, `sirens`) is not taken here: the hub converts that form only from
  its own stored record, at start. It always answers in the new form.
- Leaving `codes` out keeps the stored codes; `"codes": []` clears them.
- `alarm.get` never returns the codes, only `codes_count`.
- An error about a sensor reads `profiles[P].sensors[N]: ...`. `N` is the sensor's row in that profile's
  `sensors` list as sent, counted from 0. A problem with the device itself (`... is not a device on this
  hub`, or nothing it can watch) names the first profile that lists the sensor, and its row there. A
  sensor listed twice in one profile is `profiles[1].sensors[3]: listed twice`, and a 49th different
  sensor, in any profile, is `profiles[2].sensors[7]: more than 48 different sensors`.
- A sensor appears in each profile that lists it, with its own `entry` flag. `role` is for an intrusion
  profile only (`""` is none). An output carries `mode`, `level` and `strobe` for kind `warning`, `melody` and
  `volume` for kind `alarm`, and `value` (`on` or `off`) and `keep` for kind `state`.
- The config is refused while any profile is arming, pending or triggered: `an alarm is running: disarm or
  wait, then save`.
- Limits:
  - 8 profiles; delays 0-300 s; `siren_time` 10-1800 s;
  - 48 different sensors, each in any number of profiles; 8 outputs in a profile and 32 in all;
    8 keypads; 8 codes of 4-8 digits (as text);
  - `id`: 1-13 of `a-z`, `0-9`, `_`, starting with a letter, unique, and not one of the ten reserved
    words `alarm_state`, `alarm_sensor`, `armed`, `disarmed`, `arming`, `pending`, `triggered`,
    `pin_code`, `action_code` or `color_hex` (`profiles[0]: id armed is reserved`); `name`: 1-24 bytes
    of UTF-8, no control characters; each `role` at most once;
  - `melody` and `volume`: plain text of up to 23 bytes of UTF-8, no control characters;
  - every sensor must expose `contact`, `occupancy`, `presence`, `vibration`, `water_leak`, `smoke`, `gas` or
    `carbon_monoxide`; every output needs something settable for its kind: `warning` a settable `warning`,
    `alarm` a settable `alarm` (a smoke sensor's `alarm` is only a reading), `state` a settable `state`
    (`profiles[0].outputs[0]: Hall smoke has no alarm switch the hub can set ...`);
  - one switch used as a `state` output in several profiles needs the same `value` and `keep` in all of them;
  - the class of a saved profile cannot change (`profiles[0]: the class of a saved profile cannot change`);
  - the config is kept in flash in at most 8 KB, which the largest config the limits allow fits; a
    frame to the hub is at most 32 KB (see [Size limits](#size-limits)), and that config is about 22 KB.
    A save that cannot be stored answers `could not save the config`.

## Push events

Events are broadcast unsolicited to every signed-in socket using the envelope:

```json
{ "event": "<name>", "data": <payload> }
```

`data` is a JSON value of any shape — object, array, number, string.
No `id` field, no correlation — events are fire-and-forget.

Implementation: `push_event` in `zhac-wired-core/main/ws_bridge.cpp`. Each event is built in its
own PSRAM buffer and goes to every signed-in socket (`ws_server_broadcast`) and, while the cloud
link is up, to the cloud, which gets the bare payload.

### Event catalogue

| event | when | payload |
|-------|------|---------|
| `attr.changed` | a device reported a value | `{ieee, key, value, nwk, ep, cluster, attr_id, ts?}`: `ts` in epoch seconds, absent while the hub's clock is unset. A keypad PIN (`action_code`, `pin_code`) goes to the hub page only, never the cloud |
| `alarm.changed` | a profile of the alarm changed state, or the config was saved | the `alarm.get` status without `config` (see [Safety](#safety)) |
| `attr.bulk` | a device answered again after a silence, or left its availability ping unanswered | `[{ieee, last_seen?, offline, attrs: {}}]` |
| `device.added` | a device joined | `{ieee, friendly, name}` |
| `device.removed` | a device left the network | `{ieee}` |
| `group.added` / `group.updated` | a collection was created or changed | the collection, as `group.get` answers it |
| `group.deleted` | a collection was deleted | `{id}` |
| `rule.added` / `rule.updated` | a rule was saved, switched on or off | the row `rule.list` carries: `{id, enabled, trigger_type, rule_type, name, dsl}` |
| `rule.deleted` | a rule was deleted | `{id}` |
| `script.added` / `script.updated` | a script was saved (REST or WebSocket) | `{name, size, fp, mtime?}` |
| `script.deleted` | a script was deleted | `{name}` |
| `script.error` | a script failed to compile at load, reload or run, or raised an error while running; at most one per script per 10 s and 17 in all per 10 s; once a minute while the hub holds its scripts | `{name, line, message}` (`message` at most 120 bytes; `name` only when it is `[A-Za-z0-9_-]{1,24}`, else `""`) |
| `status.tick` | every 10 s | `{local_time, fw_version, ip, mac, link_up, link_speed, link_duplex, mqtt_connected, ws_clients, scripts_held?, …}`: the Info page's live values |
| `ota.start` / `ota.progress` / `ota.complete` | a firmware update (`ota.update`) started, advanced or ended | see `ota.update` |
| `net.map.progress` | after each router answers a map scan; hub page only, never the cloud | `{done, total, current}` |
| `net.map.done` | the scan finished; the page then calls `net.map.get` | `{ts, ok, err?}` |
| `hub.caps` | "Allow script changes from the cloud" or "Log to cloud" changed | `{caps, remote_scripts, log_to_cloud}` |
| `log.batch` | Log to cloud on: every 5 s, or once 6 KB waits; to the cloud only | `{boot, seq, up, clock, dropped, lines: [[up_ms, "E"\|"W"\|"I", tag, msg], …]}`, at most 6,144 bytes; `seq` is the first line's number in this run, `clock` the hub's epoch ms or 0 when its clock is not set |
| `log.tail` | Log to cloud on: once per run, first; to the cloud only | `{boot, prev_boot, up, clock, reason, planned, prev_clock_base, prev_sent, crash, lines: [[up_ms, level, tag, msg, seq], …]}`: why the hub restarted, a crash summary, and the previous run's lines the cloud never got |

The `rule.*` pushes are sent for every change, whichever door made it (WebSocket, REST, the
cloud, a backup restore), and the `script.*` ones for every save and delete, REST included. The
`group.*` ones follow the WebSocket commands only (the cloud's included): a collection changed
over REST is not pushed.

### Log lines

The web UI's Log page polls `logs.get` every 5 s. A push per log line exists but is off: settings
`log_ws_enabled: true` with `log_ws_level` (`E`, `W` or `I`; `settings.set` or
`POST /api/settings`) turns it on until the hub restarts. Every line at that level or worse then
goes to every socket as a bare frame, not an event envelope:
`{"type": "log", "level": "W", "entry": {…}}`. Per-line pushes once stalled the hub's web server
under boot load, which is why the page polls.

---

## Connection lifecycle

1. The client opens `ws://<hub>/ws`; `ws_server` (zhac-components) handles the HTTP upgrade.
2. While sign-in is on, the first frame must be `auth` ([Signing in](#signing-in)).
3. Only text frames are read. Each is parsed as JSON and dispatched; a frame that is not JSON is
   answered `bad json` with `id` 0.
4. Replies go to the socket that asked (`ws_server_reply`); events go to every signed-in socket.
5. The hub's web server holds at most 9 sockets, HTTP and WebSocket together; when a new one
   arrives and none is free, the one idle longest is closed. Mobile browsers open several
   speculative connections, and this keeps them from locking the hub page out.

---

## See also

- [`REST_API.md`](REST_API.md) — the REST routes, with their own request and reply shapes.
- [`LUA_API.md`](LUA_API.md) §8–§9 — scripts over REST and WebSocket.
- `zhac-wired-core/main/ws_bridge.cpp` — the command dispatcher (`dispatch_envelope`) and the event pushes.
- `zhac-components/components/ws_server/` — the socket server: frames, sign-in, deadlines.
