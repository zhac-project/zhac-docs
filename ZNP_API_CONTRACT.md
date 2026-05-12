# ZNP API contract — what zhac actually uses

**Audience:** an independent agent implementing an
ESP32-C6/H2-based replacement for the TI CC2652 radio coprocessor.
Re-implementing the surface listed here on the C6 (running
`esp-zigbee-sdk` or equivalent) lets that chip drop in as a ZNP NCP
without changing P4 firmware.

**Source of truth:** the actual call sites in `components/zigbee_mgr/`
and `components/znp_driver/` of zhac as of 2026-04-25.
Anything not listed here is **not** consumed by zhac and can be
omitted from a clean-room reimplementation.

---

## 1. Wire framing (TI MT serial)

```
+------+------+------+------+----------+-----+
| SOF  | LEN  | CMD0 | CMD1 |  DATA …  | FCS |
+------+------+------+------+----------+-----+
   1B     1B     1B     1B     LEN B    1B
```

| Field | Value / definition |
|-------|-------------------|
| `SOF` | constant `0xFE` |
| `LEN` | byte count of `DATA`, range `0…250` |
| `CMD0` | type bits `<<4` OR'd with subsystem id |
| `CMD1` | command id within subsystem |
| `DATA` | command-specific payload (see tables below) |
| `FCS` | XOR of `LEN ⊕ CMD0 ⊕ CMD1 ⊕ each DATA byte` |

**UART:** 115200 baud, 8-N-1, no flow control. (`znp_transport.cpp`
configures this; user-tunable via Kconfig.)

### `CMD0` encoding

```
bit 7  6 5 4   3 2 1 0
       │ │ │   └─ subsystem (0x0…0xF)
       └─┴─┴───── type
                  0x0 POLL  (unused)
                  0x2 SREQ  (sync request,  host → NCP)
                  0x4 AREQ  (async event,    either direction)
                  0x6 SRSP  (sync response,  NCP → host)
```

zhac uses these subsystems only:

| Subsystem | Id | SREQ cmd0 | AREQ cmd0 | SRSP cmd0 |
|-----------|----|-----------|-----------|-----------|
| `SYS`     | 0x01 | 0x21 | 0x41 | 0x61 |
| `AF`      | 0x04 | 0x24 | 0x44 | 0x64 |
| `ZDO`     | 0x05 | 0x25 | 0x45 | 0x65 |
| `APP_CNF` | 0x0F | 0x2F | 0x4F | 0x6F |

(Subsystems `MAC`, `NWK`, `SAPI`, `UTIL` are NOT used by zhac.)

### Synchronous semantics

For every `SREQ` the host expects exactly one `SRSP` with the same
subsystem and `cmd1` within `timeout_ms` (typically 2-3 s). A late or
unsolicited `SRSP` is dropped and counted in stats — the host never
delivers it as the reply for a previously-timed-out call.

Two callable shapes: `znp_call(cmd0, cmd1, data, len, &srsp, timeout)`
and `znp_call_retry(..., max_attempts)`.

`AREQ` frames are dispatched by `(cmd0, cmd1)` to subscribed handlers;
multiple subscribers per id are allowed and all fire.

---

## 2. SYS subsystem (0x01)

| `cmd1` | Name | Direction | Purpose |
|--------|------|-----------|---------|
| `0x00` | `SYS_RESET_REQ` | SREQ → no SRSP, AREQ `SYS_RESET_IND` follows | Soft-reset the NCP |
| `0x01` | `SYS_PING` | SREQ ↔ SRSP | Heartbeat / liveness |
| `0x02` | `SYS_VERSION` | SREQ ↔ SRSP | Firmware version |
| `0x04` | `SYS_GET_EXTADDR` | SREQ ↔ SRSP | Coordinator IEEE address |
| `0x07` | `SYS_OSAL_NV_ITEM_INIT` | SREQ ↔ SRSP | Create NV item if missing |
| `0x12` | `SYS_OSAL_NV_DELETE` | SREQ ↔ SRSP | Delete NV item |
| `0x13` | `SYS_OSAL_NV_LENGTH` | SREQ ↔ SRSP | NV item byte length |
| `0x1C` | `SYS_OSAL_NV_READ` | SREQ ↔ SRSP | Read NV item value |
| `0x1D` | `SYS_OSAL_NV_WRITE` | SREQ ↔ SRSP | Write NV item value |
| `0x80` | `SYS_RESET_IND` | AREQ (NCP → host) | Indicates reset complete |

### `SYS_RESET_REQ` (0x00)

- **Payload (1 byte):** `Type` — `0x00` hard reset, `0x01` soft (zhac uses 0x01)
- **Response:** none on the SREQ wire — the NCP boots, then emits
  `SYS_RESET_IND` (0x80) when ready.

### `SYS_PING` (0x01)

- Payload: empty.
- SRSP payload: `Capabilities (2B LE)` — feature bitmap. zhac doesn't
  parse it; non-empty SRSP is treated as success.

### `SYS_VERSION` (0x02)

- Payload: empty.
- SRSP payload: `TransportRev (1) | ProductId (1) | MajorRel (1) | MinorRel (1) | MaintRel (1)`
- zhac uses `ProductId` for product detection logging only.

### `SYS_GET_EXTADDR` (0x04)

- Payload: empty.
- SRSP payload: 8 bytes — coordinator IEEE address LE.

### `SYS_OSAL_NV_ITEM_INIT` (0x07)

- Payload: `Id (2B LE) | Length (2B LE) | InitLen (1B) | InitData (InitLen B)`
- SRSP payload: `Status (1B)` — `0x00` success / `0x09` already-exists.
  zhac treats both as OK.

### `SYS_OSAL_NV_DELETE` (0x12)

- Payload: `Id (2B LE) | Length (2B LE)` (length is required by Z-Stack 3.x).
- SRSP payload: `Status (1B)` — `0x00` success / `0x09` not-found.

### `SYS_OSAL_NV_LENGTH` (0x13)

- Payload: `Id (2B LE)`
- SRSP payload: `Length (2B LE)` — 0 if item missing.

### `SYS_OSAL_NV_READ` (0x1C)

- Payload: `Id (2B LE) | Offset (1B)`
- SRSP payload: `Status (1B) | Length (1B) | Value (Length B)`

### `SYS_OSAL_NV_WRITE` (0x1D)

- Payload: `Id (2B LE) | SubId (2B LE, zhac uses 0x0000) | Length (2B LE) | Value (Length B)`
- SRSP payload: `Status (1B)` — `0x00` success.
- zhac caps `Length` at 128.

### `SYS_RESET_IND` (0x80, AREQ)

- Payload: `Reason (1B) | TransportRev (1) | ProductId (1) | Major (1) | Minor (1) | Maint (1)`
- zhac uses arrival as the "NCP up" signal; no payload fields parsed.
  `coordinator_start()` re-asserts hardware reset and waits up to 6 s
  per attempt for this AREQ (currently 3 attempts).

### Required NV items

zhac touches these NV ids (must be persistable on the NCP):

| Id | Name | Length | Value used by zhac |
|----|------|--------|--------------------|
| `0x0003` | `NV_STARTUP_OPTION` | 1 | `0x03` (clear network state on reboot) → then back to `0x00` |
| `0x0067` | `NV_LOGICAL_TYPE` | 1 | `0x00` (coordinator) |
| `0x002D` | `NV_PRECFGKEYS_ENABLE` | 1 | `0x00` (don't use pre-configured key) |
| `0x0083` | `NV_PANID` | 2 | LE PAN ID |
| `0x0084` | `NV_CHANLIST` | 4 | bitmap; bit `n` = channel `n+11` |
| `0x002E` | `NV_PRECFGKEY` | 16 | network key |
| `0x008F` | `NV_ZDO_DIRECT_CB` | 1 | `0x01` (direct ZDO callbacks on, required for AREQ_RSPs) |

If the NCP already has different defaults, the host overwrites them
during `do_commissioning()`.

---

## 3. AF subsystem (0x04) — Application Framework

| `cmd1` | Name | Direction | Purpose |
|--------|------|-----------|---------|
| `0x00` | `AF_REGISTER` | SREQ ↔ SRSP | Register a host endpoint |
| `0x01` | `AF_DATA_REQUEST` | SREQ ↔ SRSP, AREQ confirm | Send a frame to a remote device |
| `0x80` | `AF_DATA_CONFIRM` | AREQ (NCP → host) | TX status for a prior AF_DATA_REQUEST |
| `0x81` | `AF_INCOMING_MSG` | AREQ (NCP → host) | Inbound ZCL frame |
| `0x82` | `AF_INCOMING_MSG_EXT` | AREQ (NCP → host) | Same but extended (some Z-Stack 3.x builds) |

### `AF_REGISTER` (0x00)

- Payload (9 B + clusters):
  ```
  EndPoint (1)
  AppProfileId (2 LE)
  AppDeviceId (2 LE)
  AppDevVer (1)
  LatencyReq (1)
  AppNumInClusters (1)
  AppInClusterList (2·N LE)
  AppNumOutClusters (1)
  AppOutClusterList (2·M LE)
  ```
- SRSP payload: `Status (1B)` — `0x00` success / `0x08` ZMemError /
  `0xB8` ZApsDuplicateEntry. zhac treats `0x08` and `0xB8` as
  "already registered" and continues.
- zhac registers three endpoints with **0 in/out clusters** (the
  coordinator routes traffic, doesn't expose its own clusters):
  | EP | Profile | DeviceId |
  |----|---------|----------|
  | 1 | 0x0104 (HA) | 0x0005 |
  | 2 | 0x0108 (IPM) | 0x0005 |
  | 4 | 0x0107 (TA)  | 0x0005 |

### `AF_DATA_REQUEST` (0x01)

- Payload (10 B header + ZCL data, max ~250):
  ```
  DstAddr (2 LE)         // 16-bit network short address
  DstEndpoint (1)
  SrcEndpoint (1)         // zhac uses 1
  ClusterId (2 LE)
  TransId (1)             // shared with the ZCL transaction seq
  Options (1)             // zhac uses 0x00 (no APS-ack request)
  Radius (1)              // hop limit; zhac uses 0x0F (15)
  Len (1)
  Data (Len B)            // ZCL frame: [FrameCtrl, Seq, Cmd, body...]
  ```
- SRSP payload: `Status (1B)` — `0x00` success.
- AREQ confirm (0x80) follows asynchronously with the actual radio
  status. zhac subscribes to it for diagnostics + duplicate
  suppression but doesn't block on it.

### `AF_DATA_CONFIRM` (0x80, AREQ)

- Payload: `Status (1) | EndPoint (1) | TransId (1)`
- Status `0x00` = delivered (or no APS-ack requested), other =
  delivery failure code.

### `AF_INCOMING_MSG` (0x81, AREQ) — most-frequent path

- Payload (≥17 B header + Data):
  ```
  GroupId (2 LE)
  ClusterId (2 LE)
  SrcAddr (2 LE)
  SrcEndpoint (1)
  DstEndpoint (1)
  WasBroadcast (1)
  LinkQuality (1)
  SecurityUse (1)
  TimeStamp (4 LE)
  TransSeqNumber (1)
  Len (1)
  Data (Len B)        // raw ZCL frame
  ```
- zhac uses GroupId, ClusterId, SrcAddr, SrcEndpoint, LinkQuality, and
  Data. The ZCL parsing happens above this layer (in `zhc` library).

### `AF_INCOMING_MSG_EXT` (0x82, AREQ)

- Same shape as `AF_INCOMING_MSG` for the fields zhac reads. Some
  Z-Stack 3.x firmwares route certain frames here; zhac subscribes
  to both with the same handler.

---

## 4. ZDO subsystem (0x05) — Zigbee Device Object

| `cmd1` | Name | Direction | Purpose |
|--------|------|-----------|---------|
| `0x02` | `ZDO_NODE_DESC_REQ` | SREQ ↔ SRSP, AREQ `0x82` rsp | Query node descriptor |
| `0x04` | `ZDO_SIMPLE_DESC_REQ` | SREQ ↔ SRSP, AREQ `0x84` rsp | Query simple descriptor (per endpoint) |
| `0x05` | `ZDO_ACTIVE_EP_REQ` | SREQ ↔ SRSP, AREQ `0x85` rsp | Query endpoint list |
| `0x21` | `ZDO_BIND_REQ` | SREQ ↔ SRSP, AREQ `0xA1` rsp | Bind two endpoints (server-side) |
| `0x22` | `ZDO_UNBIND_REQ` | SREQ ↔ SRSP, AREQ `0xA2` rsp | Unbind |
| `0x34` | `ZDO_MGMT_LEAVE_REQ` | SREQ ↔ SRSP | Force a device to leave |
| `0x36` | `ZDO_MGMT_PERMIT_JOIN_REQ` | SREQ ↔ SRSP | Open / close the network for joining |
| `0x3E` | `ZDO_MGMT_NWK_UPDATE_REQ` | SREQ ↔ SRSP | Channel change |
| `0x40` | `ZDO_STARTUP_FROM_APP` | SREQ ↔ SRSP | Start coordinator (post-NV-config) |
| `0x50` | `ZDO_EXT_NWK_INFO` | SREQ ↔ SRSP | Read coordinator network state |
| `0x82` | `ZDO_NODE_DESC_RSP` | AREQ (NCP → host) | Node desc reply |
| `0x84` | `ZDO_SIMPLE_DESC_RSP` | AREQ (NCP → host) | Simple desc reply |
| `0x85` | `ZDO_ACTIVE_EP_RSP` | AREQ (NCP → host) | Active EP reply |
| `0xA1` | `ZDO_BIND_RSP` | AREQ (NCP → host) | Bind reply |
| `0xC0` | `ZDO_STATE_CHANGE_IND` | AREQ (NCP → host) | NWK state machine change |
| `0xC9` | `ZDO_LEAVE_IND` | AREQ (NCP → host) | A device left |
| `0xCA` | `ZDO_TC_DEV_IND` | AREQ (NCP → host) | Trust Center device join |

### Common ZDO REQ payload prefix

Every ZDO REQ that targets a remote node starts with a 2-byte
`DstAddr` (network short address, LE). Examples below show the full
payload after that prefix.

### `ZDO_NODE_DESC_REQ` (0x02)

- Payload: `DstAddr (2 LE) | NWKAddrOfInterest (2 LE)` — usually equal.
- SRSP payload: `Status (1)` — request accepted.
- Async response on AREQ `0x82`:
  `SrcAddr (2 LE) | Status (1) | NWKAddrOfInterest (2 LE) | NodeDesc (13)`

### `ZDO_SIMPLE_DESC_REQ` (0x04)

- Payload: `DstAddr (2 LE) | NWKAddrOfInterest (2 LE) | Endpoint (1)`
- SRSP payload: `Status (1)`
- Async response on AREQ `0x84`:
  ```
  SrcAddr (2 LE)
  Status (1)
  NWKAddrOfInterest (2 LE)
  Length (1)                 // length of the SimpleDesc that follows
  Endpoint (1)
  AppProfileId (2 LE)
  AppDeviceId (2 LE)
  AppDevVer (nibble in hi)+reserved (1)
  AppNumInClusters (1)
  AppInClusterList (2·N LE)
  AppNumOutClusters (1)
  AppOutClusterList (2·M LE)
  ```
  zhac walks `AppNumInClusters` from offset 12 and the in-cluster
  list from offset 13.

### `ZDO_ACTIVE_EP_REQ` (0x05)

- Payload: `DstAddr (2 LE) | NWKAddrOfInterest (2 LE)`
- SRSP payload: `Status (1)`
- Async response on AREQ `0x85`:
  ```
  SrcAddr (2 LE) | Status (1) | NWKAddrOfInterest (2 LE)
  ActiveEPCount (1) | ActiveEPList (ActiveEPCount B)
  ```

### `ZDO_BIND_REQ` (0x21) / `ZDO_UNBIND_REQ` (0x22)

- Payload (23 B):
  ```
  DstAddr (2 LE)             // network short address of the device being told to bind
  SrcIeee (8 LE)             // IEEE of the binding source
  SrcEndpoint (1)
  ClusterId (2 LE)
  DstAddrMode (1)            // zhac uses 0x03 = IEEE
  DstIeee (8 LE)             // typically the coordinator's IEEE
  DstEndpoint (1)
  ```
- SRSP payload: `Status (1)`
- Async response on AREQ `0xA1` / `0xA2`:
  `SrcAddr (2 LE) | Status (1)`

### `ZDO_MGMT_LEAVE_REQ` (0x34)

- Payload: `DstAddr (2 LE) | DeviceAddress (8 LE) | RemoveChildren_Rejoin (1)`
- SRSP payload: `Status (1)`
- zhac uses this when the user removes a device.

### `ZDO_MGMT_PERMIT_JOIN_REQ` (0x36)

- Payload (5 B):
  ```
  AddrMode (1)            // 0x0F = broadcast 0xFFFC
  DstAddr (2 LE)          // 0xFFFC for broadcast
  Duration (1)            // 0=close, 1..254=seconds, 255=forever
  TCSignificance (1)      // MUST be 0x01 so coordinator also opens
  ```
- SRSP payload: `Status (1)`

### `ZDO_MGMT_NWK_UPDATE_REQ` (0x3E)

- Payload: `DstAddr (2 LE) | DstAddrMode (1) | ChannelMask (4 LE) | ScanDuration (1) | ScanCount (1) | NwkManagerAddr (2 LE)` plus mode-specific fields.
- zhac uses this to migrate the coordinator to a new channel.

### `ZDO_STARTUP_FROM_APP` (0x40)

- Payload: `StartDelay (2 LE)` — zhac uses 0x0064 (100 ms).
- SRSP payload: `Status (1)` — `0x00` restored, `0x01` new network, `0x02` leave-and-not-started.

### `ZDO_EXT_NWK_INFO` (0x50)

- Payload: empty.
- SRSP payload (≥7 B):
  ```
  ShortAddr (2 LE)
  DevState (1)         // 0x09 = STARTED_AS_COORDINATOR
  PanId (2 LE)
  ExtPanId (8 LE)      // zhac stops parsing after PanId
  Channel (1)
  IeeeAddr (8 LE)
  ```
- zhac polls this in a loop after `STARTUP_FROM_APP` waiting for
  `PanId != 0x0000 && != 0xFFFF` to confirm formation.

### `ZDO_STATE_CHANGE_IND` (0xC0, AREQ)

- Payload (1 B): `State`. Value `0x09` = `DEV_ZB_COORD` (started as coordinator).
- zhac sets `s_coordinator_ready = true` on `0x09`.

### `ZDO_LEAVE_IND` (0xC9, AREQ)

- Payload: `SrcAddr (2 LE) | ExtAddr (8 LE) | Request (1) | Removed (1) | Rejoin (1)`
- zhac removes the device from its pool.

### `ZDO_TC_DEV_IND` (0xCA, AREQ)

- Payload: `Nwk (2 LE) | ExtAddr (8 LE) | ParentAddr (2 LE)`
- zhac kicks off the interview pipeline (NODE_DESC → ACTIVE_EP →
  SIMPLE_DESC × N → Basic-cluster read).

---

## 5. APP_CNF subsystem (0x0F) — Base Device Behaviour

Used only during commissioning.

| `cmd1` | Name | Direction | Purpose |
|--------|------|-----------|---------|
| `0x05` | `APP_CNF_BDB_START_COMMISSIONING` | SREQ ↔ SRSP | Trigger BDB commissioning mode |
| `0x08` | `APP_CNF_BDB_SET_CHANNEL` | SREQ ↔ SRSP | Set channel mask |

### `APP_CNF_BDB_START_COMMISSIONING` (0x05)

- Payload: `CommissioningMode (1)` — zhac uses `0x04` (network formation)
  during initial commissioning, then `0x02` (network steering) when
  opening for joining.
- SRSP payload: `Status (1)`. zhac uses `0x04` best-effort (some
  builds hold the SREQ during formation; a `state=0x09` AREQ on ZDO
  confirms success either way).

### `APP_CNF_BDB_SET_CHANNEL` (0x08)

- Payload (5 B):
  ```
  IsPrimary (1)              // 0x01 primary, 0x00 secondary
  ChannelMask (4 LE)         // bit n = channel (n+11). zhac sets primary mask.
  ```
- SRSP payload: `Status (1)`.

---

## 6. AREQ subscriptions — what zhac listens to

A complete enumeration. Any other AREQ the NCP emits is ignored
silently. (Source: `zigbee_mgr_init` and `zigbee_interview_init` in
the firmware.)

| Subsystem | `cmd1` | Name | Handler purpose |
|-----------|-------|------|------------------|
| SYS  | `0x80` | `SYS_RESET_IND` | NCP reset complete |
| AF   | `0x80` | `AF_DATA_CONFIRM` | TX status for outgoing data |
| AF   | `0x81` | `AF_INCOMING_MSG` | Inbound ZCL frame |
| AF   | `0x82` | `AF_INCOMING_MSG_EXT` | Inbound ZCL frame (extended variant) |
| ZDO  | `0x82` | `ZDO_NODE_DESC_RSP` | Async response for `0x02` |
| ZDO  | `0x84` | `ZDO_SIMPLE_DESC_RSP` | Async response for `0x04` |
| ZDO  | `0x85` | `ZDO_ACTIVE_EP_RSP` | Async response for `0x05` |
| ZDO  | `0xA1` | `ZDO_BIND_RSP` | Async response for `0x21` (and unbind `0x22` reuses `0xA2` similarly) |
| ZDO  | `0xC0` | `ZDO_STATE_CHANGE_IND` | NWK state transitions |
| ZDO  | `0xC9` | `ZDO_LEAVE_IND` | Device left the network |
| ZDO  | `0xCA` | `ZDO_TC_DEV_IND` | Device joined |

---

## 7. Coordinator startup sequence (reference flow)

The C6 NCP must support this exact sequence before zhac will declare
itself "ready":

```
1.  Host: assert NRESET low 10 ms, release.
2.  NCP : send SYS_RESET_IND (AREQ 0x80) within 6 s.
3.  Host: SYS_PING (SREQ 0x01).                       expect SRSP
4.  Host: SYS_GET_EXTADDR (SREQ 0x04).                 expect SRSP, parse 8B IEEE
5.  Host: SYS_VERSION (SREQ 0x02).                     informational only

6.  if NV state missing:
       Host: NV_ITEM_INIT/WRITE for STARTUP_OPTION, LOGICAL_TYPE, PRECFGKEYS_ENABLE,
             PANID, CHANLIST, PRECFGKEY, ZDO_DIRECT_CB.
       Host: SYS_RESET_REQ soft (0x00 + Type=1).      wait for SYS_RESET_IND again
       Host: NV_WRITE STARTUP_OPTION = 0x00.
       Host: APP_CNF_BDB_SET_CHANNEL primary + secondary.
       Host: APP_CNF_BDB_START_COMMISSIONING mode=0x04 (form).
       NCP : ZDO_STATE_CHANGE_IND state=0x09.

7.  Host: AF_REGISTER for endpoints 1, 2, 4 (profiles 0x0104 / 0x0108 / 0x0107,
          0 in / 0 out clusters).
8.  Host: ZDO_STARTUP_FROM_APP delay=100 ms.
9.  Host: poll ZDO_EXT_NWK_INFO (SREQ 0x50) until DevState=0x09 and
          PanId is not 0x0000/0xFFFF.
10. Host: ZDO_MGMT_PERMIT_JOIN_REQ duration=N, broadcast.

→ Coordinator ready. From here on host listens to AF_INCOMING_MSG /
  ZDO_TC_DEV_IND / ZDO_LEAVE_IND and sends AF_DATA_REQUEST / ZDO_BIND_REQ
  on demand.
```

---

## 8. What zhac does NOT use (and a clean-room NCP can omit)

- Entire `MAC` (`0x02`), `NWK` (`0x03`), `SAPI` (`0x06`), `UTIL` (`0x07`)
  subsystems. zhac speaks only SYS / AF / ZDO / APP_CNF.
- `AF_DATA_REQUEST_EXT` / `AF_DATA_REQUEST_SRC_RTG` variants — only
  the standard `AF_DATA_REQUEST` (0x01) is used.
- ZDO `MGMT_LQI_REQ`, `MGMT_RTG_REQ`, `MGMT_BIND_REQ` — none used.
- `SYS_TEST_*`, `SYS_RPC_*` — none used.
- Greenpower (cluster `0x0021`) — passes through `AF_INCOMING_MSG` but
  the NCP doesn't need a dedicated subsystem; zhac handles it in the
  ZHC library.
- Any ZNP NV item beyond the seven listed in §2.

---

## 9. Quick verification checklist for a C6 NCP claim

If you're building the C6 firmware, you can self-check against zhac
without flashing it:

1. NCP comes up, emits `SYS_RESET_IND` over UART within 6 s of nRESET release.
2. Round-trip a `SYS_PING` SREQ; SRSP arrives within 1 s with non-empty payload.
3. Round-trip a `SYS_VERSION` SREQ; SRSP returns ≥5 bytes.
4. Round-trip a `SYS_GET_EXTADDR` SREQ; SRSP returns the C6's 8-byte IEEE.
5. Issue `NV_ITEM_INIT` for each of the seven items; SRSP status `0x00` or `0x09`.
6. After commissioning, `ZDO_EXT_NWK_INFO` returns DevState=0x09 with a PanId.
7. With a known Zigbee end-device powered on, `ZDO_TC_DEV_IND` arrives
   on join, followed by an `AF_INCOMING_MSG` carrying its Basic
   cluster modelId/manufacturerName.
8. `AF_DATA_REQUEST` SREQ to that device's cluster `0x0006` cmd `0x01`
   produces an `AF_DATA_CONFIRM` AREQ with status `0x00` and the
   physical bulb turns on.

If 1-8 pass, zhac will treat the C6 as a working ZNP NCP. The
`c6_driver` scaffolded under `components/c6_driver/` is then
unnecessary — you can stay on the existing `znp_driver` with just a
config change to swap the UART pins and chip type.

---

## Reference: source files

| Concern | File |
|---------|------|
| Wire framing + FCS | `components/znp_driver/src/znp_parser.cpp` |
| RX / TX tasks | `components/znp_driver/src/znp_rx.cpp`, `znp_worker.cpp` |
| AREQ dispatch table | `components/znp_driver/src/znp_areq_dispatch.cpp` |
| Hardware reset | `components/znp_driver/src/znp_transport.cpp` (`znp_hw_reset`) |
| SYS / NV usage | `components/zigbee_mgr/zigbee_mgr.cpp` |
| AF_DATA_REQUEST / AF_REGISTER | `components/zigbee_mgr/zcl_commands.cpp`, `zhc_send_bridge.cpp` |
| ZDO interview flow | `components/zigbee_mgr/zigbee_interview.cpp` |
| Bind / unbind | `components/zigbee_mgr/zcl_commands.cpp` (`zdo_bind_unbind`) |
| ZDO state-change handling | `components/zigbee_mgr/zigbee_mgr.cpp` (`on_state_change`) |

Pin all of these to a specific commit when forking — the contract
above won't change incompatibly without an entry in `CHANGELOG.md`.
