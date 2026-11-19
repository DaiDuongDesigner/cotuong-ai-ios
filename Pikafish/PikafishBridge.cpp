// Cầu nối C cho Pikafish (GPL-3.0): chạy vòng lặp UCI trong một luồng riêng,
// chuyển std::cin / std::cout của engine sang hàng đợi trong bộ nhớ.
#include <chrono>
#include <condition_variable>
#include <cstring>
#include <deque>
#include <iostream>
#include <memory>
#include <mutex>
#include <streambuf>
#include <string>
#include <thread>
#include <vector>

#include "attacks.h"
#include "misc.h"
#include "position.h"
#include "tune.h"
#include "uci.h"

#include "PikafishBridge.h"

using namespace Stockfish;

namespace {

struct LineQueue {
    std::mutex              m;
    std::condition_variable cv;
    std::deque<std::string> q;

    void push(std::string s) {
        {
            std::lock_guard<std::mutex> l(m);
            q.push_back(std::move(s));
        }
        cv.notify_one();
    }
    bool pop(std::string& out, int timeoutMs) {
        std::unique_lock<std::mutex> l(m);
        if (timeoutMs < 0)
            cv.wait(l, [&] { return !q.empty(); });
        else if (!cv.wait_for(l, std::chrono::milliseconds(timeoutMs), [&] { return !q.empty(); }))
            return false;
        out = std::move(q.front());
        q.pop_front();
        return true;
    }
    void clear() {
        std::lock_guard<std::mutex> l(m);
        q.clear();
    }
};

LineQueue toEngine, fromEngine;

class InBuf: public std::streambuf {
    std::string cur;

   protected:
    int_type underflow() override {
        if (gptr() < egptr())
            return traits_type::to_int_type(*gptr());
        std::string line;
        toEngine.pop(line, -1);
        cur = line + "\n";
        setg(&cur[0], &cur[0], &cur[0] + cur.size());
        return traits_type::to_int_type(*gptr());
    }
};

class OutBuf: public std::streambuf {
    std::string cur;
    std::mutex  m;

    void put(char c) {
        if (c == '\n')
        {
            fromEngine.push(cur);
            cur.clear();
        }
        else
            cur.push_back(c);
    }

   protected:
    int_type overflow(int_type c) override {
        if (c == traits_type::eof())
            return 0;
        std::lock_guard<std::mutex> l(m);
        put(static_cast<char>(c));
        return c;
    }
    std::streamsize xsputn(const char* s, std::streamsize n) override {
        std::lock_guard<std::mutex> l(m);
        for (std::streamsize i = 0; i < n; ++i)
            put(s[i]);
        return n;
    }
};

InBuf          inbuf;
OutBuf         outbuf;
std::once_flag startedFlag;

}  // namespace

extern "C" void pikafish_start(const char* resourceDir) {
    std::string dir(resourceDir ? resourceDir : ".");
    std::call_once(startedFlag, [dir] {
        std::cin.rdbuf(&inbuf);
        std::cout.rdbuf(&outbuf);
        std::thread([dir] {
            // argv[0] nằm trong thư mục tài nguyên để engine tìm thấy pikafish.nnue.
            std::string       exe = dir + "/pikafish";
            std::vector<char> a(exe.begin(), exe.end());
            a.push_back('\0');
            char* argv[] = {a.data(), nullptr};
            Attacks::init();
            auto cli = CommandLine(1, argv);
            auto uci = std::make_unique<UCIEngine>(std::move(cli));
            Tune::init(uci->engine_options());
            uci->loop();
        }).detach();
    });
}

extern "C" void pikafish_send(const char* cmd) { toEngine.push(cmd ? cmd : ""); }

extern "C" int pikafish_read(char* buf, int cap, int timeoutMs) {
    std::string s;
    if (!fromEngine.pop(s, timeoutMs))
        return -1;
    size_t n = s.size() < static_cast<size_t>(cap - 1) ? s.size() : static_cast<size_t>(cap - 1);
    std::memcpy(buf, s.data(), n);
    buf[n] = '\0';
    return static_cast<int>(n);
}

extern "C" void pikafish_clear_output(void) { fromEngine.clear(); }

// Thay cho exit() trong Pikafish (vá khi build): báo lỗi rồi treo riêng luồng engine,
// để app không bị đóng khi mạng NNUE không nạp được.
extern "C" [[noreturn]] void pikafish_fatal(void) {
    fromEngine.push("FATAL");
    for (;;)
        std::this_thread::sleep_for(std::chrono::hours(1));
}
