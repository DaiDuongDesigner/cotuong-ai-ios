import SwiftUI
import PhotosUI
import CoreImage

/// Hiệu chỉnh: người dùng chọn ảnh chụp màn hình app cờ ở thế ban đầu, kéo 2 góc để lưới khớp với quân.
struct CalibrationView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var item: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var p0 = CGPoint(x: 0.08, y: 0.30)   // giao điểm trên-trái (chuẩn hoá)
    @State private var p1 = CGPoint(x: 0.92, y: 0.70)   // giao điểm dưới-phải
    @State private var flipped = false
    @State private var active = 0
    @State private var working = false
    @State private var message = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("1. Mở app cờ bạn hay chơi, vào một ván mới (thế cờ ban đầu) và **chụp màn hình**.\n2. Chọn ảnh đó bên dưới.\n3. Kéo 2 chấm vàng vào **tâm quân Xe góc trên-trái** và **tâm quân Xe góc dưới-phải** sao cho các vòng tròn trùng với quân.")
                    .font(.subheadline)

                PhotosPicker(selection: $item, matching: .screenshots) {
                    Label(image == nil ? "Chọn ảnh chụp màn hình" : "Chọn ảnh khác", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                if let image {
                    Toggle("Tôi cầm quân Đen (quân Đen nằm ở dưới)", isOn: $flipped)

                    Image(uiImage: image)
                        .resizable().scaledToFit()
                        .overlay(GeometryReader { geo in overlay(size: geo.size) })
                        .frame(maxHeight: 620)

                    Picker("Đang chỉnh", selection: $active) {
                        Text("Góc trên-trái").tag(0); Text("Góc dưới-phải").tag(1)
                    }.pickerStyle(.segmented)
                    HStack {
                        Spacer()
                        nudge("arrow.left", -1, 0); nudge("arrow.up", 0, -1); nudge("arrow.down", 0, 1); nudge("arrow.right", 1, 0)
                        Spacer()
                    }

                    Button {
                        save(image)
                    } label: {
                        Group { if working { ProgressView() } else { Text("Lưu hiệu chỉnh") } }.frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint(gold).foregroundStyle(.black).disabled(working)
                }
                if !message.isEmpty { Text(message).font(.subheadline) }
            }
            .padding()
        }
        .navigationTitle("Hiệu chỉnh")
        .onAppear {
            if let c = model.calibration {
                p0 = CGPoint(x: c.x0, y: c.y0); p1 = CGPoint(x: c.x1, y: c.y1); flipped = c.flipped
            }
        }
        .onChange(of: item) { it in
            Task {
                if let data = try? await it?.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                    await MainActor.run { image = img; message = "" }
                }
            }
        }
    }

    // Lưới 90 vòng tròn + 2 chấm kéo được
    @ViewBuilder private func overlay(size: CGSize) -> some View {
        let a = CGPoint(x: p0.x * size.width, y: p0.y * size.height)
        let b = CGPoint(x: p1.x * size.width, y: p1.y * size.height)
        let dx = (b.x - a.x) / 8, dy = (b.y - a.y) / 9
        ZStack {
            Canvas { ctx, _ in
                let r = max(2, min(abs(dx), abs(dy)) * 0.42)
                for row in 0..<10 { for col in 0..<9 {
                    let c = CGPoint(x: a.x + CGFloat(col) * dx, y: a.y + CGFloat(row) * dy)
                    ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                               with: .color(.green.opacity(0.85)), lineWidth: 1.5)
                } }
            }
            handle(at: a, index: 0, size: size)
            handle(at: b, index: 1, size: size)
        }
    }

    private func handle(at p: CGPoint, index: Int, size: CGSize) -> some View {
        Circle().fill(gold).frame(width: 22, height: 22)
            .overlay(Circle().stroke(.black, lineWidth: 2))
            .position(p)
            .gesture(DragGesture().onChanged { g in
                active = index
                let n = CGPoint(x: min(max(g.location.x / size.width, 0), 1),
                                y: min(max(g.location.y / size.height, 0), 1))
                if index == 0 { p0 = n } else { p1 = n }
            })
    }

    private func nudge(_ icon: String, _ x: CGFloat, _ y: CGFloat) -> some View {
        Button {
            guard let image else { return }
            let sx = 1 / image.size.width, sy = 1 / image.size.height   // 1 điểm ảnh
            if active == 0 { p0.x += x * sx; p0.y += y * sy } else { p1.x += x * sx; p1.y += y * sy }
        } label: { Image(systemName: icon).frame(width: 44, height: 36) }
        .buttonStyle(.bordered)
    }

    private func save(_ img: UIImage) {
        guard let cg = img.cgImage else { message = "Ảnh không hợp lệ"; return }
        working = true; message = ""
        let (a, b, f) = (p0, p1, flipped)
        DispatchQueue.global(qos: .userInitiated).async {
            let res = Recognizer().calibrate(image: CIImage(cgImage: cg), x0: a.x, y0: a.y, x1: b.x, y1: b.y, flipped: f)
            DispatchQueue.main.async {
                working = false
                guard let res else { message = "Không xử lý được – kiểm tra lại 2 góc."; return }
                p0 = CGPoint(x: res.calibration.x0, y: res.calibration.y0)
                p1 = CGPoint(x: res.calibration.x1, y: res.calibration.y1)
                if res.correct >= 88 {
                    do {
                        try model.saveCalibration(res.calibration)
                        message = "✅ Đã lưu. Tự kiểm tra: đọc đúng \(res.correct)/90 ô. Lưới đã được tự căn chỉnh."
                    } catch { message = "Lỗi lưu: \(error.localizedDescription)" }
                } else {
                    message = "⚠️ Chỉ đọc đúng \(res.correct)/90 ô. Hãy chắc ảnh đang ở thế cờ ban đầu, đúng màu quân, và căn lại 2 góc."
                }
            }
        }
    }
}
