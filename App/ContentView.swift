import SwiftUI
import PhotosUI

let gold = Color(red: 0.88, green: 0.70, blue: 0.36)

struct Card<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased()).font(.caption.bold()).foregroundStyle(gold)
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(white: 0.11), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @State private var testItem: PhotosPickerItem?
    @State private var testMsg = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    calibrationCard
                    pipCard
                    screenCard
                    modelCard
                    openingCard
                    settingsCard
                    testCard
                    if !model.history.isEmpty {
                        Card(title: "Các nước đã ghi nhận") {
                            Text(model.history.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "   "))
                                .font(.footnote.monospaced())
                        }
                    }
                    Text("Pikafish © các tác giả Pikafish, phát hành theo GNU GPL v3. Dữ liệu đám mây: chessdb.cn.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationTitle("Cờ Tướng AI")
        }
    }

    private var calibrationCard: some View {
        Card(title: "1. Hiệu chỉnh bàn cờ") {
            Text(model.calibration == nil
                 ? "Chụp màn hình app cờ bạn chơi khi đang ở thế cờ ban đầu, rồi kéo lưới cho khớp tương đối – app tự căn phần còn lại."
                 : "Đã hiệu chỉnh – bạn cầm quân \(model.myColor == 0 ? "Đỏ" : "Đen"). Làm lại nếu đổi app cờ hoặc đổi màu quân.")
                .font(.subheadline).foregroundStyle(.secondary)
            NavigationLink {
                CalibrationView()
            } label: {
                Label(model.calibration == nil ? "Hiệu chỉnh ngay" : "Hiệu chỉnh lại", systemImage: "viewfinder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(gold).foregroundStyle(.black)
        }
    }

    private var pipCard: some View {
        Card(title: "2. Cửa sổ nổi") {
            PiPLayerView(controller: model.pip)
                .aspectRatio(BoardRenderer.size, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            Button {
                model.pip.toggle()
            } label: {
                Label("Bật / tắt cửa sổ nổi", systemImage: "pip.enter").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            Text("Cửa sổ nổi tự bật khi bạn rời app. Dùng 2 ngón tay để phóng to/thu nhỏ, kéo ra mép để thu gọn.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var screenCard: some View {
        Card(title: "3. Đọc toàn màn hình") {
            HStack(spacing: 14) {
                BroadcastPicker().frame(width: 56, height: 56)
                    .background(Color(white: 0.18), in: Circle())
                Text("Chạm nút tròn → chọn **Cờ Tướng AI** → **Bắt đầu phát**. Hệ thống sẽ ghi **toàn bộ màn hình** (mọi app), không chỉ riêng app này.")
                    .font(.subheadline)
            }
            HStack(spacing: 8) {
                Circle().fill(model.receiving ? (model.boardVisible ? Color.green : Color.orange) : Color.gray)
                    .frame(width: 10, height: 10)
                Text(model.screenStatus).font(.footnote)
            }
            DisclosureGroup("Bật từ Trung tâm điều khiển") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("1. Cài đặt → Trung tâm điều khiển → thêm **Ghi màn hình** (nếu chưa có).")
                    Text("2. Vuốt mở Trung tâm điều khiển, **chạm giữ** nút Ghi màn hình ⏺.")
                    Text("3. Chọn **Cờ Tướng AI** (không chọn Ảnh) → **Bắt đầu phát**.")
                    Text("4. Mở app cờ, chơi bình thường. Dừng bằng cách chạm thanh/chấm đỏ ở góc màn hình.")
                }
                .font(.footnote).padding(.top, 4)
            }
            .font(.subheadline)
            Text("Hình ảnh chỉ được xử lý ngay trên máy, không gửi đi đâu.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var modelCard: some View {
        Card(title: "Model AI") {
            Picker("Model AI", selection: $model.model) {
                ForEach(AIModel.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Text(model.model.detail).font(.footnote).foregroundStyle(.secondary)
            if model.model != .local {
                Text("Pikafish: \(model.pikafishState)").font(.footnote)
            }
            Picker("Thời gian nghĩ", selection: $model.thinkMs) {
                Text("0,5 giây").tag(500); Text("1,5 giây").tag(1500); Text("3 giây").tag(3000); Text("6 giây").tag(6000)
            }
            .pickerStyle(.segmented)
            if let a = model.analysis, !a.over {
                Text("Đánh giá \(a.scoreText) · độ sâu \(a.depth) · \(a.source)\nBiến chính: \(a.pv.prefix(8).joined(separator: " "))")
                    .font(.footnote.monospaced())
            } else if model.thinking {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder private var openingCard: some View {
        Card(title: "Khai cuộc") {
            if let op = model.opening {
                if op.name.isEmpty {
                    Text("Chưa vào khai cuộc có tên.").font(.subheadline).foregroundStyle(.secondary)
                } else {
                    Text("📖 " + op.name).font(.headline)
                    Text(op.desc).font(.footnote).foregroundStyle(.secondary)
                }
                if !op.book.isEmpty {
                    Text("Nước theo sổ khai cuộc:").font(.footnote.bold())
                    ForEach(op.book.prefix(8), id: \.self) { b in
                        Text("• \(b.note) – \(b.name)").font(.footnote)
                    }
                }
            } else {
                Text("Bắt đầu theo dõi từ giữa ván nên không xác định được khai cuộc. Bấm “Đặt lại ván” khi vào ván mới.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private var settingsCard: some View {
        Card(title: "Thiết lập") {
            Toggle("Chỉ gợi ý khi tới lượt tôi", isOn: $model.onlyMyTurn)
            Toggle("Đọc nước gợi ý bằng giọng nói", isOn: $model.voice)
            HStack {
                Button("Đổi lượt đi") { model.switchSide() }.buttonStyle(.bordered)
                Button("Đặt lại ván") { model.resetGame() }.buttonStyle(.bordered)
            }
            Text("Nếu app hiểu sai lượt đi (ví dụ mở giữa ván), bấm “Đổi lượt đi”.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var testCard: some View {
        Card(title: "Thử nhận diện bằng ảnh") {
            PhotosPicker(selection: $testItem, matching: .images) {
                Label("Chọn ảnh chụp màn hình", systemImage: "photo").frame(maxWidth: .infinity)
            }.buttonStyle(.bordered)
            if !testMsg.isEmpty { Text(testMsg).font(.footnote) }
        }
        .onChange(of: testItem) { item in
            Task {
                guard let data = try? await item?.loadTransferable(type: Data.self),
                      let img = UIImage(data: data) else { return }
                await MainActor.run {
                    testMsg = model.recognize(image: img) ? "Đã đọc thế cờ ✓" : "Không đọc được – kiểm tra hiệu chỉnh."
                }
            }
        }
    }
}
