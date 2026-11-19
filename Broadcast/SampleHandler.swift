import ReplayKit
import CoreImage
import QuartzCore

/// Broadcast Upload Extension: nhận khung hình màn hình khi bạn đang ở app cờ khác,
/// đọc thế cờ ~2 lần/giây và gửi cho app chính (qua App Group và/hoặc kênh nội bộ 127.0.0.1).
/// Không gửi hình ảnh đi đâu cả – mọi thứ xử lý ngay trên máy.
final class SampleHandler: RPBroadcastSampleHandler {
    private let recognizer = Recognizer()
    private let client = LoopbackClient()
    private let lock = NSLock()
    private var _calibration: Calibration?
    private var calibration: Calibration? {
        get { lock.lock(); defer { lock.unlock() }; return _calibration }
        set { lock.lock(); _calibration = newValue; lock.unlock() }
    }
    private var lastProcess: CFTimeInterval = 0
    private var lastRead: String?
    private var lastSent: String?
    private var framesInWindow = 0
    private var windowStart: CFTimeInterval = 0
    private var lastVisible: CFTimeInterval = 0

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        SharedStore.isBroadcasting = true
        calibration = SharedStore.loadCalibration()
        client.onCalibration = { [weak self] cal in self?.calibration = cal }
        client.start()
        // Chờ nhận hiệu chỉnh từ app chính (trường hợp không có App Group).
        DispatchQueue.global().asyncAfter(deadline: .now() + 6) { [weak self] in
            guard let self, self.calibration == nil else { return }
            self.finishBroadcastWithError(NSError(domain: "CoTuongAI", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Chưa nhận được hiệu chỉnh. Mở app Cờ Tướng AI, làm bước Hiệu chỉnh, bật cửa sổ nổi rồi phát lại."]))
        }
    }

    override func broadcastFinished() { SharedStore.isBroadcasting = false; client.stop() }
    override func broadcastPaused() {}
    override func broadcastResumed() {}

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video, let cal = calibration else { return }
        let now = CACurrentMediaTime()
        if windowStart == 0 { windowStart = now }
        if now - windowStart >= 2 {
            let fps = Double(framesInWindow) / (now - windowStart)
            let visible = now - lastVisible < 3
            client.heartbeat(fps: fps, boardVisible: visible)
            SharedStore.writeHeartbeat(fps: fps, boardVisible: visible)
            framesInWindow = 0; windowStart = now
        }
        guard now - lastProcess >= 0.5 else { return }
        lastProcess = now
        framesInWindow += 1
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        autoreleasepool {
            var image = CIImage(cvPixelBuffer: pixelBuffer)
            if let num = CMGetAttachment(sampleBuffer, key: RPVideoSampleOrientationKey as CFString,
                                         attachmentModeOut: nil) as? NSNumber,
               let ori = CGImagePropertyOrientation(rawValue: num.uint32Value), ori != .up {
                image = image.oriented(ori)
            }
            guard let board = recognizer.read(image: image, cal: cal) else { lastRead = nil; return }
            lastVisible = now
            // Chỉ gửi khi đọc được giống nhau 2 khung liên tiếp (tránh lúc quân đang trượt).
            if board == lastRead && board != lastSent {
                lastSent = board
                SharedStore.publishBoard(board)
                client.send(board: board)
            }
            lastRead = board
        }
    }
}
