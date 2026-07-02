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

    /// Published so menu rows can reflect the on/off + click-through state.
    @Published private(set) var showing: Set<CGDirectDisplayID> = []
    @Published private(set) var clickThrough: Set<CGDirectDisplayID> = []

    func isShowing(_ id: CGDirectDisplayID) -> Bool { showing.contains(id) }
    func isClickThrough(_ id: CGDirectDisplayID) -> Bool { clickThrough.contains(id) }

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
        let mouseDisplay = displayUnderMouse()
        for (id, ctrl) in controllers {
            let onVirtual = (mouseDisplay == id)

            // 1) Cursor on the virtual display → grow/shrink the PiP.
            if onVirtual && !enlarged.contains(id) {
                enlarge(id, ctrl)
            } else if !onVirtual && enlarged.contains(id) {
                restore(id, ctrl)
            }

            // 2) Cursor over the PiP window itself → transparency spotlight (not while the
            //    window is enlarged, since then the cursor is on the virtual display).
            let vm = viewModels[id]
            if !onVirtual, let win = ctrl.window, win.frame.contains(mouse) {
                if vm?.hoverScreenPoint != mouse { vm?.hoverScreenPoint = mouse }
            } else if vm?.hoverScreenPoint != nil {
                vm?.hoverScreenPoint = nil
            }
        }
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
