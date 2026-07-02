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
        vm.startCapture()
        ctrl.show()
        pin(ctrl, to: corner)
        showing.insert(id)
        clickThrough.insert(id)
    }

    func hide(_ id: CGDirectDisplayID) {
        viewModels[id]?.stopCapture()
        controllers[id]?.close()
        controllers[id] = nil
        viewModels[id] = nil
        showing.remove(id)
        clickThrough.remove(id)
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
        let vf = screen.visibleFrame
        let m: CGFloat = 16
        let f = win.frame
        let x: CGFloat, y: CGFloat
        switch corner {
        case .topLeft:     x = vf.minX + m;           y = vf.maxY - f.height - m
        case .topRight:    x = vf.maxX - f.width - m; y = vf.maxY - f.height - m
        case .bottomLeft:  x = vf.minX + m;           y = vf.minY + m
        case .bottomRight: x = vf.maxX - f.width - m; y = vf.minY + m
        }
        win.setFrameOrigin(CGPoint(x: x, y: y))
    }
}
