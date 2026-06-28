import SwiftUI

/// Volume control for an external display over DDC/CI (VCP 0x62 + mute 0x8D).
///
/// While the monitor's audio support is being probed the row shows a slider in
/// a neutral state. If the probe determines the display has no DDC audio control
/// the row collapses to a short "not supported" hint so it never looks broken.
struct VolumeSliderView: View {
    @ObservedObject var display: DisplayInfo

    @State private var localVolume: Double = 50
    @State private var isDragging: Bool = false
    @State private var ddcStatus: Bool? = nil   // nil = probing, true = available, false = unsupported
    /// Throttle DDC writes during drag to ~100ms intervals (I2C is slow).
    @State private var lastDDCWrite: Date = .distantPast

    var body: some View {
        Group {
            if ddcStatus == false {
                // Probed and unsupported — show a compact, unobtrusive hint.
                HStack(spacing: 6) {
                    Image(systemName: "speaker.slash")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 14)
                        .accessibilityHidden(true)
                    Text("此显示器不支持 DDC 音量控制")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .help("显示器未通过 DDC/CI 报告音量控制（VCP 0x62）")
            } else {
                sliderRow
            }
        }
        .task(id: display.displayID) {
            localVolume = display.volume
            await VolumeService.shared.refreshVolume(for: display)
            ddcStatus = VolumeService.shared.isDDCVolumeAvailable(for: display.displayID)
        }
        .onChange(of: display.volume) { _, newValue in
            if !isDragging && abs(newValue - localVolume) >= 1 {
                localVolume = newValue
            }
        }
    }

    private var sliderRow: some View {
        HStack(spacing: 6) {
            // Mute toggle button
            Button {
                let newMuted = !display.isMuted
                VolumeService.shared.setMute(newMuted, for: display)
            } label: {
                Image(systemName: display.isMuted ? "speaker.slash.fill" : speakerIcon)
                    .font(.caption)
                    .foregroundColor(display.isMuted ? .red : .secondary)
                    .frame(width: 14)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(display.isMuted ? "取消静音" : "静音")
            .help(display.isMuted ? "取消静音" : "静音")

            Slider(value: $localVolume, in: 0...100, step: 1) { editing in
                isDragging = editing
                if !editing {
                    VolumeService.shared.setVolume(localVolume, for: display)
                    lastDDCWrite = Date()
                    // Re-read availability after the first real write.
                    ddcStatus = VolumeService.shared.isDDCVolumeAvailable(for: display.displayID)
                }
            }
            .disabled(display.isMuted)
            .accessibilityLabel("显示器音量")
            .accessibilityValue("\(Int(localVolume))%")
            .help("拖动调整显示器音量")
            .onChange(of: localVolume) { _, newValue in
                guard isDragging else { return }
                let now = Date()
                // Throttle DDC writes to ~100ms during drag to avoid flooding the I2C bus.
                if now.timeIntervalSince(lastDDCWrite) < 0.1 {
                    display.volume = newValue
                    return
                }
                lastDDCWrite = now
                VolumeService.shared.setVolume(newValue, for: display)
            }

            Text("\(Int(localVolume))%")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 40, alignment: .trailing)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    private var speakerIcon: String {
        if localVolume < 1 { return "speaker.fill" }
        else if localVolume < 34 { return "speaker.wave.1.fill" }
        else if localVolume < 67 { return "speaker.wave.2.fill" }
        else { return "speaker.wave.3.fill" }
    }
}
