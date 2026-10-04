import AVFoundation
import AppKit
import SwiftUI

/// Shows a feed's frames with mirror, rotation, zoom and pan applied. Mouse handling lives here
/// too: click to spotlight, drag to pan when zoomed, scroll or pinch to zoom, double-click to reset.
struct VideoLayerView: NSViewRepresentable {
    let router: FrameRouter
    var mirrored: Bool
    var quarterTurns: Int
    @Binding var zoom: CGFloat
    @Binding var pan: CGSize
    var onClick: () -> Void

    func makeNSView(context: Context) -> VideoNSView {
        let view = VideoNSView()
        view.attach(router)
        return view
    }

    func updateNSView(_ view: VideoNSView, context: Context) {
        if view.router !== router { view.attach(router) }
        view.mirrored = mirrored
        view.quarterTurns = quarterTurns
        view.zoom = zoom
        view.pan = pan
        view.onClick = onClick
        view.onZoomPan = { newZoom, newPan in
            zoom = newZoom
            pan = newPan
        }
        view.needsLayout = true
    }

    static func dismantleNSView(_ view: VideoNSView, coordinator: ()) {
        view.detach()
    }
}

final class VideoNSView: NSView {
    private(set) var router: FrameRouter?
    private var sinkID: UUID?
    private let displayLayer = AVSampleBufferDisplayLayer()
    private var format: CMVideoFormatDescription?
    private let formatLock = NSLock()

    var mirrored = false
    var quarterTurns = 0
    var zoom: CGFloat = 1
    var pan: CGSize = .zero
    var onClick: (() -> Void)?
    var onZoomPan: ((CGFloat, CGSize) -> Void)?

    private var dragged = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.masksToBounds = true
        displayLayer.videoGravity = .resizeAspect
        layer?.addSublayer(displayLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func attach(_ router: FrameRouter) {
        detach()
        self.router = router
        sinkID = router.addSink { [weak self] buffer in
            self?.enqueue(buffer)
        }
    }

    func detach() {
        if let sinkID { router?.removeSink(sinkID) }
        sinkID = nil
        router = nil
    }

    // MARK: Rendering

    private func enqueue(_ pixelBuffer: CVPixelBuffer) {
        let format: CMVideoFormatDescription? = formatLock.withLock {
            if self.format == nil || !CMVideoFormatDescriptionMatchesImageBuffer(self.format!, imageBuffer: pixelBuffer) {
                var newFormat: CMVideoFormatDescription?
                CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: pixelBuffer, formatDescriptionOut: &newFormat)
                self.format = newFormat
            }
            return self.format
        }
        guard let format else { return }

        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()), decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: pixelBuffer, formatDescription: format, sampleTiming: &timing, sampleBufferOut: &sample)
        guard let sample else { return }

        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true), CFArrayGetCount(attachments) > 0 {
            let dictionary = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(dictionary, Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(), Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }

        let renderer = displayLayer.sampleBufferRenderer
        if renderer.status == .failed || renderer.requiresFlushToResumeDecoding {
            renderer.flush()
        }
        renderer.enqueue(sample)
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let sideways = quarterTurns % 2 != 0
        displayLayer.bounds = CGRect(
            x: 0, y: 0,
            width: sideways ? bounds.height : bounds.width,
            height: sideways ? bounds.width : bounds.height
        )
        displayLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)

        // Same order as Snapshotter so photos match what's on screen.
        let transform = CGAffineTransform(scaleX: mirrored ? -1 : 1, y: 1)
            .concatenating(CGAffineTransform(rotationAngle: -CGFloat(quarterTurns) * .pi / 2))
            .concatenating(CGAffineTransform(scaleX: zoom, y: zoom))
            .concatenating(CGAffineTransform(translationX: pan.width, y: -pan.height))
        displayLayer.setAffineTransform(transform)

        CATransaction.commit()
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        dragged = false
        if event.clickCount == 2 {
            onZoomPan?(1, .zero)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard zoom > 1 else { return }
        dragged = true
        setPan(CGSize(width: pan.width + event.deltaX, height: pan.height + event.deltaY))
    }

    override func mouseUp(with event: NSEvent) {
        if !dragged, event.clickCount == 1 {
            onClick?()
        }
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY / 200 : event.scrollingDeltaY / 20
        setZoom(zoom * (1 + delta))
    }

    override func magnify(with event: NSEvent) {
        setZoom(zoom * (1 + event.magnification))
    }

    private func setZoom(_ newZoom: CGFloat) {
        let clamped = min(max(newZoom, 1), 5)
        onZoomPan?(clamped, clamped == 1 ? .zero : clampedPan(pan, zoom: clamped))
    }

    private func setPan(_ newPan: CGSize) {
        onZoomPan?(zoom, clampedPan(newPan, zoom: zoom))
    }

    /// Keeps the zoomed picture covering the tile.
    private func clampedPan(_ pan: CGSize, zoom: CGFloat) -> CGSize {
        let maxX = bounds.width * (zoom - 1) / 2
        let maxY = bounds.height * (zoom - 1) / 2
        return CGSize(width: min(max(pan.width, -maxX), maxX), height: min(max(pan.height, -maxY), maxY))
    }
}
