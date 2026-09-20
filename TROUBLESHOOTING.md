<!--
SPDX-FileCopyrightText: 2025-2026 Evgenij Cjura and project contributors
SPDX-License-Identifier: AGPL-3.0-or-later
-->

# Troubleshooting

One page for the things that go wrong on a hub in a home. Each entry says what you see, why,
and the one thing to do next. When a step says "Info" or "Log", that is a page in the hub's
web UI. If a fix here does not work, [open a bug](https://github.com/zhac-project/zhac-platform/issues/new?template=bug.yml)
and paste the relevant Log lines; the Log never contains your password or API token.

## I cannot find the hub

**`http://zhac.local` does not load.** Some Android phones and older Windows PCs do not resolve
`.local` names. Open your router's client list and look for a device called **zhac**; open
its address (for example `http://192.168.1.47`). Bookmark that address.

**Two hubs, or a hub that was replaced.** Every hub calls itself `zhac`, so with two on one
network the name may point at either. Use the address from the router's list, and give each
hub a different name under Settings → Network (hostname) so the router shows which is which.

**The page loads but stays empty.** The browser reached the hub but the WebSocket did not
connect. Reload once. If it stays empty, another browser may be signed in with an old
password: sign out there, or open Settings → Auth on a browser that works and rotate the
token.

## Set-up and passwords

**"Set-up window closed."** A hub with no password only lets one be set in the first ten
minutes after power-on, so a hub nobody claimed cannot be taken by whoever finds it later.
Unplug the hub, wait a few seconds, plug it back in, wait half a minute, then reload and set
the password within ten minutes.

**"The hub's sign-in storage is not readable."** The flash area that holds the password
could not be opened when the hub started. The hub locks itself rather than opening up:
connect USB, read the token it prints on the serial console at that boot, sign in with *Use
API token instead*, then reset storage from Settings and set the password again. Restore a
backup afterwards for names, rules and scripts.

**I forgot the password.** Connect a USB cable to the hub and open its serial console at
115200 baud (the browser flasher has a *Logs* button that does this). At every boot the hub
prints its API token. On the login page choose *Use API token instead*, paste it, then set a
new password under Settings → Auth. Only someone with physical access to the hub can do this.

**"Wrong password" five times.** That address is locked out for the rest of the minute. Wait a
minute; the lock is per device, so a phone and a laptop lock separately.

## Pairing devices

**"The Zigbee radio is not running."** Nothing can pair or report until it runs. Restart the
hub. If the message comes back, the radio has no firmware yet: on the ESP32-P4 board the
ESP32-C6 must be flashed once through its own header, see the wired hub's README, *Zigbee
radio*. Info shows the radio's last error; `radio_crashed` after a firmware update means the
radio image and the hub firmware do not match, so flash the radio image from the same release.

**Nothing appears after "Add a device".** Hold the device's reset button until its light
blinks fast; that clears the network it was on before (a device that thinks it is still paired
elsewhere never looks for a new hub). Bring it within a few metres of the hub for pairing; it
can go back afterwards. Then press *Retry*.

**It joined but stays at "reading what it is…".** Battery devices sleep between reports, so
the hub cannot ask them questions. Press the device's button once to wake it. If it stays
silent for a minute, move it closer and re-pair.

**"No definition for what it reports."** The device joined and works as a radio, but the hub
does not know how to read it. It stays paired and does nothing yet. Open a
[device request](https://github.com/zhac-project/zhac-platform/issues/new?template=device-request.yml)
with the two values the panel shows (model and manufacturer); a definition is usually a small
change.

**Values stop updating for one device.** Its "last seen" on the Devices page says when it last
spoke. A battery device that has been silent for hours is either out of range (the LQI column
was low) or out of battery. Mains devices that go silent after a router reboot usually come
back within a few minutes; if not, power-cycle the device.

## Time and schedules

**"The hub's clock is not set yet."** No ZHAC board has a battery-backed clock. After every
power cut the hub asks the router for a time server and, failing that, the internet; on a
network without internet access whose router serves no time, it cannot. Either name a time
server on your own network under Settings → Time (many routers serve one; enter the router's
address), or open the web UI: the browser hands over its clock.
Until the clock is set, "last seen" shows "—" and scheduled rules wait; everything else works.

**A scheduled rule fires at the wrong hour.** Set the time zone under Settings → System. The
clock itself is always UTC; rules use the zone.

## Updates

**"The new firmware is on trial."** After an update the hub keeps the new firmware only once
its storage, web server and radio check out. That takes under a minute on a healthy hub. Wait;
do not start another update meanwhile.

**"The last update was undone."** The new firmware never became healthy within ten minutes,
so the hub went back to the previous version by itself. The reason on the OTA page says which
check failed. *Zigbee radio not ready* after an update means the radio image needs updating
from the same release first. Try the update again once that is done; if it comes back, open a
bug with the reason.

**"Could not reach GitHub from this browser."** The OTA page lists versions by reading
GitHub from your browser. On a network without internet access it cannot, and the hub could not
download the file either. Download the `-ota.bin` from the releases page on another device,
host it on your own network, and use *Advanced: install from a URL*.

**Is the update genuine?** The hub fetches over HTTPS with the server's certificate checked, so
what arrives is what GitHub serves. `SHA256SUMS` in the release lets you check a hand-downloaded
file; `sources-<tag>.txt` names the commits it was built from. Images are not signed, so only
install from the OTA page's list or the project's own releases page: an image from elsewhere
runs with the hub's full access.

**The update failed while downloading.** Power loss or a dropped connection during the download
leaves the hub on the old firmware: the new one is written to a spare slot and only used once
complete. Just start the update again.

**The hub does not come back after an update.** Wait two full minutes: the hub reboots once
into the new firmware and, if that fails, once more into the old one. If it is still not
reachable, connect USB and check the serial console; the browser flasher can write a full
image, which keeps devices, rules and settings as long as you do not erase the flash.

## Backups

**What a backup contains.** Device names, rules, scripts, collections and their members. Save
one under Settings → Backup after you finish setting up, and again after big changes.

**What it does not contain.** The Zigbee network itself (its keys and the devices' membership),
the admin password and the API token, and the Wi-Fi password on a Wi-Fi hub. So:

- **Same hub, fresh flash** (you erased it): restore the backup, then pair every device again.
  Names and rules attach by device address, so they come back as soon as each device rejoins.
- **Replacement hub**: the same. There is no seamless move of a Zigbee network between hubs.
- **Ordinary firmware update**: nothing to do; everything above stays.

## Where the details are

- [FIRST_20_MINUTES.md](FIRST_20_MINUTES.md) — the set-up path this page assumes.
- [RULES_DSL.md](RULES_DSL.md) — every trigger and action a rule can use.
- [HOME_ASSISTANT.md](HOME_ASSISTANT.md) — MQTT discovery and its own troubleshooting.
- [REST_API.md](REST_API.md) — the status fields mentioned above (`clock_set`, `ota_state`,
  `ota_rollback_reason`, `auth_setup_secs_left`, `radio_error`).
