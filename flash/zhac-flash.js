// SPDX-FileCopyrightText: 2025-2026 Evgenij Cjura and project contributors
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// <zhac-install-button manifest="manifest-x.json"> — flash a ZHAC image from
// the browser over Web Serial, straight on esptool-js.
//
// Why not ESP Web Tools: its published bundle carries esptool-js 0.6, which
// does not know the ESP32-S31, and the S31 board is the one we point people
// at. esptool-js 0.7.0 has the S31 target. The manifest format is ESP Web
// Tools' (name, version, new_install_prompt_erase, builds[{chipFamily,
// parts[{path, offset}]}]), so switching back later costs nothing.
//
// Flow: click -> pick the serial port -> connect and detect the chip -> pick
// the build whose chipFamily matches -> download its parts -> (erase) ->
// write -> reset. Everything the user needs to know is rendered inline.

import { ESPLoader, Transport } from "esptool-js";

const STYLE = `
  :host { display:block; margin:12px 0; }
  button { font:inherit; font-weight:600; padding:10px 18px; border-radius:8px; border:0;
           background:var(--accent, #1f6fd1); color:#fff; cursor:pointer; }
  button[disabled] { opacity:.55; cursor:default; }
  label { display:block; margin:8px 0 0; font-size:.95em; }
  progress { width:100%; height:10px; margin:10px 0 4px; }
  .status { font-size:.95em; margin:6px 0 0; }
  .err { color:#b42318; }
  .ok { color:#0f7b3e; }
  .log { font:12px/1.4 ui-monospace, monospace; background:rgba(127,127,127,.12);
         border-radius:6px; padding:8px; max-height:140px; overflow:auto; white-space:pre-wrap; margin-top:8px; }
`;

class ZhacInstallButton extends HTMLElement {
  constructor() {
    super();
    this.attachShadow({ mode: "open" });
    this.shadowRoot.innerHTML = `<style>${STYLE}</style>
      <button part="button">Install</button>
      <label><input type="checkbox" class="erase"> Erase the whole flash first (first install, or to start over; keeps nothing)</label>
      <progress max="100" value="0" hidden></progress>
      <p class="status"></p>
      <pre class="log" hidden></pre>`;
    this.$ = (s) => this.shadowRoot.querySelector(s);
  }

  connectedCallback() {
    const btn = this.$("button");
    btn.textContent = this.getAttribute("label") || "Install";
    if (!("serial" in navigator)) {
      btn.disabled = true;
      this.say("Your browser has no Web Serial. Use Chrome or Edge on a desktop (not iOS).", "err");
      return;
    }
    btn.addEventListener("click", () => this.run());
  }

  say(text, cls = "") { const s = this.$(".status"); s.textContent = text; s.className = "status " + cls; }
  log(line) { const l = this.$(".log"); l.hidden = false; l.textContent += line + "\n"; l.scrollTop = l.scrollHeight; }

  async run() {
    const btn = this.$("button"), bar = this.$("progress");
    btn.disabled = true; bar.hidden = true; bar.value = 0; this.$(".log").textContent = "";
    let transport = null;
    try {
      const manifest = await (await fetch(this.getAttribute("manifest"), { cache: "no-store" })).json();
      if (manifest.new_install_prompt_erase === false) this.$("label").hidden = true;

      this.say("Choose the board's serial port…");
      const port = await navigator.serial.requestPort();
      transport = new Transport(port, false);
      const loader = new ESPLoader({
        transport, baudrate: 921600, romBaudrate: 115200,
        terminal: { clean: () => {}, writeLine: (t) => this.log(t), write: (t) => this.log(t) },
      });

      this.say("Connecting… (if nothing happens, hold BOOT, tap RESET, release BOOT, then retry)");
      const chip = await loader.main();
      this.log(`chip: ${chip}`);
      const build = manifest.builds.find((b) => chip.startsWith(b.chipFamily));
      if (!build) throw new Error(`This image is for ${manifest.builds.map((b) => b.chipFamily).join(" / ")}, but the connected chip is ${chip}.`);

      this.say(`Downloading ${manifest.name} ${manifest.version}…`);
      const fileArray = [];
      for (const part of build.parts) {
        const r = await fetch(new URL(part.path, this.getAttribute("manifest")), { cache: "no-store" });
        if (!r.ok) throw new Error(`Could not download ${part.path} (${r.status}).`);
        fileArray.push({ data: new Uint8Array(await r.arrayBuffer()), address: part.offset });
      }

      const eraseAll = this.$(".erase").checked;
      bar.hidden = false;
      this.say(eraseAll ? "Erasing, then writing…" : "Writing…");
      await loader.writeFlash({
        fileArray, flashSize: "keep", flashMode: "keep", flashFreq: "keep",
        eraseAll, compress: true,
        reportProgress: (i, written, total) => { bar.value = Math.round((written / total) * 100); },
      });
      bar.value = 100;
      try { await loader.hardReset(); } catch (_) { /* some bridges cannot pulse reset: press RESET */ }
      this.say(`Done: ${manifest.name} ${manifest.version} is on the board. It is rebooting now.`, "ok");
    } catch (e) {
      this.log(String(e && e.stack ? e.stack : e));
      this.say((e && e.message) || String(e), "err");
    } finally {
      try { if (transport) await transport.disconnect(); } catch (_) {}
      btn.disabled = false;
    }
  }
}

customElements.define("zhac-install-button", ZhacInstallButton);
