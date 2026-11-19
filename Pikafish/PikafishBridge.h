#ifndef PIKAFISH_BRIDGE_H
#define PIKAFISH_BRIDGE_H

#ifdef __cplusplus
extern "C" {
#endif

/// Khởi động engine (chỉ lần đầu). resourceDir: thư mục chứa pikafish.nnue.
void pikafish_start(const char* resourceDir);
/// Gửi một lệnh UCI (không cần "\n").
void pikafish_send(const char* cmd);
/// Đọc một dòng engine in ra. Trả về độ dài, hoặc -1 nếu hết thời gian chờ.
int pikafish_read(char* buf, int cap, int timeoutMs);
/// Bỏ các dòng chưa đọc.
void pikafish_clear_output(void);

#ifdef __cplusplus
}
#endif

#endif
