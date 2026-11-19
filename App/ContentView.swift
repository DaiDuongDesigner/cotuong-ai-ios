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
                    Card(title: "1. Hiệu chỉnh bàn cờ") {
                        Text(model.calibration == nil
                             ? "Chụp màn hình app cờ bạn chơi khi đang ở thế cờ ban đầu, rồi căn lưới một lần."
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

                    Card(title: "2. Bật cửa sổ nổi") {
                        PiPLayerView(controller: model.pip)
                            .aspectRatio(BoardRenderer.size, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        Button {
                            model.pip.toggle()
                        } label: {
                            Label("Bật / tắt cửa sổ nổi", systemImage: "pip.enter").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        Text("Cửa sổ nổi cũng tự bật khi bạn rời app. Có thể kéo nó ra mép màn hình để thu gọn.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }

                    Card(title: "3. Bắt đầu đọc màn hình") {
                        HStack(spacing: 14) {
                            BroadcastPicker().frame(width: 56, height: 56)
                                .background(Color(white: 0.18), in: Circle())
                            Text("Chạm nút tròn → chọn **Cờ Tướng AI** → **Bắt đầu phát**. Sau đó mở app cờ của bạn; nước gợi ý hiện trong cửa sổ nổi.")
                                .font(.subheadline)
                        }
                        Text("Hình ảnh chỉ được xử lý ngay trên máy, không gửi đi đâu. Dừng bằng cách chạm thanh đỏ ở góc màn hình.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }

                    Card(title: "Thiết lập") {
                        Picker("AI nghĩ", selection: $model.thinkMs) {
                            Text("0,5 giây").tag(500); Text("1,5 giây").tag(1500); Text("3 giây").tag(3000)
                        }.pickerStyle(.segmented)
                        Toggle("Chỉ gợi ý khi tới lượt tôi", isOn: $model.onlyMyTurn)
                        HStack {
                            Button("Đổi lượt đi") { model.switchSide() }.buttonStyle(.bordered)
                            Button("Đặt lại ván") { model.resetGame() }.buttonStyle(.bordered)
                        }
                        Text("Nếu app hiểu sai lượt đi (ví dụ mở giữa ván), bấm “Đổi lượt đi”.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }

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

                    if !model.history.isEmpty {
                        Card(title: "Các nước đã ghi nhận") {
                            Text(model.history.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "   "))
                                .font(.footnote.monospaced())
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Cờ Tướng AI")
        }
    }
}
