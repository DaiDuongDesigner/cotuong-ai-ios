import Foundation
import JavaScriptCore

/// Các "model AI" người dùng có thể chọn.
enum AIModel: String, CaseIterable, Identifiable {
    case local, pikafish, cloud
    var id: String { rawValue }
    var title: String {
        switch self {
        case .local: return "Nội bộ (nhanh)"
        case .pikafish: return "Pikafish NNUE"
        case .cloud: return "ChessDB đám mây"
        }
    }
    var detail: String {
        switch self {
        case .local: return "Engine gọn nhẹ chạy trên máy, phản hồi tức thì, không cần mạng."
        case .pikafish: return "Engine mạng nơ-ron mạnh nhất hiện nay, chạy hoàn toàn trên máy (tốn pin hơn)."
        case .cloud: return "Kho cờ đám mây chessdb.cn: hàng tỷ thế cờ, khai cuộc và tàn cuộc rất sâu. Cần Internet; thế lạ sẽ tự chuyển về Pikafish/nội bộ."
        }
    }
}

/// Engine JS (engine.js – cùng engine với bản web) + tiện ích: ký hiệu, FEN, khai cuộc, khớp nước.
final class EngineService {
    private let queue = DispatchQueue(label: "cotuongai.engine", qos: .userInitiated)
    private var ctx: JSContext?

    init() {
        queue.async {
            let c = JSContext()
            c?.exceptionHandler = { _, e in NSLog("JS error: %@", e?.toString() ?? "?") }
            if let url = Bundle.main.url(forResource: "engine", withExtension: "js"),
               let src = try? String(contentsOf: url, encoding: .utf8) {
                c?.evaluateScript(src)
            } else {
                NSLog("Không tìm thấy engine.js trong bundle")
            }
            self.ctx = c
        }
    }

    private func callString(_ fn: String, _ args: [Any]) -> String? {
        ctx?.objectForKeyedSubscript(fn)?.call(withArguments: args)?.toString()
    }

    private func call(_ fn: String, _ args: [Any]) -> [String: Any]? {
        guard let s = callString(fn, args), let d = s.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
        return o
    }

    /// Đồng bộ (chỉ gọi từ hàng đợi engine hoặc nền).
    func sync<T>(_ work: @escaping (EngineService) -> T) -> T { queue.sync { work(self) } }

    /// Tìm nước (hoặc 2 nước) biến `prev` thành `next`, cho phép sai tối đa `maxDiff` ô.
    func findMove(prev: String, next: String, side: Int, maxDiff: Int, completion: @escaping (MoveInfo?) -> Void) {
        queue.async {
            let r = self.call("apiFindMove", [prev, next, side, maxDiff])
            let info = r.map { d in
                MoveInfo(side: d["side"] as? Int ?? 0, from: d["from"] as? Int ?? -1, to: d["to"] as? Int ?? -1,
                         notes: d["notes"] as? [String] ?? [], moves: d["moves"] as? [Int] ?? [],
                         board: d["board"] as? String ?? next, fuzzy: d["fuzzy"] as? Bool ?? false)
            }
            DispatchQueue.main.async { completion(info) }
        }
    }

    func analyzeLocal(board: String, side: Int, ms: Int, completion: @escaping (Analysis?) -> Void) {
        queue.async {
            let a = self.call("apiAnalyze", [board, side, ms]).map { d in
                Analysis(over: d["over"] as? Bool ?? false, side: d["side"] as? Int ?? side,
                         check: d["check"] as? Bool ?? false,
                         from: d["from"] as? Int ?? -1, to: d["to"] as? Int ?? -1,
                         score: d["score"] as? Int ?? 0, mate: d["mate"] as? Int ?? 0,
                         depth: d["depth"] as? Int ?? 0, pv: d["pv"] as? [String] ?? [], source: "Nội bộ")
            }
            DispatchQueue.main.async { completion(a) }
        }
    }

    // Các hàm tiện ích chạy đồng bộ trên hàng đợi engine.
    func fen(board: String, side: Int) -> String { queue.sync { callString("apiFen", [board, side]) ?? "" } }

    func status(board: String, side: Int) -> (over: Bool, check: Bool) {
        queue.sync {
            let d = call("apiStatus", [board, side])
            return (d?["over"] as? Bool ?? false, d?["check"] as? Bool ?? false)
        }
    }

    func notateUci(board: String, side: Int, moves: [String]) -> (notes: [String], from: Int, to: Int) {
        queue.sync {
            let d = call("apiNotateUci", [board, side, moves])
            return (d?["notes"] as? [String] ?? [], d?["from"] as? Int ?? -1, d?["to"] as? Int ?? -1)
        }
    }

    func opening(moves: [Int], completion: @escaping (OpeningInfo) -> Void) {
        queue.async {
            let json = (try? JSONSerialization.data(withJSONObject: moves)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
            let d = self.call("apiOpening", [json])
            let book = (d?["book"] as? [[String: Any]] ?? []).map {
                BookMove(note: $0["note"] as? String ?? "", from: $0["from"] as? Int ?? -1,
                         to: $0["to"] as? Int ?? -1, name: $0["name"] as? String ?? "")
            }
            let info = OpeningInfo(name: d?["name"] as? String ?? "", desc: d?["desc"] as? String ?? "", book: book)
            DispatchQueue.main.async { completion(info) }
        }
    }
}

struct MoveInfo {
    var side: Int, from: Int, to: Int
    var notes: [String], moves: [Int]
    var board: String
    var fuzzy: Bool
}

struct BookMove: Hashable { var note: String; var from: Int; var to: Int; var name: String }
struct OpeningInfo { var name: String; var desc: String; var book: [BookMove] }

struct Analysis {
    var over: Bool, side: Int, check: Bool
    var from: Int, to: Int
    var score: Int, mate: Int, depth: Int
    var pv: [String]
    var source: String

    /// Điểm theo góc nhìn bên Đỏ, dạng "+0.45" hoặc "Đỏ chiếu hết sau 3".
    var scoreText: String {
        if mate != 0 {
            let redMate = side == 0 ? mate : -mate
            return (redMate > 0 ? "Đỏ" : "Đen") + " hết cờ sau \(abs(mate))"
        }
        let red = side == 0 ? score : -score
        return String(format: "%@%.2f", red >= 0 ? "+" : "", Double(red) / 100)
    }
}
