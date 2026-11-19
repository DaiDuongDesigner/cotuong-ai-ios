import Foundation
import CoreImage
import CoreGraphics
import Accelerate

/// Thế cờ ban đầu, chuẩn (Đỏ ở dưới). Chỉ số = hàng*9 + cột, hàng 0 là phía quân Đen.
let INIT90 = "rnbakabnr..........c.....c.p.p.p.p.p..................P.P.P.P.P.C.....C..........RNBAKABNR"

/// Kết quả hiệu chỉnh: vị trí lưới trên màn hình + mẫu hình từng loại quân của app cờ.
struct Calibration: Codable {
    /// Toạ độ chuẩn hoá (0…1, gốc trên-trái) của giao điểm trên-trái và dưới-phải trên MÀN HÌNH.
    var x0: Double, y0: Double, x1: Double, y1: Double
    /// true = người dùng cầm Đen, bàn cờ trong app bị lật (Đen ở dưới).
    var flipped: Bool
    /// Mẫu hình chuẩn hoá cho từng ký hiệu quân (K A B N R C P / k a b n r c p).
    var templates: [String: [Float]]
}

/// Lưới ảnh nhỏ dùng để so mẫu: mỗi ô cờ được kéo về 32 px.
enum Geo {
    static let P = 32                 // khoảng cách giữa 2 giao điểm (px)
    static let M = 32                 // lề
    static let W = 8 * P + 2 * M      // 320
    static let H = 9 * P + 2 * M      // 352
    static let N = 24                 // kích thước mẫu
    static let cropScale = 0.84
}

final class Recognizer {
    private let ctx = CIContext(options: [.cacheIntermediates: false])
    private let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    var threshold: Float = 0.75

    // MARK: - Dựng ảnh lưới nhỏ (320×352) từ ảnh màn hình

    func bitmap(_ image: CIImage, _ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> [UInt8]? {
        let ext = image.extent
        let W = Double(ext.width), H = Double(ext.height)
        let px0 = x0 * W, py0 = y0 * H, px1 = x1 * W, py1 = y1 * H
        guard px1 > px0 + 20, py1 > py0 + 20 else { return nil }
        let sx = Double(8 * Geo.P) / (px1 - px0)
        let sy = Double(9 * Geo.P) / (py1 - py0)
        let M = Double(Geo.M), Hb = Double(Geo.H)
        let img = image.transformed(by: CGAffineTransform(translationX: -ext.origin.x, y: -ext.origin.y))
        // CoreImage có gốc dưới-trái: đổi sang lưới có gốc trên-trái.
        let t = CGAffineTransform(a: sx, b: 0, c: 0, d: sy,
                                  tx: M - px0 * sx,
                                  ty: Hb - M - (H - py0) * sy)
        guard let cg = ctx.createCGImage(img.transformed(by: t),
                                         from: CGRect(x: 0, y: 0, width: Geo.W, height: Geo.H)) else { return nil }
        var buf = [UInt8](repeating: 0, count: Geo.W * Geo.H * 4)
        let ok: Bool = buf.withUnsafeMutableBytes { raw in
            guard let c = CGContext(data: raw.baseAddress, width: Geo.W, height: Geo.H, bitsPerComponent: 8,
                                    bytesPerRow: Geo.W * 4, space: cs,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            c.draw(cg, in: CGRect(x: 0, y: 0, width: Geo.W, height: Geo.H))
            return true
        }
        return ok ? buf : nil
    }

    // MARK: - Đặc trưng

    private static let mask: [(Int, Int)] = {
        var m: [(Int, Int)] = []
        let n = Double(Geo.N), r = n * 0.46
        for y in 0..<Geo.N { for x in 0..<Geo.N {
            let dx = Double(x) - n / 2 + 0.5, dy = Double(y) - n / 2 + 0.5
            if dx * dx + dy * dy <= r * r { m.append((x, y)) }
        } }
        return m
    }()

    private static func normalize(_ v: inout [Float]) {
        guard !v.isEmpty else { return }
        var mean: Float = 0
        for x in v { mean += x }
        mean /= Float(v.count)
        var ss: Float = 0
        for i in v.indices { v[i] -= mean; ss += v[i] * v[i] }
        let inv = 1 / (ss.squareRoot() + 1e-6)
        for i in v.indices { v[i] *= inv }
    }

    static func dot(_ a: [Float], _ b: [Float]) -> Float {
        var r: Float = 0
        vDSP_dotpr(a, 1, b, 1, &r, vDSP_Length(min(a.count, b.count)))
        return r
    }

    /// Đặc trưng màu RGB trong vùng tròn quanh (cx, cy).
    func feature(_ buf: [UInt8], _ cx: Double, _ cy: Double) -> [Float] {
        let s = Geo.cropScale * Double(Geo.P), n = Double(Geo.N)
        var v = [Float](); v.reserveCapacity(Self.mask.count * 3)
        for (x, y) in Self.mask {
            let px = cx - s / 2 + (Double(x) + 0.5) * s / n
            let py = cy - s / 2 + (Double(y) + 0.5) * s / n
            let ix = min(max(Int(px), 0), Geo.W - 1), iy = min(max(Int(py), 0), Geo.H - 1)
            let o = (iy * Geo.W + ix) * 4
            v.append(Float(buf[o])); v.append(Float(buf[o + 1])); v.append(Float(buf[o + 2]))
        }
        Self.normalize(&v)
        return v
    }

    /// Đặc trưng xám toàn ô vuông (dùng để dò tâm quân khi hiệu chỉnh).
    private func grayCrop(_ buf: [UInt8], _ cx: Double, _ cy: Double) -> [Float] {
        let s = Geo.cropScale * Double(Geo.P) * 1.15, n = Double(Geo.N)
        var v = [Float](repeating: 0, count: Geo.N * Geo.N)
        for y in 0..<Geo.N { for x in 0..<Geo.N {
            let ix = min(max(Int(cx - s / 2 + (Double(x) + 0.5) * s / n), 0), Geo.W - 1)
            let iy = min(max(Int(cy - s / 2 + (Double(y) + 0.5) * s / n), 0), Geo.H - 1)
            let o = (iy * Geo.W + ix) * 4
            v[y * Geo.N + x] = (Float(buf[o]) + Float(buf[o + 1]) + Float(buf[o + 2])) / 3
        } }
        Self.normalize(&v)
        return v
    }

    private func center(_ r: Int, _ c: Int) -> (Double, Double) {
        (Double(Geo.M + c * Geo.P), Double(Geo.M + r * Geo.P))
    }

    /// Ô trên màn hình (r, c) ứng với ô nào trên bàn cờ chuẩn.
    private func boardIndex(_ r: Int, _ c: Int, _ flipped: Bool) -> Int {
        flipped ? (9 - r) * 9 + (8 - c) : r * 9 + c
    }

    // MARK: - Hiệu chỉnh

    struct CalibResult { var calibration: Calibration; var correct: Int; var total: Int }

    /// `image`: ảnh chụp màn hình app cờ đang ở THẾ CỜ BAN ĐẦU.
    func calibrate(image: CIImage, x0: Double, y0: Double, x1: Double, y1: Double, flipped: Bool) -> CalibResult? {
        let init90 = Array(INIT90)
        // Tự căn lưới 3 lượt liên tiếp: chịu được việc chấm góc lệch tới ~30% một ô.
        var g = (x0, y0, x1, y1)
        for _ in 0..<3 {
            guard let r = refineGrid(image: image, g.0, g.1, g.2, g.3, flipped: flipped) else { return nil }
            g = r
        }
        let (rx0, ry0, rx1, ry1) = g
        return finishCalibration(image: image, init90: init90, rx0, ry0, rx1, ry1, flipped: flipped)
    }

    private func refineGrid(image: CIImage, _ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double,
                            flipped: Bool) -> (Double, Double, Double, Double)? {
        let init90 = Array(INIT90)
        guard let buf0 = bitmap(image, x0, y0, x1, y1) else { return nil }

        // 1) Tự căn lưới: dò tâm từng quân bằng một mẫu "đĩa quân" đối xứng, rồi khớp lưới bình phương tối thiểu.
        var pts: [(Int, Int)] = []
        for r in 0..<10 { for c in 0..<9 where init90[boardIndex(r, c, flipped)] != "." { pts.append((r, c)) } }
        var cen = pts.map { center($0.0, $0.1) }
        for it in 0..<3 {
            var t = [Float](repeating: 0, count: Geo.N * Geo.N)
            for p in cen { let g = grayCrop(buf0, p.0, p.1); for i in 0..<t.count { t[i] += g[i] } }
            let n = Geo.N
            var sym = [Float](repeating: 0, count: n * n)
            for y in 0..<n { for x in 0..<n {
                sym[y * n + x] = t[y * n + x] + t[(n - 1 - y) * n + x] + t[y * n + (n - 1 - x)]
                    + t[(n - 1 - y) * n + (n - 1 - x)] + t[x * n + y] + t[(n - 1 - x) * n + (n - 1 - y)]
            } }
            Self.normalize(&sym)
            let range = it == 0 ? 6 : 3
            for k in 0..<cen.count {
                var best: (Float, Double, Double) = (-2, cen[k].0, cen[k].1)
                for oy in -range...range { for ox in -range...range {
                    let cx = cen[k].0 + Double(ox), cy = cen[k].1 + Double(oy)
                    let v = Self.dot(sym, grayCrop(buf0, cx, cy))
                    if v > best.0 { best = (v, cx, cy) }
                } }
                cen[k] = (best.1, best.2)
            }
        }
        func fit(_ xs: [Double], _ ys: [Double]) -> (Double, Double) {   // y = a + b x
            let n = Double(xs.count), mx = xs.reduce(0, +) / n, my = ys.reduce(0, +) / n
            var sxy = 0.0, sxx = 0.0
            for i in 0..<xs.count { sxy += (xs[i] - mx) * (ys[i] - my); sxx += (xs[i] - mx) * (xs[i] - mx) }
            let b = sxy / max(sxx, 1e-9)
            return (my - b * mx, b)
        }
        let (u0, du) = fit(pts.map { Double($0.1) }, cen.map { $0.0 })
        let (v0, dv) = fit(pts.map { Double($0.0) }, cen.map { $0.1 })
        let ext = image.extent
        let W = Double(ext.width), H = Double(ext.height)
        let sx = Double(8 * Geo.P) / ((x1 - x0) * W), sy = Double(9 * Geo.P) / ((y1 - y0) * H)
        let M = Double(Geo.M)
        var rx0 = x0 + (u0 - M) / sx / W, rx1 = x0 + (u0 + 8 * du - M) / sx / W
        var ry0 = y0 + (v0 - M) / sy / H, ry1 = y0 + (v0 + 9 * dv - M) / sy / H
        // Nếu tự căn lệch quá xa (ảnh lạ), giữ nguyên lưới của người dùng.
        let cellW = (x1 - x0) / 8, cellH = (y1 - y0) / 9
        if abs(rx0 - x0) > cellW * 0.3 || abs(rx1 - x1) > cellW * 0.3 ||
            abs(ry0 - y0) > cellH * 0.3 || abs(ry1 - y1) > cellH * 0.3 {
            rx0 = x0; rx1 = x1; ry0 = y0; ry1 = y1
        }
        return (rx0, ry0, rx1, ry1)
    }

    private func finishCalibration(image: CIImage, init90: [Character], _ rx0: Double, _ ry0: Double,
                                   _ rx1: Double, _ ry1: Double, flipped: Bool) -> CalibResult? {
        // 2) Lấy mẫu từng loại quân trên lưới đã căn.
        guard let buf = bitmap(image, rx0, ry0, rx1, ry1) else { return nil }
        var acc: [String: [Float]] = [:]
        var cnt: [String: Int] = [:]
        for r in 0..<10 { for c in 0..<9 {
            let ch = init90[boardIndex(r, c, flipped)]
            guard ch != "." else { continue }
            let (cx, cy) = center(r, c)
            let f = feature(buf, cx, cy), key = String(ch)
            if acc[key] == nil { acc[key] = f } else { for i in 0..<f.count { acc[key]![i] += f[i] } }
            cnt[key, default: 0] += 1
        } }
        var templates: [String: [Float]] = [:]
        for (k, v0) in acc { var v = v0; Self.normalize(&v); templates[k] = v }

        let cal = Calibration(x0: rx0, y0: ry0, x1: rx1, y1: ry1, flipped: flipped, templates: templates)
        // 3) Tự kiểm tra: đọc lại chính ảnh hiệu chỉnh.
        let readBack = read(image: image, cal: cal, validate: false) ?? ""
        let rb = Array(readBack)
        var ok = 0
        if rb.count == 90 { for i in 0..<90 where init90[i] == rb[i] { ok += 1 } }
        return CalibResult(calibration: cal, correct: ok, total: 90)
    }

    // MARK: - Đọc thế cờ

    /// Trả về chuỗi 90 ký tự (thế cờ chuẩn, Đỏ ở dưới) hoặc nil nếu không đọc được.
    func read(image: CIImage, cal: Calibration, validate: Bool = true) -> String? {
        guard let buf = bitmap(image, cal.x0, cal.y0, cal.x1, cal.y1) else { return nil }
        let keys = Array(cal.templates.keys)
        let mats = keys.map { cal.templates[$0]! }
        var out = [Character](repeating: ".", count: 90)
        let offs: [Double] = [-4, 0, 4]
        for r in 0..<10 { for c in 0..<9 {
            let (cx, cy) = center(r, c)
            var best: Float = -2, bestK = 0
            for oy in offs { for ox in offs {
                let f = feature(buf, cx + ox, cy + oy)
                for k in 0..<mats.count {
                    let s = Self.dot(mats[k], f)
                    if s > best { best = s; bestK = k }
                }
            } }
            if best > threshold { out[boardIndex(r, c, cal.flipped)] = Character(keys[bestK]) }
        } }
        let s = String(out)
        if validate && !Self.plausible(s) { return nil }
        return s
    }

    /// Loại khung hình vô lý (bị popup che, đang chuyển cảnh…).
    static func plausible(_ s: String) -> Bool {
        let limits: [Character: Int] = ["k": 1, "a": 2, "b": 2, "n": 2, "r": 2, "c": 2, "p": 5]
        var count: [Character: Int] = [:]
        for ch in s where ch != "." { count[ch, default: 0] += 1 }
        guard count["K"] == 1, count["k"] == 1 else { return false }
        for (ch, n) in count {
            guard let lim = limits[Character(ch.lowercased())], n <= lim else { return false }
        }
        return true
    }
}
