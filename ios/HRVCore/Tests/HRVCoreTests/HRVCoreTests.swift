import XCTest
@testable import HRVCore

final class HRVCoreTests: XCTestCase {
    /// Kelipatan 300 detik, jadi pas di awal jendela 5 menit.
    let awal = Date(timeIntervalSince1970: 1_800_000_000)

    private func sampel(_ ppi: [Int], blocker: Set<Int> = []) -> [SampelPPI] {
        ppi.enumerated().map { i, p in SampelPPI(ppiMs: p, errorMs: 5, blocker: blocker.contains(i)) }
    }

    func testSaringanDasar() {
        var s = PenyaringDetak()
        XCTAssertEqual(s.nilai(ppiMs: 800, errorMs: 5, blocker: true), "gerak (blocker Polar)")
        XCTAssertEqual(s.nilai(ppiMs: 800, errorMs: 31, blocker: false), "error 31 ms")
        XCTAssertEqual(s.nilai(ppiMs: 250, errorMs: 5, blocker: false), "di luar 300-2000 ms")
        XCTAssertEqual(s.nilai(ppiMs: 2100, errorMs: 5, blocker: false), "di luar 300-2000 ms")
        for _ in 0..<3 { XCTAssertEqual(s.nilai(ppiMs: 800, errorMs: 5, blocker: false), "") }
        XCTAssertEqual(s.nilai(ppiMs: 1100, errorMs: 5, blocker: false), "loncat >20%")
        XCTAssertEqual(s.nilai(ppiMs: 900, errorMs: 5, blocker: false), "")
    }

    func testAcuanResetSetelah5Loncat() {
        var s = PenyaringDetak()
        for _ in 0..<5 { XCTAssertEqual(s.nilai(ppiMs: 1000, errorMs: 5, blocker: false), "") }
        let hasil = (0..<10).map { _ in s.nilai(ppiMs: 667, errorMs: 5, blocker: false) }
        XCTAssertEqual(hasil.prefix(5).filter { $0.isEmpty }.count, 0, "5 detak pertama di level baru harus dibuang")
        XCTAssertEqual(hasil.suffix(5).filter { $0.isEmpty }.count, 5, "abis acuan direset, detak berikutnya valid")
    }

    func testRmssdSdnnSatuJendela() throws {
        let ppi = (0..<200).map { $0 % 2 == 0 ? 800 : 850 }
        let detak = ProsesHRV.proses(sampel(ppi), mulaiRekaman: awal, mulaiHeader: nil)
        XCTAssertTrue(detak.allSatisfy(\.valid))
        let jendela = ProsesHRV.hitungJendela(detak)
        XCTAssertEqual(jendela.count, 1)
        let j = try XCTUnwrap(jendela.first)
        XCTAssertEqual(j.mulai, awal)
        XCTAssertEqual(j.selesai, awal.addingTimeInterval(300))
        XCTAssertEqual(j.total, 200)
        XCTAssertEqual(j.dipakai, 200)
        XCTAssertEqual(j.pasangan, 199)
        XCTAssertEqual(try XCTUnwrap(j.rmssd), 50, accuracy: 1e-9)
        let sdnnHarusnya = (200.0 * 625.0 / 199.0).squareRoot()
        XCTAssertEqual(try XCTUnwrap(j.sdnn), sdnnHarusnya, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(j.hrRata), 60000.0 / 825.0, accuracy: 1e-9)
        XCTAssertEqual(j.kualitas, .bagus)
        XCTAssertTrue(j.layak)
    }

    func testPasanganGakLewatDetakBuangan() throws {
        let detak = ProsesHRV.proses(sampel([800, 800, 800, 800, 800, 800], blocker: [3]),
                                     mulaiRekaman: awal, mulaiHeader: nil)
        let j = try XCTUnwrap(ProsesHRV.hitungJendela(detak).first)
        XCTAssertEqual(j.dipakai, 5)
        XCTAssertEqual(j.pasangan, 3)
        XCTAssertEqual(j.kualitas, .kurangData)
        XCTAssertFalse(j.layak)
    }

    func testTimestampSensorDanCelah() {
        // Header = jam dinding sensor 1000 detik sejak 2000-01-01, dibaca sebagai UTC.
        let header = Date(timeIntervalSince1970: WaktuSensor.epoch2000 + 1000)
        var detikSensor = 1000.0
        var daftar: [SampelPPI] = []
        for i in 0..<20 {
            if i == 10 { detikSensor += 60 } // sensor kelepas 1 menit
            detikSensor += 0.8
            daftar.append(SampelPPI(timeStampNs: UInt64((detikSensor * 1e9).rounded()), ppiMs: 800, errorMs: 5))
        }
        let t = WaktuSensor.tempatkan(daftar, mulaiRekaman: awal, mulaiHeader: header)
        XCTAssertTrue(t.pakaiTimestamp)
        XCTAssertEqual(t.waktu[0].timeIntervalSince(awal), 0.8, accuracy: 1e-3)
        XCTAssertEqual(t.waktu[19].timeIntervalSince(awal), 0.8 * 20 + 60, accuracy: 1e-3)
        XCTAssertEqual(t.putus.enumerated().filter { $0.element }.map(\.offset), [0, 10])

        // Celah juga bikin pasangan RMSSD gak nyambung.
        let detak = ProsesHRV.proses(daftar, mulaiRekaman: awal, mulaiHeader: header)
        XCTAssertTrue(detak[10].putusSebelumnya)
        XCTAssertEqual(ProsesHRV.hitungJendela(detak).first?.pasangan, 18)
    }

    func testTanpaTimestampDijumlahin() {
        let t = WaktuSensor.tempatkan(sampel([1000, 900, 1100]), mulaiRekaman: awal,
                                      mulaiHeader: Date(timeIntervalSince1970: 0))
        XCTAssertFalse(t.pakaiTimestamp)
        for (hasil, harusnya) in zip(t.waktu.map { $0.timeIntervalSince(awal) }, [1.0, 1.9, 3.0]) {
            XCTAssertEqual(hasil, harusnya, accuracy: 1e-6)
        }
        XCTAssertEqual(t.putus, [true, false, false])
    }

    func testTimestampAnehBalikKePenjumlahan() {
        // Timestamp ngaco (jauh dari header) -> jangan dipercaya.
        let header = Date(timeIntervalSince1970: WaktuSensor.epoch2000 + 1000)
        let daftar = (0..<5).map { i in
            SampelPPI(timeStampNs: UInt64((5_000_000 + Double(i)) * 1e9), ppiMs: 1000, errorMs: 5)
        }
        let t = WaktuSensor.tempatkan(daftar, mulaiRekaman: awal, mulaiHeader: header)
        XCTAssertFalse(t.pakaiTimestamp)
        XCTAssertEqual(t.waktu.last!.timeIntervalSince(awal), 5, accuracy: 1e-9)
    }

    func testDipotongPerLimaMenit() {
        let detak = ProsesHRV.proses(sampel(Array(repeating: 1000, count: 450)), mulaiRekaman: awal, mulaiHeader: nil)
        let jendela = ProsesHRV.hitungJendela(detak)
        XCTAssertEqual(jendela.map(\.total), [299, 151])
        XCTAssertEqual(jendela.map(\.mulai), [awal, awal.addingTimeInterval(300)])
        XCTAssertEqual(jendela[0].pasangan, 298)
        XCTAssertEqual(jendela[1].pasangan, 150)
    }

    func testKualitas() {
        XCTAssertEqual(ProsesHRV.kualitas(pasangan: 59, persenDibuang: 0), .kurangData)
        XCTAssertEqual(ProsesHRV.kualitas(pasangan: 60, persenDibuang: 5), .bagus)
        XCTAssertEqual(ProsesHRV.kualitas(pasangan: 60, persenDibuang: 20), .lumayan)
        XCTAssertEqual(ProsesHRV.kualitas(pasangan: 60, persenDibuang: 20.1), .jelek)
    }

    func testGabungPilihYangDatanyaLebihBanyak() {
        func j(_ pasangan: Int, keHealth: Bool) -> JendelaHRV {
            JendelaHRV(mulai: awal, selesai: awal.addingTimeInterval(300), total: pasangan + 1, dipakai: pasangan + 1,
                       pasangan: pasangan, persenDibuang: 0, detikData: 200, rmssd: 40, sdnn: 50, hrRata: 60,
                       kualitas: .bagus, keHealth: keHealth)
        }
        let lama = [j(100, keHealth: true)]
        XCTAssertEqual(ProsesHRV.gabung(lama: lama, baru: [j(80, keHealth: false)]), lama)
        let ganti = ProsesHRV.gabung(lama: lama, baru: [j(120, keHealth: false)])
        XCTAssertEqual(ganti.count, 1)
        XCTAssertEqual(ganti[0].pasangan, 120)
        XCTAssertFalse(ganti[0].keHealth)
    }

    func testJsonLamaTanpaKeHealthTetepKebaca() throws {
        let json = #"[{"mulai":1800000000,"selesai":1800000300,"total":10,"dipakai":9,"pasangan":8,"persenDibuang":10,"kualitas":"kurang-data"}]"#
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .secondsSince1970
        let hasil = try dec.decode([JendelaHRV].self, from: Data(json.utf8))
        XCTAssertEqual(hasil.first?.keHealth, false)
        XCTAssertEqual(hasil.first?.kualitas, .kurangData)

        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .secondsSince1970
        let balik = try dec.decode([JendelaHRV].self, from: enc.encode(hasil))
        XCTAssertEqual(balik, hasil)
    }

    func testCsv() {
        let detak = ProsesHRV.proses(sampel([800, 810, 820], blocker: [1]), mulaiRekaman: awal, mulaiHeader: nil)
        let zona = TimeZone(identifier: "Europe/Istanbul")!
        let teksDetak = CSVHRV.detak(detak, zona: zona).split(separator: "\n")
        XCTAssertEqual(teksDetak.count, 4)
        XCTAssertEqual(String(teksDetak[0]), CSVHRV.kolomDetak.joined(separator: ","))
        XCTAssertTrue(teksDetak[2].hasSuffix(",0,gerak (blocker Polar)"))

        let jendela = ProsesHRV.hitungJendela(detak)
        let teksJendela = CSVHRV.jendela(jendela, zona: zona).split(separator: "\n")
        XCTAssertEqual(teksJendela.count, 2)
        XCTAssertEqual(String(teksJendela[0]), CSVHRV.kolomJendela.joined(separator: ","))
        XCTAssertEqual(CSVHRV.aman("a,b"), "\"a,b\"")
    }

    func testRingkasan() {
        let detak = ProsesHRV.proses(sampel((0..<600).map { $0 % 2 == 0 ? 800 : 850 }), mulaiRekaman: awal, mulaiHeader: nil)
        let r = ProsesHRV.ringkas(ProsesHRV.hitungJendela(detak))
        XCTAssertEqual(r.jumlahJendela, 2)
        XCTAssertEqual(r.jumlahLayak, 2)
        XCTAssertEqual(r.rmssdMedian ?? 0, 50, accuracy: 1e-9)
        XCTAssertEqual(r.jamData, 600 * 0.825 / 3600, accuracy: 1e-9)
    }
}
