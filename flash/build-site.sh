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
cp "$HERE/index.html" "$HERE/zhac-flash.js" "$OUT/flash/"
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

publish zhac-wired-core "zhac-wired-s31-*[0-9].bin" ESP32-S31 manifest-wired-s31.json "ZHAC hub (ESP32-S31 Function-CoreBoard)" 0
publish zhac-wired-core "zhac-wired-p4-*[0-9].bin" ESP32-P4 manifest-wired-p4.json    "ZHAC wired (ESP32-P4, silicon v0.x-v1.x)" 0
publish zhac-wired-core "zhac-rcp-c6-*[0-9].bin"   ESP32-C6 manifest-rcp-c6.json      "ZHAC Zigbee radio (ESP32-C6 ot_rcp)" 0
# The S3 name must equal kImprovFirmware in zhac-net-core/main/wifi_mgr.cpp:
# ESP Web Tools matches them to recognise an installed hub.
publish zhac-platform   "zhac-dualchip-s3-*[0-9].bin" ESP32-S3 manifest-dualchip-s3.json "ZHAC dual-chip S3" 10
publish zhac-platform   "zhac-dualchip-p4-*[0-9].bin" ESP32-P4 manifest-dualchip-p4.json "ZHAC dual-chip P4 (silicon v0.x-v1.x)" 0
