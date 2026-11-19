import UIKit

/// Vẽ bàn cờ mini (dùng cho cửa sổ nổi PiP và màn hình chính).
enum BoardRenderer {
    static let size = CGSize(width: 360, height: 460)
    private static let red = ["K": "帥", "A": "仕", "B": "相", "N": "傌", "R": "俥", "C": "炮", "P": "兵"]
    private static let black = ["k": "將", "a": "士", "b": "象", "n": "馬", "r": "車", "c": "砲", "p": "卒"]

    struct State {
        var board: String
        var sideToMove: Int
        var myColor: Int
        var lastMove: (Int, Int)?
        var analysis: Analysis?
        var thinking: Bool
        var hideSuggestion: Bool
        var status: String
        var warning: String? = nil
    }

    static func image(_ s: State) -> UIImage {
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 2
        fmt.opaque = true
        return UIGraphicsImageRenderer(size: size, format: fmt).image { ctx in
            let g = ctx.cgContext
            UIColor(red: 0.08, green: 0.07, blue: 0.06, alpha: 1).setFill()
            g.fill(CGRect(origin: .zero, size: size))

            // --- Thanh tiêu đề ---
            let turnColor: UIColor = s.sideToMove == 0 ? UIColor(red: 0.85, green: 0.25, blue: 0.2, alpha: 1) : .white
            g.setFillColor(turnColor.cgColor)
            g.fillEllipse(in: CGRect(x: 14, y: 16, width: 14, height: 14))
            let mine = s.sideToMove == s.myColor
            let head = (s.sideToMove == 0 ? "Đỏ đi" : "Đen đi") + (mine ? " · lượt bạn" : " · lượt đối thủ")
            draw(head, at: CGPoint(x: 36, y: 10), size: 17, weight: .semibold, color: .white)
            if let a = s.analysis {
                draw(a.scoreText, at: CGPoint(x: 230, y: 10), size: 17, weight: .bold,
                     color: UIColor(red: 0.88, green: 0.70, blue: 0.36, alpha: 1), width: 120, align: .right)
            }
            var line2 = s.status
            if let a = s.analysis, !s.hideSuggestion, !a.over, let first = a.pv.first {
                line2 = "Nên đi: \(first)   ·   " + a.pv.dropFirst().prefix(3).joined(separator: " ")
                    + "   [\(a.source)]"
            }
            if s.thinking { line2 = "Đang tính… " + line2 }
            draw(line2, at: CGPoint(x: 14, y: 36), size: 14, weight: .regular,
                 color: UIColor(white: 0.85, alpha: 1), width: 332)

            // --- Bàn cờ ---
            let top: CGFloat = 66, cell: CGFloat = 38, left: CGFloat = (size.width - 8 * cell) / 2, oy = top + 14
            let boardRect = CGRect(x: left - 18, y: oy - 18, width: 8 * cell + 36, height: 9 * cell + 36)
            g.setFillColor(UIColor(red: 0.91, green: 0.79, blue: 0.56, alpha: 1).cgColor)
            g.addPath(UIBezierPath(roundedRect: boardRect, cornerRadius: 10).cgPath); g.fillPath()
            g.setStrokeColor(UIColor(red: 0.42, green: 0.27, blue: 0.13, alpha: 1).cgColor)
            g.setLineWidth(1)
            for r in 0..<10 { g.move(to: CGPoint(x: left, y: oy + CGFloat(r) * cell)); g.addLine(to: CGPoint(x: left + 8 * cell, y: oy + CGFloat(r) * cell)) }
            for c in 0..<9 {
                let x = left + CGFloat(c) * cell
                if c == 0 || c == 8 { g.move(to: CGPoint(x: x, y: oy)); g.addLine(to: CGPoint(x: x, y: oy + 9 * cell)) }
                else {
                    g.move(to: CGPoint(x: x, y: oy)); g.addLine(to: CGPoint(x: x, y: oy + 4 * cell))
                    g.move(to: CGPoint(x: x, y: oy + 5 * cell)); g.addLine(to: CGPoint(x: x, y: oy + 9 * cell))
                }
            }
            for (r0, r1) in [(0, 2), (7, 9)] {
                g.move(to: pt(r0, 3, left, oy, cell)); g.addLine(to: pt(r1, 5, left, oy, cell))
                g.move(to: pt(r0, 5, left, oy, cell)); g.addLine(to: pt(r1, 3, left, oy, cell))
            }
            g.strokePath()

            let flip = s.myColor == 1
            func disp(_ i: Int) -> CGPoint {
                var r = i / 9, c = i % 9
                if flip { r = 9 - r; c = 8 - c }
                return pt(r, c, left, oy, cell)
            }
            if case let (f, t)? = s.lastMove {
                g.setFillColor(UIColor(red: 0.29, green: 0.56, blue: 0.88, alpha: 0.35).cgColor)
                for i in [f, t] { let p = disp(i); g.fill(CGRect(x: p.x - 18, y: p.y - 18, width: 36, height: 36)) }
            }
            // Quân cờ
            let chars = Array(s.board)
            for i in 0..<min(90, chars.count) where chars[i] != "." {
                let k = String(chars[i]), isRed = k == k.uppercased()
                let p = disp(i)
                g.setFillColor(UIColor(red: 0.99, green: 0.95, blue: 0.86, alpha: 1).cgColor)
                g.fillEllipse(in: CGRect(x: p.x - 17, y: p.y - 17, width: 34, height: 34))
                let ink = isRed ? UIColor(red: 0.72, green: 0.15, blue: 0.11, alpha: 1) : UIColor(white: 0.1, alpha: 1)
                g.setStrokeColor(ink.cgColor); g.setLineWidth(1.5)
                g.strokeEllipse(in: CGRect(x: p.x - 14, y: p.y - 14, width: 28, height: 28))
                let ch = (isRed ? red[k] : black[k]) ?? "?"
                draw(ch, center: p, size: 19, color: ink)
            }
            // Mũi tên gợi ý
            if let a = s.analysis, !s.hideSuggestion, !a.over, a.from >= 0, a.to >= 0 {
                let p0 = disp(a.from), p1 = disp(a.to)
                let dx = p1.x - p0.x, dy = p1.y - p0.y, L = max(hypot(dx, dy), 1), ux = dx / L, uy = dy / L
                let tip = CGPoint(x: p1.x - ux * 6, y: p1.y - uy * 6)
                let base = CGPoint(x: tip.x - ux * 16, y: tip.y - uy * 16)
                g.setStrokeColor(UIColor(red: 0.12, green: 0.6, blue: 0.3, alpha: 0.9).cgColor)
                g.setLineWidth(7); g.setLineCap(.round)
                g.move(to: CGPoint(x: p0.x + ux * 6, y: p0.y + uy * 6)); g.addLine(to: base); g.strokePath()
                g.setFillColor(UIColor(red: 0.12, green: 0.6, blue: 0.3, alpha: 0.95).cgColor)
                g.move(to: tip)
                g.addLine(to: CGPoint(x: base.x - uy * 11, y: base.y + ux * 11))
                g.addLine(to: CGPoint(x: base.x + uy * 11, y: base.y - ux * 11))
                g.closePath(); g.fillPath()
            }
            // Cảnh báo (mất tín hiệu màn hình / không thấy bàn cờ)
            if let w = s.warning {
                let r = CGRect(x: 30, y: size.height - 44, width: size.width - 60, height: 32)
                g.setFillColor(UIColor(red: 0.75, green: 0.18, blue: 0.14, alpha: 0.92).cgColor)
                g.addPath(UIBezierPath(roundedRect: r, cornerRadius: 10).cgPath); g.fillPath()
                draw("⚠️ " + w, at: CGPoint(x: r.minX + 10, y: r.minY + 6), size: 15, weight: .semibold,
                     color: .white, width: r.width - 20, align: .center)
            }
        }
    }

    private static func pt(_ r: Int, _ c: Int, _ left: CGFloat, _ top: CGFloat, _ cell: CGFloat) -> CGPoint {
        CGPoint(x: left + CGFloat(c) * cell, y: top + CGFloat(r) * cell)
    }

    private static func draw(_ text: String, at p: CGPoint, size: CGFloat, weight: UIFont.Weight, color: UIColor,
                             width: CGFloat = 320, align: NSTextAlignment = .left) {
        let ps = NSMutableParagraphStyle(); ps.alignment = align; ps.lineBreakMode = .byTruncatingTail
        (text as NSString).draw(in: CGRect(x: p.x, y: p.y, width: width, height: size * 1.4), withAttributes: [
            .font: UIFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: ps])
    }

    private static func draw(_ text: String, center: CGPoint, size: CGFloat, color: UIColor) {
        let font = UIFont(name: "PingFangTC-Semibold", size: size) ?? UIFont.boldSystemFont(ofSize: size)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let sz = (text as NSString).size(withAttributes: attrs)
        (text as NSString).draw(at: CGPoint(x: center.x - sz.width / 2, y: center.y - sz.height / 2), withAttributes: attrs)
    }
}
