import Foundation

// Logika HRV buat app "HRV Seharian".
// Aturan saringannya sama persis kayak halaman web HRV (index.html) dan hrv_verity.py,
// bedanya di sini datanya seharian, jadi hasilnya dipotong per jendela 5 menit.

// MARK: - Data mentah dari sensor

/// Satu sampel PPI persis kayak yang dikasih Polar SDK.
public struct SampelPPI: Equatable, Sendable {
    /// Nanodetik sejak 2000-01-01 menurut jam sensor. 0 = sensor gak ngasih timestamp.
    public var timeStampNs: UInt64
    public var hr: Int
    public var ppiMs: Int
    public var errorMs: Int
    public var blocker: Bool
    public var kontakKulit: Bool
    public var kontakDidukung: Bool

    public init(timeStampNs: UInt64 = 0, hr: Int = 0, ppiMs: Int, errorMs: Int = 10,
                blocker: Bool = false, kontakKulit: Bool = true, kontakDidukung: Bool = false) {
        self.timeStampNs = timeStampNs
        self.hr = hr
        self.ppiMs = ppiMs
        self.errorMs = errorMs
        self.blocker = blocker
        self.kontakKulit = kontakKulit
        self.kontakDidukung = kontakDidukung
    }
}

/// Satu detak yang udah ditaruh di jam beneran, plus hasil saringannya.
public struct Detak: Equatable, Sendable {
    public var waktu: Date
    public var ppiMs: Int
    public var errorMs: Int
    public var hr: Int
    public var blocker: Bool
    public var kontakKulit: Bool
    public var kontakDidukung: Bool
    /// true kalau sebelum detak ini ada celah (awal rekaman atau data bolong).
    public var putusSebelumnya: Bool
    public var valid: Bool
    /// Alasan dibuang. Kosong kalau valid.
    public var alasan: String

    public init(waktu: Date, ppiMs: Int, errorMs: Int, hr: Int, blocker: Bool, kontakKulit: Bool,
                kontakDidukung: Bool, putusSebelumnya: Bool, valid: Bool, alasan: String) {
        self.waktu = waktu
        self.ppiMs = ppiMs
        self.errorMs = errorMs
        self.hr = hr
        self.blocker = blocker
        self.kontakKulit = kontakKulit
        self.kontakDidukung = kontakDidukung
        self.putusSebelumnya = putusSebelumnya
        self.valid = valid
        self.alasan = alasan
    }
}

// MARK: - Aturan

public struct AturanHRV: Sendable, Equatable {
    /// Buang detak yang perkiraan error-nya di atas ini.
    public var batasErrorMs = 30
    public var ppiMinMs = 300
    public var ppiMaksMs = 2000
    /// Buang detak yang loncat lebih dari 20% dari median 5 detak valid terakhir.
    public var batasLoncat = 0.20
    /// Kalau udah 5x "loncat" berturut-turut, kemungkinan acuannya yang salah, jadi acuannya direset.
    public var loncatSebelumReset = 5
    /// Panjang satu jendela (detik). 5 menit = standar HRV jangka pendek.
    public var panjangJendela: TimeInterval = 300
    /// Minimal pasangan detak berurutan yang bersih biar jendelanya dihitung.
    public var minPasangan = 60
    public var persenBagus = 5.0
    public var persenLumayan = 20.0

    public init() {}
}

public enum KualitasJendela: String, Codable, Sendable, CaseIterable {
    case bagus
    case lumayan
    case jelek
    case kurangData = "kurang-data"
}

// MARK: - Hasil per jendela 5 menit

public struct JendelaHRV: Codable, Equatable, Identifiable, Sendable {
    public var id: Date { mulai }
    public var mulai: Date
    public var selesai: Date
    public var total: Int
    public var dipakai: Int
    public var pasangan: Int
    public var persenDibuang: Double
    public var detikData: Double
    public var rmssd: Double?
    public var lnRmssd: Double?
    public var sdnn: Double?
    public var hrRata: Double?
    public var kualitas: KualitasJendela
    /// Udah dikirim ke Apple Health atau belum.
    public var keHealth: Bool

    /// Cukup bersih buat dipakai (dan dikirim ke Apple Health).
    public var layak: Bool {
        (kualitas == .bagus || kualitas == .lumayan) && rmssd != nil && sdnn != nil
    }

    public init(mulai: Date, selesai: Date, total: Int, dipakai: Int, pasangan: Int,
                persenDibuang: Double, detikData: Double, rmssd: Double? = nil, lnRmssd: Double? = nil,
                sdnn: Double? = nil, hrRata: Double? = nil, kualitas: KualitasJendela, keHealth: Bool = false) {
        self.mulai = mulai
        self.selesai = selesai
        self.total = total
        self.dipakai = dipakai
        self.pasangan = pasangan
        self.persenDibuang = persenDibuang
        self.detikData = detikData
        self.rmssd = rmssd
        self.lnRmssd = lnRmssd
        self.sdnn = sdnn
        self.hrRata = hrRata
        self.kualitas = kualitas
        self.keHealth = keHealth
    }

    enum CodingKeys: String, CodingKey {
        case mulai, selesai, total, dipakai, pasangan, persenDibuang, detikData
        case rmssd, lnRmssd, sdnn, hrRata, kualitas, keHealth
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mulai = try c.decode(Date.self, forKey: .mulai)
        selesai = try c.decode(Date.self, forKey: .selesai)
        total = try c.decode(Int.self, forKey: .total)
        dipakai = try c.decode(Int.self, forKey: .dipakai)
        pasangan = try c.decode(Int.self, forKey: .pasangan)
        persenDibuang = try c.decode(Double.self, forKey: .persenDibuang)
        detikData = try c.decodeIfPresent(Double.self, forKey: .detikData) ?? 0
        rmssd = try c.decodeIfPresent(Double.self, forKey: .rmssd)
        lnRmssd = try c.decodeIfPresent(Double.self, forKey: .lnRmssd)
        sdnn = try c.decodeIfPresent(Double.self, forKey: .sdnn)
        hrRata = try c.decodeIfPresent(Double.self, forKey: .hrRata)
        kualitas = try c.decodeIfPresent(KualitasJendela.self, forKey: .kualitas) ?? .kurangData
        keHealth = try c.decodeIfPresent(Bool.self, forKey: .keHealth) ?? false
    }
}

public struct RingkasanHari: Equatable, Sendable {
    public var jumlahJendela: Int
    public var jumlahLayak: Int
    public var rmssdMedian: Double?
    public var sdnnMedian: Double?
    public var hrRata: Double?
    /// Lama data terekam (jam), dihitung dari jumlah detak.
    public var jamData: Double
}

// MARK: - Statistik

public enum Statistik {
    public static func median(_ x: [Double]) -> Double {
        guard !x.isEmpty else { return .nan }
        let s = x.sorted()
        let n = s.count
        return n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2
    }

    public static func rata(_ x: [Double]) -> Double {
        x.isEmpty ? .nan : x.reduce(0, +) / Double(x.count)
    }

    /// Standar deviasi sampel (n-1), sama kayak SDNN di halaman web.
    public static func sd(_ x: [Double]) -> Double {
        guard x.count >= 2 else { return .nan }
        let m = rata(x)
        let v = x.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(x.count - 1)
        return v.squareRoot()
    }
}

// MARK: - Saringan detak

public struct PenyaringDetak: Sendable {
    public let aturan: AturanHRV
    private var validTerakhir: [Int] = []
    private var loncatBerturut = 0

    public init(aturan: AturanHRV = AturanHRV()) {
        self.aturan = aturan
    }

    /// Lupain acuan (dipakai abis ada celah di data).
    public mutating func reset() {
        validTerakhir = []
        loncatBerturut = 0
    }

    /// Balikin alasan dibuang, atau "" kalau detaknya valid.
    public mutating func nilai(ppiMs: Int, errorMs: Int, blocker: Bool) -> String {
        var alasan = ""
        var loncat = false
        if blocker {
            alasan = "gerak (blocker Polar)"
        } else if errorMs > aturan.batasErrorMs {
            alasan = "error \(errorMs) ms"
        } else if ppiMs < aturan.ppiMinMs || ppiMs > aturan.ppiMaksMs {
            alasan = "di luar \(aturan.ppiMinMs)-\(aturan.ppiMaksMs) ms"
        } else if validTerakhir.count >= 3 {
            let m = Statistik.median(validTerakhir.map(Double.init))
            if m > 0, abs(Double(ppiMs) - m) / m > aturan.batasLoncat {
                loncat = true
                alasan = "loncat >\(Int((aturan.batasLoncat * 100).rounded()))%"
            }
        }
        if loncat {
            loncatBerturut += 1
            if loncatBerturut >= aturan.loncatSebelumReset {
                validTerakhir = []
                loncatBerturut = 0
            }
        } else {
            loncatBerturut = 0
        }
        if alasan.isEmpty {
            validTerakhir.append(ppiMs)
            if validTerakhir.count > 5 { validTerakhir.removeFirst() }
        }
        return alasan
    }
}

// MARK: - Jam sensor -> jam beneran

public enum WaktuSensor {
    /// Detik antara 1970-01-01 dan 2000-01-01 (epoch jam Polar).
    public static let epoch2000: TimeInterval = 946_684_800

    /// Naruh tiap sampel di jam beneran.
    ///
    /// - `mulaiRekaman`: jam mulai rekaman yang bener (dari daftar rekaman di sensor, udah pakai zona waktu HP).
    /// - `mulaiHeader`: jam mulai dari header file rekaman (jam dinding sensor yang kebaca sebagai UTC).
    ///
    /// Kalau sampelnya punya timestamp, posisi tiap detak dihitung relatif ke header pakai jam sensor
    /// sendiri, jadi selisih zona waktu gak ngaruh dan celah data bisa kedeteksi.
    /// Kalau gak ada timestamp, waktunya dijumlahin dari interval PPI (celah gak kedeteksi).
    public static func tempatkan(_ sampel: [SampelPPI], mulaiRekaman: Date, mulaiHeader: Date?)
        -> (waktu: [Date], putus: [Bool], pakaiTimestamp: Bool) {
        let n = sampel.count
        guard n > 0 else { return ([], [], false) }

        var waktu: [Date] = []
        waktu.reserveCapacity(n)
        var pakaiTimestamp = false

        let adaTimestamp = sampel.reduce(0) { $0 + ($1.timeStampNs != 0 ? 1 : 0) }
        if let header = mulaiHeader, adaTimestamp * 10 >= n * 9 {
            let acuan = header.timeIntervalSince1970
            var calon: [Date] = []
            calon.reserveCapacity(n)
            var sebelum: Date?
            for s in sampel {
                let t: Date
                if s.timeStampNs != 0 {
                    let detikSensor = epoch2000 + Double(s.timeStampNs) / 1_000_000_000
                    t = mulaiRekaman.addingTimeInterval(detikSensor - acuan)
                } else {
                    t = (sebelum ?? mulaiRekaman).addingTimeInterval(Double(s.ppiMs) / 1000)
                }
                calon.append(t)
                sebelum = t
            }
            // Cek masuk akal: detak pertama gak jauh dari awal rekaman, rekaman gak lebih dari 3 hari.
            let awal = calon[0].timeIntervalSince(mulaiRekaman)
            let akhir = calon[n - 1].timeIntervalSince(mulaiRekaman)
            if awal > -120, awal < 12 * 3600, akhir >= awal, akhir < 3 * 86_400 {
                waktu = calon
                pakaiTimestamp = true
            }
        }

        if !pakaiTimestamp {
            var t = mulaiRekaman
            for s in sampel {
                t = t.addingTimeInterval(Double(s.ppiMs) / 1000)
                waktu.append(t)
            }
        }

        var putus = [Bool](repeating: false, count: n)
        putus[0] = true
        if pakaiTimestamp {
            for i in 1..<n {
                let jarak = waktu[i].timeIntervalSince(waktu[i - 1])
                let harusnya = Double(sampel[i].ppiMs) / 1000
                putus[i] = jarak > harusnya + 1.5 || jarak < harusnya - 1.0
            }
        }
        return (waktu, putus, pakaiTimestamp)
    }
}

// MARK: - Proses

public enum ProsesHRV {
    /// Sampel mentah -> detak yang udah ditaruh di jam beneran dan udah disaring.
    public static func proses(_ sampel: [SampelPPI], mulaiRekaman: Date, mulaiHeader: Date?,
                              aturan: AturanHRV = AturanHRV()) -> [Detak] {
        let tempat = WaktuSensor.tempatkan(sampel, mulaiRekaman: mulaiRekaman, mulaiHeader: mulaiHeader)
        var saring = PenyaringDetak(aturan: aturan)
        var hasil: [Detak] = []
        hasil.reserveCapacity(sampel.count)
        for (i, s) in sampel.enumerated() {
            let putus = tempat.putus[i]
            if putus { saring.reset() }
            let alasan = saring.nilai(ppiMs: s.ppiMs, errorMs: s.errorMs, blocker: s.blocker)
            hasil.append(Detak(waktu: tempat.waktu[i], ppiMs: s.ppiMs, errorMs: s.errorMs, hr: s.hr,
                               blocker: s.blocker, kontakKulit: s.kontakKulit, kontakDidukung: s.kontakDidukung,
                               putusSebelumnya: putus, valid: alasan.isEmpty, alasan: alasan))
        }
        return hasil
    }

    /// Potong detak jadi jendela 5 menit (nempel ke jam: 08:00, 08:05, ...) terus hitung HRV tiap jendela.
    public static func hitungJendela(_ detak: [Detak], aturan: AturanHRV = AturanHRV()) -> [JendelaHRV] {
        guard !detak.isEmpty else { return [] }
        let p = aturan.panjangJendela
        var kelompok: [TimeInterval: [Detak]] = [:]
        for d in detak {
            let slot = (d.waktu.timeIntervalSince1970 / p).rounded(.down) * p
            kelompok[slot, default: []].append(d)
        }
        return kelompok.keys.sorted().map { slot in
            hitungSatu(kelompok[slot] ?? [], mulai: Date(timeIntervalSince1970: slot), aturan: aturan)
        }
    }

    static func hitungSatu(_ isi: [Detak], mulai: Date, aturan: AturanHRV) -> JendelaHRV {
        let nn = isi.filter(\.valid).map { Double($0.ppiMs) }
        // Selisih cuma dari 2 detak yang beneran berurutan, dua-duanya valid, dan gak ada celah di antaranya.
        var selisih: [Double] = []
        if isi.count > 1 {
            for i in 1..<isi.count where isi[i - 1].valid && isi[i].valid && !isi[i].putusSebelumnya {
                selisih.append(Double(isi[i].ppiMs - isi[i - 1].ppiMs))
            }
        }
        let total = isi.count
        let persen = total > 0 ? 100 * Double(total - nn.count) / Double(total) : 0
        var j = JendelaHRV(mulai: mulai, selesai: mulai.addingTimeInterval(aturan.panjangJendela),
                           total: total, dipakai: nn.count, pasangan: selisih.count, persenDibuang: persen,
                           detikData: isi.reduce(0) { $0 + Double($1.ppiMs) } / 1000,
                           kualitas: .kurangData)
        if selisih.count >= 2 && nn.count >= 2 {
            let rmssd = (selisih.reduce(0) { $0 + $1 * $1 } / Double(selisih.count)).squareRoot()
            j.rmssd = rmssd
            j.lnRmssd = rmssd > 0 ? log(rmssd) : nil
            j.sdnn = Statistik.sd(nn)
            j.hrRata = 60000 / Statistik.rata(nn)
        }
        j.kualitas = kualitas(pasangan: selisih.count, persenDibuang: persen, aturan: aturan)
        return j
    }

    public static func kualitas(pasangan: Int, persenDibuang: Double, aturan: AturanHRV = AturanHRV()) -> KualitasJendela {
        if pasangan < aturan.minPasangan { return .kurangData }
        if persenDibuang <= aturan.persenBagus { return .bagus }
        if persenDibuang <= aturan.persenLumayan { return .lumayan }
        return .jelek
    }

    /// Gabungin jendela lama + baru. Kalau jamnya sama, yang datanya lebih banyak yang menang.
    public static func gabung(lama: [JendelaHRV], baru: [JendelaHRV]) -> [JendelaHRV] {
        var peta: [Date: JendelaHRV] = [:]
        for j in lama { peta[j.mulai] = j }
        for j in baru {
            if let ada = peta[j.mulai] {
                if j.pasangan > ada.pasangan || (j.pasangan == ada.pasangan && j.total > ada.total) {
                    var b = j
                    b.keHealth = false
                    peta[j.mulai] = b
                }
            } else {
                peta[j.mulai] = j
            }
        }
        return peta.values.sorted { $0.mulai < $1.mulai }
    }

    public static func ringkas(_ jendela: [JendelaHRV]) -> RingkasanHari {
        let layak = jendela.filter(\.layak)
        func med(_ x: [Double]) -> Double? { x.isEmpty ? nil : Statistik.median(x) }
        let hr = layak.compactMap(\.hrRata)
        return RingkasanHari(
            jumlahJendela: jendela.count,
            jumlahLayak: layak.count,
            rmssdMedian: med(layak.compactMap(\.rmssd)),
            sdnnMedian: med(layak.compactMap(\.sdnn)),
            hrRata: hr.isEmpty ? nil : Statistik.rata(hr),
            jamData: jendela.reduce(0) { $0 + $1.detikData } / 3600
        )
    }
}

// MARK: - CSV

public enum CSVHRV {
    public static let kolomJendela = ["tanggal", "jam_mulai", "jam_selesai", "detak_total", "detak_dipakai",
                                      "persen_dibuang", "pasangan", "detik_data", "hr_rata", "rmssd_ms",
                                      "ln_rmssd", "sdnn_ms", "kualitas", "layak", "ke_apple_health"]

    public static let kolomDetak = ["waktu", "ppi_ms", "error_ms", "hr", "blocker", "kontak_kulit",
                                    "putus_sebelumnya", "valid", "alasan"]

    public static func jendela(_ daftar: [JendelaHRV], zona: TimeZone = .current) -> String {
        let tgl = formatter("yyyy-MM-dd", zona)
        let jam = formatter("HH:mm", zona)
        var baris = [kolomJendela.joined(separator: ",")]
        baris.reserveCapacity(daftar.count + 1)
        for j in daftar {
            let sel: [String] = [
                tgl.string(from: j.mulai), jam.string(from: j.mulai), jam.string(from: j.selesai),
                String(j.total), String(j.dipakai), angka(j.persenDibuang, 1), String(j.pasangan),
                angka(j.detikData, 0), angka(j.hrRata, 1), angka(j.rmssd, 1), angka(j.lnRmssd, 3),
                angka(j.sdnn, 1), j.kualitas.rawValue, j.layak ? "1" : "0", j.keHealth ? "1" : "0",
            ]
            baris.append(sel.map(aman).joined(separator: ","))
        }
        return baris.joined(separator: "\n") + "\n"
    }

    public static func detak(_ daftar: [Detak], zona: TimeZone = .current) -> String {
        let f = formatter("yyyy-MM-dd HH:mm:ss.SSS", zona)
        var baris = [kolomDetak.joined(separator: ",")]
        baris.reserveCapacity(daftar.count + 1)
        for d in daftar {
            let sel: [String] = [
                f.string(from: d.waktu), String(d.ppiMs), String(d.errorMs), String(d.hr),
                d.blocker ? "1" : "0", d.kontakDidukung ? (d.kontakKulit ? "1" : "0") : "",
                d.putusSebelumnya ? "1" : "0", d.valid ? "1" : "0", d.alasan,
            ]
            baris.append(sel.map(aman).joined(separator: ","))
        }
        return baris.joined(separator: "\n") + "\n"
    }

    static func formatter(_ pola: String, _ zona: TimeZone) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = zona
        f.dateFormat = pola
        return f
    }

    static func angka(_ x: Double?, _ desimal: Int) -> String {
        guard let x = x, x.isFinite else { return "" }
        return String(format: "%.\(desimal)f", x)
    }

    static func aman(_ s: String) -> String {
        guard s.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return s }
        return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
