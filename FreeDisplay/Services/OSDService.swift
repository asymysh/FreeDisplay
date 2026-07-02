import SwiftUI
import AppKit

@MainActor
final class OSDService {
    static let shared = OSDService()
    private init() {}

    private var windows: [CGDirectDisplayID: NSWindow] = [:]
    private var dismissTasks: [CGDirectDisplayID: Task<Void, Never>] = [:]

    func show(icon: String, value: Double, maxValue: Double = 100, on displayID: CGDirectDisplayID) {
        dismissTasks[displayID]?.cancel()

        let fraction = min(1.0, max(0.0, value / maxValue))
        let window = windows[displayID] ?? createWindow(for: displayID)
        windows[displayID] = window

        let view = OSDOverlayView(icon: icon, fraction: fraction, label: "\(Int(value))")
        window.contentView = NSHostingView(rootView: view)
        window.orderFrontRegardless()

        dismissTasks[displayID] = Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            self.windows[displayID]?.orderOut(nil)
        }
    }

    private func createWindow(for displayID: CGDirectDisplayID) -> NSWindow {
        let bounds = CGDisplayBounds(displayID)
        let size = NSSize(width: 200, height: 70)
        let origin = NSPoint(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2 - bounds.height * 0.3
        )

        let window = NSWindow(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        return window
    }
}

struct OSDOverlayView: View {
    let icon: String
    let fraction: Double
    let label: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 28)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.2))
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white)
                        .frame(width: geo.size.width * fraction, height: 8)
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }

            Text(label)
                .font(.system(size: 14, weight: .semibold).monospacedDigit())
                .foregroundColor(.white)
                .frame(width: 32, alignment: .trailing)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        )
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.55))
        )
    }
}
