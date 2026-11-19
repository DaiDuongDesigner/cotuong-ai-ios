import SwiftUI
import CoreImage

/// Bộ não của app: nhận thế cờ từ extension → suy ra nước vừa đi và lượt đi → hỏi engine → cập nhật cửa sổ nổi.
/// Mọi thao tác chạy trên luồng chính (engine trả kết quả về main queue).
final class AppModel: ObservableObject {
    @Published var board = INIT90
    @Published var sideToMove = 0
    @Published var lastMove: (Int, Int)?
    @Published var analysis: Analysis?
    @Published var thinking = false
    @Published var history: [String] = []
    @Published var status = "Chưa nhận thế cờ"
    @Published var calibration: Calibration? = SharedStore.loadCalibration()
    @Published var preview: UIImage = UIImage()

    @Published var thinkMs: Int = UserDefaults.standard.object(forKey: "thinkMs") as? Int ?? 1500 {
        didSet { UserDefaults.standard.set(thinkMs, forKey: "thinkMs") }
    }
    @Published var onlyMyTurn: Bool = UserDefaults.standard.object(forKey: "onlyMyTurn") as? Bool ?? true {
        didSet { UserDefaults.standard.set(onlyMyTurn, forKey: "onlyMyTurn"); refresh() }
    }

    let engine = EngineService()
    let pip = PiPController()
    let server = LoopbackServer()
    private var busy = false
    private var pending: String?
    private var generation = 0

    var myColor: Int { (calibration?.flipped ?? false) ? 1 : 0 }

    init() {
        DarwinObserver.shared.handler = { [weak self] in
            guard let self, let s = SharedStore.readBoard() else { return }
            self.receive(s)
        }
        DarwinObserver.shared.start()
        server.calibrationJSON = { SharedStore.calibrationJSON() }
        server.onBoard = { [weak self] s in self?.receive(s) }
        server.start()
        refresh()
    }

    // MARK: Nhận thế cờ mới

    func receive(_ newBoard: String) {
        guard newBoard.count == 90 else { return }
        if busy { pending = newBoard; return }
        process(newBoard)
    }

    private func process(_ newBoard: String) {
        guard newBoard != board else { next(); return }
        if newBoard == INIT90 {
            board = newBoard; sideToMove = 0; lastMove = nil; history = []
            status = "Ván mới"
            analyze(); next(); return
        }
        busy = true
        engine.findMove(prev: board, next: newBoard, side: sideToMove) { [weak self] info in
            guard let self else { return }
            self.board = newBoard
            if let info {
                self.sideToMove = info.side
                self.lastMove = (info.from, info.to)
                self.history.append(contentsOf: info.notes)
                self.status = "Vừa đi: " + info.notes.joined(separator: ", ")
            } else {
                // Không nối được với thế trước (mới mở app giữa ván…): giả định đang là lượt của bạn.
                self.sideToMove = self.myColor
                self.lastMove = nil
                self.status = "Thế cờ mới – giả định lượt bạn"
            }
            self.busy = false
            self.analyze()
            self.next()
        }
    }

    private func next() {
        if let p = pending { pending = nil; receive(p) }
    }

    // MARK: Phân tích

    func analyze() {
        generation += 1
        let gen = generation
        thinking = true
        analysis = nil
        refresh()
        engine.analyze(board: board, side: sideToMove, ms: thinkMs) { [weak self] a in
            guard let self, gen == self.generation else { return }
            self.thinking = false
            self.analysis = a
            if let a, a.over { self.status = (a.side == 0 ? "Đen" : "Đỏ") + " thắng" }
            self.refresh()
        }
    }

    func refresh() {
        let hide = onlyMyTurn && sideToMove != myColor
        let img = BoardRenderer.image(.init(board: board, sideToMove: sideToMove, myColor: myColor,
                                            lastMove: lastMove, analysis: analysis, thinking: thinking,
                                            hideSuggestion: hide,
                                            status: hide ? "Chờ đối thủ đi…" : status))
        preview = img
        pip.update(img)
    }

    // MARK: Điều chỉnh tay

    func switchSide() { sideToMove ^= 1; analyze() }
    func resetGame() { board = INIT90; sideToMove = 0; lastMove = nil; history = []; status = "Ván mới"; analyze() }

    /// Thử nhận diện từ một ảnh chụp màn hình (để kiểm tra không cần phát sóng).
    func recognize(image: UIImage) -> Bool {
        guard let cal = calibration, let cg = image.cgImage else { return false }
        guard let s = Recognizer().read(image: CIImage(cgImage: cg), cal: cal) else { return false }
        receive(s)
        return true
    }

    func saveCalibration(_ c: Calibration) throws {
        try SharedStore.saveCalibration(c)
        calibration = c
        server.broadcastCalibration()
        refresh()
    }
}
