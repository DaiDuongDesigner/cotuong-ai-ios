import Foundation

/// Dữ liệu dùng chung giữa app chính và Broadcast Extension (qua App Group).
/// ⚠️ Đổi `groupID` cho khớp với App Group bạn tạo trong tài khoản Apple Developer.
enum SharedStore {
    static let groupID = "group.com.example.cotuongai"
    static let darwinName = "com.example.cotuongai.board" as CFString

    static var container: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)
    }
    static var defaults: UserDefaults? { UserDefaults(suiteName: groupID) }

    // MARK: Hiệu chỉnh
    private static var localURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("calibration.json")
    }

    /// Lưu vào App Group (nếu có) và vào thư mục riêng của app (dự phòng khi cài bằng ESign).
    static func saveCalibration(_ c: Calibration) throws {
        let data = try JSONEncoder().encode(c)
        var saved = false
        if let url = container?.appendingPathComponent("calibration.json"),
           (try? data.write(to: url, options: .atomic)) != nil { saved = true }
        if let url = localURL, (try? data.write(to: url, options: .atomic)) != nil { saved = true }
        if !saved {
            throw NSError(domain: "CoTuongAI", code: 1, userInfo: [NSLocalizedDescriptionKey: "Không lưu được hiệu chỉnh."])
        }
    }

    static func loadCalibration() -> Calibration? {
        for url in [container?.appendingPathComponent("calibration.json"), localURL].compactMap({ $0 }) {
            if let data = try? Data(contentsOf: url),
               let c = try? JSONDecoder().decode(Calibration.self, from: data) { return c }
        }
        return nil
    }

    static func calibrationJSON() -> String? {
        guard let c = loadCalibration(), let d = try? JSONEncoder().encode(c) else { return nil }
        return String(data: d, encoding: .utf8)
    }

    // MARK: Thế cờ đọc được từ màn hình
    static func publishBoard(_ board: String) {
        defaults?.set(board, forKey: "board")
        defaults?.set(Date().timeIntervalSince1970, forKey: "boardTime")
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                             CFNotificationName(darwinName), nil, nil, true)
    }

    static func readBoard() -> String? { defaults?.string(forKey: "board") }

    static func writeHeartbeat(fps: Double, boardVisible: Bool) {
        defaults?.set(Date().timeIntervalSince1970, forKey: "hbTime")
        defaults?.set(fps, forKey: "hbFps")
        defaults?.set(boardVisible, forKey: "hbVisible")
    }
    static func readHeartbeat() -> (time: Double, fps: Double, visible: Bool)? {
        guard let d = defaults, d.double(forKey: "hbTime") > 0 else { return nil }
        return (d.double(forKey: "hbTime"), d.double(forKey: "hbFps"), d.bool(forKey: "hbVisible"))
    }

    static var isBroadcasting: Bool {
        get { defaults?.bool(forKey: "broadcasting") ?? false }
        set { defaults?.set(newValue, forKey: "broadcasting") }
    }
}

/// Lắng nghe thông báo Darwin do extension gửi khi thế cờ thay đổi.
final class DarwinObserver {
    static let shared = DarwinObserver()
    var handler: (() -> Void)?
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, _, _, _ in
                guard let observer else { return }
                let me = Unmanaged<DarwinObserver>.fromOpaque(observer).takeUnretainedValue()
                DispatchQueue.main.async { me.handler?() }
            },
            SharedStore.darwinName, nil, .deliverImmediately)
    }
}
