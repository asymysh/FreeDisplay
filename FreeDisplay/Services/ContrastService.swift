import Foundation
import CoreGraphics

// MARK: - ContrastService
//
// Controls external-display contrast over DDC/CI (VCP feature code 0x12).
// Built-in displays have no contrast control and are ignored. Like volume,
// there is no software fallback: if the monitor doesn't implement VCP 0x12 the
// control is marked unavailable and the UI hides it.
final class ContrastService: @unchecked Sendable {
    static let shared = ContrastService()
    private init() {}

    private let lock = NSLock()
    private var ddcAvailable: [CGDirectDisplayID: Bool] = [:]
    private var ddcMaxContrast: [CGDirectDisplayID: UInt16] = [:]

    /// nil = not yet probed, true = available, false = unsupported.
    func isAvailable(for displayID: CGDirectDisplayID) -> Bool? {
        lock.withLock { ddcAvailable[displayID] }
    }

    /// Probe the current contrast from the monitor and update the model.
    @MainActor
    func refreshContrast(for display: DisplayInfo) async {
        guard !display.isBuiltin else { return }
        let displayID = display.displayID

        let knownUnavailable: Bool = lock.withLock { ddcAvailable[displayID] == false }
        if knownUnavailable { return }

        DDCService.shared.readAsync(
            displayID: displayID,
            command: DDCService.contrastVCP
        ) { [weak self] result in
            guard let self else { return }
            if let result, result.max > 0 {
                let contrast = Double(result.current) / Double(result.max) * 100.0
                self.lock.withLock {
                    self.ddcAvailable[displayID] = true
                    self.ddcMaxContrast[displayID] = result.max
                }
                Task { @MainActor in display.contrast = contrast }
            } else {
                self.lock.withLock {
                    if self.ddcAvailable[displayID] == nil {
                        self.ddcAvailable[displayID] = false
                    }
                }
            }
        }
    }

    /// Set the contrast (0–100). Marks DDC unavailable if the write fails.
    @MainActor
    func setContrast(_ contrast: Double, for display: DisplayInfo) {
        guard !display.isBuiltin else { return }
        let clamped = max(0.0, min(100.0, contrast))
        let displayID = display.displayID
        display.contrast = clamped

        let knownMax: UInt16 = lock.withLock { ddcMaxContrast[displayID] ?? 100 }
        let ddcValue = UInt16((clamped / 100.0) * Double(knownMax))

        DDCService.shared.writeAsync(
            displayID: displayID,
            command: DDCService.contrastVCP,
            value: ddcValue
        ) { [weak self] success in
            guard let self else { return }
            self.lock.withLock { self.ddcAvailable[displayID] = success }
        }
    }

    /// Clear cached state for a disconnected display.
    func invalidate(for displayID: CGDirectDisplayID) {
        lock.withLock {
            ddcAvailable.removeValue(forKey: displayID)
            ddcMaxContrast.removeValue(forKey: displayID)
        }
    }
}
