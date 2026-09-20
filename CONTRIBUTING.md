# Contributing to zhac-docs

Thanks for helping keep the ZHAC documentation accurate and
readable. This repo holds platform-wide docs — architecture, API
reference, design plans, reviews, glossary. Per-module READMEs and
CHANGELOGs stay with their respective modules.

## License and CLA

Licensed under **AGPL-3.0-or-later**. All contributions require
signing `CLA.md`. See `CONTRIBUTORS.md` for the signup mechanism —
signing once anywhere in the ZHAC project (in any repo) covers you
for all contributions to every repo.

## Workflow

1. Clone: `git clone https://github.com/zhac-project/zhac-docs.git`
2. Make your edit.
3. Run link check: `npm run lint` (or the GitHub Actions job will
   do it on your PR).
4. Open a PR against `main`.

No ESP-IDF or hardware required to contribute here — just a text
editor.

## Contributing to the firmware and web UI without a hub

Most of ZHAC can be worked on and checked with nothing but a laptop:

- **Web UI** (`www-spa`): `npm install`, then `npm run demo` starts a fake hub with six
  devices, rules and scripts on `http://localhost:8080`; `npm run dev` serves the UI against
  it. `npm test` runs the pure-logic tests (release picker, recipes, backup preview). The demo
  hub has switches for the awkward states: `DEMO_CLOCK_UNSET`, `DEMO_AUTH=setup|closed`,
  `DEMO_OTA_PENDING`, `DEMO_JOIN=unsupported|none`, `DEMO_RADIO_DOWN` (see the top of
  `tools/demo-server.mjs`).
- **Shared components** (`zhac-components`): the rule engine, HAP codec, event bus and others
  have host tests under `components/<name>/test/host/` — `cmake -B build -S . && cmake --build
  build && ctest --test-dir build`, plain g++, no ESP-IDF.
- **Device library** (`embedded-zhc`): `cmake -B build && cmake --build build && ctest
  --test-dir build` runs the parity suite (366 tests). `tests/README.md` has the six-step recipe
  for pinning a device's behaviour with a fixture, and every test runs without a radio.
- **A device definition change**: the files under `definitions/<vendor>/generated/` are
  produced by a private generator and are not edited by hand. To fix a device, add a
  hand-written definition next to them (a `kDef_*` in `definitions/<vendor>/`), point the
  vendor's `registry.cpp` at it, and pin the behaviour with a fixture test from the recipe
  above. A pull request with the definition, the fixture and the device's model and
  manufacturer strings is complete; the maintainer checks it on hardware.
- **Documentation** (this repository): as above, a text editor.

What does need a hub: anything Zigbee on the air (pairing, reports, writes) and the update
and sign-in paths on real boards. Say in the pull request what you could and could not run.

## Style

- **Markdown-first.** Keep plain prose that renders cleanly on
  GitHub's web viewer. Avoid HTML unless markdown genuinely can't
  express what you need.
- **Short sentences.** Technical clarity beats literary flair.
- **Code snippets must be valid.** If you show a build command or
  a YAML manifest, make it real — reviewers will paste it and run
  it.
- **Diagrams in ASCII where possible.** Tree diagrams, sequence
  arrows, simple state machines all work fine with `dot`-style
  ASCII. For serious architecture diagrams, check in the source
  (mermaid, plantuml) alongside the rendered PNG/SVG.

## What belongs here vs in a module README

| Topic | Here | Module README |
|-------|------|---------------|
| "How does attribute write propagate from UI → S3 → P4 → Zigbee" | ✅ | — |
| "What does `simple_rules::eval_trigger` do internally" | — | ✅ (zhac-net-core) |
| "WS API command list" | ✅ | — |
| "How to configure the P4 Kconfig for ZNP vs EZSP" | — | ✅ (zhac-main-core) |
| "Release process + version tag scheme" | ✅ | — |
| "Change log entry for `v2026042302`" | — | ✅ CHANGELOG.md per repo |

If unsure, open an issue here first.

## SPDX headers

For new prose files (`.md`):

```markdown
<!--
SPDX-FileCopyrightText: 2025-2026 Evgenij Cjura and project contributors
SPDX-License-Identifier: AGPL-3.0-or-later
-->
```

For doc-support scripts (link-checker, toc-generator, etc.):

```python
# SPDX-FileCopyrightText: 2025-2026 Evgenij Cjura and project contributors
# SPDX-License-Identifier: AGPL-3.0-or-later
```

## Reporting errors

Open an issue with:
- Which document
- Which paragraph / section
- What's wrong (stale info, broken link, ambiguous wording)
- Ideally: a proposed fix (PR welcome directly)
