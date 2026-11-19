import SwiftUI
import ReplayKit

@main
struct CoTuongAIApp: App {
    @StateObject private var model = AppModel()
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .preferredColorScheme(.dark)
        }
    }
}

/// Nút hệ thống để bắt đầu/dừng "phát sóng màn hình" vào extension của app.
struct BroadcastPicker: UIViewRepresentable {
    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let v = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 56, height: 56))
        v.preferredExtension = Self.extensionBundleID()
        v.showsMicrophoneButton = false
        if let b = v.subviews.compactMap({ $0 as? UIButton }).first {
            b.imageView?.tintColor = UIColor(red: 0.88, green: 0.70, blue: 0.36, alpha: 1)
        }
        return v
    }
    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}

    /// Chẩn đoán: extension có còn trong app sau khi ký (ESign) không, và bundle id có hợp lệ không.
    static func diagnose() -> (ok: Bool, text: String) {
        let appID = Bundle.main.bundleIdentifier ?? "?"
        guard let dir = Bundle.main.builtInPlugInsURL,
              let items = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil),
              let appex = items.first(where: { $0.pathExtension == "appex" }) else {
            return (false, "❌ Không tìm thấy phần đọc màn hình trong app – công cụ ký (ESign) đã gỡ nó. Hãy ký lại và TẮT tuỳ chọn xoá plugin/tiện ích mở rộng.")
        }
        let b = Bundle(url: appex)
        let extID = b?.bundleIdentifier ?? "?"
        guard extID.hasPrefix(appID + ".") else {
            return (false, "❌ Mã định danh không khớp: app \(appID), phần đọc màn hình \(extID). iOS sẽ bỏ qua phần này. Khi ký, đừng đổi Bundle ID (hoặc dùng tuỳ chọn đổi cho cả plugin).")
        }
        return (true, "✅ Phần đọc màn hình đã cài (\(extID)). Nếu chưa thấy trong danh sách Ghi màn hình, hãy khởi động lại iPhone.")
    }

    /// Đọc bundle id thật của extension (ESign có thể đổi bundle id khi ký lại).
    static func extensionBundleID() -> String? {
        guard let dir = Bundle.main.builtInPlugInsURL,
              let items = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return nil }
        for url in items where url.pathExtension == "appex" {
            if let b = Bundle(url: url), let id = b.bundleIdentifier { return id }
        }
        return nil
    }
}
