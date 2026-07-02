# 📚 FreeDisplay Documentation

Everything is linked from here. Start with the top section; the rest is the
original author's engineering documentation, preserved and attributed.

---

## Start here

| Doc | What it's for |
|-----|---------------|
| [**ARCHITECTURE.md**](ARCHITECTURE.md) | How the whole app works — services, the DDC engine, private APIs, data flow. Read this first to understand the codebase. |
| [**FORK-CHANGES.md**](FORK-CHANGES.md) | 🍴 Exactly what this fork ([asymysh](https://github.com/asymysh)) adds on top of the original — volume, contrast, OSD, AMD DDC, no-Xcode build. |
| [**../NOTICE.md**](../NOTICE.md) | Attribution & licensing (fork vs. original by [huberdf](https://github.com/huberdf)). |
| [**../CHANGELOG.md**](../CHANGELOG.md) | Version history. |
| [**../README.md**](../README.md) | Project overview, features, install. |

---

## Original author's docs (huberdf) — preserved & attributed

These document the original app and its AI-assisted, phase-based development
workflow. They belong to the original author; kept here for completeness.

### Code map
- [`codemap/file-tree.md`](codemap/file-tree.md) — annotated file tree
- [`codemap/relationships.md`](codemap/relationships.md) — how components relate
- [`codemap/CLAUDE.md`](codemap/CLAUDE.md) — code-map notes

### Engineering lessons
- [`lessons/iokit.md`](lessons/iokit.md) — IOKit / DDC gotchas
- [`lessons/coregraphics.md`](lessons/coregraphics.md) — CoreGraphics display APIs
- [`lessons/services.md`](lessons/services.md) — service-layer patterns
- [`lessons/swiftui.md`](lessons/swiftui.md) — SwiftUI menu-bar patterns
- [`lessons/build.md`](lessons/build.md) — build notes

### Roadmap
- [`ROADMAP.md`](ROADMAP.md) — roadmap index
- [`roadmap/phase-18.md`](roadmap/phase-18.md) … [`phase-22.md`](roadmap/phase-22.md) — active/recent phases
- [`roadmap/archive/`](roadmap/archive/) — completed phases 0–17

### Process
- [`habits.md`](habits.md) · [`BLOCKING.md`](BLOCKING.md) — the original author's autopilot workflow notes
