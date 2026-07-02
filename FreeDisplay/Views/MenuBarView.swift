import SwiftUI
import CoreGraphics

// MARK: - Shared Icon Helper

/// A colored rounded-square SF Symbol icon, consistent with macOS Settings style.
struct MenuItemIcon: View {
    let systemName: String
    var color: Color = .blue

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.white)
            .frame(width: 20, height: 20)
            .background(RoundedRectangle(cornerRadius: 5).fill(color))
    }
}

// MARK: - ExpandableRow

struct ExpandableRow: View {
    let icon: String
    var iconColor: Color = .blue
    let label: String
    var subtitle: String? = nil
    @Binding var isExpanded: Bool
    @State private var isHovered = false

    var body: some View {
        HStack {
            MenuItemIcon(systemName: icon, color: iconColor)
            Text(label).font(.body)
            Spacer()
            if let sub = subtitle, !sub.isEmpty {
                Text(sub)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .animation(.easeInOut(duration: 0.2), value: isExpanded)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(isHovered ? 0.06 : 0))
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isExpanded.toggle()
            }
        }
        .onHover { isHovered = $0 }
        .accessibilityLabel(isExpanded ? "\(label), expanded" : "\(label), collapsed")
        .accessibilityHint("Tap to expand or collapse this section")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - MenuBarView

struct MenuBarView: View {
    @EnvironmentObject var displayManager: DisplayManager
    @ObservedObject private var updateService = UpdateService.shared
    @ObservedObject private var virtualDisplayService = VirtualDisplayService.shared
    @State private var showSettings: Bool = false
    @State private var quitHovered: Bool = false
    @State private var expandedAdvanced: Set<CGDirectDisplayID> = []
    @State private var showArrangement: Bool = false
    @State private var showVirtualDisplays: Bool = false
    @State private var showAutoBrightness: Bool = false

    private var visibleDisplays: [DisplayInfo] {
        displayManager.displays.filter { !virtualDisplayService.isVirtualDisplay($0.displayID) }
    }

    // Per-display "Advanced" expand/collapse state, keyed by display ID.
    private func advancedBinding(for id: CGDirectDisplayID) -> Binding<Bool> {
        Binding(
            get: { expandedAdvanced.contains(id) },
            set: { on in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    if on { expandedAdvanced.insert(id) } else { expandedAdvanced.remove(id) }
                }
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack(spacing: 6) {
                Image(systemName: "display").foregroundColor(.accentColor)
                Text("FreeDisplay").font(.headline)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 6)

            Divider().opacity(0.4)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    if visibleDisplays.isEmpty {
                        VStack(spacing: 6) {
                            Image(systemName: "display.trianglebadge.exclamationmark")
                                .font(.title2)
                                .foregroundColor(.secondary)
                            Text("No displays detected")
                                .font(.callout)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                    } else {
                        ForEach(Array(visibleDisplays.enumerated()), id: \.element.id) { index, display in
                            DisplayControlCard(display: display)

                            // Advanced: resolution/HiDPI, color profile, image
                            // adjustment, set-as-main, notch (per display).
                            ExpandableRow(
                                icon: "slider.horizontal.below.rectangle",
                                iconColor: .gray,
                                label: "Advanced",
                                isExpanded: advancedBinding(for: display.displayID)
                            )
                            if expandedAdvanced.contains(display.displayID) {
                                DisplayDetailView(display: display)
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                            }

                            if index < visibleDisplays.count - 1 {
                                Divider().opacity(0.3).padding(.horizontal, 12)
                            }
                        }
                    }

                    Divider().opacity(0.4).padding(.vertical, 2)

                    // Presets — save / restore full display configurations.
                    PresetListView()

                    // Arrange displays (only with 2+ displays).
                    if visibleDisplays.count > 1 {
                        Divider().opacity(0.3).padding(.vertical, 2)
                        ExpandableRow(
                            icon: "rectangle.3.offgrid",
                            iconColor: .blue,
                            label: "Arrange Displays",
                            isExpanded: $showArrangement
                        )
                        if showArrangement {
                            ArrangementView()
                                .environmentObject(displayManager)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }

                    Divider().opacity(0.3).padding(.vertical, 2)

                    // Tools
                    Text("Tools")
                        .font(.caption2).fontWeight(.semibold).foregroundColor(.secondary)
                        .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 2)

                    // Virtual displays (HiDPI dummies / headless).
                    ExpandableRow(
                        icon: "display.2",
                        iconColor: .blue,
                        label: "Virtual Displays",
                        isExpanded: $showVirtualDisplays
                    )
                    if showVirtualDisplays {
                        VirtualDisplayView()
                            .padding(.leading, 8)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    // Auto-brightness sync.
                    ExpandableRow(
                        icon: "sun.and.horizon.fill",
                        iconColor: .orange,
                        label: "Auto Brightness",
                        isExpanded: $showAutoBrightness
                    )
                    if showAutoBrightness {
                        AutoBrightnessView()
                            .padding(.leading, 8)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    Divider().opacity(0.4).padding(.vertical, 2)

                    // Settings
                    ExpandableRow(
                        icon: "gearshape.fill",
                        iconColor: .gray,
                        label: "Settings",
                        isExpanded: $showSettings
                    )
                    if showSettings {
                        SettingsView()
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    // Update banner
                    if updateService.hasUpdate, let ver = updateService.latestVersion {
                        Button { updateService.openReleasePage() } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.down.circle.fill").foregroundColor(.green)
                                Text("Update available: v\(ver)")
                                    .font(.caption).foregroundColor(.green)
                                Spacer()
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                        .help("Open the latest release page")
                    }
                }
            }

            Divider().opacity(0.4)

            // Footer: version + quit
            HStack {
                Text("v\(updateService.currentVersion)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: { NSApplication.shared.terminate(nil) }) {
                    HStack(spacing: 3) {
                        Image(systemName: "power").accessibilityHidden(true)
                        Text("Quit")
                    }
                    .font(.callout)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(quitHovered ? Color.primary.opacity(0.08) : .clear)
                    .cornerRadius(6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundColor(quitHovered ? .red : .secondary)
                .onHover { quitHovered = $0 }
                .help("Quit FreeDisplay")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .frame(width: 300)
        .fixedSize(horizontal: false, vertical: true)
        .task {
            if SettingsService.shared.checkUpdatesOnLaunch {
                await updateService.checkForUpdates()
            }
        }
    }
}

// MARK: - SettingsView

struct SettingsView: View {
    @ObservedObject private var settings = SettingsService.shared
    @ObservedObject private var pip = PiPManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Transparent Mode — cursor "spotlight" that dissolves a PiP around the pointer.
            Toggle(isOn: Binding(
                get: { pip.transparentMode },
                set: { pip.setTransparentMode($0) }
            )) {
                HStack(spacing: 6) {
                    MenuItemIcon(systemName: "circle.dotted.circle", color: .teal)
                    Text("Transparent Mode").font(.body)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .padding(.horizontal, 14)
            .help("Hovering a PiP window dissolves a see-through circle around the cursor")

            // Fun Mode — the PiP window runs away from the cursor.
            Toggle(isOn: Binding(
                get: { pip.funMode },
                set: { pip.setFunMode($0) }
            )) {
                HStack(spacing: 6) {
                    MenuItemIcon(systemName: "hare.fill", color: .pink)
                    Text("Fun Mode").font(.body)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .padding(.horizontal, 14)
            .help("The PiP window playfully flees the mouse (grab its pink border to move/resize). Turns Transparent Mode off.")
            // Launch at login
            Toggle(isOn: Binding(
                get: { settings.launchAtLogin },
                set: { newValue in
                    if newValue {
                        LaunchService.shared.enable()
                    } else {
                        LaunchService.shared.disable()
                    }
                    settings.launchAtLogin = newValue
                }
            )) {
                HStack(spacing: 6) {
                    MenuItemIcon(systemName: "power", color: .green)
                    Text("Launch at login").font(.body)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .padding(.horizontal, 14)
            .help("Start FreeDisplay automatically when you log in")

            // Check for updates on launch
            Toggle(isOn: $settings.checkUpdatesOnLaunch) {
                HStack(spacing: 6) {
                    MenuItemIcon(systemName: "arrow.clockwise.circle", color: .blue)
                    Text("Check for updates on launch").font(.body)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .padding(.horizontal, 14)
            .help("Check GitHub Releases for a newer version at startup")
        }
        .padding(.vertical, 8)
    }
}
