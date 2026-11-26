import AVKit
import CoreMedia
import UIKit

/// A Picture-in-Picture window that floats over every app.
/// It shows a drawn status card; its pause button is the Stop button.
final class PiPController: NSObject, ObservableObject {
    let displayLayer = AVSampleBufferDisplayLayer()

    @Published private(set) var isActive = false
    @Published private(set) var isPossible = false

    /// Called when the PiP play/pause button is tapped (true = play).
    var onSetPlaying: ((Bool) -> Void)?

    private var controller: AVPictureInPictureController?
    private var possibleObservation: NSKeyValueObservation?
    private var paused = false

    var isSupported: Bool { AVPictureInPictureController.isPictureInPictureSupported() }

    func setUp() {
        guard controller == nil, isSupported else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
        try? session.setActive(true)

        displayLayer.videoGravity = .resizeAspect
        let source = AVPictureInPictureController.ContentSource(sampleBufferDisplayLayer: displayLayer, playbackDelegate: self)
        let pip = AVPictureInPictureController(contentSource: source)
        pip.delegate = self
        pip.canStartPictureInPictureAutomaticallyFromInline = true
        possibleObservation = pip.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { [weak self] c, _ in
            DispatchQueue.main.async { self?.isPossible = c.isPictureInPicturePossible }
        }
        controller = pip
    }

    func start() { controller?.startPictureInPicture() }
    func stop() { controller?.stopPictureInPicture() }

    /// Draws the status card and shows it in the PiP window.
    func render(stopped: Bool, connected: Bool, detail: String) {
        paused = stopped
        if let image = StatusCard.image(stopped: stopped, connected: connected, detail: detail),
           let sample = StatusCard.sampleBuffer(from: image) {
            if displayLayer.status == .failed { displayLayer.flush() }
            displayLayer.enqueue(sample)
        }
        controller?.invalidatePlaybackState()
    }
}

extension PiPController: AVPictureInPictureControllerDelegate, AVPictureInPictureSampleBufferPlaybackDelegate {
    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        DispatchQueue.main.async { self.isActive = true }
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        DispatchQueue.main.async { self.isActive = false }
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, setPlaying playing: Bool) {
        paused = !playing
        DispatchQueue.main.async { self.onSetPlaying?(playing) }
    }

    func pictureInPictureControllerTimeRangeForPlayback(_ pictureInPictureController: AVPictureInPictureController) -> CMTimeRange {
        // A "live stream" with no scrubber.
        CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
    }

    func pictureInPictureControllerIsPlaybackPaused(_ pictureInPictureController: AVPictureInPictureController) -> Bool {
        paused
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                    didTransitionToRenderSize newRenderSize: CMVideoDimensions) {}

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                    skipByInterval skipInterval: CMTime,
                                    completion completionHandler: @escaping () -> Void) {
        completionHandler()
    }
}

/// Renders the card the PiP window shows.
enum StatusCard {
    static let size = CGSize(width: 640, height: 360)

    static func image(stopped: Bool, connected: Bool, detail: String) -> UIImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            let bg: UIColor
            let title: String
            let hint: String
            if !connected {
                bg = UIColor(white: 0.25, alpha: 1)
                title = "Not connected"
                hint = "Open Claude Control to check the PC address"
            } else if stopped {
                bg = UIColor(red: 0.30, green: 0.30, blue: 0.34, alpha: 1)
                title = "■ Claude is stopped"
                hint = "Press ▶ to let Claude continue"
            } else {
                bg = UIColor(red: 0.80, green: 0.20, blue: 0.16, alpha: 1)
                title = "Claude is controlling"
                hint = "Press ⏸ to STOP"
            }
            bg.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            let center = NSMutableParagraphStyle()
            center.alignment = .center
            center.lineBreakMode = .byTruncatingTail
            func draw(_ text: String, font: UIFont, y: CGFloat, height: CGFloat, alpha: CGFloat = 1) {
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: UIColor.white.withAlphaComponent(alpha),
                    .paragraphStyle: center,
                ]
                (text as NSString).draw(in: CGRect(x: 24, y: y, width: size.width - 48, height: height), withAttributes: attrs)
            }
            draw(title, font: .systemFont(ofSize: 54, weight: .heavy), y: 70, height: 70)
            draw(hint, font: .systemFont(ofSize: 34, weight: .semibold), y: 160, height: 46)
            draw(detail, font: .systemFont(ofSize: 28, weight: .regular), y: 250, height: 70, alpha: 0.8)
        }
    }

    static func sampleBuffer(from image: UIImage) -> CMSampleBuffer? {
        guard let cg = image.cgImage else { return nil }
        let width = cg.width, height = cg.height
        let attrs = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: Any],
        ] as CFDictionary
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, attrs, &pixelBuffer)
        guard let buffer = pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )
        context?.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        CVPixelBufferUnlockBaseAddress(buffer, [])

        var format: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: buffer, formatDescriptionOut: &format)
        guard let formatDescription = format else { return nil }

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 30),
            presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
            decodeTimeStamp: .invalid
        )
        var sample: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault, imageBuffer: buffer,
            formatDescription: formatDescription, sampleTiming: &timing, sampleBufferOut: &sample
        )
        guard let sampleBuffer = sample else { return nil }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true),
           CFArrayGetCount(attachments) > 0 {
            let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(dict,
                                 Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                                 Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        return sampleBuffer
    }
}
