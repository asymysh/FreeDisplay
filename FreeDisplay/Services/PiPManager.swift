import AppKit
import CoreGraphics

// MARK: - PiPManager
//
// Owns the live picture-in-picture windows — one floating, corner-pinned capture
// window per display. Composes the recovered Phase-9 pieces (ScreenCaptureService +
// StreamViewModel + PiPWindowController) with the requested behaviors:
//   • always-on-top (floating window level)
//   • resizable + draggable
//   • click-through (default ON = passive corner monitor; toggle OFF to drag/resize)
//   • pinned to a screen corner on open
@MainActor
final class PiPManager: ObservableObject {
    static let shared = PiPManager()
    private init() {}

    enum Corner { case topLeft, topRight, bottomLeft, bottomRight }

    private var controllers: [CGDirectDisplayID: PiPWindowController] = [:]
    private var viewModels:  [CGDirectDisplayID: StreamViewModel] = [:]

    // Hover-to-enlarge state: while the cursor is on a virtual display, its PiP grows to
    // `enlargedWidthFraction` of the host screen's width, then glides back on exit.
    private var corners:     [CGDirectDisplayID: Corner] = [:]
    private var savedFrames: [CGDirectDisplayID: NSRect] = [:]
    private var enlarged:    Set<CGDirectDisplayID> = []
    private var hoverTimer:  Timer?
    private let enlargedWidthFraction: CGFloat = 0.60
    private let hoverAnimationDuration: TimeInterval = 0.35

    // Fun-mode state: the window flees the cursor. `funEdgeMargin` is a transparent border
    // added around the video so its outer edge (resize handles + middle-drag zone) stays
    // reachable while the video core itself stays out of reach. `fleeRadius` (< margin) is
    // how close to the video the cursor may get before it bolts.
    private let funEdgeMargin: CGFloat = 72
    private let fleeRadius: CGFloat = 46

    /// Published so menu rows can reflect the on/off + click-through state.
    @Published private(set) var showing: Set<CGDirectDisplayID> = []
    @Published private(set) var clickThrough: Set<CGDirectDisplayID> = []
    /// Global PiP behavior toggles (surfaced in the menu under Settings).
    @Published private(set) var transparentMode: Bool = true
    @Published private(set) var funMode: Bool = false

    func isShowing(_ id: CGDirectDisplayID) -> Bool { showing.contains(id) }
    func isClickThrough(_ id: CGDirectDisplayID) -> Bool { clickThrough.contains(id) }

    /// Enable/disable the cursor transparency spotlight globally.
    func setTransparentMode(_ on: Bool) {
        transparentMode = on
        if !on { for vm in viewModels.values { vm.hoverScreenPoint = nil } }
    }

    /// Enable/disable Fun Mode. Turning it on forces Transparent Mode off and grows each
    /// window's grabbable border; turning it off restores the normal window.
    func setFunMode(_ on: Bool) {
        guard funMode != on else { return }
        funMode = on
        if on {
            setTransparentMode(false)
            for (id, ctrl) in controllers {
                if enlarged.contains(id) { restore(id, ctrl) }
                ctrl.funMode = true
                enterFunFrame(ctrl, vm: viewModels[id])
            }
        } else {
            for (id, ctrl) in controllers {
                ctrl.funMode = false
                exitFunFrame(ctrl, vm: viewModels[id])
            }
        }
    }

    func toggle(displayID id: CGDirectDisplayID, corner: Corner = .topRight) {
        if controllers[id] != nil { hide(id) } else { show(displayID: id, corner: corner) }
    }

    func show(displayID id: CGDirectDisplayID, corner: Corner = .topRight) {
        guard controllers[id] == nil else { return }
        let vm = StreamViewModel(displayID: id)
        let ctrl = PiPWindowController(viewModel: vm)
        ctrl.pipLevel = .floating   // always-on-top
        ctrl.isResizable = true     // resizable
        ctrl.isMovable = true       // draggable (once click-through is off)
        ctrl.showTitleBar = false
        ctrl.ignoresMouse = true    // click-through by default: passive corner monitor
        viewModels[id] = vm
        controllers[id] = ctrl
        corners[id] = corner
        vm.startCapture()
        ctrl.show()
        pin(ctrl, to: corner)
        showing.insert(id)
        clickThrough.insert(id)
        if funMode {                 // opened while Fun Mode is already on
            ctrl.funMode = true
            enterFunFrame(ctrl, vm: vm)
        }
        startHoverTracking()
    }

    func hide(_ id: CGDirectDisplayID) {
        viewModels[id]?.stopCapture()
        controllers[id]?.close()
        controllers[id] = nil
        viewModels[id] = nil
        showing.remove(id)
        clickThrough.remove(id)
        corners[id] = nil
        savedFrames[id] = nil
        enlarged.remove(id)
        if controllers.isEmpty { stopHoverTracking() }
    }

    /// Toggle click-through. When ON the window ignores the mouse (clicks pass through to
    /// windows behind it); turn OFF to grab, drag, and resize it.
    func toggleClickThrough(_ id: CGDirectDisplayID) {
        guard let ctrl = controllers[id] else { return }
        let newVal = !ctrl.ignoresMouse
        ctrl.ignoresMouse = newVal
        if newVal { clickThrough.insert(id) } else { clickThrough.remove(id) }
    }

    private func pin(_ ctrl: PiPWindowController, to corner: Corner) {
        guard let win = ctrl.window, let screen = win.screen ?? NSScreen.main else { return }
        win.setFrameOrigin(anchoredOrigin(size: win.frame.size, corner: corner, in: screen.visibleFrame))
    }

    /// Origin that keeps `size` pinned to `corner` of `vf`, clamped fully on-screen.
    private func anchoredOrigin(size: CGSize, corner: Corner, in vf: NSRect, margin m: CGFloat = 16) -> CGPoint {
        var x: CGFloat, y: CGFloat
        switch corner {
        case .topLeft:     x = vf.minX + m;              y = vf.maxY - size.height - m
        case .topRight:    x = vf.maxX - size.width - m; y = vf.maxY - size.height - m
        case .bottomLeft:  x = vf.minX + m;              y = vf.minY + m
        case .bottomRight: x = vf.maxX - size.width - m; y = vf.minY + m
        }
        x = max(vf.minX + m, min(x, vf.maxX - size.width - m))
        y = max(vf.minY + m, min(y, vf.maxY - size.height - m))
        return CGPoint(x: x, y: y)
    }

    // MARK: - Hover-to-enlarge

    private func startHoverTracking() {
        guard hoverTimer == nil else { return }
        // ~60 Hz so the transparency spotlight follows the cursor smoothly.
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.hoverTick() }
        }
        RunLoop.main.add(t, forMode: .common)
        hoverTimer = t
    }

    private func stopHoverTracking() {
        hoverTimer?.invalidate()
        hoverTimer = nil
    }

    private func hoverTick() {
        guard !controllers.isEmpty else { return }
        let mouse = NSEvent.mouseLocation

        // Fun Mode overrides everything: windows just flee the cursor.
        if funMode {
            for (_, ctrl) in controllers { flee(ctrl, from: mouse) }
            return
        }

        let mouseDisplay = displayUnderMouse()
        for (id, ctrl) in controllers {
            let onVirtual = (mouseDisplay == id)

            // 1) Cursor on the virtual display → grow/shrink the PiP.
            if onVirtual && !enlarged.contains(id) {
                enlarge(id, ctrl)
            } else if !onVirtual && enlarged.contains(id) {
                restore(id, ctrl)
            }

            // 2) Cursor over the PiP window itself → transparency spotlight (only when
            //    Transparent Mode is on, and not while enlarged — then the cursor is on
            //    the virtual display).
            let vm = viewModels[id]
            if transparentMode, !onVirtual, let win = ctrl.window, win.frame.contains(mouse) {
                if vm?.hoverScreenPoint != mouse { vm?.hoverScreenPoint = mouse }
            } else if vm?.hoverScreenPoint != nil {
                vm?.hoverScreenPoint = nil
            }
        }
    }

    // MARK: - Fun Mode (runaway window)

    /// Grow the window with a transparent grabbable border and inset the video into it.
    private func enterFunFrame(_ ctrl: PiPWindowController, vm: StreamViewModel?) {
        guard let win = ctrl.window, (vm?.edgeInset ?? 0) == 0 else { return }
        let m = funEdgeMargin
        vm?.edgeInset = m
        let f = win.frame
        let grown = NSRect(x: f.minX - m, y: f.minY - m, width: f.width + 2 * m, height: f.height + 2 * m)
        win.setFrame(clampToScreen(grown, for: win), display: true)
        // Faint border so the extended (otherwise invisible) grab area is discoverable.
        win.contentView?.wantsLayer = true
        win.contentView?.layer?.borderColor = NSColor.systemPink.withAlphaComponent(0.7).cgColor
        win.contentView?.layer?.borderWidth = 2
    }

    /// Undo `enterFunFrame`: shrink back to the video's own size and drop the border.
    private func exitFunFrame(_ ctrl: PiPWindowController, vm: StreamViewModel?) {
        guard let win = ctrl.window, let m = vm?.edgeInset, m > 0 else { return }
        vm?.edgeInset = 0
        win.contentView?.layer?.borderWidth = 0
        let f = win.frame
        let shrunk = NSRect(x: f.minX + m, y: f.minY + m, width: f.width - 2 * m, height: f.height - 2 * m)
        win.setFrame(clampToScreen(shrunk, for: win), display: true)
    }

    /// Move the window away from the cursor if it comes within `fleeRadius` of the video
    /// core (the frame inset by the grab margin). Suspended while the user middle-drags.
    private func flee(_ ctrl: PiPWindowController, from mouse: NSPoint) {
        guard let win = ctrl.window, !ctrl.isMiddleDragging else { return }
        let core = win.frame.insetBy(dx: funEdgeMargin, dy: funEdgeMargin)
        let d = distance(from: mouse, to: core)
        guard d < fleeRadius else { return }

        // Push directly away from the cursor, with a goofy perpendicular wobble.
        var dx = core.midX - mouse.x, dy = core.midY - mouse.y
        if abs(dx) < 0.5 && abs(dy) < 0.5 { dx = CGFloat.random(in: -1...1); dy = CGFloat.random(in: -1...1) }
        let len = max(1, hypot(dx, dy))
        let urgency = (fleeRadius - d) / fleeRadius        // 0…1, closer = faster
        let step = 16 + urgency * 46
        let wobble = CGFloat.random(in: -9...9)
        let nx = win.frame.origin.x + (dx / len) * step + (-dy / len) * wobble
        let ny = win.frame.origin.y + (dy / len) * step + ( dx / len) * wobble

        let scr = (win.screen ?? NSScreen.main)?.frame ?? win.frame
        let maxX = scr.maxX - win.frame.width, maxY = scr.maxY - win.frame.height
        let cx = min(max(scr.minX, nx), maxX)
        let cy = min(max(scr.minY, ny), maxY)

        // Cornered (can't get further away) → teleport to whichever corner is farthest.
        if abs(cx - win.frame.origin.x) < 0.5 && abs(cy - win.frame.origin.y) < 0.5 {
            let corners = [NSPoint(x: scr.minX, y: scr.minY), NSPoint(x: maxX, y: scr.minY),
                           NSPoint(x: scr.minX, y: maxY), NSPoint(x: maxX, y: maxY)]
            if let far = corners.max(by: { hypot($0.x - mouse.x, $0.y - mouse.y) < hypot($1.x - mouse.x, $1.y - mouse.y) }) {
                win.setFrameOrigin(far)
            }
        } else {
            win.setFrameOrigin(NSPoint(x: cx, y: cy))
        }
    }

    /// Shortest distance from a point to a rectangle (0 if inside).
    private func distance(from p: NSPoint, to r: NSRect) -> CGFloat {
        let nx = max(r.minX, min(p.x, r.maxX))
        let ny = max(r.minY, min(p.y, r.maxY))
        return hypot(p.x - nx, p.y - ny)
    }

    /// Keep a frame fully within its screen.
    private func clampToScreen(_ frame: NSRect, for win: NSWindow) -> NSRect {
        let scr = (win.screen ?? NSScreen.main)?.frame ?? frame
        var f = frame
        f.origin.x = min(max(scr.minX, f.origin.x), scr.maxX - f.width)
        f.origin.y = min(max(scr.minY, f.origin.y), scr.maxY - f.height)
        return f
    }

    /// CGDirectDisplayID of the screen currently under the mouse cursor, if any.
    private func displayUnderMouse() -> CGDirectDisplayID? {
        let loc = NSEvent.mouseLocation
        for screen in NSScreen.screens where screen.frame.contains(loc) {
            if let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
                return CGDirectDisplayID(num.uint32Value)
            }
        }
        return nil
    }

    private func enlarge(_ id: CGDirectDisplayID, _ ctrl: PiPWindowController) {
        guard let win = ctrl.window else { return }
        enlarged.insert(id)
        savedFrames[id] = win.frame                 // remember the size/pos to return to
        // Enlarge bounds cover the Dock (left/right/bottom) but stay under the menu bar.
        let bounds = enlargeBounds(for: win)
        let aspect = aspectRatio(for: id, fallback: win.frame)
        var w = bounds.width * enlargedWidthFraction
        var h = w / aspect
        if h > bounds.height {                       // cap to available height, keep aspect
            h = bounds.height
            w = h * aspect
        }
        let size = CGSize(width: w, height: h)
        // Grow toward the screen corner the PiP is *closest* to (by its center) and pin
        // flush to it, so multiple PiPs expand away from each other (and over the Dock)
        // instead of overlapping.
        let corner = nearestCorner(of: win.frame, in: bounds)
        let origin = anchoredOrigin(size: size, corner: corner, in: bounds, margin: 0)
        // Raise above the Dock (but still below the menu bar) so the window renders OVER
        // the Dock instead of being occluded by it. Click-through keeps the Dock usable.
        win.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 1)
        animate(win, to: NSRect(origin: origin, size: size))
    }

    private func restore(_ id: CGDirectDisplayID, _ ctrl: PiPWindowController) {
        guard let win = ctrl.window else { return }
        enlarged.remove(id)
        let target = savedFrames[id] ?? win.frame
        savedFrames[id] = nil
        win.level = ctrl.pipLevel.nsLevel           // drop back below the Dock
        animate(win, to: target)
    }

    /// Bounds the enlarged PiP may occupy: the full screen frame (so it can extend over
    /// the Dock on the left/right/bottom), but capped at the top by the visible frame so
    /// it never covers the menu bar.
    private func enlargeBounds(for win: NSWindow) -> NSRect {
        let screen = win.screen ?? NSScreen.main
        let full = screen?.frame ?? win.frame
        let vis  = screen?.visibleFrame ?? full
        return NSRect(x: full.minX, y: full.minY, width: full.width, height: vis.maxY - full.minY)
    }

    /// Screen corner nearest to the window's center (Cocoa coords: y grows upward).
    private func nearestCorner(of frame: NSRect, in vf: NSRect) -> Corner {
        let cx = frame.midX, cy = frame.midY
        let left = cx < vf.midX
        let top  = cy >= vf.midY
        switch (top, left) {
        case (true, true):   return .topLeft
        case (true, false):  return .topRight
        case (false, true):  return .bottomLeft
        case (false, false): return .bottomRight
        }
    }

    /// Aspect ratio (w/h) of the virtual display, falling back to the window's own.
    private func aspectRatio(for id: CGDirectDisplayID, fallback: NSRect) -> CGFloat {
        let b = CGDisplayBounds(id)
        if b.width > 0, b.height > 0 { return b.width / b.height }
        if fallback.width > 0, fallback.height > 0 { return fallback.width / fallback.height }
        return 16.0 / 9.0
    }

    private func animate(_ win: NSWindow, to frame: NSRect) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = hoverAnimationDuration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            ctx.allowsImplicitAnimation = true
            win.animator().setFrame(frame, display: true)
        }
    }
}
