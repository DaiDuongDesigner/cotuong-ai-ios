import AVKit
import UIKit
import SwiftUI

/// Cửa sổ nổi Picture-in-Picture: phát "video" là ảnh bàn cờ mini, cập nhật mỗi khi có gợi ý mới.
/// Đây là cách duy nhất iOS cho phép một khung của app hiển thị đè lên app khác.
final class PiPController: NSObject, ObservableObject {
    let displayLayer = AVSampleBufferDisplayLayer()
    private var pip: AVPictureInPictureController?
    private var timer: Timer?
    private var current: UIImage?
    @Published var isActive = false
    @Published var isSupported = AVPictureInPictureController.isPictureInPictureSupported()

    override init() {
        super.init()
        displayLayer.videoGravity = .resizeAspect
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
        try? session.setActive(true)
        if isSupported {
            let source = AVPictureInPictureController.ContentSource(sampleBufferDisplayLayer: displayLayer,
                                                                    playbackDelegate: self)
            let c = AVPictureInPictureController(contentSource: source)
            c.delegate = self
            c.canStartPictureInPictureAutomaticallyFromInline = true
            pip = c
        }
        // Gửi lại khung hình định kỳ để PiP không bị đen khi ở nền.
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.push() }
    }

    func update(_ image: UIImage) {
        current = image
        push()
    }

    private func push() {
        guard let img = current, let sb = img.makeSampleBuffer() else { return }
        if displayLayer.status == .failed { displayLayer.flush() }
        displayLayer.enqueue(sb)
    }

    func toggle() {
        guard let pip else { return }
        if pip.isPictureInPictureActive { pip.stopPictureInPicture() } else { pip.startPictureInPicture() }
    }
}

extension PiPController: AVPictureInPictureControllerDelegate {
    func pictureInPictureControllerDidStartPictureInPicture(_ c: AVPictureInPictureController) { isActive = true }
    func pictureInPictureControllerDidStopPictureInPicture(_ c: AVPictureInPictureController) { isActive = false }
    func pictureInPictureController(_ c: AVPictureInPictureController,
                                    failedToStartPictureInPictureWithError error: Error) {
        print("PiP lỗi:", error.localizedDescription)
    }
}

extension PiPController: AVPictureInPictureSampleBufferPlaybackDelegate {
    func pictureInPictureController(_ c: AVPictureInPictureController, setPlaying playing: Bool) {}
    func pictureInPictureControllerTimeRangeForPlayback(_ c: AVPictureInPictureController) -> CMTimeRange {
        CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)   // dạng "phát trực tiếp"
    }
    func pictureInPictureControllerIsPlaybackPaused(_ c: AVPictureInPictureController) -> Bool { false }
    func pictureInPictureController(_ c: AVPictureInPictureController,
                                    didTransitionToRenderSize newRenderSize: CMVideoDimensions) {}
    func pictureInPictureController(_ c: AVPictureInPictureController, skipByInterval skipInterval: CMTime,
                                    completion completionHandler: @escaping () -> Void) { completionHandler() }
}

/// View SwiftUI chứa lớp hiển thị (PiP cần lớp này nằm trên màn hình của app).
struct PiPLayerView: UIViewRepresentable {
    let controller: PiPController
    func makeUIView(context: Context) -> LayerHost { LayerHost(layer: controller.displayLayer) }
    func updateUIView(_ uiView: LayerHost, context: Context) {}

    final class LayerHost: UIView {
        let hosted: CALayer
        init(layer: CALayer) {
            hosted = layer
            super.init(frame: .zero)
            self.layer.addSublayer(layer)
            backgroundColor = .black
        }
        required init?(coder: NSCoder) { fatalError() }
        override func layoutSubviews() { super.layoutSubviews(); hosted.frame = bounds }
    }
}

extension UIImage {
    func makeSampleBuffer() -> CMSampleBuffer? {
        guard let cg = cgImage else { return nil }
        let w = cg.width, h = cg.height
        var pbOut: CVPixelBuffer?
        let attrs = [kCVPixelBufferCGImageCompatibilityKey: true,
                     kCVPixelBufferCGBitmapContextCompatibilityKey: true,
                     kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: Any]] as CFDictionary
        guard CVPixelBufferCreate(kCFAllocatorDefault, w, h, kCVPixelFormatType_32BGRA, attrs, &pbOut) == kCVReturnSuccess,
              let pb = pbOut else { return nil }
        CVPixelBufferLockBaseAddress(pb, [])
        let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pb), width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: CVPixelBufferGetBytesPerRow(pb), space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        ctx?.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        CVPixelBufferUnlockBaseAddress(pb, [])

        var fmtOut: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pb,
                                                     formatDescriptionOut: &fmtOut)
        guard let fmt = fmtOut else { return nil }
        var timing = CMSampleTimingInfo(duration: .invalid,
                                        presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
                                        decodeTimeStamp: .invalid)
        var sbOut: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pb,
                                                 formatDescription: fmt, sampleTiming: &timing, sampleBufferOut: &sbOut)
        guard let sb = sbOut else { return nil }
        if let arr = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: true), CFArrayGetCount(arr) > 0 {
            let dict = unsafeBitCast(CFArrayGetValueAtIndex(arr, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(dict,
                                 Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                                 Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        return sb
    }
}
