import Foundation
import HRVCore

enum Format {
    private static let fJam: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f
    }()

    private static let fHari: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "id_ID")
        f.dateFormat = "EEEE, d MMM"
        return f
    }()

    static func ms(_ x: Double?) -> String {
        guard let x = x, x.isFinite else { return "–" }
        return "\(Int(x.rounded())) ms"
    }

    static func jam(_ d: Date) -> String {
        fJam.string(from: d)
    }

    static func hari(_ d: Date) -> String {
        let kal = Calendar.current
        if kal.isDateInToday(d) { return "Hari ini" }
        if kal.isDateInYesterday(d) { return "Kemarin" }
        return fHari.string(from: d)
    }

    static func byte(_ x: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: x), countStyle: .file)
    }

    static func durasi(jam: Double) -> String {
        let menit = Int((jam * 60).rounded())
        if menit >= 60 { return "\(menit / 60) jam \(menit % 60) menit" }
        return "\(menit) menit"
    }

    static func kualitas(_ k: KualitasJendela) -> String {
        switch k {
        case .bagus: return "bagus"
        case .lumayan: return "lumayan"
        case .jelek: return "jelek"
        case .kurangData: return "kurang data"
        }
    }
}
