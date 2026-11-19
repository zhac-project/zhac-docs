# ZHAC REST API Reference

**Base URL:** `http://<hub>/api`
**Content-Type:** `application/json`, unless a route says otherwise.

REST is there for scripts and other integrations; the web UI and the ZHAC Cloud relay use the
WebSocket API ([`WS_API.md`](WS_API.md)). The routes live in `zhac-wired-core/main/api_*.cpp`,
with sign-in in `auth.cpp`, the full backup in `backup.cpp` and device firmware updates in
`device_ota.cpp`. Many of them call the same code as the WebSocket commands, but each transport
reads its own arguments and frames its own reply: the shapes on this page are REST's own.

A refused request answers an HTTP status with a short reason: `{"error": "<code>"}` from the
sign-in layer, the backup and device-update routes, plain text (`missing ieee`) from the others.
See [Error responses](#error-responses).

---

## Authentication

While sign-in is on, every route except `GET /api/status`, `POST /api/auth/login` and
`POST /api/auth/setup` needs the header:

```
X-Api-Key: <token>
```

Without it, or with a wrong one, the hub answers `401 {"error":"unauthorized"}`. With sign-in
off the routes need no token, but they answer only the hub's own page and clients that are not
web pages: a request whose `Origin` is another site, or whose `Host` is not the hub's IP address
or its `.local` name, is refused `403 {"error":"cross_site"}`, so a page of another site cannot
drive the hub through your browser. `GET /api/status` follows the same rule.

The token is a 32-character hex string generated on first boot and printed to the serial console:

```
W (1234) main: *** NEW API TOKEN (save this): a1b2c3d4e5f6... ***
```

The token persists in NVS across reboots. With a password set, a boot prints only the token's
last four characters; the boot after a password lockout prints it in full (TROUBLESHOOTING.md,
"I forgot the password").

### Password login (web UI flow)

Humans don't handle 32-hex tokens well, so the web UI authenticates with an
**admin password** and exchanges it for the token. The token remains the only
wire credential; these endpoints are the exchange layer on top:

| Endpoint | Auth | Body | Purpose |
|---|---|---|---|
| `POST /api/auth/login` | none (is the exchange) | `{"password":"…"}` | Verify password → `{"ok":true,"token":"<32hex>"}`. `401` wrong password, `409` no password set yet, `429 {"error":"too_many_attempts"}` (with `Retry-After: 60`) while locked out. |
| `POST /api/auth/setup` | none, **only while no password exists and for 10 minutes after power-on** | `{"password":"…"}` | First-boot: set the admin password (8-63 chars) and return the token. `403 {"error":"already_set"}` once set; `403 {"error":"setup_closed"}` when the window has passed (power-cycle the hub to reopen it). |
| `POST /api/auth/password` | **Auth required** + current password | `{"current":"…","new":"…"}` | Change password. Rotates the API token (invalidates other clients) and returns the fresh one. |

The password is stored as a salted iterated-SHA-256 hash in NVS (never
plaintext). Wrong passwords (`/api/auth/login`, `/api/auth/password`) and
wrong tokens count together per address (an IPv6 peer: its /64): five within a
minute lock that address out until the first of them is a minute old. Meanwhile
every route that needs the token answers it `401`, even the right token, and a
WebSocket `auth` answers `auth failed`; login and password change answer `429`
(`Retry-After: 60`). A request to such a route without `X-Api-Key` counts as a
wrong token. Twenty wrong passwords within a minute from any addresses also
lock the password for everyone (`429`); a valid token keeps working. The three routes take only `Content-Type: application/json`
bodies (`415 {"error":"json_required"}` otherwise). `/api/status` reports
`auth_setup_required: true` while auth is enabled but no password exists — the
web UI shows its one-time setup card then — and `auth_setup_secs_left`, the
seconds the first-claim window has left (0 once it closed). `storage_error: true`
means the whole NVS partition could not be initialised at boot; the hub runs
locked and empty, erases nothing by itself, and the WebSocket command
`system.storage_reset` (no REST twin) erases it and restarts on the owner's request.
`auth_storage_error: true` means the hub could not open its sign-in
storage at boot and locked itself: sign-in is on, the only credential is the token printed
on the serial console for that boot, and `POST /api/auth/setup` answers
`503 {"error":"storage_error"}`. The window bounds the "first visitor claims the hub" pattern: a hub
that was never set up, or was reset weeks ago, cannot be claimed by whoever
finds it on the network later, only by someone who can power-cycle it.
The serial-printed token remains the recovery path (lost password → sign in
with the token, or erase NVS to re-run setup).

---

## System

#### `GET /api/status`

The hub's state. With sign-in on, a request without the API token gets only what the sign-in
page needs: `sku` (`"wired"`) and the `auth_*` fields. Send the token for the rest. A request
without a key is not a wrong guess and counts toward no lockout; a wrong key does. The
WebSocket `status` command answers the same object (`api_status_fill`).

| Group | Fields |
|-------|--------|
| Firmware | `fw_version`, `fw`, `target`, `revision`, `cores`, `uptime`, `uptime_s`, `reset_reason`, `last_crash`, `safe_mode` |
| Memory, CPU | `heap`, `heap_min`, `int_free`, `int_min`, `int_blk`, `psram_free`, `psram_min`, `psram_blk`, `psram_total`, `heap_internal_free`, `heap_internal_min`, `heap_internal_blk`, `heap_total_free`, `psram_size`, `stack_hwm`, `stack_hwm_task`, `cpu_c0`, `cpu_c1` |
| Network | `ip`, `mac`, `ip6`, `ip6_ll`, `ip6_global`, `has_ip6`, `hostname`, `link_up`, `link_speed`, `link_duplex`, `net_transport`, `net_link_up`, `net_speed`, `net_duplex`, `wifi`, `wifi_mode`, `wifi_hosted`, `ap_disabled` |
| Zigbee | `zigbee_present`, `zigbee_ok`, `radio_error`, `device_count`, `synced` |
| MQTT | `mqtt_connected`, `mqtt_active`, `mqtt_root_topic`, `mqtt_tls_pin`, `mqtt_cleartext_credentials`, `log_mqtt_enabled`, `metrics_enabled`, `metrics_mqtt_enabled`, `metrics_mqtt_interval_s` |
| Time | `local_time`, `clock_set`, `timezone`, `ntp_server`, `ntp_dhcp_server` |
| Updates, storage | `ota`, `ota_state`, `ota_rollback_reason`, `ota_store_unconfirmed`, `restart`, `storage_error` |
| Sign-in | `auth_enabled`, `auth_setup_required`, `auth_setup_secs_left`, `auth_storage_error` |
| Features | `full_backup`, `device_ota`, `remote_available`, `remote_state`, `remote_scripts`, `log_to_cloud`, `log_ws_enabled`, `scripts_held`, `ws_clients` |

- `ota_state` is `pending` while a freshly updated firmware is on trial and `verified` once the
  hub has kept it; `ota_rollback_reason` appears only after an update was undone and says which
  check failed (storage, web server or radio). See the zhac-wired-core README, "Updates".
- `ota_store_unconfirmed: true` appears while the device store's move could not be marked final
  (storage full?); the hub retries, backing off to once an hour, and keeps the old copy on `nvs`
  until then. A restart or a newer update meanwhile keeps what was saved since, as long as `nvs`
  reads back whole at that boot. If it does not, the device store stays shut for that boot
  (`storage_error`; restart before you erase anything). When the flash layer repaired the bad
  entry by erasing it, the next boot takes the store from `nvs` again, and what was saved since
  the update is lost. An older version is refused until the move is final.
- `ntp_dhcp_server` appears when the router offered a time server (DHCP option 42) and the hub is
  using it; it comes first, `ntp_server` second. Naming a server switches the offer off.
- `scripts_held` appears while the hub holds its scripts after two restarts in a row during their
  start; see [`WS_API.md`](WS_API.md#scripts).

#### `POST /api/settings`

Update settings. Every field is optional; send only what changes. **Auth required.** The
WebSocket `settings.set` takes the same object (one code path, `system_apply_settings`).

```json
{ "broker_url": "mqtt://192.168.1.10:1883", "timezone": "CET-1CEST,M3.5.0,M10.5.0/3",
  "ntp_server": "192.168.1.1" }
```

Fields: `broker_url`, `mqtt_enabled`, `mqtt_client_id`, `mqtt_root_topic`, `mqtt_tls_pin`,
`ha_discovery`, `ha_prefix` (MQTT and Home Assistant discovery, kept in NVS); `ntp_server`,
`timezone`; `auth_enabled`, `ap_disabled`; `metrics_enabled`, `metrics_mqtt_enabled`,
`metrics_mqtt_interval_s`; `log_mqtt_enabled` / `log_mqtt_level` and `log_ws_enabled` /
`log_ws_level` (log lines to MQTT and to the hub's sockets until the next restart; the level is
the least severe one sent, `E`, `W`, `I`, `D` or `V`); `remote_scripts`, `log_to_cloud` (the cloud link; the relay may not change these, see
[`WS_API.md`](WS_API.md#remote-editing-from-zhac-cloud)).

`mqtt_tls_pin` is the SHA-256 fingerprint of an `mqtts://` or `wss://`
broker's certificate, 64 hex digits with or without colons, as
`openssl x509 -noout -fingerprint -sha256 -in broker.crt` prints it (its `sha256 Fingerprint=` label
may stay); `""` removes it. With a pin the
hub trusts exactly that certificate, whoever signed it and whatever name and dates it carries: a
broker with its own CA or a self-signed certificate. A value that is not a fingerprint is ignored. The status
reports it as `mqtt_tls_pin`, and `mqtt_cleartext_credentials: true` when the stored broker URL sends
a user name or password without TLS (`mqtt://` or `ws://`). Sending back the address the status shows keeps the stored user name and
password; to drop them, send a different address. The status shows the broker URL without
its user name and password; send `broker_url` only to change it.

`ntp_server` is the time server SNTP asks. Name one on your own network when the hub has no
internet access, or send an empty string for the public default (`pool.ntp.org`). It is
persisted and applied at once, and `GET /api/status` reports it as `ntp_server` alongside
`clock_set`. A host with spaces, quotes or over 63 characters is rejected.

**Response:** `{"ok": true}` — takes effect immediately without reboot. A body that does not
parse, or a setting that could not be saved, answers `400 bad settings`.

#### `POST /api/token/rotate`

Replace the API token. **Auth required.** Also at `POST /api/system/token/rotate`.

**Response:** `{"ok": true, "token": "<32hex>"}`; `500 nvs` when it could not be saved.

#### `GET /api/logs`

The hub's recent log lines, oldest first, each prefixed with its time in milliseconds.
**Auth required.**

**Response:** `{"logs": ["<ms> <line>", …]}`.

#### `GET /api/diagnostics/unhandled`

The Zigbee messages no device definition handled (the Diag page's list). **Auth required.**

**Response:** `{"entries": [{"ieee", "cluster", "id", "cs", "count", "age_s"}, …]}`: `id` is the
attribute or command id, `cs` whether it was a cluster-specific command, `age_s` the seconds since
the last one.

The hub's own firmware update has no REST route: use the WebSocket `ota.update` command, or the
web UI's OTA page.

---

## Network

The hub is Ethernet-only.

#### `GET /api/net/status`

**Auth required.** `{"transport": "ethernet", "link_up", "has_ip", "ip", "netmask", "gateway",
"mac", "speed_mbps", "duplex", "hostname"}`.

#### `GET /api/wifi/status`

Also `GET /api/wifi`. **Auth required.** A compatibility answer for older clients:
`{"mode": "eth", "ssid": "", "ip", "rssi": 0, "sta_configured", "sta_connected", "sta_ssid": "",
"sta_ip", "sta_rssi": 0, "ap_ssid": ""}`.

#### `GET /api/wifi/scan`

**Auth required.** `{"networks": []}`, always empty.

#### `POST /api/wifi/connect`

Also `POST /api/wifi/disconnect` and `POST /api/wifi`. **Auth required.** Always
`501 {"error": "wifi_unsupported", "detail": "…"}`: configure the network on your router.

---

## Devices

Renaming, removing and binding a device, and its native ZCL groups, are WebSocket commands
(`device.rename`, `device.delete`, `device.bind`, `device.groups.*`); so is one device's full
record (`device.get`).

#### `GET /api/devices`

Every device. Also `GET /api/device/list`. **Auth required.**

**Response:** an array, one object per device:

```json
[
  {
    "ieee": "0x00158D0001020304", "nwk": 4660, "friendly": "front_door",
    "model": "MCCGQ11LM", "vendor": "Aqara", "manufacturer": "LUMI",
    "model_id": "lumi.sensor_magnet.aq2", "last_seen": 1731940000,
    "lqi": 180, "battery": 90, "power_source": 3, "ep_count": 1,
    "endpoints": [ … ],
    "attrs": { "contact": 1, "battery": 90, "voltage": 3005 }
  }
]
```

`model` and `vendor` come from the matched device definition (the device's own strings when none
matched); `attrs` are the stored values, decimals as numbers.

#### `POST /api/device/attr/set`

Write one value to a device. Also `POST /api/device_state`. **Auth required.**

```json
{ "ieee": "0x00158D0001020304", "key": "state", "value": 1 }
```

`value` may be a boolean, an integer, a decimal (`21.5` — the device's converter scales it;
a thermostat setpoint goes out as 2150, a Tuya datapoint with divisor 10 as 215; a converter
that only takes integers refuses it with "no zhc converter") or a string (an enum option).
The same rule applies to the WebSocket `device.attr.set`.

**Response:** `{"ok": true}`. **Errors:** `400` (`missing ieee or key`, `bad ieee`, a value the
converter refuses), `404` no such device, `500` the command could not be sent.

#### `POST /api/device/options/set`

Save device options; merged into what is stored. Also `POST /api/device/options`. **Auth required.**

```json
{ "ieee": "0x00158D0001020304", "occupancy_timeout": 120 }
```

The options are `occupancy_timeout` and `no_occupancy_since`; see the WebSocket
[`device.get`](WS_API.md#devices). **Response:** `{"ok": true}`; `500 options apply failed`.

#### `POST /api/device/reinterview`

Interview a device again (its endpoints, clusters and Basic attributes), then run its bindings,
reporting setup and first reads, as when it joined. **Auth required.** Body `{"ieee": "0x…"}`.

**Response:** `{"ok": true}`, or `{"ok": false, "err": "unknown or sleepy"}` for a device the hub
does not know or that sleeps (wake it first).

#### `POST /api/device/configure`

Run a device's bindings, reporting setup and first reads again, as after pairing: for a device
paired before its definition gained them. **Auth required.** Body `{"ieee": "0x…"}`.

**Response:** `{"ok": true, "queued": true}`; `404` when the device is unknown or was never
interviewed.

#### `POST /api/permit_join`

Open the Zigbee network for new devices. Also `POST /api/zigbee/permit_join`. **Auth required.**

```json
{ "duration": 254 }
```

`duration` — seconds, 0–254, required. `254` is the longest window (about four minutes); `0`
closes it.

**Response:** `{"ok": true, "duration": 254}`. **Errors:** `400 duration 0-254`,
`500 permit_join failed`.

---

## Collections

The hub's collections of devices (the web UI's Groups page). The routes run the same code as the
WebSocket `group.*` commands (`zhac-wired-core/main/api_groups.cpp`), so they take and answer the
same JSON. A change made here is not pushed to open pages ([`WS_API.md`](WS_API.md#event-catalogue)).
**Auth required** on all.

A collection: `{"id": 1, "name": "Living Room", "members": [{"ieee": "0x…", "ep": 1}]}`.

#### `GET /api/groups`

**Response:** `{"groups": [ <collection>, … ]}`.

#### `POST /api/groups`

Create one: `{"name": "Living Room", "members": [{"ieee": "0x…", "ep": 1}]}` (`ep` defaults to 1).
**Response:** the new collection; `500 create failed`.

#### `POST /api/group/get`

`{"id": 1}` → the collection; `404 no such group`.

#### `POST /api/group/update`

`{"id": 1, "name": "…", "members": […]}`; a field left out stays. **Response:** the collection;
`404 no such group`.

#### `POST /api/group/delete`

`{"id": 1}` → `{"ok": true}`, or `{"ok": false}` when there is no such collection.

#### `POST /api/group/cmd`

Send a command to every member: `{"id": 1, "val": "ON"}` (`key` defaults to `state`; `ON`, `OFF`,
`TOGGLE`), `{"id": 1, "cluster": 6, "cmd": 1}` (On/Off cluster: 0 Off, 1 On, 2 Toggle; cluster 3
command 0 is Identify), or any value, `{"id": 1, "key": "brightness", "val": 128}`.

**Response:** `{"ok": true, "sent": <members>, "failed": <members>}`, or `{"ok": false, "err":
"…"}` (`not found`, `unsupported group command`, `val must be a boolean, number or string`). How
On, Off and Toggle reach the members (one groupcast or one command each):
[`WS_API.md`](WS_API.md#collections-and-native-groups).

---

## Rules

**Auth required** on all. A rule's `id` is 1–65535 (`400 bad id` otherwise).

#### `GET /api/rules`

**Response:** an array of `{"id", "enabled", "trigger_type", "rule_type", "name", "dsl"}`.

#### `POST /api/rules`

```json
{ "name": "door_light", "dsl": "ON front_door#contact=0 DO zigbee.set lamp state 1 ENDON", "enabled": false }
```

`enabled` is optional (absent or `null`: On). `false` creates the rule Off in one step; anything
but a boolean is refused (`400 enabled must be true or false`). See [RULES_DSL.md](RULES_DSL.md).

**Response:** `{"ok": true, "id": <new id>, "enabled": <bool>}`. A rule the parser refuses answers
`400 {"ok": false, "err": "<parser message>"}`; no `dsl`, `400 missing dsl`.

#### `PUT /api/rules/<id>`

Replace a rule's name and text: `{"name": "…", "dsl": "…"}`. **Response:** `{"ok": true}`; the
parser's refusal as above.

#### `DELETE /api/rules/<id>`

**Response:** `{"ok": true}`; `404 rule not found`.

#### `POST /api/rules/<id>/enable`

Switch a rule on or off: `{"enabled": false}`. **Response:** `{"ok": true}`; `404 rule not found`.

---

## Scripts (Lua)

See [LUA_API.md](LUA_API.md) for the scripting API. **Auth required** on all. Names: up to 24
letters, digits, `_` or `-`. Source: at most 16,384 bytes per script, 16 scripts.

#### `GET /api/scripts`

**Response:** `[{"name": "motion", "size": 256}, …]`.

#### `GET /api/scripts/<name>`

**Response:** the source, `text/plain`. **Errors:** `400 bad name`, `404 not found`.

#### `PUT /api/scripts/<name>`

Create or overwrite a script; `POST /api/scripts/<name>` does the same. The body is the raw Lua
source, no JSON wrapper.

**Response:** `{"ok": true}`. A body over 16,384 bytes is answered `413`, one that does not arrive
in full `408` (timeout) or `400`, and a chunked upload (`Transfer-Encoding` without
`Content-Length`) `411`; the stored script is kept in each case. `500 write failed` when it could
not be stored.

#### `DELETE /api/scripts/<name>`

**Response:** `{"ok": true}`; `404 not found`.

#### `POST /api/scripts/<name>/run`

Queue the script on the Lua task. **Response:** `{"ok": true, "queued": true}`; `500` when the
queue is full or there is no such script (`queue saturated or missing`), or while the hub holds
its scripts (`scripts are held: …`).

#### `POST /api/scripts/<name>/check`

Check a source without saving it; the body is the source. **Response:** `{"ok": bool, "err":
"<message>", "line": <n>}`.

---

## Hub pins

The pins of the hub's own board, used by rules and Lua: see [GPIO.md](GPIO.md). **Auth required.**

#### `GET /api/io`

**Response:** `{"target", "adc_unit", "max", "allowed": […], "adc_pins": […], "pins": […]}`: the
pins the board allows, those that can read analog values, and each configured pin with its
current `value` and `err`.

#### `PUT /api/io`

Replace the pin configuration: `{"pins": [ … ]}`, under 4 KB. **Response:** the state above;
`400 {"error": "<why>"}` for a configuration the hub refuses.

---

## Cloud link

The hub's link to ZHAC Cloud. **Auth required.**

#### `GET /api/remote/status`

**Response:** `{"enabled", "state", "connected_since", "last_event_at", "rtt_ms", "tx_drops",
"auth_fails", "log_sent", "log_dropped"}`.

#### `POST /api/remote/connect`

Store the cloud's address and the hub's token, and connect:
`{"url": "wss://…", "token": "…", "device_id": "…"}`. An empty `device_id` keeps the stored one.
**Response:** `{"ok": true}`; `400` with the reason (`url + token required`).

#### `POST /api/remote/disconnect`

Drop the link; `{"forget": true}` also erases the stored address and token.
**Response:** `{"ok": true, "forget": <bool>}`.

---

## Full backup

The whole hub as one file: the Zigbee network with its keys, devices, rules,
scripts, settings and sign-in (partitions `nvs`, `zb_storage`, `zhac_data`,
`scripts`). The hub encrypts it with a password you give (PBKDF2-HMAC-SHA256,
100 000 rounds, then AES-256-GCM) and decrypts it again on restore. The file
never leaves the hub unencrypted, but the password itself crosses your network
in plain HTTP, like the hub's sign-in: anyone who captures both can open the
file. Use a password you use nowhere else, on a network you trust.
`GET /api/status` reports `"full_backup": true` on firmware
that has these routes. Both run for seconds, during which the hub's other web
requests wait. `tools/zhac_backup.py` (zhac-wired-core repository) reads, decrypts and
makes the same files on a computer; `decrypt` also prints the `esptool`
command that writes the partitions back over USB.

#### `POST /api/backup/full`
Download a full backup. **Auth required.** `Content-Type: application/json`.

**Request:**
```json
{ "password": "8 to 63 bytes" }
```

**Response:** `200` `application/octet-stream`, `Content-Disposition:
attachment; filename="zhac-full-<host>-<YYYYMMDD>.zhacbak"` (no date while the
clock is unset), about 3.2 MB. A transfer cut off midway means the backup
failed; such a file never restores (its tag is missing).

**Errors:** `400 password_length`, `415 json_required`, `500 partition_missing`,
`500 crypto`, `503 busy` (the storage kept changing during five tries),
`503 no_memory`.

#### `POST /api/backup/restore`
Restore a full backup onto this hub. **Auth required.**
`Content-Type: application/octet-stream`; body = the password's length in
bytes (u16, little-endian), the password (UTF-8), then the file.

The hub checks the file (format, partitions and sizes, firmware version, the
password) before it writes anything. Its NVS partitions (`nvs`, `zb_storage`,
`zhac_data`) may be larger than the backup's, never smaller, and `scripts` must
be the same size: a backup of a hub installed before 2026-10-25 (16 KB
`zb_storage`) restores onto a newly flashed one (128 KB), not the other way.
It then decrypts it into the idle firmware slot, checking the whole file's
tag. On `200` `{"ok": true}` it restarts and writes the backup over its
storage before anything opens it; the restored
network then sends above every frame counter the old hub used. Keep the hub
the backup came from switched off for good. Sign-in, the password and the API
token come from the backup.

**Errors:** `400 not_a_backup`, `400 password_length`, `400 wrong_password`,
`400 incomplete`, `400 damaged` (nothing armed, storage kept),
`409 partitions_differ` (+ `partition`: missing or smaller here),
`409 newer_firmware` (+ `fw`: restore
on that firmware or newer), `409 on_trial` (a firmware update is still being
checked), `409 update_running`, `415 octet_stream_required`, `500 no_space`,
`500 flash`, `500 crypto`, `503 no_memory`.

---

## Device firmware update

Updates one Zigbee device's firmware with an OTA file you upload: the hub
checks the file, holds it in memory and serves it through the OTA Upgrade
server on its endpoint 1, to that device only. The hub fetches no images
itself. One update runs at a time; a device of the same model that asks
meanwhile is told there is no image. A hub restart drops the file: the
device's download then fails and it keeps its firmware. With no file loaded
the hub answers every device's query with "no image available".
`GET /api/status` reports `"device_ota": true` on firmware that has these
routes. The upload holds the hub's other web requests for the seconds it
takes. **Auth required** on all three routes.

#### `POST /api/device/ota?ieee=0x00158D0001020304`

Body: the OTA file (`Content-Type: application/octet-stream`, at most 4 MB).
The hub looks for the OTA header (`0x0BEEF11E`, header version 1.0) from the
start, so a vendor prefix before it is fine, and serves the image's total size
from there; bytes after it are ignored. It does not compare the file with the
device's node descriptor: the device's own query decides (manufacturer code
and image type), and the state below says when it asked for another image.
A device that already runs this version, or a newer one, is not sent the
file: the hub does not install older versions. Then the hub sends the device an Image Notify (query jitter 100) so an awake
device asks at once; a sleepy one asks when it wakes.

**Response:** `200` `{"manuf": 4476, "image_type": 8449, "file_version": 587751985, "size": 245760}`.

**Errors:** `400 no_device`, `400 not_an_ota_file`, `400 incomplete`,
`404 unknown_device`, `409 busy` (another update runs), `409 radio_down`,
`413 too_large`, `415 octet_stream_required`, `503 radio_busy` (try again),
`503 no_memory`.

#### `GET /api/device/ota`

`{"state": "idle"}`, or the update:

```json
{
  "state": "sending", "ieee": "0x00158D0001020304",
  "manuf": 4476, "image_type": 8449, "file_version": 587751985, "size": 245760,
  "offset": 98304, "pct": 40, "fits": true, "reason": "", "device_status": 0,
  "elapsed_s": 312,
  "device_manuf": 4476, "device_image_type": 8449, "device_version": 587751697
}
```

`state`: `waiting` (for the device's query), `sending`, `done` (the device has
the whole image and applies it at once; `reason` `same_version` when it
already ran it), `failed` (`reason`: `device_newer` (the device runs a newer
version and keeps it), `device_status` with the device's Upgrade End status in
`device_status`, `device_aborted`, `device_silent` (no block request for 10
minutes while sending; waiting has no limit), `device_left`), `cancelled`. The `device_*` fields appear once the device asked (Query Next
Image) and stay after the end, so they show the version it runs after its
restart. `fits` turns `false` when the device asked for another manufacturer
code or image type: it will never take this file.

#### `POST /api/device/ota/cancel`

Stops the update and drops the file; answers with the state above. A device
in the middle of its download is refused its next block and keeps its
firmware.

---

## Error responses

| HTTP | Meaning |
|------|---------|
| `400` | A missing or invalid field; the reason in the body |
| `401` | Sign-in on, and no or a wrong `X-Api-Key`, or the address is locked out (`{"error":"unauthorized"}`) |
| `403` | `{"error":"cross_site"}`: sign-in off, and the request came from another site's page or through a host name that is not the hub's |
| `404` | No such device, rule, script or collection |
| `405` | The route does not take that method |
| `408` / `411` / `413` / `415` | The body timed out, came chunked, is too large, or has the wrong `Content-Type` |
| `429` | Login or password change while the address, or for passwords the whole hub, is locked out: wait a minute (`Retry-After: 60`) |
| `500` | The hub could not do it (memory, storage, radio); the reason in the body |
| `501` | `{"error":"wifi_unsupported"}`: a Wi-Fi route on an Ethernet hub |
| `503` | Busy or not ready; try again |
