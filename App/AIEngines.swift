import Foundation

/// Kết quả thô từ engine UCI / đám mây.
struct UCIResult {
    var depth: Int
    var cp: Int?
    var mate: Int?
    var pv: [String]
}

// MARK: - Pikafish (NNUE, chạy trên máy)

final class PikafishEngine {
    static let shared = PikafishEngine()
    private let queue = DispatchQueue(label: "cotuongai.pikafish", qos: .userInitiated)
    private(set) var ready = false
    private(set) var failed = false
    private var starting = false

    /// Có file mạng NNUE trong app không (bản build có Pikafish).
    var available: Bool {
        guard let url = Bundle.main.url(forResource: "pikafish", withExtension: "nnue"),
              let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber
        else { return false }
        return size.intValue > 1_000_000
    }

    func start(completion: ((Bool) -> Void)? = nil) {
        guard available else { failed = true; completion?(false); return }
        queue.async {
            if self.ready || self.failed { DispatchQueue.main.async { completion?(self.ready) }; return }
            if !self.starting {
                self.starting = true
                pikafish_start(Bundle.main.resourcePath ?? ".")
                pikafish_send("uci")
                _ = self.waitFor("uciok", ms: 5000)
                let threads = max(1, min(4, ProcessInfo.processInfo.activeProcessorCount - 2))
                pikafish_send("setoption name Threads value \(threads)")
                pikafish_send("setoption name Hash value 64")
                pikafish_send("isready")
                self.ready = self.waitFor("readyok", ms: 30000)
                self.failed = !self.ready
                NSLog("Pikafish sẵn sàng: %d", self.ready ? 1 : 0)
            }
            DispatchQueue.main.async { completion?(self.ready) }
        }
    }

    private func readLine(_ timeoutMs: Int32) -> String? {
        var buf = [CChar](repeating: 0, count: 16384)
        let n = pikafish_read(&buf, Int32(buf.count), timeoutMs)
        return n < 0 ? nil : String(cString: buf)
    }

    private func waitFor(_ prefix: String, ms: Int) -> Bool {
        let deadline = Date().addingTimeInterval(Double(ms) / 1000)
        while Date() < deadline {
            guard let l = readLine(500) else { continue }
            if l == "FATAL" { return false }
            if l.hasPrefix(prefix) { return true }
        }
        return false
    }

    func analyze(fen: String, ms: Int, completion: @escaping (UCIResult?) -> Void) {
        queue.async {
            guard self.ready else { DispatchQueue.main.async { completion(nil) }; return }
            pikafish_clear_output()
            pikafish_send("position fen \(fen)")
            pikafish_send("go movetime \(ms)")
            var last: UCIResult?
            let deadline = Date().addingTimeInterval(Double(ms) / 1000 + 8)
            while Date() < deadline {
                guard let l = self.readLine(1000) else { continue }
                if l == "FATAL" { self.ready = false; self.failed = true; break }
                if l.hasPrefix("info"), l.contains(" pv "), let r = Self.parseInfo(l) { last = r }
                if l.hasPrefix("bestmove") {
                    let parts = l.split(separator: " ")
                    if parts.count > 1, parts[1] != "(none)" {
                        let bm = String(parts[1])
                        if last == nil || last!.pv.first != bm { last = UCIResult(depth: last?.depth ?? 0, cp: last?.cp, mate: last?.mate, pv: [bm]) }
                    }
                    break
                }
            }
            DispatchQueue.main.async { completion(last) }
        }
    }

    static func parseInfo(_ line: String) -> UCIResult? {
        let t = line.split(separator: " ").map(String.init)
        var r = UCIResult(depth: 0, cp: nil, mate: nil, pv: [])
        var i = 0
        while i < t.count {
            switch t[i] {
            case "depth": if i + 1 < t.count { r.depth = Int(t[i + 1]) ?? 0 }; i += 2
            case "score":
                if i + 2 < t.count {
                    if t[i + 1] == "cp" { r.cp = Int(t[i + 2]) } else if t[i + 1] == "mate" { r.mate = Int(t[i + 2]) }
                }
                i += 3
            case "pv": r.pv = Array(t[(i + 1)...]); i = t.count
            default: i += 1
            }
        }
        return r.pv.isEmpty ? nil : r
    }
}

// MARK: - ChessDB đám mây (chessdb.cn)

enum CloudEngine {
    /// Truy vấn biến chính từ kho cờ đám mây. Trả nil nếu thế cờ chưa có trong kho hoặc lỗi mạng.
    static func analyze(fen: String, completion: @escaping (UCIResult?) -> Void) {
        var comps = URLComponents(string: "https://www.chessdb.cn/chessdb.php")!
        comps.queryItems = [URLQueryItem(name: "action", value: "querypv"),
                            URLQueryItem(name: "board", value: fen),
                            URLQueryItem(name: "json", value: "1")]
        guard let url = comps.url else { completion(nil); return }
        var req = URLRequest(url: url, timeoutInterval: 6)
        req.setValue("CoTuongAI-iOS", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { data, _, _ in
            var result: UCIResult?
            if let data, let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               (o["status"] as? String) == "ok", let pv = o["pv"] as? [String], !pv.isEmpty {
                let score = (o["score"] as? Int) ?? Int((o["score"] as? String) ?? "") ?? 0
                var mate: Int?
                if abs(score) > 20000 { mate = score > 0 ? max(1, (30000 - score + 1) / 2) : -max(1, (30000 + score + 1) / 2) }
                result = UCIResult(depth: o["depth"] as? Int ?? 0, cp: mate == nil ? score : nil, mate: mate, pv: pv)
            }
            DispatchQueue.main.async { completion(result) }
        }.resume()
    }
}
