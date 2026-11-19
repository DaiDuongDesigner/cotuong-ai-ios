import AVFoundation

/// Đọc nước gợi ý bằng tiếng Việt, ví dụ "P2-5" → "Pháo hai bình năm".
final class Speaker {
    static let shared = Speaker()
    private let synth = AVSpeechSynthesizer()
    private var lastSpoken = ""

    private static let pieces: [String: String] = ["Tg": "Tướng", "S": "Sĩ", "T": "Tượng", "M": "Mã",
                                                   "X": "Xe", "P": "Pháo", "B": "Binh"]
    private static let digits = ["không", "một", "hai", "ba", "bốn", "năm", "sáu", "bảy", "tám", "chín"]

    static func phrase(_ note: String) -> String {
        var s = Substring(note)
        var name = ""
        if s.hasPrefix("Tg") { name = pieces["Tg"]!; s = s.dropFirst(2) }
        else if let f = s.first, let n = pieces[String(f)] { name = n; s = s.dropFirst() }
        var out = [name]
        for ch in s {
            switch ch {
            case ".": out.append("tiến")
            case "/": out.append("thoái")
            case "-": out.append("bình")
            case "t": out.append("trước")
            case "s": out.append("sau")
            case "g": out.append("giữa")
            default: if let d = ch.wholeNumberValue { out.append(digits[d]) }
            }
        }
        return out.joined(separator: " ")
    }

    func say(_ note: String) {
        guard note != lastSpoken else { return }
        lastSpoken = note
        let u = AVSpeechUtterance(string: Self.phrase(note))
        u.voice = AVSpeechSynthesisVoice(language: "vi-VN")
        u.rate = 0.5
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        synth.speak(u)
    }

    func reset() { lastSpoken = "" }
}
