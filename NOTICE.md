# NOTICE & Attribution

FreeDisplay (this repository) is a **fork** of the original project by
**[@huberdf](https://github.com/huberdf)**:

> **Upstream:** https://github.com/huberdf/FreeDisplay

**All credit for the FreeDisplay application — its concept, architecture, and the
overwhelming majority of its code — belongs to the original author, huberdf**
(commits authored as `mac-jm`). This fork stands entirely on their work.

---

## ⚠️ Licensing status (please read)

At the time this fork was created, the **upstream repository carried no license
file**. Under default copyright law that means the original code is **"all rights
reserved" by its author** — it is not, strictly speaking, open source, despite the
project describing itself as a "free & open-source alternative."

Consequences and our position:

- We do **not** claim ownership of the original code, and we do **not** relicense
  it. Its copyright remains with **huberdf**.
- The `LICENSE` file in this repository (**MIT**) applies **only to the Fork
  Additions listed below** — the new code contributed by this fork.
- This fork is maintained for **personal use** (an AMD Hackintosh setup). If you
  intend to redistribute FreeDisplay, please seek clarity on the upstream license
  first.
- **Recommendation:** the upstream project would benefit from adding an explicit
  open-source license (e.g. MIT/GPLv3) so its "open-source" description is
  unambiguous. Consider opening an issue upstream to request one.

---

## Fork Additions (© 2026 asymysh, MIT — see LICENSE)

Only the following are contributed by this fork and covered by our MIT `LICENSE`.
Full technical detail: [`docs/FORK-CHANGES.md`](docs/FORK-CHANGES.md).

**New files**

| File | What it adds |
|------|--------------|
| `FreeDisplay/Services/VolumeService.swift` | External-display speaker volume/mute over DDC/CI (VCP `0x62` / `0x8D`) |
| `FreeDisplay/Views/VolumeSliderView.swift` | Volume slider + mute UI |
| `FreeDisplay/Services/ContrastService.swift` | External-display contrast over DDC/CI (VCP `0x12`) |
| `FreeDisplay/Services/OSDService.swift` | Native on-screen-display overlay for brightness/contrast/volume |
| `FreeDisplay/Views/DisplayControlCard.swift` | Reusable per-display control card (`DDCSliderRow`) with throttled DDC updates |
| `build-local.sh` | No-Xcode build (Command Line Tools only) for AMD Hackintosh / no-Developer-account setups |

**Modified upstream files** (fork changes layered on huberdf's originals)

`FreeDisplay/Services/DDCService.swift` (AMD-GPU registry DDC read/write path +
combined/split VCP read strategies), `FreeDisplay/Models/DisplayInfo.swift`
(contrast/volume model fields), `FreeDisplay/App/AppDelegate.swift` +
`FreeDisplay/App/FreeDisplayApp.swift` (OSD wiring), `FreeDisplay/Views/MenuBarView.swift`
(refactor onto `DisplayControlCard`), `FreeDisplay/Services/DDCService.swift`,
`FreeDisplay/Views/DisplayDetailView.swift`, `project.yml` (ad-hoc signing).

Fork commits: `e0ff910` (audio + no-Xcode build), `a65c9b8` (contrast, OSD,
DisplayControlCard, AMD DDC).

---

## Third-party references & inspiration

- **[BetterDisplay](https://github.com/waydabber/BetterDisplay)** — the paid app this project offers a free alternative to.
- **[MonitorControl](https://github.com/MonitorControl/MonitorControl)** — DDC/CI VCP code reference (volume/mute/contrast cross-checked against it).
- **[Lunar](https://lunar.fyi/)** — inspiration for display-control UX.
- **[Chromium `virtual_display_mac_util.mm`](https://chromium.googlesource.com/chromium/src/+/main/ui/display/mac/test/virtual_display_mac_util.mm)** — basis for the CGVirtualDisplay bridging.
