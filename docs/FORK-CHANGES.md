# 🍴 Fork Changes

Everything this fork ([asymysh/FreeDisplay](https://github.com/asymysh/FreeDisplay))
adds on top of the original [huberdf/FreeDisplay](https://github.com/huberdf/FreeDisplay).
For attribution and licensing, see [`../NOTICE.md`](../NOTICE.md).

**Motivation:** run FreeDisplay on an **AMD Hackintosh** (no Apple Developer account,
no full Xcode, AMD GPU framebuffers) and add the DDC controls that were missing —
**speaker volume, mute, and contrast** — with **on-screen feedback**.

| Change | Type | Commit |
|--------|------|--------|
| DDC audio volume & mute | New feature | `e0ff910` |
| No-Xcode local build (`build-local.sh`) | Build tooling | `e0ff910` |
| DDC contrast control | New feature | `a65c9b8` |
| Native OSD overlay | New feature | `a65c9b8` |
| `DisplayControlCard` UI refactor | Refactor | `a65c9b8` |
| AMD-GPU registry DDC path | Engine | `a65c9b8` |

---

## 1. DDC audio volume & mute  🔊

Control an **external monitor's built-in speaker** straight from the menu bar — the
same DDC/CI channel BetterDisplay's paid volume control uses.

- **`Services/VolumeService.swift`** — reads/writes volume and mute over DDC/CI.
- **`Views/VolumeSliderView.swift`** — volume slider + mute toggle per external display.
- **VCP feature codes:**
  - `0x62` — Audio Speaker Volume (0–100)
  - `0x8D` — Audio Mute (`1` = mute, `2` = unmute)
- Reuses the existing `DDCService` I2C / `IOAVService` engine, so it works on Intel,
  Apple Silicon, **and** AMD Hackintosh.
- **Graceful degradation:** volume has *no software fallback*. Monitors that don't
  report audio support over DDC show a "not supported" hint instead of a dead
  slider, so the UI never lies about what the hardware can do.

## 2. DDC contrast control  🌗

- **`Services/ContrastService.swift`** — external-display contrast over DDC/CI.
- **VCP feature code:** `0x12` — Contrast (0–100).
- **`Models/DisplayInfo.swift`** gains a `@Published var contrast` field.
- Built-in displays have no hardware contrast and are ignored; like volume, there is
  no software fallback, so the control is hidden when a monitor doesn't implement
  VCP `0x12`.

## 3. Native OSD overlay  🎚️

- **`Services/OSDService.swift`** — a floating, auto-dismissing overlay window that
  shows a macOS-style on-screen display (icon + level bar) **on the specific display
  being adjusted**, for brightness / contrast / volume changes.
- Wired from `App/AppDelegate.swift`; keeps one reusable `NSWindow` per
  `CGDirectDisplayID` and cancels/reschedules its own dismiss task so rapid changes
  don't flicker.

## 4. `DisplayControlCard` UI refactor  🧩

- **`Views/DisplayControlCard.swift`** — a reusable per-display "card" plus a
  **`DDCSliderRow`** used for brightness, contrast, and volume.
- Each row keeps a **local mirror** of the model value so live service updates don't
  fight the user's drag, and **throttles** live writes to ~100 ms because DDC I2C is
  slow.
- **`Views/MenuBarView.swift`** was refactored onto this card, collapsing three
  near-duplicate slider blocks into one consistent component.
- Full feature access is retained in the menu: each display's card has an **Advanced**
  expandable (resolution/HiDPI, color profile, image adjustment, set-as-main, notch via
  the slimmed-down `DisplayDetailView`), and the global tools (**Presets, Arrange
  Displays, Virtual Displays, Auto-Brightness, Settings**) sit below the cards.

## 5. AMD-GPU registry DDC path  🧠

The original DDC engine targets Intel I2C and Apple Silicon `IOAVService`. AMD GPU
framebuffers on a Hackintosh don't always expose a usable I2C interface the same way,
so **`Services/DDCService.swift`** gained:

- **`amdWriteViaRegistry(command:value:)`** / **`amdReadViaRegistry(command:)`** — a
  fallback path that drives DDC through the AMD framebuffer's IOKit registry.
- **`ddcReadCombined(...)`** and **`ddcReadSplit(...)`** — two VCP-read strategies
  (single combined transaction vs. *send request → wait 60 ms → read reply
  separately*). Splitting the read is far more reliable on flaky/slow monitors and
  AMD framebuffers.
- `ddcWriteOnConnection(...)` — write helper on a given I2C connection.

This is what makes hardware brightness/contrast/volume actually work on AMD
Hackintosh setups.

## 6. No-Xcode local build (AMD Hackintosh friendly)  🛠️

- **`build-local.sh`** — builds the complete `.app` bundle with only the **Command
  Line Tools**: `swiftc` (all sources, `-swift-version 5`, `-parse-as-library`,
  `-undefined dynamic_lookup` for the private-API bridging), `iconutil` for the
  icon (no `actool`/Xcode), and **ad-hoc `codesign`** (no Apple Developer account).

  ```bash
  ./build-local.sh            # build into build-local/FreeDisplay.app
  ./build-local.sh install    # build, then copy to /Applications
  ```

- **`project.yml`** switched to **ad-hoc signing** (no team / Developer account).
- The existing DDC engine already iterates all 8 I2C buses, which pairs well with the
  AMD registry path above for Hackintosh GPU framebuffers.

> ℹ️ **Why `-swift-version 5`?** The services' `@MainActor` DDC-completion closures
> legitimately run on a background I2C queue. Building in Swift 6 language mode turns
> that into hard runtime isolation traps (`SIGILL` / `dispatch_assert_queue_fail`) on
> the first DDC read. `build-local.sh` and `project.yml` pin Swift 5 semantics
> (`SWIFT_STRICT_CONCURRENCY: minimal`).

## 7. Picture-in-Picture (restored)  🖼️

The original author built PiP in **Phase 9** (ScreenCaptureKit floating window) then
**deleted it in Phase 21** to cut maintenance. This fork **restores it from git
history** (commit `7c8da6e`) and re-wires it into the current UI:

- **`Services/ScreenCaptureService.swift`** — ScreenCaptureKit capture of one display → live frames.
- **`ViewModels/StreamViewModel.swift`** — capture control + frame processing.
- **`Views/PiPWindow.swift`** — `PiPWindowController` + borderless floating `PiPNSWindow`.
- **`Views/PiPRenderView.swift`** — Metal-backed `CIImage` renderer.
- **`Services/PiPManager.swift`** (new) — one PiP window per display with the requested
  behaviors: **always-on-top, resizable, draggable, click-through (toggle), pinned to a corner**.
- **Hover-to-enlarge ("peek"):** when the cursor moves *onto a virtual display* (which you
  otherwise can't see), that display's PiP smoothly grows to **60% of its host screen's
  width** — aspect-correct, clamped on-screen — and glides back to its previous
  size/position the moment the cursor returns. A 20 Hz hover tracker maps the cursor to a
  display via `NSScreen`; the resize is animated (`NSAnimationContext`, 0.35 s
  ease-in-out). No extra permissions needed.
  - Each PiP grows toward the screen corner it is **closest to** (by its center), so
    multiple PiPs expand *away* from each other instead of overlapping.
- Wired into **`VirtualDisplayView`**: each *active* virtual display gets a **PiP toggle**
  and a **click-through toggle**. Requires Screen Recording permission — the
  `NSScreenCaptureUsageDescription` was already declared (a Phase-9 leftover).

> **Click-through vs. left-drag are mutually exclusive** (a click-through window can't
> be grabbed by left-click). Default is **click-through ON** (passive corner monitor);
> toggle it **OFF** to left-drag/resize.
>
> **Middle-click drag** works in *either* state: hold the **middle mouse button** over
> the PiP window and drag to reposition it — implemented via a global `NSEvent` monitor
> so it grabs the window even while it's click-through.

---

## Building & verifying this fork

```bash
git clone https://github.com/asymysh/FreeDisplay.git
cd FreeDisplay
./build-local.sh install     # needs only Xcode Command Line Tools
```

Verified on this machine: `build-local.sh` compiles all sources cleanly (warnings
only, no errors) and the produced `.app` launches and stays resident in the menu bar.

## VCP feature codes used across the app

| VCP | Feature | Added by fork? |
|----:|---------|:--------------:|
| `0x10` | Brightness (0–100) | — (upstream) |
| `0x12` | Contrast (0–100) | 🍴 |
| `0x62` | Audio speaker volume (0–100) | 🍴 |
| `0x8D` | Audio mute (1=mute, 2=unmute) | 🍴 |
