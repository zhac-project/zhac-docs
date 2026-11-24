# ZHAC Security Documentation

## Threat model

ZHAC is a one-board Zigbee hub (zhac-wired-core, on an ESP32-S31 or an ESP32-P4 with an ESP32-C6
radio) intended for a **trusted home LAN**. The baseline assumptions:

- The hub is wired to a network under the operator's control. Attackers on the
  open internet cannot reach it unless the operator deliberately port-forwards.
- The physical device sits in a physically-trusted location (same
  category as a home router). An attacker with hands-on access to the
  board can dump flash, attach to UART, or reflash over USB — we do
  not defend against this today (flash encryption is on the backlog,
  see [NVS encryption](#nvs-encryption) below).
- The Zigbee mesh is protected by the network key; we do not
  additionally validate per-device payloads cryptographically beyond
  what Zigbee itself provides.
- On the ESP32-P4 board, the UART between the P4 and the ESP32-C6 radio is
  treated as a **trusted on-board link**: whoever can probe or inject on it
  controls the radio. Do not expose those pads.

What is **out** of scope:
- Internet-exposed deployments without the operator providing their
  own TLS + auth perimeter.
- State-level physical attackers.
- Side-channel power/EM analysis against the SoC.

## Authentication

### API token

While sign-in is on, every REST route but those in [Unauthenticated endpoints](#unauthenticated-endpoints),
and every WebSocket command but `auth`, needs the API token (`X-Api-Key` header on REST; see [REST_API.md](REST_API.md#authentication)).

- The token is a 32-character hex string generated from `esp_fill_random` on first boot.
- It is stored in NVS namespace `zhac_auth`, key `token`.
- It is printed in full on the serial console (never in the log the web UI and the cloud see) only while no admin password exists, and on the one boot after a password lockout, which is how an owner with physical access recovers a lost password. Every other boot prints its last four characters only.
- Changing the admin password rotates the token, which signs every other browser out; the first password set-up rotates it too, so the token printed before the hub was claimed stops working. `POST /api/token/rotate` replaces it at any time.
- Five wrong tokens or passwords from one address within a minute lock that address out until the first of them is a minute old: meanwhile every route that needs the token, and password sign-in, answer it `429` even with the right token (`Retry-After: 60`; a WebSocket `auth` gets `auth failed`). A request without `X-Api-Key` to a route that needs it counts as a wrong token. Twenty wrong passwords within a minute, from any addresses, stop password sign-in for the whole hub the same way.

The Web UI stores the token in `localStorage` (key `zhac_token`).

With sign-in off the hub needs no token, but it refuses a request whose `Origin` is another site,
or whose `Host` is not the hub's address or its `.local` name (`403 {"error":"cross_site"}`): a
page of another site cannot drive the hub through your browser. Any device on the LAN still can.

### Unauthenticated endpoints

The following endpoints intentionally require no authentication:

| Endpoint | Reason |
|----------|--------|
| `GET /api/status` | What the sign-in page needs. With sign-in on, a request without the token gets only `sku` and the `auth_*` fields; monitoring tools send the token for the rest |
| `POST /api/auth/login`, `POST /api/auth/setup` | The password exchange. Setup answers only while no password exists, and for 10 minutes after power-on |
| `GET /*` (static files) | Web UI assets are public |
| WebSocket `/ws` | With sign-in on, a socket must send `auth` with the token within 5 s or it is closed; until it does, every other command is refused (`auth required`) |

### Response headers

Every answer of the hub's web server handlers (not the server's own error answers, such as the 405
for a method a path does not take) carries `X-Content-Type-Options: nosniff` and
`Referrer-Policy: no-referrer` (links out of the hub page do not send its address). The web UI's
Content-Security-Policy lets its WebSocket reach only the hub itself (`connect-src 'self'` and the
`ws://` / `wss://` of the address the page was loaded from), plus `https://api.github.com` for the
version list.

## Transport security

**Current state:** All communication is plain HTTP and unencrypted WebSocket (`ws://`). This is acceptable for local-network IoT devices where the threat model is assumed to be a trusted home network.

The hub's own TLS clients (updates, the cloud link, `mqtts://`) check the server certificate against
IDF's CA bundle and its host name. They also check the
certificate's dates once the hub's clock is set (SNTP or the web UI); before that the dates cannot be
judged and are left out. Whatever the clock says, a certificate that ended before the day the firmware
was built is refused, so a clock set back does not bring it back. The clock itself comes from SNTP
unauthenticated, which bounds what the date check is worth. An MQTT broker with its own CA or a
self-signed certificate is trusted by the SHA-256 fingerprint of its certificate (`mqtt_tls_pin`,
Settings → MQTT); a pinned certificate is trusted whatever its name and dates. Settings warns when a
broker address sends its user name and password in clear (`mqtt://`).

## NVS encryption

**Current state:** NVS is unencrypted: zhac-wired-core enables neither flash nor NVS encryption.

**Planned:** `nvs_flash_secure_init` with an eFuse-burned key. This protects credentials (API token, MQTT broker URL with its user name and password, the cloud link's token) against physical flash extraction.

## Attack surface

### Network

| Surface | Notes |
|---------|-------|
| HTTP REST API | Sign-in gates every route but those listed above; with sign-in off, the cross-site check. The web UI is served from a pack inside the firmware image: a path is looked up in its table, never on a file system |
| WebSocket | Sign-in as above; a frame over 32 KB (32,768 bytes) closes the session |
| MQTT | Publishes device state and takes commands under its root topic. `mqtts://` checks the broker as above |
| ZHAC Cloud link | Outbound `wss://` only, off until the owner connects it. The relay may not change the cloud settings (`remote_scripts`, `log_to_cloud`) |

### Physical

| Surface | Notes |
|---------|-------|
| UART (serial) | Exposes ESP-IDF log output including boot messages; the API token in full only on the boots described above. No shell. |
| USB flashing | Anyone with physical USB access can reflash. Standard ESP32 threat model. |
| NVS | Unencrypted. Flash extraction exposes the API token, the password hash, MQTT credentials and the cloud token. |

### Firmware

| Protection | Status |
|-----------|--------|
| Brownout detection | Enabled via `sdkconfig.defaults` |
| FreeRTOS stack watchpoints | Enabled |
| Stack canaries | Enabled (strong) |
| Core dump to flash | Enabled (`CONFIG_ESP_COREDUMP_ENABLE_TO_FLASH`) |
| Task watchdog | 10 s timeout, triggers panic |
| App rollback | Enabled (`CONFIG_BOOTLOADER_APP_ROLLBACK_ENABLE`): see [OTA security](#ota-security) |

## OTA security

The hub updates itself from a URL the owner gives: the WebSocket `ota.update` command, which the web
UI's OTA page sends (the page reads the version list from GitHub and hands the hub one download URL).

| Property | Status |
|----------|--------|
| Who may start it | The API token holder while sign-in is on |
| Transport | `https://` only, every redirect included; the server is checked as in [Transport security](#transport-security) |
| Which image | This firmware's own project only, and no older release unless the owner asks for one ("Allow an older version") |
| Integrity | ESP-IDF validates the written image (`esp_ota_end`) before the hub boots it: a broken or cut-off image is refused |
| Authenticity | **None**: no signature check, Secure Boot v2 is not enabled |
| Trial and rollback | The new firmware runs on trial: unless its storage, web server, event dispatcher and sign-in storage, plus the device store and the Zigbee radio if they worked before the update, stay healthy for five minutes in a row within ten minutes, the hub goes back to the previous version; so does a restart before then. A lost Ethernet link does not count against it |

**Threat:** whoever may start an update can install any image that passes these checks from any
HTTPS server: nothing proves the image came from the ZHAC project. Keep sign-in on, and take
images from the project's releases (the OTA page's version list) or your own build.

## Known limitations

1. **No TLS on the hub's own web server** — the web UI, REST and WebSocket are plain HTTP on the local network.
2. **Unsigned updates** — see [OTA security](#ota-security).
3. **Credentials in unencrypted NVS** — the MQTT broker URL (with any user name and password in it) and the cloud token, see [NVS encryption](#nvs-encryption).
4. **Sign-in off means open to the LAN** — the cross-site check stops only other sites' pages in a browser.

## Responsible disclosure

Report security vulnerabilities via the project issue tracker, marked
with the `security` label. For sensitive issues, contact the
maintainer directly **before** public disclosure.

**Disclosure timeline:** we aim to acknowledge within 7 days and
publish a fix or mitigation within 90 days of the initial report. If a
vulnerability is already public (e.g. an upstream CVE affecting
ArduinoJson / PUC-Lua / esp-mqtt), we treat it as a regular issue and
fix in the next release.

**Out-of-band severity markers:** do not publish a PoC that requires
the ZHAC network key until the fix ships. Zigbee mesh key leakage
affects every device in the network, not just ZHAC.
