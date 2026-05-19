# ZHAC Security Documentation

## Threat model

ZHAC is a dual-chip Zigbee controller intended for a **trusted home
LAN**. The baseline assumptions:

- The device is connected to a WiFi network under the operator's
  control. Attackers on the open internet cannot reach it unless the
  operator deliberately port-forwards.
- The physical device sits in a physically-trusted location (same
  category as a home router). An attacker with hands-on access to the
  board can dump flash, attach to UART, or reflash over USB — we do
  not defend against this today (flash encryption is on the backlog,
  see §NVS / flash encryption below).
- The Zigbee mesh is protected by the network key; we do not
  additionally validate per-device payloads cryptographically beyond
  what Zigbee itself provides.
- The SPI bus between the S3 (Wi-Fi side) and P4 (Zigbee side) is
  treated as a **trusted in-chassis bus**. If an attacker can probe
  or inject on this bus, they control both cores — this is a
  deliberate design decision. Do not expose the SPI pads externally.

What is **out** of scope:
- Internet-exposed deployments without the operator providing their
  own TLS + auth perimeter.
- State-level physical attackers.
- Side-channel power/EM analysis against the SoC.

## Authentication

### API token

All mutating REST endpoints (`POST`, `PUT`, `DELETE`) and sensitive read endpoints require an API token in the `X-Api-Key` request header.

- The token is a 32-character hex string generated from `esp_fill_random` on first boot.
- It is stored in NVS namespace `zhac_auth`, key `token`.
- It is printed to the serial console on first boot: `*** NEW API TOKEN (save this): <token> ***`
- Subsequent boots log only the token length, not the value.

The Web UI stores the token in `localStorage` (key `zhacToken`). Tokens are not rotatable without reflashing or clearing NVS.

### Unauthenticated endpoints

The following endpoints intentionally require no authentication:

| Endpoint | Reason |
|----------|--------|
| `GET /api/status` | Non-sensitive system health info; needed by monitoring tools |
| `GET /metrics` | Prometheus scrape endpoint (no secrets exposed); only active when enabled |
| `GET /*` (static files) | Web UI assets are public |
| WebSocket `/ws` | Token is sent as first message after connection; unauthenticated WS frames are ignored |

## Transport security

**Current state:** All communication is plain HTTP and unencrypted WebSocket (`ws://`). This is acceptable for local-network IoT devices where the threat model is assumed to be a trusted home network.

## NVS encryption

**Current state:** NVS is unencrypted. A `TODO` comment exists in `zhac-net-core/main/main.cpp:417`.

**Planned:** `nvs_flash_secure_init` with an eFuse-burned key. This protects credentials (WiFi password, API token, MQTT broker URL) against physical flash extraction.

## Attack surface

### Network

| Surface | Notes |
|---------|-------|
| HTTP REST API | Auth token gates all mutations; static file handler uses `path_normalize()` to block directory traversal |
| WebSocket | Only broadcasts state; inbound frames require valid token |
| MQTT | Subscribes to `zhac/#`; publishes device state and alerts. Broker URL is configurable. No TLS yet. |
| Prometheus `/metrics` | Disabled by default; exposes non-sensitive counters only |

### Physical

| Surface | Notes |
|---------|-------|
| UART (serial) | Exposes ESP-IDF log output including boot messages. No shell. |
| USB flashing | Anyone with physical USB access can reflash. Standard ESP32 threat model. |
| NVS | Unencrypted until Sprint 5. Flash extraction exposes WiFi credentials and API token. |

### Firmware

| Protection | Status |
|-----------|--------|
| Brownout detection | Enabled via `sdkconfig.defaults` |
| FreeRTOS stack watchpoints | Enabled |
| Stack canaries | Enabled |
| Core dump to flash | Enabled (`CONFIG_ESP_COREDUMP_ENABLE_TO_FLASH`) |
| Task watchdog | 10 s timeout, triggers panic |
| OTA SHA-256 integrity | Blocked on mbedTLS linkage in IDF v6 (see TODO in `p4_ota.cpp`) |

## OTA security

### S3 firmware update (`POST /api/ota`)

S3 OTA uses `esp_https_ota`. The endpoint requires authentication (API token) but has the following limitations:

| Property | Status |
|----------|--------|
| Transport encryption | Available when `https://` URL is supplied, but **server identity is not verified** (`skip_cert_common_name_check = true`, no CA certificate configured) |
| Image signing / integrity | **None** — no SHA-256 or signature check after download |
| Rate limiting | 60 s cooldown between requests |

**Threat:** A LAN-MITM attacker who can intercept the HTTP/HTTPS response for the OTA URL can serve arbitrary firmware. The authentication token prevents unauthenticated trigger of OTA, but once triggered the image itself is trusted unconditionally.

**Mitigations available now:**
- Use OTA URLs on a dedicated, isolated VLAN or point directly at a device on the same L2 segment.
- Prefer `https://` OTA URLs — provides transport confidentiality even without server authentication.
- Monitor serial output during OTA for unexpected source IPs.

**Path to resolution:** Configure `esp_http_client_config_t.cert_pem` with a CA certificate once TLS is enabled (see `docs/FEATURE.md` — TLS). Full image signing requires Secure Boot v2 (ESP-IDF feature, separate from this project).

### P4 firmware update (`POST /api/p4-ota`)

P4 OTA is delivered chunk-by-chunk over the HAP SPI link from S3. Additional limitations on top of S3 OTA:

| Property | Status |
|----------|--------|
| Image integrity | **None** — no CRC32, no SHA-256 over the full image |
| Per-chunk verification | **None** — a dropped or corrupted SPI chunk is written to flash silently |
| SHA-256 signing | Blocked on mbedTLS linkage in IDF v6 (see `TODO` in `p4_ota.cpp`) |

**Threat:** A corrupt flash write (from SPI noise, flash wear, or an incomplete transfer) produces a broken P4 image. The device will attempt to boot it; if the image is invalid, P4 will crash-loop and require a serial reflash.

**Planned mitigation:** CRC32 full-image accumulation in `p4_ota.cpp` (see `docs/FEATURE.md` — P4 OTA CRC32). This stops accidental corruption; it does not stop a deliberate attack.

## Known limitations

1. **No token rotation** — API token cannot be changed without reflashing or NVS wipe.
2. **No rate limiting on read endpoints** — Only `permit_join`, `wifi`, and `ota` have rate limiting.
3. **No TLS** — All traffic is cleartext on the local network.
4. **MQTT credentials** — MQTT broker URL (including any embedded credentials) is stored in plaintext NVS.
5. **Prometheus endpoint has no auth** — By design for compatibility with Prometheus scrapers; disable if on an untrusted network.

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
