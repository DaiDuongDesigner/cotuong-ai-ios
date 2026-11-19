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
