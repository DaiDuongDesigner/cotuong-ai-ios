# Cờ Tướng AI – Trợ lý nổi cho iPhone

Ứng dụng iOS **tự đọc bàn cờ** trên màn hình khi bạn đang chơi ở một app cờ tướng khác, rồi hiện **nước gợi ý + điểm đánh giá** trong một **cửa sổ nổi (Picture-in-Picture)** nằm đè lên app đó.

## Cách hoạt động

```
App cờ khác ──(Phát sóng màn hình / ReplayKit)──► Broadcast Extension
                                                   • đọc bàn cờ ~2 lần/giây
                                                   • so mẫu từng giao điểm với mẫu quân đã hiệu chỉnh
                                                   • gửi thế cờ (90 ký tự) qua App Group
                                                          │
                                                          ▼
                                        App chính (chạy nền nhờ PiP)
                                         • suy ra nước vừa đi & lượt đi
                                         • engine cờ tướng (JavaScriptCore) tính nước tốt nhất
                                         • vẽ bàn cờ mini + mũi tên → cửa sổ nổi PiP
```

iOS **không cho** app vẽ đè lên app khác như Android. Hai cơ chế duy nhất được phép là **Phát sóng màn hình** (để đọc) và **PiP** (để hiển thị), nên app ghép hai thứ đó lại. Mọi xử lý đều diễn ra **trên máy**, không gửi hình ảnh đi đâu.

## Cần có

- Máy **Mac** cài **Xcode 15** trở lên, và iPhone chạy **iOS 16** trở lên.
- **Apple ID** đăng nhập trong Xcode. Nếu Xcode không cho bật App Group bằng tài khoản miễn phí, bạn sẽ cần tài khoản Apple Developer trả phí (99 USD/năm). Với tài khoản miễn phí, app cài lên máy chỉ chạy được 7 ngày, sau đó phải cài lại.

## Build

1. Cài XcodeGen: `brew install xcodegen`.
2. Trong `project.yml` và `Shared/SharedStore.swift`, đổi `com.example` thành tiền tố riêng của bạn, ví dụ `com.tenban`. Hai App Group ID phải khớp nhau.
3. Trong thư mục này, chạy `xcodegen generate` rồi mở `CoTuongAI.xcodeproj`.
4. Ở cả 2 target (**CoTuongAI** và **CoTuongAIBroadcast**), vào *Signing & Capabilities* → chọn Team. Kiểm tra App Group đã được bật và có cùng ID.
5. Cắm iPhone vào máy, chọn target **CoTuongAI**, rồi bấm **Run**.

> Nếu không muốn dùng XcodeGen: tạo dự án *App* mới trong Xcode (SwiftUI), thêm target *Broadcast Upload Extension* (bỏ chọn "Include UI Extension"), chép các file trong `App/`, `Shared/`, `Broadcast/` và `Resources/engine.js` vào, sau đó bật App Group và Background Modes → *Audio, AirPlay, and Picture in Picture*.

## Sử dụng

1. **Hiệu chỉnh (làm 1 lần cho mỗi app cờ):**
   - Mở app cờ, vào một ván mới rồi chụp màn hình.
   - Trong Cờ Tướng AI, mở *Hiệu chỉnh* và chọn ảnh vừa chụp.
   - Kéo 2 chấm vàng vào tâm 2 quân Xe ở góc trên-trái và góc dưới-phải. Các vòng tròn xanh phải trùng với các quân.
   - Bấm *Lưu*. App tự căn lại lưới và tự kiểm tra; nếu đọc đúng từ 88/90 ô trở lên thì hiệu chỉnh được lưu.
2. **Bật cửa sổ nổi:** bấm *Bật / tắt cửa sổ nổi*. Cửa sổ cũng tự bật khi bạn rời app.
3. **Bắt đầu đọc màn hình:** chạm nút tròn → chọn *Cờ Tướng AI* → *Bắt đầu phát*.
4. Mở app cờ và chơi. Khi đến lượt bạn, cửa sổ nổi hiện mũi tên xanh, nước nên đi và điểm số.
5. Muốn dừng: chạm thanh/chấm đỏ ở góc màn hình → *Dừng*.

## Giới hạn

- Chỉ hỗ trợ màn hình **dọc**. Bàn cờ trong app cờ phải **đứng yên** (không thu phóng, không cuộn). Đổi app cờ hoặc đổi giao diện quân thì phải hiệu chỉnh lại.
- Nếu bạn mở app khi ván đã chơi dở, app chưa biết đang đến lượt ai và sẽ giả định là lượt bạn. Nếu sai, bấm **Đổi lượt đi**.
- Hiệu ứng như quân đang trượt hay popup che bàn cờ sẽ được bỏ qua, vì app chỉ nhận một thế cờ khi đọc được giống nhau 2 lần liên tiếp và thế cờ đó hợp lệ.
- Thuật toán nhận diện đã được thử trên ảnh chụp màn hình thật (cả khi bàn cờ lật). Tuy vậy mã Swift **chưa được biên dịch trên Mac**, nên lần build đầu có thể cần sửa vài lỗi nhỏ.

## Lưu ý về luật chơi

Nhiều app và giải đấu cờ tướng **cấm dùng AI hỗ trợ trong ván có xếp hạng hoặc ván đấu với người thật**, và có thể khoá tài khoản vi phạm. Nên dùng trợ lý này để luyện tập, xem lại ván, hoặc chơi với máy.
