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
