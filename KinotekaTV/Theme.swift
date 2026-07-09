import SwiftUI

// ===========================================================
// Тема: лаймовый акцент как в PWA (#aef23c), тёмный фон,
// хелперы форматирования.
// ===========================================================

enum Theme {
    static let accent = Color(red: 0xAE / 255.0, green: 0xF2 / 255.0, blue: 0x3C / 255.0)
    static let genreAccent = Color(red: 0xB3 / 255.0, green: 0xFE / 255.0, blue: 0x4B / 255.0)
    static let bg = Color(red: 0x0A / 255.0, green: 0x0A / 255.0, blue: 0x0C / 255.0)
    static let card = Color.white.opacity(0.08)
}

enum Fmt {
    static func year(_ date: String?) -> String {
        guard let d = date, d.count >= 4 else { return "" }
        return String(d.prefix(4))
    }

    static func rating(_ vote: Double?) -> String {
        guard let v = vote, v > 0 else { return "—" }
        return String(format: "%.1f", v)
    }

    static func time(_ seconds: Double) -> String {
        let s = Int(seconds)
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, sec) }
        return String(format: "%d:%02d", m, sec)
    }

    static func runtime(_ minutes: Int?) -> String {
        guard let m = minutes, m > 0 else { return "" }
        if m < 60 { return "\(m) мин" }
        return "\(m / 60) ч \(m % 60) мин"
    }

    static func date(_ s: String?) -> String {
        guard let s, !s.isEmpty else { return "" }
        let inF = DateFormatter()
        inF.dateFormat = "yyyy-MM-dd"
        guard let d = inF.date(from: s) else { return s }
        let outF = DateFormatter()
        outF.locale = Locale(identifier: "ru_RU")
        outF.dateFormat = "d MMMM yyyy"
        return outF.string(from: d)
    }

    static func dateShort(_ s: String?) -> String {
        guard let s, !s.isEmpty else { return "" }
        let inF = DateFormatter()
        inF.dateFormat = "yyyy-MM-dd"
        guard let d = inF.date(from: s) else { return s }
        let outF = DateFormatter()
        outF.locale = Locale(identifier: "ru_RU")
        outF.dateFormat = "d MMM"
        return outF.string(from: d)
    }
}

// Постер-плейсхолдер с плавной загрузкой.
struct RemoteImage: View {
    let url: URL?
    var contentMode: ContentMode = .fill

    var body: some View {
        AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.25))) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(contentMode: contentMode)
            case .failure:
                Rectangle().fill(Theme.card)
            case .empty:
                Rectangle().fill(Theme.card)
            @unknown default:
                Rectangle().fill(Theme.card)
            }
        }
    }
}
