import SwiftUI
import CoreImage
import Metal

// MARK: - StreamContentView
//
// Renders the live captured frame for a display into the PiP window. Recovered from
// the original Phase-9 StreamWindow.swift (deleted in commit 6f65f78) and trimmed to
// just the pieces the PiP feature needs.
struct StreamContentView: View {
    @ObservedObject var viewModel: StreamViewModel
    // The live frames are @Published on the *nested* ScreenCaptureService, and SwiftUI
    // does not propagate changes from a nested ObservableObject. Observe it directly, or
    // the view renders exactly once and freezes on the first frame.
    @ObservedObject var service: ScreenCaptureService

    init(viewModel: StreamViewModel) {
        self.viewModel = viewModel
        self.service = viewModel.service
    }

    var body: some View {
        ZStack {
            Color.black
            if let frame = service.latestFrame {
                CIImageDisplayView(ciImage: viewModel.processedImage(frame))
            } else if viewModel.isCapturing {
                ProgressView("Waiting for frames…")
                    .progressViewStyle(.circular)
                    .tint(.white)
            } else if let err = service.errorMessage {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 32))
                        .foregroundColor(.orange)
                    Text(err)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "display.trianglebadge.exclamationmark")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("Not capturing")
                        .foregroundColor(.secondary)
                }
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - CIImageDisplayView

/// NSViewRepresentable wrapper that renders a CIImage into a layer-backed NSView.
struct CIImageDisplayView: NSViewRepresentable {
    let ciImage: CIImage

    func makeNSView(context: Context) -> StreamNSView { StreamNSView() }
    func updateNSView(_ nsView: StreamNSView, context: Context) { nsView.ciImage = ciImage }
}

// MARK: - StreamNSView

/// Layer-backed NSView that renders a CIImage efficiently via a Metal-backed CIContext.
final class StreamNSView: NSView {
    var ciImage: CIImage? {
        didSet { needsDisplay = true }
    }

    private static let ciContext: CIContext = {
        if let device = MTLCreateSystemDefaultDevice() {
            return CIContext(mtlDevice: device, options: [.useSoftwareRenderer: false])
        }
        return CIContext(options: [.useSoftwareRenderer: false])
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = CGColor.black
    }

    required init?(coder: NSCoder) { fatalError() }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        guard let ciImage = ciImage else {
            layer?.contents = nil
            return
        }
        let extent = ciImage.extent
        guard !extent.isEmpty, !extent.isInfinite else { return }
        if let cgImage = Self.ciContext.createCGImage(ciImage, from: extent) {
            layer?.contents = cgImage
            layer?.contentsGravity = .resizeAspect
            layer?.backgroundColor = CGColor.black
        }
    }
}
