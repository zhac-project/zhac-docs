<!--
SPDX-FileCopyrightText: 2025-2026 Evgenij Cjura and project contributors
SPDX-License-Identifier: AGPL-3.0-or-later
-->

# HAP — Host Application Protocol (ESP32-S3 ⇄ ESP32-P4 link)

HAP is the binary protocol on the on-board SPI bus between the two ZHAC chips:
the **ESP32-S3 net core** (WiFi / REST / WebSocket / MQTT gateway) and the
**ESP32-P4 main core** (Zigbee coordinator + Lua engine). Every cross-chip
message — device state, commands, joins/leaves, OTA, rules, Lua, telemetry —
rides HAP.

> **Normative spec:** this page is the platform-level overview. The byte-exact,
> authoritative wire format is the `hap_protocol` component README:
> [`zhac-components/components/hap_protocol/README.md`](https://github.com/zhac-project/zhac-components/blob/master/components/hap_protocol/README.md).
> It is the only host-buildable codec and the source of truth for framing, CRCs,
> and offsets. When this overview and that README disagree, the README wins.

## Layering

```
hap_dispatch (P4)              api_handlers (S3)
        │                            │
     hap_session   ── reliability: sliding window, retransmit, ACK echo, dedup
        │                            │
hap_slave (P4) ────── SPI ────── hap_master (S3)
        │                            │
        └──────── hap_protocol ──────┘   encode / decode / CRC (pure logic, host-testable)
```

`hap_protocol` is pure logic (no FreeRTOS / SPI), so it host-builds and
fuzz-tests cleanly. `hap_session` adds reliability; `hap_master`/`hap_slave` own
the SPI DMA transport.

## Frame format (v4, current)

Version is the 4th preamble byte; peers **must** reject a mismatch (no backward
compatibility). SPI slave DMA on S3/P4 requires 64-byte-aligned address *and*
length, so v4 splits each frame into two SPI transactions:

**Stage 1** — a fixed 16-byte header, zero-padded to 64 B for DMA:

| Offset | Field | Size | Notes |
|---|---|---|---|
| 0..3 | PREAMBLE | 4 B | `AA 55 FE 04` (magic16 + sentinel + version) |
| 4 | TYPE | 1 B | `HapMsgType` (catalog below) |
| 5 | FLAGS | 1 B | `NEEDS_ACK 0x01` / `NO_ACK 0x02` |
| 6..7 | SEQ | 2 B LE | sender sequence; `0` reserved |
| 8..9 | ACK_SEQ | 2 B LE | `0` = no correlation, else echoes the request SEQ |
| 10..11 | LEN | 2 B LE | stage-2 payload length, `0..4096` |
| 12 | RESERVED | 1 B | `0x00` |
| 13..14 | HDR_CRC16 | 2 B | CRC-CCITT (`0x1021`/`0xFFFF`) over bytes 0..12 |
| 15 | pad | 1 B | `0x00` |

**Stage 2** — `LEN` payload bytes + a 2-byte `PAYLOAD_CRC16`, padded up to the
next 64-byte boundary. The two CRCs protect the two transactions independently:
a bit-flipped `LEN` fails HDR_CRC16 in stage 1, so the slave never clocks a
wildly-wrong byte count off DMA.

A legacy **v3 single-frame** form (15-byte overhead, CRC-8 header + CRC-16
payload) is still decoded by the codec for non-DMA paths — see the component
README §4.1. Payload is JSON or binary per message type; `HAP_MAX_PAYLOAD` = 4096.

## Reliability (`hap_session`)

- **Sliding window** of `WIN_SIZE = 16` in-flight `NEEDS_ACK` frames.
- **Retransmit:** `ACK_TIMEOUT_MS = 1000` per try, `MAX_RETRIES = 5`, then
  `on_link_dead` fires (triggers a re-SYNC).
- **ACK:** the receiver echoes the request's SEQ in `ACK_SEQ` of a `ACK` frame.
- **Dedup:** a 64-entry exact-match `(seq,type)` ring plus a wrap-aware monotonic
  high-water mark drop peer retransmits so a lost ACK never double-dispatches.
- **SYNC** (`0x05`) resets the dedup state: a peer that rebooted rewinds its SEQ
  to 1, and both sides clear the high-water so fresh low-SEQ frames aren't judged
  stale. `NO_ACK` / `ACK` / `SYNC` bypass the window.

## Message-type catalog

Direction: **S3→P4** commands the engine; **P4→S3** reports state/results.

| Range | Type (hex) | Purpose |
|---|---|---|
| Core | CMD `01`, EVT `02`, ACK `03`, ERR `04`, SYNC `05`, STREAM `06` | generic frame kinds + link handshake |
| Device query | GET_DEVICES `10` / DEVICE_LIST `11` · GET_DEVICE_BY_ID `12` / DEVICE_INFO `13` · SET_ATTRIBUTE `14` / SET_ACK `15` | list / inspect / drive devices |
| Device lifecycle | DEVICE_EVENT `20` · DEVICE_JOIN `21` · DEVICE_LEAVE `22` · ALERT `23` · DEVICE_SET_NAME `24` · PERMIT_JOIN `25` · BIND_REQ `27` / BIND_ACK `28` · DEVICE_DELETE `29` / `_ACK 2A` · INTERVIEW_REQ `2B` · DEVICE_OPTIONS_SET `2C` / `_ACK 2D` · CONFIGURE_REQ `2E` | join/leave, bind, delete, re-interview, per-device options |
| Rules & Lua | RULE_CREATE `30` · RULE_DELETE `31` · RULE_EXEC_RESULT `32` · RULE_LIST_REQ `33` / `_RSP 34` · RULE_UPDATE `35` / `_DSL 3D` · SCRIPT_WRITE `36` / `_ACK 37` · SCRIPT_DELETE `38` · SCRIPT_LIST_REQ `39` / `_RSP 3A` · SCRIPT_READ_REQ `3B` / `_RSP 3C` | simple-rules CRUD + Lua script management |
| Bridge / time | MQTT_MSG_IN `3E` · TIME_SYNC `3F` | inbound MQTT to the engine, clock sync |
| OTA | OTA_CHUNK `40` · OTA_STATUS `41` · OTA_CHECKPOINT_REQ `42` / `_RSP 43` | P4 firmware update over the link (resumable) |
| System / diag | HEARTBEAT `50` · ZIGBEE_FACTORY_RESET `51` · DIAG_UNHANDLED_REQ `52` / `_RSP 53` · ZIGBEE_CFG_SET `54` / `_ACK 55` · METRICS_REQ `56` / `_RSP 57` · SCRIPT_RUN_REQ `58` · SCRIPT_CHECK_REQ `59` / `_RSP 5A` | liveness, factory reset, radio config, Prometheus metrics, Lua run/parse-check |
| Bulk / bridge out | BULK_STATE_UPDATE `60` · MQTT_PUBLISH `70` · TG_SETTOKEN `71` · TG_SETCHAT `72` · TG_SEND `73` | batched shadow push, outbound MQTT + Telegram |
| Logs | LOG_LINE `80` | P4 log forwarding into the S3 `/api/logs` ring |

Exact per-message payload shapes are documented at the `HapMsgType` enum in
[`hap_protocol.h`](https://github.com/zhac-project/zhac-components/blob/master/components/hap_protocol/include/hap_protocol.h)
and at the handlers in `zhac-main-core/main/hap_dispatch.cpp` (P4) /
`zhac-net-core/main/hap_bridge.cpp` (S3).

## Integrity & security posture

- **CRCs everywhere:** stage-1 HDR_CRC16 gates the length before any stage-2 DMA;
  PAYLOAD_CRC16 gates the body. A CRC failure is *not* dispatched.
- **Bounds:** stage-1 decode clamps `LEN` to `HAP_MAX_PAYLOAD`, so a malformed
  header cannot drive an out-of-bounds read.
- **Trust model:** the two chips are a *trusted pair* on a private PCB bus — HAP
  has no authentication or encryption of its own (unlike the S3's LAN/cloud
  surface, which is token-gated). Wire traces redact the Zigbee network key.
- Resync markers: `hap_decode_stream` uses the rare `0xFE` sentinel to recover
  the frame boundary inside a corrupted buffer.

## See also

- Normative wire spec — `hap_protocol` component README (linked above).
- Reliability internals — `hap_session` component README.
- SPI transport / tasking — `hap_master` (S3) and `hap_slave` (P4) READMEs.
- Codec + fuzz tests — `zhac-components/components/hap_protocol/test/`.
