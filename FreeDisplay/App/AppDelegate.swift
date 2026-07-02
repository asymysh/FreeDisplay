import AppKit
import SwiftUI
import CoreGraphics

class AppDelegate: NSObject, NSApplicationDelegate {
    private var wakeObserver: NSObjectProtocol?
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var eventMonitor: Any?

    /// Shared DisplayManager — the single source of truth for all display state.
    /// Initialized in applicationDidFinishLaunching (which runs on the main thread).
    var displayManager: DisplayManager!

    /// Called by FreeDisplayApp to provide access to the live DisplayManager instance.
    var onWake: (() -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Prevent duplicate instances
        let runningApps = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == Bundle.main.bundleIdentifier
        }
        if runningApps.count > 1 {
            print("[FreeDisplay] Another instance is already running, exiting.")
            NSApp.terminate(nil)
            return
        }

        displayManager = DisplayManager()

        // Set up the status bar item (menu bar icon)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "display", accessibilityDescription: "FreeDisplay")
            button.action = #selector(togglePopover)
            button.target = self
        }

        // Set up the popover with the SwiftUI MenuBarView
        popover = NSPopover()
        popover.contentSize = NSSize(width: 300, height: 0)
        popover.behavior = .transient
        popover.animates = true

        let menuView = MenuBarView()
            .environmentObject(displayManager)
        popover.contentViewController = NSHostingController(rootView: menuView)

        // Start intercepting brightness keys to route them to the display under the cursor.
        BrightnessKeyService.shared.start()

        // Wake-from-sleep handling
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleWake()
        }

        // Initial setup tasks
        Task { @MainActor in
            // Enable "external above built-in" arrangement by default on first launch.
            let defaults = UserDefaults.standard
            if defaults.object(forKey: "fd.arrangement.externalAbove") == nil {
                defaults.set(true, forKey: "fd.arrangement.externalAbove")
            }

            // After a 2-second delay (allows displays to fully initialize),
            // position any external display above the built-in display.
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            displayManager.arrangeExternalAboveBuiltin()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let obs = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
        }
        BrightnessKeyService.shared.stop()
        VirtualDisplayService.shared.destroyAll()
    }

    // MARK: - Popover

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            // Close popover when clicking outside
            eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                self?.closePopover()
            }
        }
    }

    private func closePopover() {
        popover.performClose(nil)
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    // MARK: - Wake

    private func handleWake() {
        Task { @MainActor in
            // Give WindowServer 2 seconds to stabilize after wake before
            // touching display state.
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            displayManager.refreshDisplays()
            try? await Task.sleep(nanoseconds: 500_000_000)
            for display in displayManager.displays {
                BrightnessService.shared.reapplySoftwareBrightnessIfNeeded(for: display)
                GammaService.shared.reapplyIfNeeded(for: display.displayID)
                ResolutionService.shared.reapplySavedModeIfNeeded(for: display.displayID)
            }
        }
    }
}
