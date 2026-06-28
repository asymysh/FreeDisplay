# FreeDisplay

> **Free & open-source alternative to [BetterDisplay](https://github.com/waydabber/BetterDisplay)** — all the core display management features, zero cost.

> 🍴 **This is a fork** of the original [**huberdf/FreeDisplay**](https://github.com/huberdf/FreeDisplay) by [@huberdf](https://github.com/huberdf) — all credit for the app goes to the original author. This fork adds **DDC audio volume & mute control** for external displays plus a no-Xcode local build for AMD Hackintosh setups. See [Fork Additions](#-fork-additions) below.

BetterDisplay is a great app, but its best features are locked behind a paid Pro license. FreeDisplay implements the most essential BetterDisplay features as a completely free, open-source macOS menu bar app.

[Download Latest Release](https://github.com/huberdf/FreeDisplay/releases/latest) | [Report an Issue](https://github.com/huberdf/FreeDisplay/issues)

---

## What BetterDisplay Features Does This Replace?

| BetterDisplay Feature | FreeDisplay | Notes |
|----------------------|:-----------:|-------|
| DDC Brightness & Contrast | ✅ | Hardware control via IOKit I2C (Intel) / IOAVService (Apple Silicon) |
| DDC Volume & Mute 🍴 | ✅ | **Fork addition** — external-display speaker volume/mute via DDC/CI (VCP `0x62` / `0x8D`) |
| Software Brightness (Gamma) | ✅ | Per-display gamma table control with smooth transitions |
| Keyboard Brightness Keys for External Displays | ✅ | Intercepts brightness keys when cursor is on external display, shows native macOS OSD |
| Auto Brightness Sync | ✅ | Syncs external display brightness with built-in display changes |
| HiDPI Virtual Displays | ✅ | Creates HiDPI dummy displays via CGVirtualDisplay private API |
| Display Arrangement | ✅ | Position displays (external above built-in, etc.) |
| Resolution & HiDPI Switching | ✅ | Browse and switch all available display modes including HiDPI |
| ICC Color Profile Management | ✅ | Switch color profiles per display via ColorSync |
| Image Adjustment (Gamma/Temperature) | ✅ | Software contrast, color temperature, RGB channels, invert |
| Display Presets | ✅ | Save & restore full display configurations with one click |
| Virtual Display (Dummy) | ✅ | Create headless virtual displays |
| Notch Management | ✅ | Hide the MacBook notch with a black overlay |
| Launch at Login | ✅ | Via SMAppService |

### Not Included (intentionally)

- Screen streaming / PiP — rarely used, adds complexity
- EDID override — requires SIP disabled
- XDR/HDR extra brightness — requires specific hardware

---

## 🍴 Fork Additions

Everything below is added by this fork on top of [@huberdf](https://github.com/huberdf)'s original work:

### DDC Audio Volume & Mute Control

Control your **external monitor's built-in speaker volume** directly from the menu bar — the same DDC/CI channel BetterDisplay's paid volume control uses.

- **Volume slider + mute button** under each external display's panel (`Views/VolumeSliderView.swift`)
- Driven by `Services/VolumeService.swift` over standard DDC/CI VCP codes:
  - `0x62` — Audio Speaker Volume
  - `0x8D` — Audio Mute (`1` = mute, `2` = unmute)
- Reuses the existing `DDCService` I2C/IOAVService engine, so it works on both Intel and Apple Silicon
- **Graceful degradation**: monitors that don't report audio support over DDC show a "not supported" hint instead of a dead slider (volume has no software fallback)

### No-Xcode Local Build (AMD Hackintosh friendly)

- `build-local.sh` — builds the full `.app` with just the **Command Line Tools** (no full Xcode, `xcodegen`, or `actool` required), using `swiftc` + `iconutil` + ad-hoc `codesign`
- `project.yml` switched to **ad-hoc signing** (no Apple Developer account / team required)
- The existing DDC engine already iterates all 8 I2C buses, which works well with AMD GPU framebuffers on Hackintosh

```bash
git clone https://github.com/asymysh/FreeDisplay.git
cd FreeDisplay
./build-local.sh install   # builds and copies to /Applications
```

---

## Screenshots

*Coming soon*

---

## Installation

### Option 1: Download DMG

1. Download `FreeDisplay.dmg` from [Releases](https://github.com/huberdf/FreeDisplay/releases/latest)
2. Open the DMG and drag **FreeDisplay.app** to **Applications**
3. First launch: right-click → **Open** (unsigned app, one-time approval)

### Option 2: Build from Source

```bash
brew install xcodegen
git clone https://github.com/huberdf/FreeDisplay.git
cd FreeDisplay
xcodegen generate
xcodebuild -scheme FreeDisplay -configuration Release build
```

---

## Permissions

| Permission | Why |
|------------|-----|
| **Accessibility** | Required for brightness key interception on external displays |

No internet connection required (except optional update checks via GitHub Releases API).

---

## Tech Stack

- **Swift 6** + **SwiftUI** (MenuBarExtra)
- **IOKit** — DDC/CI I2C for hardware brightness/contrast
- **CoreGraphics** — Display enumeration, resolution, arrangement
- **ColorSync** — ICC color profile management
- **CGVirtualDisplay** — Virtual display creation (private API, macOS 14+)
- **CoreDisplay** — Built-in display brightness reading (private API, via dlopen)
- Zero third-party dependencies

---

## Project Structure

```
FreeDisplay/
├── App/              # AppDelegate, app entry point
├── Models/           # DisplayInfo, DisplayMode, DisplayPreset
├── Services/         # System-level services (DDC, brightness, resolution, gamma, etc.)
└── Views/            # SwiftUI views for each feature section
```

---

## How It Works

FreeDisplay sits in your menu bar and talks directly to your displays:

- **External monitors**: Uses DDC/CI protocol over I2C (Intel) or IOAVService (Apple Silicon) to control hardware brightness, contrast, and other settings
- **Built-in display**: Uses CoreGraphics gamma tables for software brightness adjustment
- **Brightness keys**: Installs a CGEventTap to intercept keyboard brightness keys and route them to the display under your mouse cursor
- **Auto brightness**: Polls the built-in display brightness via CoreDisplay private API and proportionally adjusts external displays
- **HiDPI**: Creates virtual displays via CGVirtualDisplay private API, or writes display override plists for persistent HiDPI

---

## Contributing

Issues and PRs welcome. This project uses:
- `xcodegen` for project generation (edit `project.yml`, not `.xcodeproj`)
- Swift 6 with `SWIFT_STRICT_CONCURRENCY: minimal`
- MVVM architecture (View → ViewModel → Service)

---

## License

MIT License — see [LICENSE](LICENSE) for details.

---

## Acknowledgments

- **Original author**: [@huberdf](https://github.com/huberdf) — this fork is built entirely on top of [huberdf/FreeDisplay](https://github.com/huberdf/FreeDisplay). All credit for the app and its architecture goes to them.
- Volume/mute VCP code reference cross-checked against [MonitorControl](https://github.com/MonitorControl/MonitorControl)
- Inspired by [BetterDisplay](https://github.com/waydabber/BetterDisplay), [MonitorControl](https://github.com/MonitorControl/MonitorControl), and [Lunar](https://lunar.fyi/)
- CGVirtualDisplay bridging header based on [Chromium's virtual_display_mac_util.mm](https://chromium.googlesource.com/chromium/src/+/main/ui/display/mac/test/virtual_display_mac_util.mm)
