import Foundation
import HRVCore

/// Nyimpen hasil HRV per 5 menit (JSON) + detak mentah tiap rekaman (CSV) di folder Documents app.
/// Folder itu kelihatan di app Files: Di iPhone Saya > HRV Seharian.
@MainActor
final class PenyimpanHRV: ObservableObject {
    @Published private(set) var jendela: [JendelaHRV] = []

    struct HasilSimpan {
        let detak: Int
        let jendela: Int
        let layak: Int
        let pakaiTimestamp: Bool
    }

    private let folder: URL
    private var fileJendela: URL { folder.appendingPathComponent("hrv_jendela.json") }
    private var folderMentah: URL { folder.appendingPathComponent("detak_mentah", isDirectory: true) }

    init() {
        folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        muat()
    }

    private func muat() {
        guard let data = try? Data(contentsOf: fileJendela) else { return }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .secondsSince1970
        do {
            jendela = try dec.decode([JendelaHRV].self, from: data)
        } catch {
            CatatanLog.shared.tambah("APP ERROR file hasil rusak: \(error)")
        }
    }

    private func simpan() throws {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .secondsSince1970
        try enc.encode(jendela).write(to: fileJendela, options: .atomic)
    }

    func simpanRekaman(sampel: [SampelPPI], mulaiRekaman: Date, mulaiHeader: Date?) throws -> HasilSimpan {
        let tempat = WaktuSensor.tempatkan(sampel, mulaiRekaman: mulaiRekaman, mulaiHeader: mulaiHeader)
        let detak = ProsesHRV.proses(sampel, mulaiRekaman: mulaiRekaman, mulaiHeader: mulaiHeader)
        let baru = ProsesHRV.hitungJendela(detak)

        try FileManager.default.createDirectory(at: folderMentah, withIntermediateDirectories: true)
        let nama = "PPI_" + Self.namaFile(mulaiRekaman) + ".csv"
        try Data(CSVHRV.detak(detak).utf8).write(to: folderMentah.appendingPathComponent(nama), options: .atomic)

        jendela = ProsesHRV.gabung(lama: jendela, baru: baru)
        try simpan()
        return HasilSimpan(detak: detak.count, jendela: baru.count, layak: baru.filter(\.layak).count,
                           pakaiTimestamp: tempat.pakaiTimestamp)
    }

    // MARK: - Buat tampilan

    var hari: [Date] {
        let kal = Calendar.current
        return Set(jendela.map { kal.startOfDay(for: $0.mulai) }).sorted(by: >)
    }

    func jendelaPada(hari: Date) -> [JendelaHRV] {
        let kal = Calendar.current
        return jendela.filter { kal.isDate($0.mulai, inSameDayAs: hari) }
    }

    var belumKeHealth: [JendelaHRV] {
        jendela.filter { $0.layak && !$0.keHealth }
    }

    func tandaiKeHealth(_ mulai: Set<Date>) {
        guard !mulai.isEmpty else { return }
        for i in jendela.indices where mulai.contains(jendela[i].mulai) {
            jendela[i].keHealth = true
        }
        try? simpan()
    }

    func fileCsvJendela() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("hrv_seharian_\(Self.namaFile(Date())).csv")
        try Data(CSVHRV.jendela(jendela).utf8).write(to: url, options: .atomic)
        return url
    }

    func hapusSemua() {
        jendela = []
        try? FileManager.default.removeItem(at: fileJendela)
        try? FileManager.default.removeItem(at: folderMentah)
    }

    private static func namaFile(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd_HHmmss"
        return f.string(from: d)
    }
}
