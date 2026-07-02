import SwiftUI

// MARK: - DDCSliderRow
//
// A reusable labeled slider row used for brightness / contrast / volume.
// Keeps a local mirror of the model value so service-driven updates don't fight
// the user's drag, and throttles live updates to ~100ms (DDC I2C is slow).
struct DDCSliderRow: View {
    let icon: String
    let tint: Color
    let label: String
    /// Current value coming from the display model (0–100).
    let modelValue: Double
    var range: ClosedRange<Double> = 0...100
    var enabled: Bool = true
    /// Tapping the icon (e.g. mute toggle). When nil the icon is static.
    var onIconTap: (() -> Void)? = nil
    /// Apply a value. `live == true` during a drag, `false` on release.
    let apply: (Double, _ live: Bool) -> Void

    @State private var local: Double = 50
    @State private var isDragging = false
    @State private var lastWrite: Date = .distantPast

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if let onIconTap {
                    Button(action: onIconTap) {
                        Image(systemName: icon).foregroundColor(tint)
                    }
                    .buttonStyle(.plain)
                } else {
                    Image(systemName: icon).foregroundColor(tint)
                }
            }
            .font(.caption)
            .frame(width: 16)

            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 58, alignment: .leading)

            Slider(value: $local, in: range, step: 1) { editing in
                isDragging = editing
                if !editing {
                    apply(local, false)
                    lastWrite = Date()
                }
            }
            .disabled(!enabled)
            .controlSize(.small)
            .onChange(of: local) { _, newValue in
                guard isDragging else { return }
                let now = Date()
                if now.timeIntervalSince(lastWrite) < 0.1 { return }
                lastWrite = now
                apply(newValue, true)
            }

            Text("\(Int(local))%")
                .font(.caption)
                .foregroundColor(enabled ? .secondary : Color.secondary.opacity(0.4))
                .frame(width: 36, alignment: .trailing)
                .monospacedDigit()
        }
        .onAppear { local = modelValue }
        .onChange(of: modelValue) { _, v in if !isDragging { local = v } }
    }
}

// MARK: - DisplayControlCard
//
// One card per display: name + resolution@refresh, then brightness (all displays)
// and contrast + volume sliders (external displays that support DDC audio/contrast).
struct DisplayControlCard: View {
    @ObservedObject var display: DisplayInfo

    @State private var brightnessIsSoftware = false
    @State private var contrastSupported: Bool? = nil
    @State private var volumeSupported: Bool? = nil
    @State private var lastTempWrite: Date = .distantPast

    private var resolutionLine: String {
        guard let mode = display.currentDisplayMode else { return "—" }
        var s = mode.resolutionString
        if mode.refreshRate > 0 { s += " @ \(mode.refreshRateString)" }
        if mode.isHiDPI { s += " · HiDPI" }
        return s
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header: name + resolution / refresh
            HStack(spacing: 8) {
                Image(systemName: display.isBuiltin ? "laptopcomputer" : "display")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(display.name)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        if display.isMain {
                            Text("Main")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.accentColor)
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .background(Color.accentColor.opacity(0.15))
                                .cornerRadius(3)
                        }
                    }
                    Text(resolutionLine)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
                Spacer()
            }

            // Brightness — available on every display.
            DDCSliderRow(
                icon: brightnessIsSoftware ? "sun.max.trianglebadge.exclamationmark" : "sun.max.fill",
                tint: .yellow,
                label: brightnessIsSoftware ? "Bright (sw)" : "Brightness",
                modelValue: display.brightness,
                range: 5...100
            ) { value, live in
                if live {
                    Task { @MainActor in await BrightnessService.shared.setBrightness(value, for: display) }
                } else {
                    BrightnessService.shared.setBrightnessSmooth(value, for: display)
                }
                brightnessIsSoftware = BrightnessService.shared.isDDCAvailable(for: display.displayID) == false
            }

            // Contrast — external displays that report VCP 0x12.
            if !display.isBuiltin && contrastSupported != false {
                DDCSliderRow(
                    icon: "circle.righthalf.filled",
                    tint: .blue,
                    label: "Contrast",
                    modelValue: display.contrast,
                    range: 0...100
                ) { value, live in
                    ContrastService.shared.setContrast(value, for: display)
                    contrastSupported = ContrastService.shared.isAvailable(for: display.displayID)
                }
            }

            // Volume — external displays with DDC audio (VCP 0x62 / mute 0x8D).
            if !display.isBuiltin {
                if volumeSupported == false {
                    HStack(spacing: 8) {
                        Image(systemName: "speaker.slash").font(.caption).foregroundColor(.secondary).frame(width: 16)
                        Text("Volume")
                            .font(.caption).foregroundColor(.secondary)
                            .frame(width: 58, alignment: .leading)
                        Text("Not supported over DDC")
                            .font(.caption2).foregroundColor(.secondary)
                        Spacer()
                    }
                } else {
                    DDCSliderRow(
                        icon: display.isMuted ? "speaker.slash.fill" : volumeIcon,
                        tint: display.isMuted ? .red : .secondary,
                        label: "Volume",
                        modelValue: display.volume,
                        range: 0...100,
                        enabled: !display.isMuted,
                        onIconTap: { VolumeService.shared.setMute(!display.isMuted, for: display) }
                    ) { value, live in
                        VolumeService.shared.setVolume(value, for: display)
                        volumeSupported = VolumeService.shared.isDDCVolumeAvailable(for: display.displayID)
                    }
                }
            }

            // Color temperature — software gamma adjustment, works on all displays.
            DDCSliderRow(
                icon: colorTempIcon,
                tint: .orange,
                label: "Temperature",
                modelValue: tempSliderValue,
                range: 0...100,
                onIconTap: {
                    display.colorTemperature = 0
                    applyColorTemp(0)
                }
            ) { value, live in
                let mapped = (value - 50) * 2  // 0-100 slider → -100 to +100
                display.colorTemperature = mapped
                if !live {
                    applyColorTemp(mapped)
                } else {
                    let now = Date()
                    if now.timeIntervalSince(lastTempWrite) > 0.1 {
                        lastTempWrite = now
                        applyColorTemp(mapped)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .task(id: display.displayID) {
            await BrightnessService.shared.refreshBrightness(for: display)
            brightnessIsSoftware = BrightnessService.shared.isDDCAvailable(for: display.displayID) == false
            if !display.isBuiltin {
                await ContrastService.shared.refreshContrast(for: display)
                await VolumeService.shared.refreshVolume(for: display)
                contrastSupported = ContrastService.shared.isAvailable(for: display.displayID)
                volumeSupported = VolumeService.shared.isDDCVolumeAvailable(for: display.displayID)
            }
        }
    }

    private var volumeIcon: String {
        if display.volume < 1 { return "speaker.fill" }
        else if display.volume < 34 { return "speaker.wave.1.fill" }
        else if display.volume < 67 { return "speaker.wave.2.fill" }
        else { return "speaker.wave.3.fill" }
    }

    private var tempSliderValue: Double {
        (display.colorTemperature + 100) / 2  // -100...+100 → 0...100
    }

    private var colorTempIcon: String {
        if display.colorTemperature > 20 { return "sun.max.fill" }
        else if display.colorTemperature < -20 { return "moon.fill" }
        else { return "circle.lefthalf.filled" }
    }

    private func applyColorTemp(_ value: Double) {
        var adj = GammaService.shared.loadSavedState(for: display.displayID) ?? GammaAdjustment()
        adj.colorTemperature = value
        adj.isPaused = false
        GammaService.shared.apply(adj, for: display.displayID)
        GammaService.shared.saveState(adj, for: display.displayID)
    }
}
