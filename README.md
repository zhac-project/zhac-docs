# zhac-docs

Platform-wide documentation for [ZHAC] — an ESP32 dual-chip Zigbee
Home Automation Controller. Architecture notes, API references,
design plans, reviews, glossary, and similar material that isn't
tied to a single sub-repo.

[ZHAC]: https://github.com/zhac-project/zhac-platform

## What's here

- **Architecture** — how the S3 and P4 cores split responsibilities,
  HAP wire format, SPI framing, shadow persistence, rules/Lua
  integration.
- **API reference** — WebSocket (`/ws`) envelope, push events, full
  command catalogue.
- **Design plans** — markdown specs for features that span multiple
  sub-repos (rich Lua editor, SPA editor chunking, MQTT re-arch,
  ...).
- **Reviews** — historical code reviews + post-mortems.
- **Glossary** — project vocabulary (HAP, ZHC, EZSP, ZNP, exposes,
  TzConverter, ...).

## What's NOT here

Per-module `README.md` and `CHANGELOG.md` stay with their module.
Module-internal notes (e.g. ESP-IDF component wiring, sdkconfig
rationale) stay with the module. If you're looking for
"how does this specific component work", check that component's
source repo first.

## Contributing

This repo is deliberately isolated from the build tree.
Anyone is welcome to open a PR.

1. Read `CLA.md` — signing is one-time across the whole ZHAC
   project.
2. Make your edit. Markdown preferred; prose over diagrams where a
   sentence suffices.
3. `npm run lint` (link-check) locally if you're adding new
   cross-document links — CI runs the same check.
4. Open a PR against `main`.

## License

AGPL-3.0-or-later for the documentation prose + diagrams. See
`LICENSE` and `LICENSES/AGPL-3.0-or-later.txt`. Code snippets
embedded in documentation are licensed under the same terms as the
code they illustrate (Apache-2.0 for `embedded-zhc` examples,
AGPL-3.0-or-later for firmware examples).

## Versioning

Releases tagged `vYYYYMMDDVV`. See the
[zhac-platform](https://github.com/zhac-project/zhac-platform) README
for the scheme. Doc tags often lag behind firmware tags — no
strict coupling required.
