import Foundation
import CoreGraphics

// MARK: - VolumeService
//
// Controls external-display audio volume and mute over DDC/CI.
//   - Volume  → VCP feature code 0x62
//   - Mute    → VCP feature code 0x8D (1 = mute, 2 = unmute)
//
// Unlike brightness there is no software fallback: if the monitor does not
// implement the audio VCP codes the control is simply marked unavailable and
// the UI hides/disables itself. Built-in displays are never handled here.
final class VolumeService: @unchecked Sendable {
    static let shared = VolumeService()
    private init() {}

    private let lock = NSLock()

    /// Whether DDC audio control is available per display.
    /// nil = not yet probed, true = a read/write succeeded, false = unsupported.
    private var ddcAvailable: [CGDirectDisplayID: Bool] = [:]

    /// Per-display max volume value reported by the monitor (DDC native range).
    private var ddcMaxVolume: [CGDirectDisplayID: UInt16] = [:]

    // MARK: - Public API

    /// Returns availability of DDC volume control for a display (nil = unknown).
    func isDDCVolumeAvailable(for displayID: CGDirectDisplayID) -> Bool? {
        lock.withLock { ddcAvailable[displayID] }
    }

    /// Probe the current volume (and mute) from the monitor and update the model.
    @MainActor
    func refreshVolume(for display: DisplayInfo) async {
        guard !display.isBuiltin else { return }
        let displayID = display.displayID

        let knownUnavailable: Bool = lock.withLock { ddcAvailable[displayID] == false }
        if knownUnavailable { return }

        DDCService.shared.readAsync(
            displayID: displayID,
            command: DDCService.volumeVCP
        ) { [weak self] result in
            guard let self else { return }
            if let result, result.max > 0 {
                let volume = Double(result.current) / Double(result.max) * 100.0
                self.lock.withLock {
                    self.ddcAvailable[displayID] = true
                    self.ddcMaxVolume[displayID] = result.max
                }
                Task { @MainActor in display.volume = volume }
            } else {
                self.lock.withLock {
                    if self.ddcAvailable[displayID] == nil {
                        self.ddcAvailable[displayID] = false
                    }
                }
            }
        }

        // Mute state (VCP 0x8D). Best-effort: failure here doesn't flip availability,
        // since some monitors expose volume but not a readable mute register.
        DDCService.shared.readAsync(
            displayID: displayID,
            command: DDCService.muteVCP
        ) { result in
            guard let result else { return }
            // 1 = muted, 2 = unmuted per DDC/CI spec.
            let muted = result.current == 1
            Task { @MainActor in display.isMuted = muted }
        }
    }

    /// Set the volume (0–100). Marks DDC unavailable if the write fails.
    @MainActor
    func setVolume(_ volume: Double, for display: DisplayInfo) {
        guard !display.isBuiltin else { return }
        let clamped = max(0.0, min(100.0, volume))
        let displayID = display.displayID
        display.volume = clamped

        let knownMax: UInt16 = lock.withLock { ddcMaxVolume[displayID] ?? 100 }
        let ddcValue = UInt16((clamped / 100.0) * Double(knownMax))

        DDCService.shared.writeAsync(
            displayID: displayID,
            command: DDCService.volumeVCP,
            value: ddcValue
        ) { [weak self] success in
            guard let self else { return }
            self.lock.withLock { self.ddcAvailable[displayID] = success }
            #if DEBUG
            if !success { print("[VolumeService] DDC volume write failed for display \(displayID)") }
            #endif
        }
    }

    /// Toggle/set mute over VCP 0x8D (1 = mute, 2 = unmute).
    @MainActor
    func setMute(_ muted: Bool, for display: DisplayInfo) {
        guard !display.isBuiltin else { return }
        display.isMuted = muted
        DDCService.shared.writeAsync(
            displayID: display.displayID,
            command: DDCService.muteVCP,
            value: muted ? 1 : 2,
            completion: nil
        )
    }

    /// Clear cached availability/max for a disconnected display.
    func invalidate(for displayID: CGDirectDisplayID) {
        lock.withLock {
            ddcAvailable.removeValue(forKey: displayID)
            ddcMaxVolume.removeValue(forKey: displayID)
        }
    }
}
