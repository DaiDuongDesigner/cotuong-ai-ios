import SwiftUI
import CoreImage

/// Bộ não của app: nhận thế cờ từ extension → suy ra nước vừa đi và lượt đi → hỏi model AI → cập nhật cửa sổ nổi.
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
    @Published var opening: OpeningInfo?
    @Published var pikafishState = "Chưa khởi động"

    // Trạng thái đọc màn hình
    @Published var screenFps: Double = 0
    @Published var boardVisible = false
    @Published var lastHeartbeat: Date?

    @Published var thinkMs: Int = UserDefaults.standard.object(forKey: "thinkMs") as? Int ?? 1500 {
        didSet { UserDefaults.standard.set(thinkMs, forKey: "thinkMs") }
    }
    @Published var onlyMyTurn: Bool = UserDefaults.standard.object(forKey: "onlyMyTurn") as? Bool ?? true {
        didSet { UserDefaults.standard.set(onlyMyTurn, forKey: "onlyMyTurn"); refresh() }
    }
    @Published var voice: Bool = UserDefaults.standard.bool(forKey: "voice") {
        didSet { UserDefaults.standard.set(voice, forKey: "voice"); Speaker.shared.reset() }
    }
    @Published var model: AIModel = AIModel(rawValue: UserDefaults.standard.string(forKey: "model") ?? "") ?? .local {
        didSet {
            UserDefaults.standard.set(model.rawValue, forKey: "model")
            if model != .local { startPikafish() }
            analyze()
        }
    }

    let engine = EngineService()
    let pip = PiPController()
    let server = LoopbackServer()
    private var busy = false
    private var pending: String?
    private var generation = 0
    /// Chuỗi nước từ thế ban đầu (nil nếu bắt đầu theo dõi giữa ván) – dùng nhận diện khai cuộc.
    private var gameMoves: [Int]? = []
    private var hbTimer: Timer?

    var myColor: Int { (calibration?.flipped ?? false) ? 1 : 0 }
    var receiving: Bool { (lastHeartbeat.map { Date().timeIntervalSince($0) < 6 }) ?? false }

    init() {
        DarwinObserver.shared.handler = { [weak self] in
            guard let self, let s = SharedStore.readBoard() else { return }
            self.receive(s)
        }
        DarwinObserver.shared.start()
        server.calibrationJSON = { SharedStore.calibrationJSON() }
        server.onBoard = { [weak self] s in self?.receive(s) }
        server.onHeartbeat = { [weak self] fps, ok in self?.heartbeat(fps: fps, visible: ok) }
        server.start()
        hbTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.pollHeartbeat() }
        if model != .local { startPikafish() }
        updateOpening()
        refresh()
    }

    // MARK: Trạng thái đọc màn hình

    private func heartbeat(fps: Double, visible: Bool) {
        let changed = !receiving || visible != boardVisible
        screenFps = fps; boardVisible = visible; lastHeartbeat = Date()
        if changed { refresh() }
    }

    private func pollHeartbeat() {
        if let hb = SharedStore.readHeartbeat(), Date().timeIntervalSince1970 - hb.time < 5 {
            heartbeat(fps: hb.fps, visible: hb.visible)
        } else if lastHeartbeat != nil && !receiving {
            objectWillChange.send()
            refresh()
        }
    }

    var screenStatus: String {
        guard receiving else { return "Chưa nhận màn hình – hãy bắt đầu phát" }
        return boardVisible
            ? String(format: "Đang đọc màn hình · %.1f lần/giây · thấy bàn cờ", screenFps)
            : "Đang đọc màn hình · KHÔNG thấy bàn cờ (mở app cờ hoặc hiệu chỉnh lại)"
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
            startNewGame(); next(); return
        }
        busy = true
        engine.findMove(prev: board, next: newBoard, side: sideToMove, maxDiff: 2) { [weak self] info in
            guard let self else { return }
            if let info {
                self.board = info.board          // thế cờ đã sửa lỗi nhận diện (nếu có)
                self.sideToMove = info.side
                self.lastMove = (info.from, info.to)
                self.history.append(contentsOf: info.notes)
                self.gameMoves?.append(contentsOf: info.moves)
                self.status = "Vừa đi: " + info.notes.joined(separator: ", ") + (info.fuzzy ? " (đã tự sửa ô đọc nhầm)" : "")
            } else {
                // Không nối được với thế trước (mở app giữa ván…): giả định đang là lượt của bạn.
                self.board = newBoard
                self.sideToMove = self.myColor
                self.lastMove = nil
                self.gameMoves = nil
                self.status = "Thế cờ mới – giả định lượt bạn"
            }
            self.busy = false
            self.updateOpening()
            self.analyze()
            self.next()
        }
    }

    private func next() {
        if let p = pending { pending = nil; receive(p) }
    }

    private func startNewGame() {
        board = INIT90; sideToMove = 0; lastMove = nil; history = []; gameMoves = []
        status = "Ván mới"
        updateOpening()
        analyze()
    }

    private func updateOpening() {
        guard let mv = gameMoves else { opening = nil; return }
        engine.opening(moves: mv) { [weak self] info in
            self?.opening = info
            self?.refresh()
        }
    }

    // MARK: Phân tích

    private func startPikafish() {
        guard PikafishEngine.shared.available else { pikafishState = "Bản này không kèm Pikafish"; return }
        pikafishState = "Đang nạp mạng NNUE…"
        PikafishEngine.shared.start { [weak self] ok in
            self?.pikafishState = ok ? "Sẵn sàng" : "Lỗi nạp – dùng engine nội bộ"
            if ok { self?.analyze() }
        }
    }

    func analyze() {
        generation += 1
        let gen = generation
        thinking = true
        analysis = nil
        refresh()
        let b = board, s = sideToMove, ms = thinkMs
        let done: (Analysis?) -> Void = { [weak self] a in
            guard let self, gen == self.generation else { return }
            self.thinking = false
            self.analysis = a
            if let a, a.over { self.status = (a.side == 0 ? "Đen" : "Đỏ") + " thắng" }
            self.refresh()
            self.speakIfNeeded()
        }
        switch model {
        case .local:
            engine.analyzeLocal(board: b, side: s, ms: ms, completion: done)
        case .pikafish:
            runPikafish(b, s, ms, done)
        case .cloud:
            let fen = engine.fen(board: b, side: s)
            CloudEngine.analyze(fen: fen) { [weak self] r in
                guard let self else { return }
                if let r, let a = self.makeAnalysis(r, b, s, source: "ChessDB") { done(a) }
                else { self.runPikafish(b, s, ms, done) }   // thế lạ: chuyển sang Pikafish/nội bộ
            }
        }
    }

    private func runPikafish(_ b: String, _ s: Int, _ ms: Int, _ done: @escaping (Analysis?) -> Void) {
        guard PikafishEngine.shared.ready else {
            engine.analyzeLocal(board: b, side: s, ms: ms, completion: done); return
        }
        let fen = engine.fen(board: b, side: s)
        PikafishEngine.shared.analyze(fen: fen, ms: ms) { [weak self] r in
            guard let self else { return }
            if let r, let a = self.makeAnalysis(r, b, s, source: "Pikafish") { done(a) }
            else { self.engine.analyzeLocal(board: b, side: s, ms: ms, completion: done) }
        }
    }

    private func makeAnalysis(_ r: UCIResult, _ b: String, _ s: Int, source: String) -> Analysis? {
        let n = engine.notateUci(board: b, side: s, moves: r.pv)
        guard !n.notes.isEmpty, n.from >= 0 else { return nil }
        let st = engine.status(board: b, side: s)
        return Analysis(over: st.over, side: s, check: st.check, from: n.from, to: n.to,
                        score: r.cp ?? 0, mate: r.mate ?? 0, depth: r.depth, pv: n.notes, source: source)
    }

    private var hideSuggestion: Bool { onlyMyTurn && sideToMove != myColor }

    private func speakIfNeeded() {
        guard voice, !hideSuggestion, let a = analysis, !a.over, let first = a.pv.first else { return }
        Speaker.shared.say(first)
    }

    func refresh() {
        var line = hideSuggestion ? "Chờ đối thủ đi…" : status
        if let op = opening, !op.name.isEmpty { line = "📖 " + op.name + " · " + line }
        let warn: String? = lastHeartbeat == nil ? nil
            : (!receiving ? "Mất tín hiệu màn hình" : (!boardVisible ? "Không thấy bàn cờ" : nil))
        let img = BoardRenderer.image(.init(board: board, sideToMove: sideToMove, myColor: myColor,
                                            lastMove: lastMove, analysis: analysis, thinking: thinking,
                                            hideSuggestion: hideSuggestion, status: line, warning: warn))
        pip.update(img)
    }

    // MARK: Điều chỉnh tay

    func switchSide() { sideToMove ^= 1; gameMoves = nil; updateOpening(); analyze() }
    func resetGame() { startNewGame() }

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
