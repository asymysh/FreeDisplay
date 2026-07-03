<div align="center">

# 🖥️ FreeDisplay

**A free & open-source alternative to [BetterDisplay](https://github.com/waydabber/BetterDisplay)** —
all the core display-management features, in your menu bar, at zero cost.

![Platform](https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white)
![Swift](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)
![UI](https://img.shields.io/badge/UI-SwiftUI%20MenuBarExtra-1575F9)
![Deps](https://img.shields.io/badge/dependencies-zero-brightgreen)
![Fork](https://img.shields.io/badge/fork%20of-huberdf%2FFreeDisplay-orange?logo=github)

</div>

> ### 🍴 This is a fork — credit where it's due
> The FreeDisplay app is the work of **[@huberdf](https://github.com/huberdf)**
> ([huberdf/FreeDisplay](https://github.com/huberdf/FreeDisplay)) — **all credit for
> the app, its concept and architecture goes to them.** This fork
> ([asymysh/FreeDisplay](https://github.com/asymysh/FreeDisplay)) adds **DDC volume,
> mute & contrast controls, a native OSD overlay, AMD-Hackintosh DDC support, and a
> no-Xcode build.** See **[NOTICE.md](NOTICE.md)** (attribution & licensing) and
> **[docs/FORK-CHANGES.md](docs/FORK-CHANGES.md)** (exactly what we changed).

BetterDisplay is a great app, but its best features are locked behind a paid Pro
license. FreeDisplay implements the most essential ones as a completely free,
open-source macOS menu-bar app.

---

## ✨ Features

| BetterDisplay feature | FreeDisplay | Notes |
|-----------------------|:-----------:|-------|
| DDC **Brightness & Contrast** | ✅ 🍴 | Hardware control via IOKit I2C (Intel) / IOAVService (Apple Silicon) / AMD registry (Hackintosh). Contrast is a fork addition (VCP `0x12`) |
| DDC **Volume & Mute** 🍴 | ✅ | **Fork addition** — external-display speaker volume/mute via DDC/CI (VCP `0x62` / `0x8D`) |
| **Native OSD overlay** 🍴 | ✅ | **Fork addition** — on-screen brightness/contrast/volume feedback on the adjusted display |
| **Picture-in-Picture** 🍴 | ✅ | **Fork addition (restored)** — floating, corner-pinned, click-through preview of a (virtual) display via ScreenCaptureKit, with **hover-to-enlarge**, a **cursor transparency spotlight**, and a playful **Fun Mode** |
| **High-refresh virtual displays** 🍴 | ✅ | **Fork addition** — create virtual displays at **120 / 144 / 165 Hz**; PiP previews at the display's real refresh rate |
| **Software brightness** (gamma) | ✅ | Per-display gamma table with smooth transitions |
| **Keyboard brightness keys** for external displays | ✅ | Intercepts brightness keys when the cursor is on an external display; shows the native macOS OSD |
| **Auto brightness sync** | ✅ | Syncs external-display brightness with built-in display changes |
| **HiDPI virtual displays** | ✅ | Creates HiDPI dummy displays via the CGVirtualDisplay private API |
| **Display arrangement** | ✅ | Position displays (external above built-in, etc.) |
| **Resolution & HiDPI switching** | ✅ | Browse/switch all modes, including HiDPI |
| **ICC color profiles** | ✅ | Per-display color-profile switching via ColorSync |
| **Image adjustment** | ✅ | Software contrast, temperature, RGB channels, invert |
| **Display presets** | ✅ | Save & restore full configurations in one click |
| **Virtual (dummy) display** | ✅ | Create headless virtual displays |
| **Notch management** | ✅ | Hide the MacBook notch with a black overlay |
| **Launch at login** | ✅ | Via SMAppService |

**🍴 = added or extended by this fork.** Intentionally *not* included: EDID
override (needs SIP off), XDR/HDR extra brightness.

> ### 🧭 Menu layout
> Each display shows a **control card** — brightness · contrast · volume ·
> temperature — with an **Advanced** section (resolution/HiDPI, color profile, image
> adjustment, set-as-main, notch). Below the cards are the global tools: **Presets,
> Arrange Displays, Virtual Displays, Auto-Brightness,** and **Settings**. So every
> feature in the table above is reachable from the menu.

---

## 🍴 What this fork adds

A short summary — full technical write-up in **[docs/FORK-CHANGES.md](docs/FORK-CHANGES.md)**:

- 🔊 **DDC audio volume & mute** for external monitors (VCP `0x62` / `0x8D`)
- 🌗 **DDC contrast** for external monitors (VCP `0x12`)
- 🎚️ **Native OSD overlay** for brightness / contrast / volume changes
- 🧠 **AMD-GPU registry DDC path** + combined/split VCP reads — makes hardware DDC work on **AMD Hackintosh** framebuffers
- 🧩 **`DisplayControlCard`** UI refactor — one throttled slider component for all DDC controls
- 🖼️ **Picture-in-Picture** — floating, corner-pinned, click-through preview via ScreenCaptureKit (restored + re-wired from the original Phase 9), with **hover-to-enlarge**, a **cursor transparency spotlight**, and a playful **Fun Mode**
- ⚡ **High-refresh virtual displays** — 120 / 144 / 165 Hz, with previews at the display's real refresh rate
- 🔏 **Stable self-signed signing** (`set-up-signing.sh`) — grant macOS permissions once; they survive rebuilds
- 🛠️ **No-Xcode build** (`build-local.sh`, ad-hoc signing) — no full Xcode, no Apple Developer account

---

## 📦 Installation

### Build from source — no Xcode required (recommended for Hackintosh)

Only the **Xcode Command Line Tools** are needed (`xcode-select --install`):

```bash
git clone https://github.com/asymysh/FreeDisplay.git
cd FreeDisplay
./build-local.sh install     # builds the .app and copies it to /Applications
```

First launch: right-click the app → **Open** (ad-hoc-signed, one-time approval).

### Build with Xcode

```bash
brew install xcodegen
git clone https://github.com/asymysh/FreeDisplay.git
cd FreeDisplay
xcodegen generate
xcodebuild -scheme FreeDisplay -configuration Release build
```

### Download a DMG

Prebuilt DMGs are published on the original project's
[Releases](https://github.com/huberdf/FreeDisplay/releases/latest) (they won't
include this fork's additions).

---

## 🔐 Permissions

| Permission | Why |
|------------|-----|
| **Accessibility** | Brightness-key interception on external displays |
| **Screen Recording** | Picture-in-Picture live preview (ScreenCaptureKit) |

No internet connection required (except optional GitHub-Releases update checks).

> ### 🔏 Make permissions stick across rebuilds (recommended for local builds)
> By default `build-local.sh` **ad-hoc-signs** the app. Ad-hoc signatures have no stable
> identity — the code hash changes on every build — so macOS **forgets every permission
> you grant** after each rebuild (the classic "I already granted Screen Recording but it
> keeps asking / fails" problem).
>
> Run the one-time setup to create a **stable self-signed identity**:
> ```bash
> ./set-up-signing.sh          # once — creates a persistent code-signing cert
> ./build-local.sh install     # now signs with it; the app's requirement is stable
> ```
> After this, grant **Screen Recording** (and **Accessibility**) **once** — they persist
> across all future rebuilds. It's self-signed and untrusted for Gatekeeper (harmless for
> a locally-built app), and weakens no system security: TCC matches on the code
> requirement, not on a trusted chain.

---

## 🧱 Tech stack

- **Swift 6** + **SwiftUI** (`MenuBarExtra`) — built in Swift-5 language mode (see [FORK-CHANGES](docs/FORK-CHANGES.md) for why)
- **IOKit** — DDC/CI I2C for hardware brightness / contrast / volume
- **CoreGraphics** — display enumeration, resolution, arrangement, gamma
- **ColorSync** — ICC color-profile management
- **CGVirtualDisplay** — virtual display creation (private API, macOS 14+)
- **CoreDisplay** — built-in brightness reading (private API, via `dlopen`)
- **Zero third-party dependencies**

---

## 🗺️ How it works

FreeDisplay sits in your menu bar and talks directly to your displays:

- **External monitors** → DDC/CI over I2C (Intel) / IOAVService (Apple Silicon) / AMD registry (Hackintosh) for hardware brightness, contrast, and volume.
- **Built-in display** → CoreGraphics gamma tables for software brightness.
- **Brightness keys** → a `CGEventTap` intercepts the keys and routes them to the display under the cursor, with a native OSD.
- **HiDPI** → virtual displays via the CGVirtualDisplay private API.

Full detail in **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)**.

---

## 📚 Documentation

| Doc | What's in it |
|-----|--------------|
| **[NOTICE.md](NOTICE.md)** | Attribution & licensing (fork vs. original) |
| **[docs/FORK-CHANGES.md](docs/FORK-CHANGES.md)** | Exactly what this fork changed, in detail |
| **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** | Full app architecture (services, DDC engine, private APIs) |
| **[CHANGELOG.md](CHANGELOG.md)** | Version history (fork + original) |
| **[docs/codemap/](docs/codemap/)** · **[docs/lessons/](docs/lessons/)** · **[docs/roadmap/](docs/roadmap/)** | Original author's code map, engineering lessons, and phase roadmap |

---

## 🤝 Contributing

- `xcodegen` for project generation — edit **`project.yml`**, not the `.xcodeproj`.
- Swift 6 with `SWIFT_STRICT_CONCURRENCY: minimal`.
- MVVM-ish flow: **View → Service**.
- For upstream issues/PRs, prefer the [original repo](https://github.com/huberdf/FreeDisplay).

---

## 📄 License & attribution

- **Fork additions** (the files listed in [NOTICE.md](NOTICE.md)) are © 2026 asymysh under the **MIT License** — see **[LICENSE](LICENSE)**.
- **The original FreeDisplay code is © [huberdf](https://github.com/huberdf).** The upstream repo carries **no license**, so its code is not relicensed here. Please read **[NOTICE.md](NOTICE.md)** before redistributing.

---

## 🙏 Acknowledgments

- **[@huberdf](https://github.com/huberdf)** — original author of FreeDisplay; this fork is built entirely on their work.
- **[MonitorControl](https://github.com/MonitorControl/MonitorControl)** — DDC/CI VCP-code reference.
- **[BetterDisplay](https://github.com/waydabber/BetterDisplay)** & **[Lunar](https://lunar.fyi/)** — inspiration.
- **[Chromium `virtual_display_mac_util.mm`](https://chromium.googlesource.com/chromium/src/+/main/ui/display/mac/test/virtual_display_mac_util.mm)** — basis for the CGVirtualDisplay bridging.
