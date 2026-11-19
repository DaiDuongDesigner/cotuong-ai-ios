import Foundation
import JavaScriptCore

/// Chạy engine cờ tướng (engine.js – cùng engine với bản web) trên một hàng đợi riêng.
final class EngineService {
    private let queue = DispatchQueue(label: "cotuongai.engine", qos: .userInitiated)
    private var ctx: JSContext?

    init() {
        queue.async {
            let c = JSContext()
            c?.exceptionHandler = { _, e in print("JS error:", e?.toString() ?? "?") }
            if let url = Bundle.main.url(forResource: "engine", withExtension: "js"),
               let src = try? String(contentsOf: url, encoding: .utf8) {
                c?.evaluateScript(src)
            } else {
                print("Không tìm thấy engine.js trong bundle")
            }
            self.ctx = c
        }
    }

    private func call(_ fn: String, _ args: [Any]) -> [String: Any]? {
        guard let s = ctx?.objectForKeyedSubscript(fn)?.call(withArguments: args)?.toString(),
              let d = s.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
        return o
    }

    /// Tìm nước (hoặc 2 nước) biến thế `prev` thành `next`.
    func findMove(prev: String, next: String, side: Int, completion: @escaping (MoveInfo?) -> Void) {
        queue.async {
            let r = self.call("apiFindMove", [prev, next, side])
            let info = r.map { MoveInfo(side: $0["side"] as? Int ?? 0,
                                        from: $0["from"] as? Int ?? -1,
                                        to: $0["to"] as? Int ?? -1,
                                        notes: $0["notes"] as? [String] ?? []) }
            DispatchQueue.main.async { completion(info) }
        }
    }

    func analyze(board: String, side: Int, ms: Int, completion: @escaping (Analysis?) -> Void) {
        queue.async {
            let r = self.call("apiAnalyze", [board, side, ms])
            let a = r.map { d in
                Analysis(over: d["over"] as? Bool ?? false,
                         side: d["side"] as? Int ?? side,
                         check: d["check"] as? Bool ?? false,
                         from: d["from"] as? Int ?? -1,
                         to: d["to"] as? Int ?? -1,
                         score: d["score"] as? Int ?? 0,
                         mate: d["mate"] as? Int ?? 0,
                         depth: d["depth"] as? Int ?? 0,
                         pv: d["pv"] as? [String] ?? [])
            }
            DispatchQueue.main.async { completion(a) }
        }
    }
}

struct MoveInfo { var side: Int; var from: Int; var to: Int; var notes: [String] }

struct Analysis {
    var over: Bool, side: Int, check: Bool
    var from: Int, to: Int
    var score: Int, mate: Int, depth: Int
    var pv: [String]

    /// Điểm theo góc nhìn bên Đỏ, dạng "+0.45" hoặc "Đỏ chiếu hết sau 3".
    var scoreText: String {
        let red = side == 0 ? score : -score
        if mate != 0 {
            let redMate = side == 0 ? mate : -mate
            return (redMate > 0 ? "Đỏ" : "Đen") + " chiếu hết sau \(abs(mate))"
        }
        return String(format: "%@%.2f", red >= 0 ? "+" : "", Double(red) / 100)
    }
}
