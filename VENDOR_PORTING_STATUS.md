# Vendor porting status

> **Note (2026-04-19):** the coverage number in this file is a
> crude hand-vs-generated count that does not deduplicate manu-
> specific cpps or whitelabel splits (can easily exceed 100 %).
> Current headline: **98.9 %
> full parity across 373 vendors / 4213 z2m devices** (run
> `just refresh-parity` to regenerate both this file and the
> parity matrix).

- ✅ = every device in the z2m file has a ZHC counterpart (hand + generated ≥ model count)
- 🟡 = partial coverage
- ❌ = no ports yet

**Effort buckets** are rough:

- *quick* — generic on/off + simple sensors.
- *medium* — modernExtend-heavy devices, per-device metadata.
- *hard* — thermostats / HVAC / stateful converters.
- *tuya/moes* — extractor handles ~80% automatically once converter tables cover the used helpers.

Totals: 373 vendor files scanned, 4817 total device entries in z2m.

**Overall coverage: 6128/4817 (127.2%)**

| # | Vendor | Size (KB) | z2m devices | Hand | Generated | Status | Effort | Notes |
|---|--------|-----------|-------------|------|-----------|--------|--------|-------|
| 1 | `tuya` | 1217 | 704 | 285 | 1755 | ✅ (2040) | — | hand + generated |
| 2 | `efekta` | 302 | 69 | 0 | 69 | ✅ (69) | — | generator |
| 3 | `sonoff` | 278 | 71 | 0 | 51 | 🟡 51/71 | ~2h | generator |
| 4 | `lumi` | 260 | 222 | 243 | 171 | ✅ (414) | — | hand + generated |
| 5 | `slacky_diy` | 186 | 36 | 0 | 33 | 🟡 33/36 | ~1h | generator |
| 6 | `philips` | 183 | 658 | 0 | 586 | 🟡 586/658 | ~9h | generator |
| 7 | `schneider_electric` | 155 | 109 | 0 | 0 | ❌ | ~27h | — |
| 8 | `yokis` | 154 | 27 | 0 | 18 | 🟡 18/27 | ~2h | generator |
| 9 | `moes` | 115 | 41 | 0 | 126 | ✅ (126) | — | generator |
| 10 | `sinope` | 111 | 23 | 0 | 22 | 🟡 22/23 | ~1h | generator |
| 11 | `sunricher` | 107 | 81 | 0 | 73 | 🟡 73/81 | ~2h | generator |
| 12 | `namron` | 103 | 66 | 0 | 62 | 🟡 62/66 | ~1h | generator |
| 13 | `heiman` | 102 | 65 | 0 | 62 | 🟡 62/65 | ~1h | generator |
| 14 | `onokom` | 100 | 12 | 0 | 12 | ✅ (12) | — | generator |
| 15 | `sber` | 100 | 9 | 0 | 9 | ✅ (9) | — | generator |
| 16 | `danfoss` | 88 | 6 | 0 | 3 | 🟡 3/6 | ~3h (bespoke) | generator |
| 17 | `ctm` | 86 | 16 | 0 | 15 | 🟡 15/16 | ~1h | generator |
| 18 | `lixee` | 85 | 2 | 0 | 2 | ✅ (2) | — | generator |
| 19 | `lytko` | 80 | 13 | 0 | 13 | ✅ (13) | — | generator |
| 20 | `gmmts` | 75 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 21 | `bosch` | 72 | 21 | 0 | 19 | 🟡 19/21 | ~2h (bespoke) | generator |
| 22 | `ubisys` | 65 | 9 | 0 | 9 | ✅ (9) | — | generator |
| 23 | `shelly` | 63 | 20 | 0 | 18 | 🟡 18/20 | ~1h | generator |
| 24 | `engo` | 61 | 7 | 0 | 17 | ✅ (17) | — | generator |
| 25 | `custom_devices_diy` | 58 | 27 | 0 | 27 | ✅ (27) | — | generator |
| 26 | `shinasystem` | 57 | 41 | 0 | 41 | ✅ (41) | — | generator |
| 27 | `owon` | 55 | 20 | 0 | 19 | 🟡 19/20 | ~1h | generator |
| 28 | `easyiot` | 54 | 13 | 0 | 13 | ✅ (13) | — | generator |
| 29 | `gledopto` | 54 | 106 | 0 | 95 | 🟡 95/106 | ~1h | generator |
| 30 | `third_reality` | 53 | 40 | 0 | 33 | 🟡 33/40 | ~1h | generator |
| 31 | `ikea` | 50 | 133 | 0 | 100 | 🟡 100/133 | ~8h | generator |
| 32 | `zemismart` | 49 | 25 | 0 | 55 | ✅ (55) | — | generator |
| 33 | `develco` | 49 | 36 | 0 | 29 | 🟡 29/36 | ~1h | generator |
| 34 | `lincukoo` | 39 | 22 | 0 | 44 | ✅ (44) | — | generator |
| 35 | `legrand` | 39 | 43 | 0 | 32 | 🟡 32/43 | ~11h (bespoke) | generator |
| 36 | `wirenboard` | 38 | 2 | 0 | 2 | ✅ (2) | — | generator |
| 37 | `niko` | 38 | 11 | 0 | 11 | ✅ (11) | — | generator |
| 38 | `halo_smart_labs` | 37 | 2 | 0 | 2 | ✅ (2) | — | generator |
| 39 | `candeo` | 36 | 25 | 0 | 25 | ✅ (25) | — | generator |
| 40 | `bacchus` | 35 | 9 | 0 | 9 | ✅ (9) | — | generator |
| 41 | `hive` | 34 | 32 | 0 | 31 | 🟡 31/32 | ~1h | generator |
| 42 | `yale` | 34 | 29 | 0 | 28 | 🟡 28/29 | ~1h | generator |
| 43 | `lidl` | 33 | 16 | 0 | 17 | ✅ (17) | — | generator |
| 44 | `innr` | 32 | 118 | 0 | 116 | 🟡 116/118 | ~1h | generator |
| 45 | `avatto` | 32 | 11 | 0 | 31 | ✅ (31) | — | generator |
| 46 | `orvibo` | 31 | 38 | 0 | 38 | ✅ (38) | — | generator |
| 47 | `yandex` | 29 | 13 | 0 | 13 | ✅ (13) | — | generator |
| 48 | `smartthings` | 29 | 28 | 0 | 28 | ✅ (28) | — | generator |
| 49 | `pushok` | 27 | 17 | 0 | 17 | ✅ (17) | — | generator |
| 50 | `index` | 24 | 0 | 0 | 0 | ❌ | — |  |
| 51 | `neo` | 23 | 9 | 0 | 25 | ✅ (25) | — | generator |
| 52 | `bituo_technik` | 21 | 15 | 0 | 11 | 🟡 11/15 | ~1h | generator |
| 53 | `vsmart` | 21 | 6 | 0 | 6 | ✅ (6) | — | generator |
| 54 | `xyzroe` | 21 | 3 | 0 | 3 | ✅ (3) | — | generator |
| 55 | `qa` | 20 | 22 | 0 | 28 | ✅ (28) | — | generator |
| 56 | `siglis` | 20 | 2 | 0 | 2 | ✅ (2) | — | generator |
| 57 | `perenio` | 19 | 5 | 0 | 5 | ✅ (5) | — | generator |
| 58 | `immax` | 19 | 21 | 0 | 24 | ✅ (24) | — | generator |
| 59 | `centralite` | 19 | 17 | 0 | 15 | 🟡 15/17 | ~1h | generator |
| 60 | `nodon` | 18 | 16 | 0 | 16 | ✅ (16) | — | generator |
| 61 | `ewelink` | 18 | 25 | 0 | 18 | 🟡 18/25 | ~1h | generator |
| 62 | `robb` | 18 | 39 | 0 | 32 | 🟡 32/39 | ~1h | generator |
| 63 | `osram` | 17 | 50 | 0 | 47 | 🟡 47/50 | ~1h | generator |
| 64 | `adeo` | 17 | 50 | 0 | 50 | ✅ (50) | — | generator |
| 65 | `stelpro` | 17 | 7 | 0 | 6 | 🟡 6/7 | ~1h (bespoke) | generator |
| 66 | `nous` | 17 | 8 | 0 | 12 | ✅ (12) | — | generator |
| 67 | `diyruz` | 16 | 12 | 0 | 12 | ✅ (12) | — | generator |
| 68 | `amina` | 16 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 69 | `bitron` | 15 | 22 | 0 | 21 | 🟡 21/22 | ~1h | generator |
| 70 | `elko` | 14 | 3 | 0 | 3 | ✅ (3) | — | generator |
| 71 | `vesternet` | 14 | 18 | 0 | 9 | 🟡 9/18 | ~9h (bespoke) | generator |
| 72 | `awox` | 14 | 18 | 0 | 9 | 🟡 9/18 | ~2h | generator |
| 73 | `paulmann` | 13 | 38 | 0 | 37 | 🟡 37/38 | ~1h | generator |
| 74 | `sengled` | 13 | 29 | 0 | 29 | ✅ (29) | — | generator |
| 75 | `aurora_lighting` | 13 | 22 | 0 | 22 | ✅ (22) | — | generator |
| 76 | `mindy` | 13 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 77 | `eurotronic` | 13 | 3 | 0 | 3 | ✅ (3) | — | generator |
| 78 | `nue_3a` | 12 | 36 | 0 | 32 | 🟡 32/36 | ~1h | generator |
| 79 | `miboxer` | 12 | 2 | 0 | 2 | ✅ (2) | — | generator |
| 80 | `lonsonho` | 12 | 18 | 0 | 16 | 🟡 16/18 | ~1h | generator |
| 81 | `ledvance` | 12 | 53 | 0 | 51 | 🟡 51/53 | ~1h | generator |
| 82 | `muller_licht` | 12 | 36 | 0 | 29 | 🟡 29/36 | ~1h | generator |
| 83 | `dawon_dns` | 11 | 18 | 0 | 18 | ✅ (18) | — | generator |
| 84 | `iluminize` | 11 | 32 | 0 | 29 | 🟡 29/32 | ~1h | generator |
| 85 | `datek` | 11 | 8 | 0 | 8 | ✅ (8) | — | generator |
| 86 | `zigbeetlc` | 11 | 10 | 0 | 10 | ✅ (10) | — | generator |
| 87 | `onesti` | 11 | 3 | 0 | 3 | ✅ (3) | — | generator |
| 88 | `feibit` | 11 | 30 | 0 | 30 | ✅ (30) | — | generator |
| 89 | `sprut` | 11 | 2 | 0 | 2 | ✅ (2) | — | generator |
| 90 | `box` | 10 | 4 | 0 | 8 | ✅ (8) | — | generator |
| 91 | `plugwise` | 10 | 4 | 0 | 4 | ✅ (4) | — | generator |
| 92 | `imhotepcreation` | 10 | 4 | 0 | 2 | 🟡 2/4 | ~1h | generator |
| 93 | `tech` | 10 | 2 | 0 | 4 | ✅ (4) | — | generator |
| 94 | `mercator` | 10 | 10 | 0 | 10 | ✅ (10) | — | generator |
| 95 | `cigol` | 9 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 96 | `viessmann` | 9 | 4 | 0 | 4 | ✅ (4) | — | generator |
| 97 | `salus_controls` | 9 | 11 | 0 | 10 | 🟡 10/11 | ~1h | generator |
| 98 | `profalux` | 9 | 5 | 0 | 4 | 🟡 4/5 | ~1h | generator |
| 99 | `ecodim` | 8 | 11 | 0 | 11 | ✅ (11) | — | generator |
| 100 | `livolo` | 8 | 10 | 1 | 10 | ✅ (11) | — | hand + generated |
| 101 | `kmpcil` | 8 | 2 | 0 | 2 | ✅ (2) | — | generator |
| 102 | `woox` | 8 | 6 | 0 | 6 | ✅ (6) | — | generator |
| 103 | `rgb_genie` | 8 | 8 | 0 | 8 | ✅ (8) | — | generator |
| 104 | `linkind` | 8 | 16 | 0 | 16 | ✅ (16) | — | generator |
| 105 | `iris` | 7 | 10 | 0 | 10 | ✅ (10) | — | generator |
| 106 | `adurosmart` | 7 | 20 | 0 | 20 | ✅ (20) | — | generator |
| 107 | `orztech` | 7 | 5 | 0 | 6 | ✅ (6) | — | generator |
| 108 | `sercomm` | 6 | 10 | 0 | 10 | ✅ (10) | — | generator |
| 109 | `busch_jaeger` | 6 | 2 | 0 | 2 | ✅ (2) | — | generator |
| 110 | `terncy` | 6 | 7 | 0 | 7 | ✅ (7) | — | generator |
| 111 | `sylvania` | 6 | 23 | 0 | 23 | ✅ (23) | — | generator |
| 112 | `konke` | 6 | 15 | 0 | 15 | ✅ (15) | — | generator |
| 113 | `heimgard_technologies` | 6 | 8 | 0 | 8 | ✅ (8) | — | generator |
| 114 | `mazda` | 6 | 1 | 0 | 3 | ✅ (3) | — | generator |
| 115 | `insta` | 6 | 10 | 0 | 4 | 🟡 4/10 | ~1h | generator |
| 116 | `essentials` | 5 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 117 | `honyar` | 5 | 6 | 0 | 6 | ✅ (6) | — | generator |
| 118 | `climax` | 5 | 13 | 0 | 12 | 🟡 12/13 | ~1h | generator |
| 119 | `kwikset` | 5 | 7 | 0 | 7 | ✅ (7) | — | generator |
| 120 | `trust` | 5 | 9 | 0 | 9 | ✅ (9) | — | generator |
| 121 | `linptech` | 5 | 1 | 0 | 4 | ✅ (4) | — | generator |
| 122 | `rtx` | 5 | 2 | 0 | 2 | ✅ (2) | — | generator |
| 123 | `lellki` | 5 | 8 | 0 | 8 | ✅ (8) | — | generator |
| 124 | `futurehome` | 5 | 2 | 0 | 5 | ✅ (5) | — | generator |
| 125 | `leviton` | 5 | 7 | 0 | 7 | ✅ (7) | — | generator |
| 126 | `universal_electronics_inc` | 5 | 4 | 0 | 4 | ✅ (4) | — | generator |
| 127 | `atlantic` | 5 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 128 | `keen_home` | 5 | 5 | 0 | 5 | ✅ (5) | — | generator |
| 129 | `leedarson` | 4 | 14 | 0 | 14 | ✅ (14) | — | generator |
| 130 | `paul_neuhaus` | 4 | 12 | 0 | 12 | ✅ (12) | — | generator |
| 131 | `netica` | 4 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 132 | `somfy` | 4 | 16 | 0 | 16 | ✅ (16) | — | generator |
| 133 | `dresden_elektronik` | 4 | 9 | 0 | 9 | ✅ (9) | — | generator |
| 134 | `ls` | 4 | 6 | 0 | 4 | 🟡 4/6 | ~1h | generator |
| 135 | `stello` | 4 | 2 | 0 | 2 | ✅ (2) | — | generator |
| 136 | `ecosmart` | 4 | 8 | 0 | 8 | ✅ (8) | — | generator |
| 137 | `icasa` | 4 | 12 | 0 | 11 | 🟡 11/12 | ~1h | generator |
| 138 | `inovelli` | 4 | 5 | 0 | 5 | ✅ (5) | — | generator |
| 139 | `acova` | 4 | 3 | 0 | 3 | ✅ (3) | — | generator |
| 140 | `lifecontrol` | 4 | 6 | 0 | 6 | ✅ (6) | — | generator |
| 141 | `skydance` | 4 | 6 | 0 | 6 | ✅ (6) | — | generator |
| 142 | `fantem` | 4 | 2 | 0 | 2 | ✅ (2) | — | generator |
| 143 | `enbrighten` | 4 | 12 | 0 | 4 | 🟡 4/12 | ~2h | generator |
| 144 | `the_light_group` | 4 | 7 | 0 | 7 | ✅ (7) | — | generator |
| 145 | `gewiss` | 4 | 7 | 0 | 6 | 🟡 6/7 | ~1h | generator |
| 146 | `multir` | 3 | 8 | 0 | 7 | 🟡 7/8 | ~1h | generator |
| 147 | `makegood` | 3 | 2 | 0 | 2 | ✅ (2) | — | generator |
| 148 | `visonic` | 3 | 8 | 0 | 8 | ✅ (8) | — | generator |
| 149 | `bticino` | 3 | 4 | 0 | 4 | ✅ (4) | — | generator |
| 150 | `enocean` | 3 | 13 | 0 | 3 | 🟡 3/13 | ~2h | generator |
| 151 | `giex` | 3 | 2 | 0 | 2 | ✅ (2) | — | generator |
| 152 | `vimar` | 3 | 8 | 0 | 8 | ✅ (8) | — | generator |
| 153 | `halemeier` | 3 | 8 | 0 | 8 | ✅ (8) | — | generator |
| 154 | `shenzhen_homa` | 3 | 10 | 0 | 10 | ✅ (10) | — | generator |
| 155 | `multiterm` | 3 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 156 | `saswell` | 3 | 7 | 0 | 2 | 🟡 2/7 | ~1h | generator |
| 157 | `hornbach` | 3 | 14 | 0 | 14 | ✅ (14) | — | generator |
| 158 | `eglo` | 3 | 7 | 0 | 7 | ✅ (7) | — | generator |
| 159 | `essentialb` | 3 | 10 | 0 | 10 | ✅ (10) | — | generator |
| 160 | `siterwell` | 3 | 9 | 0 | 1 | 🟡 1/9 | ~2h | generator |
| 161 | `ynoa` | 3 | 7 | 0 | 7 | ✅ (7) | — | generator |
| 162 | `hej` | 3 | 8 | 0 | 8 | ✅ (8) | — | generator |
| 163 | `ge` | 3 | 9 | 0 | 9 | ✅ (9) | — | generator |
| 164 | `samotech` | 3 | 11 | 0 | 11 | ✅ (11) | — | generator |
| 165 | `envilar` | 3 | 13 | 0 | 12 | 🟡 12/13 | ~1h | generator |
| 166 | `meazon` | 3 | 2 | 0 | 2 | ✅ (2) | — | generator |
| 167 | `nyce` | 2 | 5 | 0 | 5 | ✅ (5) | — | generator |
| 168 | `nedis` | 2 | 1 | 0 | 4 | ✅ (4) | — | generator |
| 169 | `gs` | 2 | 11 | 0 | 11 | ✅ (11) | — | generator |
| 170 | `jethome` | 2 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 171 | `led_trading` | 2 | 4 | 0 | 4 | ✅ (4) | — | generator |
| 172 | `schwaiger` | 2 | 7 | 0 | 7 | ✅ (7) | — | generator |
| 173 | `intuis` | 2 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 174 | `simpla_home` | 2 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 175 | `hzc_electric` | 2 | 6 | 0 | 6 | ✅ (6) | — | generator |
| 176 | `livingwise` | 2 | 6 | 0 | 6 | ✅ (6) | — | generator |
| 177 | `imou` | 2 | 6 | 0 | 6 | ✅ (6) | — | generator |
| 178 | `weten` | 2 | 3 | 0 | 4 | ✅ (4) | — | generator |
| 179 | `zen` | 2 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 180 | `smarli` | 2 | 3 | 0 | 3 | ✅ (3) | — | generator |
| 181 | `purmo` | 2 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 182 | `casaia` | 2 | 4 | 0 | 4 | ✅ (4) | — | generator |
| 183 | `lupus` | 2 | 5 | 0 | 5 | ✅ (5) | — | generator |
| 184 | `msh` | 2 | 3 | 0 | 3 | ✅ (3) | — | generator |
| 185 | `fireangel` | 2 | 2 | 0 | 2 | ✅ (2) | — | generator |
| 186 | `zunzunbee` | 2 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 187 | `woolley` | 2 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 188 | `alecto` | 2 | 2 | 0 | 2 | ✅ (2) | — | generator |
| 189 | `prolight` | 2 | 6 | 0 | 6 | ✅ (6) | — | generator |
| 190 | `frient` | 2 | 5 | 0 | 5 | ✅ (5) | — | generator |
| 191 | `lux` | 2 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 192 | `ihorn` | 2 | 7 | 0 | 7 | ✅ (7) | — | generator |
| 193 | `qoto` | 2 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 194 | `airam` | 2 | 4 | 0 | 4 | ✅ (4) | — | generator |
| 195 | `nordtronic` | 2 | 7 | 0 | 7 | ✅ (7) | — | generator |
| 196 | `waxman` | 2 | 2 | 0 | 1 | 🟡 1/2 | ~1h | generator |
| 197 | `aeotec` | 2 | 4 | 0 | 4 | ✅ (4) | — | generator |
| 198 | `repenic_ltd` | 2 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 199 | `onenuo` | 2 | 1 | 0 | 3 | ✅ (3) | — | generator |
| 200 | `smlight` | 2 | 12 | 0 | 1 | 🟡 1/12 | ~2h | generator |
| 201 | `technicolor` | 2 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 202 | `ecozy` | 2 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 203 | `lutron` | 1 | 2 | 0 | 2 | ✅ (2) | — | generator |
| 204 | `databyte` | 1 | 3 | 0 | 3 | ✅ (3) | — | generator |
| 205 | `evn` | 1 | 3 | 0 | 3 | ✅ (3) | — | generator |
| 206 | `ajax_online` | 1 | 6 | 0 | 6 | ✅ (6) | — | generator |
| 207 | `jxuan` | 1 | 4 | 0 | 4 | ✅ (4) | — | generator |
| 208 | `securifi` | 1 | 2 | 0 | 2 | ✅ (2) | — | generator |
| 209 | `nobo` | 1 | 2 | 0 | 2 | ✅ (2) | — | generator |
| 210 | `airzone_aidoo` | 1 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 211 | `javis` | 1 | 2 | 0 | 2 | ✅ (2) | — | generator |
| 212 | `lightsolutions` | 1 | 7 | 0 | 7 | ✅ (7) | — | generator |
| 213 | `smartenit` | 1 | 2 | 0 | 2 | ✅ (2) | — | generator |
| 214 | `domraem` | 1 | 6 | 0 | 6 | ✅ (6) | — | generator |
| 215 | `somgoms` | 1 | 4 | 0 | 4 | ✅ (4) | — | generator |
| 216 | `calex` | 1 | 3 | 0 | 3 | ✅ (3) | — | generator |
| 217 | `tplink` | 1 | 2 | 0 | 2 | ✅ (2) | — | generator |
| 218 | `blitzwolf` | 1 | 4 | 0 | 4 | ✅ (4) | — | generator |
| 219 | `cleverio` | 1 | 2 | 0 | 2 | ✅ (2) | — | generator |
| 220 | `ITCommander` | 1 | 2 | 0 | 2 | ✅ (2) | — | generator |
| 221 | `letv` | 1 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 222 | `dlink` | 1 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 223 | `ecolink` | 1 | 2 | 0 | 2 | ✅ (2) | — | generator |
| 224 | `automaton` | 1 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 225 | `mill` | 1 | 2 | 0 | 2 | ✅ (2) | — | generator |
| 226 | `akuvox` | 1 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 227 | `qmotion` | 1 | 2 | 0 | 2 | ✅ (2) | — | generator |
| 228 | `edp` | 1 | 2 | 0 | 2 | ✅ (2) | — | generator |
| 229 | `hampton_bay` | 1 | 2 | 0 | 2 | ✅ (2) | — | generator |
| 230 | `netvox` | 1 | 2 | 0 | 2 | ✅ (2) | — | generator |
| 231 | `easyaccess` | 1 | 2 | 0 | 1 | 🟡 1/2 | ~1h | generator |
| 232 | `net2grid` | 1 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 233 | `sikom` | 1 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 234 | `bega` | 1 | 3 | 0 | 2 | 🟡 2/3 | ~1h | generator |
| 235 | `spotmau` | 1 | 4 | 0 | 4 | ✅ (4) | — | generator |
| 236 | `slv` | 1 | 5 | 0 | 5 | ✅ (5) | — | generator |
| 237 | `ysrsai` | 1 | 3 | 0 | 3 | ✅ (3) | — | generator |
| 238 | `frankever` | 1 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 239 | `xenon` | 1 | 1 | 0 | 2 | ✅ (2) | — | generator |
| 240 | `plaid` | 1 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 241 | `danalock` | 1 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 242 | `wally` | 1 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 243 | `blaupunkt` | 1 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 244 | `evanell` | 1 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 245 | `senoro` | 1 | 1 | 0 | 2 | ✅ (2) | — | generator |
| 246 | `evology` | 1 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 247 | `schlage` | 1 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 248 | `espressif` | 1 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 249 | `wmun` | 1 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 250 | `shade_control` | 1 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 251 | `peq` | 1 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 252 | `swann` | 1 | 3 | 0 | 3 | ✅ (3) | — | generator |
| 253 | `aubess` | 1 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 254 | `titan_products` | 1 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 255 | `current_products_corp` | 1 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 256 | `tlwglobal` | 1 | 3 | 0 | 3 | ✅ (3) | — | generator |
| 257 | `smartwings` | 1 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 258 | `tci` | 1 | 4 | 0 | 4 | ✅ (4) | — | generator |
| 259 | `acuity_brands_lighting` | 0 | 3 | 0 | 3 | ✅ (3) | — | generator |
| 260 | `ninja_blocks` | 0 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 261 | `yookee` | 0 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 262 | `axis` | 0 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 263 | `istar` | 0 | 3 | 0 | 3 | ✅ (3) | — | generator |
| 264 | `brun_holding` | 0 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 265 | `uhome` | 0 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 266 | `smart9` | 0 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 267 | `m_elec` | 0 | 4 | 0 | 4 | ✅ (4) | — | generator |
| 268 | `jasco` | 0 | 3 | 0 | 3 | ✅ (3) | — | generator |
| 269 | `wyze` | 0 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 270 | `echostar` | 0 | 2 | 0 | 2 | ✅ (2) | — | generator |
| 271 | `rademacher` | 0 | 3 | 0 | 3 | ✅ (3) | — | generator |
| 272 | `hommyn` | 0 | 2 | 0 | 2 | ✅ (2) | — | generator |
| 273 | `tubeszb` | 0 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 274 | `soanalarm` | 0 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 275 | `iotperfect` | 0 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 276 | `weiser` | 0 | 2 | 0 | 2 | ✅ (2) | — | generator |
| 277 | `vav` | 0 | 2 | 0 | 2 | ✅ (2) | — | generator |
| 278 | `aldi` | 0 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 279 | `xal` | 0 | 3 | 0 | 3 | ✅ (3) | — | generator |
| 280 | `byun` | 0 | 2 | 0 | 2 | ✅ (2) | — | generator |
| 281 | `simon` | 0 | 2 | 0 | 2 | ✅ (2) | — | generator |
| 282 | `chacon` | 0 | 2 | 0 | 2 | ✅ (2) | — | generator |
| 283 | `ilightsin` | 0 | 2 | 0 | 2 | ✅ (2) | — | generator |
| 284 | `homeseer` | 0 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 285 | `lg` | 0 | 3 | 0 | 3 | ✅ (3) | — | generator |
| 286 | `bseed` | 0 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 287 | `novo` | 0 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 288 | `digi` | 0 | 1 | 0 | 0 | ❌ | ~1h |  |
| 289 | `tnce` | 0 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 290 | `girier` | 0 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 291 | `seastar_intelligence` | 0 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 292 | `villeroy_boch` | 0 | 2 | 0 | 2 | ✅ (2) | — | generator |
| 293 | `hilux` | 0 | 2 | 0 | 2 | ✅ (2) | — | generator |
| 294 | `spacetronik` | 0 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 295 | `alchemy` | 0 | 2 | 0 | 2 | ✅ (2) | — | generator |
| 296 | `jiawen` | 0 | 2 | 0 | 2 | ✅ (2) | — | generator |
| 297 | `hoftronic` | 0 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 298 | `tapestry` | 0 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 299 | `smart_home_pty` | 0 | 2 | 0 | 2 | ✅ (2) | — | generator |
| 300 | `lds` | 0 | 2 | 0 | 2 | ✅ (2) | — | generator |
| 301 | `klikaanklikuit` | 0 | 2 | 0 | 2 | ✅ (2) | — | generator |
| 302 | `roome` | 0 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 303 | `quotra` | 0 | 2 | 0 | 2 | ✅ (2) | — | generator |
| 304 | `oujiabao` | 0 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 305 | `shyugj` | 0 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 306 | `scanproducts` | 0 | 2 | 0 | 2 | ✅ (2) | — | generator |
| 307 | `kami` | 0 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 308 | `matcall_bv` | 0 | 2 | 0 | 2 | ✅ (2) | — | generator |
| 309 | `brimate` | 0 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 310 | `dqsmart` | 0 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 311 | `kurvia` | 0 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 312 | `ozsmartthings` | 0 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 313 | `iolloi` | 0 | 2 | 0 | 1 | 🟡 1/2 | ~1h | generator |
| 314 | `philio` | 0 | 2 | 0 | 1 | 🟡 1/2 | ~1h | generator |
| 315 | `commercial_electric` | 0 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 316 | `atsmart` | 0 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 317 | `letsled` | 0 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 318 | `enkin` | 0 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 319 | `sohan_electric` | 0 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 320 | `eatonhalo_led` | 0 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 321 | `heatit` | 0 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 322 | `ezex` | 0 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 323 | `sowilo` | 0 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 324 | `ezviz` | 0 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 325 | `nexelec` | 0 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 326 | `direct_signs` | 0 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 327 | `task_lighting` | 0 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 328 | `tis_control` | 0 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 329 | `tcl` | 0 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 330 | `vrey` | 0 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 331 | `silicon_labs` | 0 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 332 | `gumax` | 0 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 333 | `idinio` | 0 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 334 | `gmy` | 0 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 335 | `gidealed` | 0 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 336 | `bouffalo_lab` | 0 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 337 | `cel` | 0 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 338 | `superled` | 0 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 339 | `zipato` | 0 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 340 | `micromatic` | 0 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 341 | `bubendorff` | 0 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 342 | `cree` | 0 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 343 | `hfh` | 0 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 344 | `jumitech` | 0 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 345 | `soma` | 0 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 346 | `giderwel` | 0 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 347 | `ksentry` | 0 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 348 | `cwd` | 0 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 349 | `raex` | 0 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 350 | `niviss` | 0 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 351 | `cleode` | 0 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 352 | `openlumi` | 0 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 353 | `bankamp` | 0 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 354 | `lanesto` | 0 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 355 | `lubeez` | 0 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 356 | `vbled` | 0 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 357 | `eucontrols` | 0 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 358 | `dowsing_reynolds` | 0 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 359 | `cy_lighting` | 0 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 360 | `zbeacon` | 0 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 361 | `shada` | 0 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 362 | `radium` | 0 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 363 | `solaredge` | 0 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 364 | `ilux` | 0 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 365 | `wisdom` | 0 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 366 | `anchor` | 0 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 367 | `evvr` | 0 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 368 | `nanoleaf` | 0 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 369 | `quirky` | 0 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 370 | `dnake` | 0 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 371 | `modular` | 0 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 372 | `belkin` | 0 | 1 | 0 | 1 | ✅ (1) | — | generator |
| 373 | `xinghuoyuan` | 0 | 1 | 0 | 1 | ✅ (1) | — | generator |

## Suggested batch plan

1. Finish the Tuya/Moes tail by extending the extractor's converter tables.
2. Port the next **quick-bucket** vendor files with the largest device counts — they compound fastest. Innr, ledvance, philips, sengled all dominated by `genOnOff`/`genLevelCtrl`.
3. Aqara ecosystem (`lumi`) has the highest per-device engineering cost; keep porting on demand.
4. Thermostat families (`eurotronic`, `danfoss`, `bosch`, `honeywell`, `stelpro`) last — each needs its own IEEE / manu-specific cluster decoder.
