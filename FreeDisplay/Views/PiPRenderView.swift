import SwiftUI
import CoreImage
import Metal
import AppKit

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
        Group {
            if let frame = service.latestFrame {
                // No opaque background behind the frame — the transparency spotlight needs
                // to reveal what's behind the *window*, not a black fill.
                CIImageDisplayView(ciImage: viewModel.processedImage(frame),
                                   hoverScreenPoint: viewModel.hoverScreenPoint)
            } else {
                ZStack {
                    Color.black
                    if viewModel.isCapturing {
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
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - CIImageDisplayView

/// NSViewRepresentable wrapper that renders a CIImage into a layer-backed NSView.
struct CIImageDisplayView: NSViewRepresentable {
    let ciImage: CIImage
    let hoverScreenPoint: CGPoint?

    func makeNSView(context: Context) -> StreamNSView { StreamNSView() }
    func updateNSView(_ nsView: StreamNSView, context: Context) {
        nsView.hoverScreenPoint = hoverScreenPoint
        nsView.ciImage = ciImage
    }
}

// MARK: - StreamNSView

/// Layer-backed NSView that renders a CIImage efficiently via a Metal-backed CIContext.
/// When `hoverScreenPoint` is set, it dissolves a soft, gaussian-feathered transparent
/// hole into the frame around the cursor so the user can see through the window there.
final class StreamNSView: NSView {
    var ciImage: CIImage? {
        didSet { needsDisplay = true }
    }
    /// Screen-space cursor for the transparency spotlight; nil = fully opaque frame.
    var hoverScreenPoint: CGPoint? {
        didSet { needsDisplay = true }
    }

    // Spotlight geometry, in view points.
    private let holeRadius: CGFloat = 150    // fully transparent inner radius
    private let holeFeather: CGFloat = 150   // width of the gaussian falloff ring

    private static let ciContext: CIContext = {
        if let device = MTLCreateSystemDefaultDevice() {
            return CIContext(mtlDevice: device, options: [.useSoftwareRenderer: false])
        }
        return CIContext(options: [.useSoftwareRenderer: false])
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        // Clear (not black) so the transparency spotlight reveals what's behind the window.
        layer?.backgroundColor = .clear
    }

    required init?(coder: NSCoder) { fatalError() }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        guard let ciImage = ciImage else { layer?.contents = nil; return }
        let extent = ciImage.extent
        guard !extent.isEmpty, !extent.isInfinite else { return }

        var output = ciImage
        if let sp = hoverScreenPoint, let holed = applyHole(to: ciImage, screenPoint: sp) {
            output = holed
        }

        if let cgImage = Self.ciContext.createCGImage(output, from: extent) {
            layer?.contents = cgImage
            layer?.contentsGravity = .resizeAspect
            layer?.backgroundColor = .clear
        }

        // Wireframe border while the spotlight is active, so the (now partly transparent)
        // window edges stay visible for grabbing and resizing.
        if hoverScreenPoint != nil {
            layer?.borderColor = NSColor.white.withAlphaComponent(0.9).cgColor
            layer?.borderWidth = 1.5
        } else {
            layer?.borderWidth = 0
        }
    }

    /// Blends a transparent, gaussian-feathered circular hole into `image` centered on the
    /// cursor, so the region around the pointer becomes see-through.
    private func applyHole(to image: CIImage, screenPoint: CGPoint) -> CIImage? {
        let extent = image.extent
        let vb = bounds
        guard vb.width > 0, vb.height > 0, let win = window else { return nil }

        // screen → window → view (AppKit conversions handle any coordinate flip)
        let winPt = win.convertPoint(fromScreen: screenPoint)
        let viewPt = convert(winPt, from: nil)

        // Map the view point into image pixels using the same aspect-fit as .resizeAspect.
        let scale = min(vb.width / extent.width, vb.height / extent.height)
        guard scale > 0 else { return nil }
        let dispW = extent.width * scale, dispH = extent.height * scale
        let ox = (vb.width - dispW) / 2, oy = (vb.height - dispH) / 2
        let imgX = (viewPt.x - ox) / scale + extent.minX
        let imgY = (viewPt.y - oy) / scale + extent.minY

        let r0 = holeRadius / scale
        let r1 = (holeRadius + holeFeather) / scale

        // Mask: alpha 0 at the cursor (→ transparent) ramping to alpha 1 outside (→ frame).
        guard let grad = CIFilter(name: "CIRadialGradient") else { return nil }
        grad.setValue(CIVector(x: imgX, y: imgY), forKey: "inputCenter")
        grad.setValue(r0, forKey: "inputRadius0")
        grad.setValue(r1, forKey: "inputRadius1")
        grad.setValue(CIColor(red: 0, green: 0, blue: 0, alpha: 0), forKey: "inputColor0")
        grad.setValue(CIColor(red: 1, green: 1, blue: 1, alpha: 1), forKey: "inputColor1")
        guard var mask = grad.outputImage else { return nil }
        mask = mask.cropped(to: extent)

        // Gaussian-soften the ring for a smooth falloff.
        if let blur = CIFilter(name: "CIGaussianBlur") {
            blur.setValue(mask.clampedToExtent(), forKey: kCIInputImageKey)
            blur.setValue((holeFeather / scale) * 0.35, forKey: kCIInputRadiusKey)
            if let blurred = blur.outputImage { mask = blurred.cropped(to: extent) }
        }

        // Where mask alpha = 1 → keep the frame; where 0 → transparent background.
        guard let blend = CIFilter(name: "CIBlendWithMask") else { return nil }
        blend.setValue(image, forKey: kCIInputImageKey)
        blend.setValue(CIImage.empty(), forKey: kCIInputBackgroundImageKey)
        blend.setValue(mask, forKey: "inputMaskImage")
        return blend.outputImage?.cropped(to: extent)
    }
}
