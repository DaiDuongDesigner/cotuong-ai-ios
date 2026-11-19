import Foundation
import Network

/// Kênh truyền nội bộ trên máy (127.0.0.1) giữa app chính và Broadcast Extension.
/// Dùng khi App Group không hoạt động – thường gặp khi cài bằng ESign/ký lại bằng chứng chỉ khác.
/// Giao thức: mỗi dòng văn bản kết thúc bằng "\n".
///   App → Extension:  "CAL <json hiệu chỉnh>"
///   Extension → App:  "BOARD <90 ký tự>"  |  "HB <khung/giây> <1 nếu thấy bàn cờ, 0 nếu không>"
enum Loopback {
    static let port: NWEndpoint.Port = 47811
}

/// Đọc từng dòng từ một NWConnection.
final class LineConnection {
    let conn: NWConnection
    private var buffer = Data()
    private var closed = false
    var onLine: ((String) -> Void)?
    var onClose: (() -> Void)?

    init(_ conn: NWConnection) { self.conn = conn }

    func start(queue: DispatchQueue) {
        conn.stateUpdateHandler = { [weak self] st in
            guard let self else { return }
            switch st {
            case .failed, .cancelled:
                if !self.closed { self.closed = true; self.onClose?() }
            default: break
            }
        }
        conn.start(queue: queue)
        receive()
    }

    private func receive() {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [weak self] data, _, done, err in
            guard let self else { return }
            if let data { self.buffer.append(data) }
            while let i = self.buffer.firstIndex(of: 0x0A) {
                let line = String(decoding: self.buffer[self.buffer.startIndex..<i], as: UTF8.self)
                self.buffer.removeSubrange(self.buffer.startIndex...i)
                self.onLine?(line)
            }
            if done || err != nil { self.conn.cancel(); return }
            self.receive()
        }
    }

    func send(_ line: String) {
        conn.send(content: (line + "\n").data(using: .utf8), completion: .contentProcessed { _ in })
    }

    func cancel() { conn.cancel() }
}

/// Máy chủ trong app chính.
final class LoopbackServer {
    private var listener: NWListener?
    private var clients: [LineConnection] = []
    private let queue = DispatchQueue(label: "cotuongai.loopback")
    var calibrationJSON: () -> String? = { nil }
    var onBoard: ((String) -> Void)?
    var onHeartbeat: ((Double, Bool) -> Void)?

    func start() {
        guard listener == nil else { return }
        do {
            let params = NWParameters.tcp
            params.requiredInterfaceType = .loopback
            params.allowLocalEndpointReuse = true
            let l = try NWListener(using: params, on: Loopback.port)
            l.newConnectionHandler = { [weak self] c in self?.accept(c) }
            l.stateUpdateHandler = { [weak self] st in
                if case .failed = st { self?.listener?.cancel(); self?.listener = nil
                    self?.queue.asyncAfter(deadline: .now() + 2) { self?.start() } }
            }
            l.start(queue: queue)
            listener = l
        } catch {
            print("Loopback lỗi:", error)
        }
    }

    private func accept(_ c: NWConnection) {
        let lc = LineConnection(c)
        lc.onLine = { [weak self] line in
            if line.hasPrefix("BOARD ") {
                let s = String(line.dropFirst(6))
                DispatchQueue.main.async { self?.onBoard?(s) }
            } else if line.hasPrefix("HB ") {
                let p = line.split(separator: " ")
                let fps = p.count > 1 ? Double(p[1]) ?? 0 : 0
                let ok = p.count > 2 && p[2] == "1"
                DispatchQueue.main.async { self?.onHeartbeat?(fps, ok) }
            }
        }
        lc.onClose = { [weak self, weak lc] in
            self?.queue.async { self?.clients.removeAll { $0 === lc } }
        }
        clients.append(lc)
        lc.start(queue: queue)
        DispatchQueue.main.async { [weak self] in
            guard let json = self?.calibrationJSON() else { return }
            self?.queue.async { lc.send("CAL " + json) }
        }
    }

    /// Gửi hiệu chỉnh mới cho extension đang chạy.
    func broadcastCalibration() {
        guard let json = calibrationJSON() else { return }
        queue.async { self.clients.forEach { $0.send("CAL " + json) } }
    }
}

/// Máy khách trong Broadcast Extension: tự kết nối lại nếu mất.
final class LoopbackClient {
    private var lc: LineConnection?
    private let queue = DispatchQueue(label: "cotuongai.loopback.client")
    var onCalibration: ((Calibration) -> Void)?
    private(set) var connected = false
    private var stopped = false

    func start() {
        stopped = false
        connect()
    }

    private func connect() {
        guard !stopped else { return }
        let c = NWConnection(host: "127.0.0.1", port: Loopback.port, using: .tcp)
        let l = LineConnection(c)
        l.onLine = { [weak self] line in
            guard line.hasPrefix("CAL "), let d = String(line.dropFirst(4)).data(using: .utf8),
                  let cal = try? JSONDecoder().decode(Calibration.self, from: d) else { return }
            self?.connected = true
            self?.onCalibration?(cal)
        }
        l.onClose = { [weak self] in
            self?.connected = false
            self?.queue.asyncAfter(deadline: .now() + 2) { self?.connect() }
        }
        lc = l
        l.start(queue: queue)
    }

    func send(board: String) { queue.async { self.lc?.send("BOARD " + board) } }
    func heartbeat(fps: Double, boardVisible: Bool) {
        queue.async { self.lc?.send(String(format: "HB %.1f %d", fps, boardVisible ? 1 : 0)) }
    }

    func stop() { stopped = true; lc?.cancel() }
}
