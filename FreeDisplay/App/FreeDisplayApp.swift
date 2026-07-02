import SwiftUI

@main
struct FreeDisplayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Use a hidden Settings scene as a placeholder — the real UI is
        // driven by AppDelegate's NSStatusItem + NSPopover so it works
        // reliably on all hardware (including Hackintosh where MenuBarExtra
        // .window style silently falls back to .menu style).
        Settings {
            EmptyView()
        }
    }
}
