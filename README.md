# ZHAC — Zigbee Home Automation Controller

ZHAC is an open, self-hosted **dual-chip Zigbee controller**. An ESP32-P4 runs the
Zigbee coordinator + a Lua rules engine; an ESP32-S3 runs the WiFi gateway
(REST / WebSocket / MQTT) and serves a Preact web UI. The two chips talk over SPI;
the P4 drives an external Zigbee radio over UART.

This repo (**zhac-docs**) is the entry point for the whole project: architecture,
wiring, a from-zero build/flash guide, and the API/reference docs. Per-module notes
live in each module's own repo.

> **Org:** https://github.com/zhac-project  ·  **Meta-repo:** [zhac-platform](https://github.com/zhac-project/zhac-platform)

---

## Architecture

Three tiers, each on its own silicon:

```
  Zigbee devices          ESP32-P4 (zhac-main-core)        ESP32-S3 (zhac-net-core)        Clients
  bulbs · sensors         Zigbee coordinator · Lua          WiFi · REST/WS/MQTT             phone · browser
  · switches              rules · device shadow             · embedded Preact SPA           · MQTT · cloud
       │                          │                                  │                            │
       │  802.15.4                │  UART  (ZNP / Z-Stack MT,        │  SPI  (HAP binary,         │  WiFi / HTTP
       │                          │   115200 8N1, GPIO16/17)         │   SPI2 @6 MHz, mode 0,     │  http://<s3-ip>/
       ▼                          │                                  │   S3=master P4=slave,      │
  ┌──────────┐                ┌───┴────────┐                     ┌───┴────────┐  + DRDY irq)  ┌───┴───┐
  │  CC2652  │◀── UART ──────▶│  ESP32-P4  │◀═══════ SPI ═══════▶│  ESP32-S3  │◀═════════════▶│ users │
  │  radio   │   ZNP / MT     │ main-core  │      HAP protocol   │  net-core  │   WiFi        └───────┘
  └──────────┘                └────────────┘                     └────────────┘
```

- **ESP32-P4 (`zhac-main-core`)** — Zigbee coordinator, device shadow, Lua + DSL rules
  engine. The P4 has no native 802.15.4 radio, so it drives an **external Zigbee radio**
  (TI CC2652 running Z-Stack coordinator firmware) over UART using the **ZNP / Z-Stack
  Monitor-Test (MT)** protocol.
- **ESP32-S3 (`zhac-net-core`)** — WiFi station, REST + WebSocket + MQTT gateway, and it
  embeds the Preact single-page web UI in flash (SPIFFS).
- **P4 ⇄ S3 link** — a custom binary protocol (**[HAP](HAP_PROTOCOL.md)**) over SPI. The S3
  is SPI master, the P4 is SPI slave, with a data-ready (DRDY) interrupt line for P4→S3 flow
  control.

---

## Repositories

| Repo | Role | Toolchain |
|------|------|-----------|
| [zhac-platform](https://github.com/zhac-project/zhac-platform) | Meta-repo — submodules + `justfile` one-command build | just, ESP-IDF |
| [zhac-main-core](https://github.com/zhac-project/zhac-main-core) | ESP32-**P4** firmware (coordinator + Lua) | ESP-IDF v6.0, `esp32p4` |
| [zhac-net-core](https://github.com/zhac-project/zhac-net-core) | ESP32-**S3** firmware (WiFi gateway + SPA host) | ESP-IDF v6.0, `esp32s3` |
| [zhac-components](https://github.com/zhac-project/zhac-components) | Shared ESP-IDF components (HAP, radio stack, MQTT, rules) | ESP-IDF |
| [embedded-zhc](https://github.com/zhac-project/embedded-zhc) | Host-testable C++20 device library (~6600 device defs) | CMake (host) + ESP-IDF |
| [www-spa](https://github.com/zhac-project/www-spa) | Preact + Vite web UI (built into the S3 SPIFFS image) | Node ≥18, Vite |
| **zhac-docs** | This repo — platform docs | — |

Clone over HTTPS (no SSH key needed) or SSH (`git@github.com:zhac-project/<repo>.git`).

---

## Hardware wiring

> Logic is **3.3 V** on every link — do not connect 5 V. Tie all grounds together.
> The SPI link runs at 6 MHz; keep those five leads short (a few cm) and add a ground
> return next to the clock for signal integrity.

### ESP32-S3 ⇄ ESP32-P4 — SPI (HAP)

`SPI2`, **6 MHz**, **mode 0**, full-duplex with DMA. S3 = master, P4 = slave. These GPIOs
are **fixed in firmware** (not menuconfig — edit `hap_master.cpp` / `hap_slave.cpp` to
change them).

| Signal | S3 `zhac-net-core` | P4 `zhac-main-core` | Direction |
|--------|:------------------:|:-------------------:|-----------|
| SCLK   | GPIO12 | GPIO18 | S3 → P4 (clock) |
| MOSI   | GPIO11 | GPIO19 | S3 → P4 |
| MISO   | GPIO13 | GPIO20 | P4 → S3 |
| CS     | GPIO10 | GPIO21 | S3 → P4 (chip-select) |
| DRDY   | GPIO8 (input) | GPIO22 (output) | P4 → S3 (data-ready IRQ) |
| GND    | GND | GND | common ground |

**DRDY handshake:** the P4 drives GPIO22 **high** when it has a frame queued; the S3 sees
a **rising edge** on GPIO8 (interrupt) and clocks the exchange; the P4 lowers it once the
transfer completes.

### ESP32-P4 ⇄ Zigbee radio — UART (ZNP)

`UART1`, **115200 baud, 8N1, no flow control**. Default backend `CONFIG_ZHAC_NCP_ZNP`
(TI Z-Stack MT). The radio is a **TI CC2652** (CC2530 also supported) flashed with
Z-Stack **coordinator** firmware. These pins are **configurable** via
`idf.py menuconfig` → *ZHAC NCP* (defaults shown).

| Signal | P4 `zhac-main-core` | Radio (CC2652) | Direction |
|--------|:-------------------:|:--------------:|-----------|
| UART TX | GPIO16 | RXD | P4 → radio |
| UART RX | GPIO17 | TXD | radio → P4 |
| nRESET  | GPIO28 | RESET_N | P4 → radio (active-low pulse) |
| BSL     | GPIO29 | bootloader-select | P4 → radio (firmware flashing) |
| GND     | GND | GND | common ground |
| 3V3     | 3V3 | VCC | power |

> The radio's *own* firmware (Z-Stack coordinator NCP) is flashed separately — see TI's
> Z-Stack docs or the zigbee2mqtt CC2652 flashing guides. A Silabs **EZSP** backend
> (EFR32, UART on GPIO26/27) also exists but is disabled by default.

---

## Prerequisites

- **ESP-IDF v6.0** — install via Espressif's
  [Get Started](https://docs.espressif.com/projects/esp-idf/en/v6.0/esp32p4/get-started/index.html)
  guide (the IDF must support both `esp32p4` and `esp32s3`).
- **Node ≥ 18** — to build the web UI (`www-spa`).
- **just** *(optional)* — for the one-command meta-repo build ([casey/just](https://github.com/casey/just)).
- **Hardware** — an ESP32-P4 board, an ESP32-S3 board, and a TI CC2652 radio running
  Z-Stack coordinator firmware, wired as above.

---

## Build & flash — from zero

### 1. Get the source

**Option A — meta-repo (recommended; pulls every sub-repo + the `just` shortcuts):**

```sh
git clone --recurse-submodules https://github.com/zhac-project/zhac-platform.git
cd zhac-platform
just setup          # = git submodule update --init --recursive  +  (cd zhac-net-core/www-spa && npm ci)
```

`www-spa` is a nested submodule mounted at `zhac-net-core/www-spa`; `--recurse-submodules`
(or `just setup`) fetches it.

**Option B — side-by-side clones (no meta-repo):**

```sh
mkdir zhac && cd zhac
for r in zhac-main-core zhac-net-core zhac-components embedded-zhc www-spa; do
  git clone https://github.com/zhac-project/$r.git
done
( cd zhac-net-core/www-spa 2>/dev/null || cd www-spa ) && npm ci && cd -
```

The firmware `CMakeLists.txt` finds the shared code via a fallback chain —
`$IDF_COMPONENT_OVERRIDE_PATH` → `../zhac-components/components` → `../../components` — so
sibling checkouts resolve automatically.

### 2. Activate ESP-IDF

Activate your ESP-IDF v6.0 environment so `idf.py` and `IDF_PATH` are on the shell
(`just` fails fast if `IDF_PATH` is unset). The script is **platform-specific** — point at
*your* install directory (the paths below are examples):

- **Linux / macOS** (bash/zsh):
  ```sh
  . $HOME/esp/esp-idf/export.sh
  ```
  The Linux "eim" installer also generates `~/.espressif/tools/activate_idf_v6.0.sh`, which works the same.
- **Windows** — open the **“ESP-IDF 6.0 CMD/PowerShell”** shortcut the Windows installer adds to the Start menu, or run the env script directly:
  ```bat
  %userprofile%\esp\esp-idf\export.bat          :: Command Prompt
  ```
  ```powershell
  & "$env:userprofile\esp\esp-idf\export.ps1"   # PowerShell
  ```

Then sanity-check (any platform):

```sh
idf.py --version                  # should report v6.0.x
```

> **Shell note:** the commands in the rest of this guide use a **POSIX shell** (Linux/macOS).
> On Windows, run them inside the ESP-IDF CMD/PowerShell environment and adjust syntax —
> `set VAR=…` instead of `export VAR=…`, and `COMx` serial ports instead of `/dev/tty*`.
> Cloning, `npm`, `just`, and `idf.py` themselves are identical across platforms.

### 3. Build

The SPA **must build before the S3 firmware** — its `dist/` is packed into the S3 SPIFFS
partition at build time.

**With `just` (from `zhac-platform/`):**

```sh
just build           # builds SPA → P4 → S3, in order
# or one at a time:
just build-www       # web UI only  → zhac-net-core/www-spa/dist
just build-p4        # ESP32-P4 firmware
just build-s3        # ESP32-S3 firmware (needs dist/)
```

**Manual (from `zhac-platform/`, or adapt paths for side-by-side):**

```sh
export IDF_COMPONENT_OVERRIDE_PATH="$PWD/zhac-components/components"
export EMBEDDED_ZHC_PATH="$PWD/embedded-zhc"

( cd zhac-net-core/www-spa && npm ci && npm run build )      # 1. SPA first
( cd zhac-main-core && idf.py set-target esp32p4 && idf.py build )   # 2. P4
( cd zhac-net-core  && idf.py set-target esp32s3 && idf.py build )   # 3. S3
```

### 4. Flash

Connect each board over USB. Ports vary by OS/board — `/dev/ttyACM*` or `/dev/ttyUSB*`
on Linux, `/dev/cu.*` on macOS, `COMx` on Windows. The defaults below match the `justfile`;
pass `port=COM5` (or your port) to the `just` recipes, or `-p COM5` to `idf.py`.

```sh
just flash-p4 port=/dev/ttyACM0
just flash-s3 port=/dev/ttyUSB0
# manual equivalent:
( cd zhac-main-core && idf.py -p /dev/ttyACM0 flash )
( cd zhac-net-core  && idf.py -p /dev/ttyUSB0 flash )
```

### 5. Monitor & verify

```sh
just monitor-p4          # or: just monitor-s3      (exit the monitor with Ctrl-])
# manual: idf.py -p <port> monitor
```

Expect: the **P4** log shows the ZNP coordinator coming up and the SPI/HAP link syncing;
the **S3** joins WiFi and serves the web UI at `http://<s3-ip>/`. WiFi onboarding is
described in the [zhac-net-core](https://github.com/zhac-project/zhac-net-core) README.

### Re-flash the web UI only

After SPA-only changes, skip the full S3 build:

```sh
just spiffs-only port=/dev/ttyUSB0      # or: idf.py -p <port> spiffs-flash
```

### Housekeeping

```sh
just status        # checked-out version per submodule
just clean         # remove build artifacts
just deep-clean    # also remove node_modules
```

---

## Documentation

| Document | What |
|----------|------|
| [FEATURES.md](FEATURES.md) | Feature overview |
| [REST_API.md](REST_API.md) · [WS_API.md](WS_API.md) · [openapi.yaml](openapi.yaml) | HTTP REST + WebSocket (`/ws`) APIs |
| [RULES_DSL.md](RULES_DSL.md) | Automation rule DSL (`ON … DO … ENDON`) |
| [LUA_API.md](LUA_API.md) | Lua scripting API |
| [HAP_PROTOCOL.md](HAP_PROTOCOL.md) | P4 ↔ S3 SPI binary protocol — framing, message catalog, reliability |
| [ZNP_API_CONTRACT.md](ZNP_API_CONTRACT.md) | P4 ↔ radio ZNP/MT contract |
| [VENDOR_PORTING_STATUS.md](VENDOR_PORTING_STATUS.md) | Supported devices / porting status |
| [SECURITY.md](SECURITY.md) · [CONTRIBUTING.md](CONTRIBUTING.md) · [CLA.md](CLA.md) | Security policy, contributing, CLA |

---

## Contributing

Anyone is welcome to open a PR.

1. Read [CLA.md](CLA.md) — signing is one-time across the whole ZHAC project.
2. Make your edit. Markdown preferred; prose over diagrams where a sentence suffices.
3. Run the link-check (`npm run lint`) locally if you add cross-document links — CI runs the same.
4. Open a PR against `main`.

## License

AGPL-3.0-or-later for the documentation prose + diagrams (see [LICENSE](LICENSE)). Code
snippets are licensed under the same terms as the code they illustrate (Apache-2.0 for
`embedded-zhc` examples, AGPL-3.0-or-later for firmware examples). Sub-repos carry their
own licenses.

## Versioning

Releases are tagged `vYYYYMMDDVV` (date + 2-digit revision); the meta-repo tag pins each
submodule SHA. See the [zhac-platform](https://github.com/zhac-project/zhac-platform)
README for the scheme. Doc tags may lag firmware tags — no strict coupling.
