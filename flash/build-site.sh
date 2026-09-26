#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2025-2026 Evgenij Cjura and project contributors
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Assemble the Pages site into $1 (default _site): the device search page, the
# browser flasher, and for
# every full-flash image found in the latest GitHub release (the `*-ota.bin`
# app-only files are for in-place updates and are skipped), a copy of the image
# plus an ESP Web Tools manifest. Images are copied rather than linked because
# GitHub release downloads send no CORS headers, so a page cannot fetch them
# from another origin. Needs `gh` with a token (GH_TOKEN) that can read the
# public zhac-project repos.
set -euo pipefail
OUT=${1:-_site}
ORG=${ZHAC_ORG:-zhac-project}
HERE=$(cd "$(dirname "$0")" && pwd)

rm -rf "$OUT"
mkdir -p "$OUT/flash/firmware"
cp "$HERE/index.html" "$HERE/zhac-flash.js" "$HERE/../images/s31-board.webp" "$OUT/flash/"
# esptool-js, pinned: the browser flasher imports it from next door, so the
# page depends on nothing at unpkg at run time. A failed download fails the build.
ESPTOOL_JS_VERSION=0.7.0
curl -fsSL "https://unpkg.com/esptool-js@${ESPTOOL_JS_VERSION}/bundle.js" -o "$OUT/flash/esptool-js.bundle.js"
grep -q "ESPLoader" "$OUT/flash/esptool-js.bundle.js" || { echo "esptool-js bundle looks wrong" >&2; exit 1; }
printf '<!doctype html><meta http-equiv="refresh" content="0; url=flash/"><a href="flash/">Flash ZHAC</a>\n' > "$OUT/index.html"
touch "$OUT/.nojekyll"

# Device search page (supported-devices/index.html over the generated devices.json).
mkdir -p "$OUT/devices"
cp "$HERE/../supported-devices/index.html" "$HERE/../supported-devices/devices.json" "$OUT/devices/"

# publish <repo> <file-glob> <chipFamily> <manifest> <name> <improv-wait-s>
# improv-wait-s: how long the installer waits for Improv Wi-Fi after flashing;
# 0 for images that do not speak it, so the dialog does not stall.
publish() {
    local repo=$1 glob=$2 chip=$3 manifest=$4 name=$5 improv=$6 tag dir file
    if ! tag=$(gh release view --repo "$ORG/$repo" --json tagName -q .tagName 2>/dev/null); then
        echo "skip $manifest: $repo has no release"; return 0
    fi
    dir="$OUT/flash/firmware/$repo"
    mkdir -p "$dir"
    if ! gh release download "$tag" --repo "$ORG/$repo" --pattern "$glob" --dir "$dir" --clobber 2>/dev/null; then
        echo "skip $manifest: $repo $tag has no $glob"; return 0
    fi
    file=$(cd "$dir" && ls $glob | head -1)
    cat > "$OUT/flash/$manifest" <<JSON
{
  "name": "$name",
  "version": "$tag",
  "new_install_prompt_erase": true,
  "new_install_improv_wait_time": $improv,
  "builds": [
    { "chipFamily": "$chip", "parts": [ { "path": "firmware/$repo/$file", "offset": 0 } ] }
  ]
}
JSON
    echo "ok   $manifest -> $repo $tag $file"
}

# Parts, not the merged image: the merged file pads the gap between partition
# table and otadata with 0xFF, and that gap is NVS (devices, rules, password,
# settings) -- writing it at 0x0 wiped everything. Four regions, nothing else.
publish_parts() {
    local repo=$1 prefix=$2 chip=$3 manifest=$4 name=$5 tag dir f
    if ! tag=$(gh release view --repo "$ORG/$repo" --json tagName -q .tagName 2>/dev/null); then
        echo "skip $manifest: $repo has no release"; return 0
    fi
    dir="$OUT/flash/firmware/$repo"
    mkdir -p "$dir"
    for f in bootloader partition-table otadata ota; do
        if ! gh release download "$tag" --repo "$ORG/$repo" --pattern "${prefix}-${tag}-${f}.bin" --dir "$dir" --clobber 2>/dev/null; then
            echo "skip $manifest: $repo $tag has no ${prefix}-${tag}-${f}.bin"; return 0
        fi
    done
    cat > "$OUT/flash/$manifest" <<JSON
{
  "name": "$name",
  "version": "$tag",
  "new_install_prompt_erase": true,
  "new_install_improv_wait_time": 0,
  "builds": [
    { "chipFamily": "$chip", "parts": [
        { "path": "firmware/$repo/${prefix}-${tag}-bootloader.bin",      "offset": 8192 },
        { "path": "firmware/$repo/${prefix}-${tag}-partition-table.bin", "offset": 49152 },
        { "path": "firmware/$repo/${prefix}-${tag}-otadata.bin",         "offset": 118784 },
        { "path": "firmware/$repo/${prefix}-${tag}-ota.bin",             "offset": 131072 } ] }
  ]
}
JSON
    echo "ok   $manifest -> $repo $tag (4 parts)"
}
publish_parts zhac-wired-core zhac-wired-s31      ESP32-S31 manifest-wired-s31.json "ZHAC hub (ESP32-S31 Function-CoreBoard)"
publish_parts zhac-wired-core zhac-wired-p4-rev1x ESP32-P4  manifest-wired-p4.json  "ZHAC wired (ESP32-P4, silicon v0.x-v1.x)"
# One-time C6 radio installer for a fresh Guition M3-DEV (no JP1 wiring): OTA-writes
# ot_rcp onto the module's C6 over the SDIO pins it shares with the P4. Merged image,
# offset 0; skipped gracefully if the release predates it (see publish()).
publish zhac-wired-core "zhac-c6-rcp-installer-p4-rev1x-*[0-9].bin" ESP32-P4 manifest-rcp-installer-p4.json "ZHAC Zigbee radio installer (Guition P4, one-time)" 0
publish zhac-wired-core "zhac-rcp-c6-*[0-9].bin"   ESP32-C6 manifest-rcp-c6.json      "ZHAC Zigbee radio (ESP32-C6 ot_rcp)" 0
# The S3 name must equal kImprovFirmware in zhac-net-core/main/wifi_mgr.cpp:
# ESP Web Tools matches them to recognise an installed hub.
publish zhac-platform   "zhac-dualchip-s3-*[0-9].bin" ESP32-S3 manifest-dualchip-s3.json "ZHAC dual-chip S3" 10
publish zhac-platform   "zhac-dualchip-p4-*[0-9].bin" ESP32-P4 manifest-dualchip-p4.json "ZHAC dual-chip P4 (silicon v0.x-v1.x)" 0
