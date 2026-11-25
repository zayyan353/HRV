import Foundation
import HealthKit
import UIKit
import HRVCore

/// Nulis HRV (SDNN, sama kayak yang dipakai Apple Watch) per jendela 5 menit ke Apple Health.
/// Kalau HealthKit gak bisa dipakai (izinnya gak kebawa pas sideload), ada jalur cadangan lewat Shortcuts.
@MainActor
final class PenulisHealth: ObservableObject {
    enum Status: Equatable {
        case belumDicek
        case tidakTersedia
        case belumIzin
        case siap
        case ditolak
        case gagal(String)
    }

    @Published private(set) var status: Status = .belumDicek

    static let namaShortcut = "Catat HRV Seharian"

    private let store = HKHealthStore()
    private let tipe = HKQuantityType(.heartRateVariabilitySDNN)
    private let ms = HKUnit.secondUnit(with: .milli)

    var butuhCadangan: Bool {
        if case .gagal = status { return true }
        return status == .tidakTersedia
    }

    func cek() {
        guard HKHealthStore.isHealthDataAvailable() else {
            status = .tidakTersedia
            return
        }
        if case .gagal = status { return }
        switch store.authorizationStatus(for: tipe) {
        case .notDetermined: status = .belumIzin
        case .sharingDenied: status = .ditolak
        case .sharingAuthorized: status = .siap
        @unknown default: status = .belumIzin
        }
    }

    func mintaIzin() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            status = .tidakTersedia
            return
        }
        do {
            try await store.requestAuthorization(toShare: [tipe], read: [])
            status = .belumDicek
            cek()
        } catch {
            CatatanLog.shared.tambah("APP ERROR izin Health: \(error)")
            status = .gagal(error.localizedDescription)
        }
    }

    /// Kirim jendela ke Apple Health. Balikin jam mulai jendela yang berhasil masuk.
    func kirim(_ daftar: [JendelaHRV], namaSensor: String?, firmware: String?) async throws -> Set<Date> {
        let perangkat = HKDevice(name: namaSensor ?? "Polar Verity Sense", manufacturer: "Polar",
                                 model: "Verity Sense", hardwareVersion: nil, firmwareVersion: firmware,
                                 softwareVersion: nil, localIdentifier: namaSensor, udiDeviceIdentifier: nil)
        var pasangan: [(Date, HKQuantitySample)] = []
        for j in daftar {
            guard j.layak, let sdnn = j.sdnn, let rmssd = j.rmssd else { continue }
            let meta: [String: Any] = [
                // Sync identifier bikin data yang dikirim ulang gak dobel di Health.
                HKMetadataKeySyncIdentifier: "hrvseharian-\(Int(j.mulai.timeIntervalSince1970))",
                HKMetadataKeySyncVersion: max(1, j.pasangan),
                "HRVSeharian_RMSSD_ms": (rmssd * 10).rounded() / 10,
                "HRVSeharian_detak_dipakai": j.dipakai,
                "HRVSeharian_persen_dibuang": (j.persenDibuang * 10).rounded() / 10,
            ]
            let sampel = HKQuantitySample(type: tipe, quantity: HKQuantity(unit: ms, doubleValue: sdnn),
                                          start: j.mulai, end: j.selesai, device: perangkat, metadata: meta)
            pasangan.append((j.mulai, sampel))
        }
        guard !pasangan.isEmpty else { return [] }

        do {
            try await store.save(pasangan.map { $0.1 })
            return Set(pasangan.map { $0.0 })
        } catch {
            // Kalau sekaligus gagal (misal ada 1 yang bentrok), coba satu-satu.
            CatatanLog.shared.tambah("APP simpan Health sekaligus gagal: \(error). Coba satu-satu.")
            var masuk = Set<Date>()
            for (mulai, sampel) in pasangan {
                if (try? await store.save(sampel)) != nil { masuk.insert(mulai) }
            }
            if masuk.isEmpty {
                status = .gagal(error.localizedDescription)
                throw error
            }
            return masuk
        }
    }

    /// Jalur cadangan: salin data ke clipboard terus jalanin shortcut "Catat HRV Seharian".
    /// Format tiap baris: "2026-11-25 08:05:00;45" (SDNN dibulatin biar aman dari beda koma/titik).
    @discardableResult
    func kirimLewatShortcuts(_ daftar: [JendelaHRV]) -> Int {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let baris = daftar.compactMap { j -> String? in
            guard j.layak, let s = j.sdnn else { return nil }
            return "\(f.string(from: j.mulai));\(Int(s.rounded()))"
        }
        guard !baris.isEmpty else { return 0 }
        UIPasteboard.general.string = baris.joined(separator: "\n")
        let nama = Self.namaShortcut.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "shortcuts://run-shortcut?name=\(nama)&input=clipboard") {
            UIApplication.shared.open(url)
        }
        return baris.count
    }
}
