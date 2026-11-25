import Foundation

/// Log teknis (SDK Polar + app) buat dikirim kalau ada masalah. Disimpen di memori aja.
final class CatatanLog: @unchecked Sendable {
    static let shared = CatatanLog()

    private let kunci = NSLock()
    private var baris: [String] = []
    private let maks = 600
    private let jam: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    func tambah(_ teks: String) {
        kunci.lock()
        defer { kunci.unlock() }
        baris.append("\(jam.string(from: Date())) \(teks)")
        if baris.count > maks { baris.removeFirst(baris.count - maks) }
    }

    func semua() -> [String] {
        kunci.lock()
        defer { kunci.unlock() }
        return baris
    }
}
