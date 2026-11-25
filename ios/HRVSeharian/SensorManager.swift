import Foundation
import CoreBluetooth
import UIKit
import PolarBleSdk
import HRVCore

struct SensorKetemu: Identifiable, Equatable {
    let id: String
    let nama: String
    let rssi: Int
}

enum StatusKoneksi: Equatable {
    case putus
    case nyari
    case nyambung(String)
    case terhubung(String)
}

struct Pesan: Identifiable, Equatable {
    let id = UUID()
    let teks: String
    let error: Bool
}

/// Semua urusan sama Verity Sense lewat Polar BLE SDK resmi.
@MainActor
final class SensorManager: ObservableObject {
    @Published private(set) var koneksi: StatusKoneksi = .putus
    @Published private(set) var bluetoothNyala = true
    @Published private(set) var ditemukan: [SensorKetemu] = []
    @Published private(set) var idTersimpan: String?
    @Published private(set) var namaSensor: String?
    @Published private(set) var baterai: UInt?
    @Published private(set) var firmware: String?
    @Published private(set) var siapRekam = false
    @Published private(set) var lagiRekam: Bool?
    @Published private(set) var triggerNyala: Bool?
    @Published private(set) var rekamanDiSensor: [PolarOfflineRecordingEntry] = []
    @Published private(set) var ruangKosong: UInt64?
    @Published private(set) var ruangTotal: UInt64?
    @Published private(set) var selisihJamDetik: TimeInterval?
    @Published private(set) var sibuk: String?
    @Published private(set) var progres: Double?
    @Published var pesan: Pesan?

    private var api: PolarBleApi
    private var tugasCari: Task<Void, Never>?
    private var antrian: Task<Void, Never>?
    private var putusSengaja = false
    private static let kunciId = "idSensorPolar"

    var idAktif: String? {
        if case .terhubung(let id) = koneksi { return id }
        return nil
    }

    var rekamanPPI: [PolarOfflineRecordingEntry] {
        rekamanDiSensor.filter { $0.type == .ppi }
    }

    init() {
        api = PolarBleApiDefaultImpl.polarImplementation(DispatchQueue.main, features: [
            .feature_polar_offline_recording,
            .feature_device_info,
            .feature_battery_info,
            .feature_polar_device_time_setup,
        ])
        idTersimpan = UserDefaults.standard.string(forKey: Self.kunciId)
        api.polarFilter(true)
        api.observer = self
        api.powerStateObserver = self
        api.deviceInfoObserver = self
        api.deviceFeaturesObserver = self
        api.logger = self
        CatatanLog.shared.tambah("Polar BLE SDK \(PolarBleApiDefaultImpl.versionInfo())")
        // Sambung otomatis ke sensor terakhir begitu Bluetooth siap.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            self.sambungOtomatis()
        }
    }

    // MARK: - Nyari & nyambung

    func cariSensor() {
        guard bluetoothNyala else {
            kabari("Bluetooth iPhone lagi mati. Nyalain dulu.", error: true)
            return
        }
        tugasCari?.cancel()
        ditemukan = []
        koneksi = .nyari
        pesan = nil
        tugasCari = Task { @MainActor in
            do {
                for try await info in self.api.searchForDevice() {
                    let s = SensorKetemu(id: info.deviceId, nama: info.name, rssi: info.rssi)
                    if let i = self.ditemukan.firstIndex(where: { $0.id == s.id }) {
                        self.ditemukan[i] = s
                    } else {
                        self.ditemukan.append(s)
                    }
                }
            } catch is CancellationError {
            } catch {
                self.lapor(error, konteks: "Nyari sensor")
            }
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            if self.koneksi == .nyari {
                self.berhentiCari()
                if self.ditemukan.isEmpty {
                    self.kabari("Gak nemu sensor. Pastiin Verity Sense nyala (pencet tombolnya sampai lampunya nyala) terus coba lagi.", error: true)
                }
            }
        }
    }

    func berhentiCari() {
        tugasCari?.cancel()
        tugasCari = nil
        if koneksi == .nyari { koneksi = .putus }
    }

    func sambungkan(_ id: String) {
        tugasCari?.cancel()
        tugasCari = nil
        putusSengaja = false
        do {
            try api.connectToDevice(id)
            koneksi = .nyambung(id)
            idTersimpan = id
            UserDefaults.standard.set(id, forKey: Self.kunciId)
        } catch {
            koneksi = .putus
            lapor(error, konteks: "Nyambung")
        }
    }

    func putuskan() {
        let id: String?
        switch koneksi {
        case .terhubung(let x), .nyambung(let x): id = x
        default: id = nil
        }
        putusSengaja = true
        if let id = id { try? api.disconnectFromDevice(id) }
        koneksi = .putus
        resetStatusSensor()
    }

    func lupakanSensor() {
        putuskan()
        idTersimpan = nil
        UserDefaults.standard.removeObject(forKey: Self.kunciId)
    }

    private func sambungOtomatis() {
        guard koneksi == .putus, !putusSengaja, bluetoothNyala, let id = idTersimpan else { return }
        sambungkan(id)
    }

    private func saatTerhubung(id: String, nama: String) {
        koneksi = .terhubung(id)
        namaSensor = nama
        CatatanLog.shared.tambah("APP tersambung ke \(nama)")
    }

    private func saatPutus(id: String, info: PolarBleDisconnectInfo) {
        CatatanLog.shared.tambah("APP putus dari \(id): \(info.reason) / \(info.recoveryAction)")
        resetStatusSensor()
        if putusSengaja {
            koneksi = .putus
            return
        }
        // Kalau bukan kita yang mutusin, SDK otomatis nyoba nyambung lagi.
        koneksi = .nyambung(id)
        if info.recoveryAction == .removePairingAndPairAgain || info.reason == .pairingInformationRemoved
            || info.reason == .pairingNegotiationFailed || info.reason == .insufficientEncryption {
            kabari("Pairing sensor bermasalah. Buka Pengaturan > Bluetooth > Polar Sense > Lupakan Perangkat Ini, terus sambungin lagi dari app ini.", error: true)
        }
    }

    private func resetStatusSensor() {
        siapRekam = false
        lagiRekam = nil
        triggerNyala = nil
        rekamanDiSensor = []
        ruangKosong = nil
        ruangTotal = nil
        selisihJamDetik = nil
        baterai = nil
    }

    private func fiturSiap(_ id: String, _ fitur: PolarBleSdkFeature) {
        switch fitur {
        case .feature_polar_offline_recording:
            siapRekam = true
            antre("Ngecek sensor") { try await self.segarkanInti(id) }
        case .feature_polar_device_time_setup:
            antre("Ngecek jam sensor") { try await self.cekJam(id) }
        default:
            break
        }
    }

    // MARK: - Antrian perintah (SDK gak boleh dikasih 2 perintah barengan)

    private func antre(_ label: String, _ kerja: @escaping @MainActor () async throws -> Void) {
        let sebelumnya = antrian
        antrian = Task { @MainActor in
            await sebelumnya?.value
            self.sibuk = label
            do {
                try await kerja()
            } catch {
                self.lapor(error, konteks: label)
            }
            self.sibuk = nil
            self.progres = nil
        }
    }

    // MARK: - Status

    func segarkan() {
        guard let id = idAktif, siapRekam else { return }
        antre("Ngecek sensor") { try await self.segarkanInti(id) }
    }

    private func segarkanInti(_ id: String) async throws {
        let status = try await api.getOfflineRecordingStatus(id)
        lagiRekam = status[.ppi] ?? false
        do {
            let t = try await api.getOfflineRecordingTriggerSetup(id)
            triggerNyala = t.triggerMode == .triggerSystemStart && t.triggerFeatures.keys.contains(.ppi)
        } catch {
            CatatanLog.shared.tambah("APP trigger gak kebaca: \(error)")
        }
        var daftar: [PolarOfflineRecordingEntry] = []
        for try await e in api.listOfflineRecordings(id) {
            daftar.append(e)
        }
        rekamanDiSensor = daftar.sorted { $0.date < $1.date }
        do {
            let ruang = try await api.getDiskSpace(id)
            ruangKosong = ruang.freeSpace
            ruangTotal = ruang.totalSpace
        } catch {
            CatatanLog.shared.tambah("APP ruang memori gak kebaca: \(error)")
        }
    }

    private func cekJam(_ id: String) async throws {
        let (jamSensor, zona) = try await api.getLocalTimeWithZone(id)
        selisihJamDetik = jamSensor.timeIntervalSince(Date())
        CatatanLog.shared.tambah("APP jam sensor \(jamSensor) zona \(zona.identifier), selisih \(Int(selisihJamDetik ?? 0)) detik")
    }

    func samakanJam() {
        guard let id = idAktif else { return }
        antre("Nyamain jam sensor") {
            try await self.api.setLocalTime(id, time: Date(), zone: TimeZone.current)
            try await self.cekJam(id)
            self.kabari("Jam sensor udah disamain. Matiin terus nyalain lagi sensornya sekali biar jam barunya kepake di rekaman.")
        }
    }

    // MARK: - Rekaman

    func mulaiRekam() {
        guard let id = idAktif else { return }
        antre("Mulai rekam") {
            try await self.api.startOfflineRecording(id, feature: .ppi, settings: nil, secret: nil)
            try await self.segarkanInti(id)
            self.kabari("Rekaman PPI jalan. Sensor bakal terus ngerekam walaupun jauh dari HP.")
        }
    }

    func stopRekam() {
        guard let id = idAktif else { return }
        antre("Stop rekam") {
            try await self.api.stopOfflineRecording(id, feature: .ppi)
            try await self.segarkanInti(id)
            self.kabari("Rekaman distop. Datanya masih di sensor sampai lu tarik.")
        }
    }

    func aturTrigger(_ nyala: Bool) {
        guard let id = idAktif else { return }
        antre(nyala ? "Nyalain rekam otomatis" : "Matiin rekam otomatis") {
            let fitur: [PolarDeviceDataType: PolarSensorSetting?] = nyala ? [.ppi: nil] : [:]
            let trigger = PolarOfflineRecordingTrigger(
                triggerMode: nyala ? .triggerSystemStart : .triggerDisabled,
                triggerFeatures: fitur
            )
            try await self.api.setOfflineRecordingTrigger(id, trigger: trigger, secret: nil)
            try await self.segarkanInti(id)
            self.kabari(nyala
                ? "Rekam otomatis nyala: tiap sensor dinyalain, PPI langsung kerekam. Mulai berlaku pas sensor dinyalain berikutnya."
                : "Rekam otomatis dimatiin. Rekaman yang lagi jalan gak ikut berhenti.")
        }
    }

    /// Tarik semua rekaman PPI dari sensor, olah jadi HRV, simpan, terus (opsional) hapus dari sensor.
    func tarikData(ke penyimpan: PenyimpanHRV, hapusSetelah: Bool) {
        guard let id = idAktif else { return }
        antre("Narik data") {
            UIApplication.shared.isIdleTimerDisabled = true
            defer { UIApplication.shared.isIdleTimerDisabled = false }

            let status = try await self.api.getOfflineRecordingStatus(id)
            let tadinyaRekam = status[.ppi] ?? false
            if tadinyaRekam {
                self.sibuk = "Nge-stop rekaman bentar..."
                try await self.api.stopOfflineRecording(id, feature: .ppi)
            }

            var daftar: [PolarOfflineRecordingEntry] = []
            do {
                for try await e in self.api.listOfflineRecordings(id) where e.type == .ppi {
                    daftar.append(e)
                }
            } catch {
                if tadinyaRekam {
                    try? await self.api.startOfflineRecording(id, feature: .ppi, settings: nil, secret: nil)
                }
                throw error
            }

            // Langsung nyalain lagi biar celah rekamannya sependek mungkin.
            // Rekaman baru ini gak ada di `daftar`, jadi gak ikut ketarik/kehapus.
            if tadinyaRekam {
                self.sibuk = "Nyalain rekaman lagi..."
                do {
                    try await self.api.startOfflineRecording(id, feature: .ppi, settings: nil, secret: nil)
                } catch {
                    self.lapor(error, konteks: "Nyalain ulang rekaman")
                }
            }

            daftar.sort { $0.date < $1.date }
            var berhasil = 0
            var totalDetak = 0
            var totalLayak = 0
            var gagal = 0
            for (i, entri) in daftar.enumerated() {
                self.sibuk = "Narik rekaman \(i + 1) dari \(daftar.count)"
                self.progres = 0
                do {
                    var hasil: PolarOfflineRecordingData?
                    for try await r in self.api.getOfflineRecordWithProgress(id, entry: entri, secret: nil) {
                        switch r {
                        case .progress(let p):
                            self.progres = Double(p.progressPercent) / 100
                        case .complete(let d):
                            hasil = d
                        }
                    }
                    var bolehHapus = false
                    switch hasil {
                    case .ppiOfflineRecordingData(let ppi, let mulaiHeader)?:
                        let sampel = ppi.samples.map { s in
                            SampelPPI(timeStampNs: s.timeStamp, hr: s.hr, ppiMs: Int(s.ppInMs),
                                      errorMs: Int(s.ppErrorEstimate), blocker: s.blockerBit != 0,
                                      kontakKulit: s.skinContactStatus != 0, kontakDidukung: s.skinContactSupported != 0)
                        }
                        let r = try penyimpan.simpanRekaman(sampel: sampel, mulaiRekaman: entri.date, mulaiHeader: mulaiHeader)
                        totalDetak += r.detak
                        totalLayak += r.layak
                        bolehHapus = true
                        CatatanLog.shared.tambah("APP rekaman \(entri.path): \(r.detak) detak, \(r.jendela) jendela, timestamp sensor: \(r.pakaiTimestamp)")
                    case .emptyData?:
                        bolehHapus = true
                    default:
                        gagal += 1
                        CatatanLog.shared.tambah("APP rekaman \(entri.path) isinya bukan PPI, dilewatin")
                    }
                    if bolehHapus {
                        berhasil += 1
                        if hapusSetelah {
                            try await self.api.removeOfflineRecord(id, entry: entri)
                        }
                    }
                } catch {
                    gagal += 1
                    self.lapor(error, konteks: "Rekaman \(i + 1)")
                }
            }

            try? await self.segarkanInti(id)
            if daftar.isEmpty {
                self.kabari("Belum ada rekaman PPI di sensor.")
            } else {
                let teksGagal = gagal > 0 ? " \(gagal) gagal, coba tarik lagi." : ""
                self.kabari("Beres: \(berhasil) rekaman, \(totalDetak) detak, \(totalLayak) jendela 5 menit yang bersih.\(teksGagal)", error: gagal > 0)
            }
        }
    }

    // MARK: - Pesan

    func kabari(_ teks: String, error: Bool = false) {
        pesan = Pesan(teks: teks, error: error)
        CatatanLog.shared.tambah("APP \(error ? "ERROR " : "")\(teks)")
    }

    private func lapor(_ error: Error, konteks: String) {
        CatatanLog.shared.tambah("APP ERROR \(konteks): \(error)")
        kabari("\(konteks): \(Self.jelaskan(error))", error: true)
    }

    static func jelaskan(_ error: Error) -> String {
        if let e = error as? PolarErrors {
            switch e {
            case .deviceNotConnected:
                return "Sensor gak nyambung. Deketin sensornya terus sambungin lagi."
            case .serviceNotFound:
                return "Fitur sensor belum siap. Tunggu beberapa detik terus coba lagi."
            case .operationNotSupported:
                return "Sensor ini gak dukung perintah itu."
            case .timeout:
                return "Sensor gak jawab (timeout). Coba lagi."
            case .concurrentApiCall:
                return "Masih ada perintah lain yang jalan. Tunggu bentar."
            default:
                break
            }
        }
        let mentah = String(describing: error)
        let besar = mentah.uppercased()
        if besar.contains("BUSY") {
            return "Sensor lagi di mode rekam latihan atau renang. Pindahin ke mode sensor biasa (LED biru) dulu."
        }
        if besar.contains("DISK_FULL") || besar.contains("DISK FULL") {
            return "Memori sensor penuh. Tarik data (dengan hapus setelah ditarik) dulu."
        }
        if besar.contains("ALREADY_IN_STATE") || besar.contains("ALREADY IN STATE") {
            return "PPI-nya lagi dipakai (misalnya halaman web HRV lagi kebuka). Tutup dulu, terus coba lagi."
        }
        return mentah
    }
}

// MARK: - Callback dari SDK (datang di luar main actor, jadi dilempar balik ke main)

extension SensorManager: PolarBleApiObserver {
    nonisolated func deviceConnecting(_ identifier: PolarDeviceInfo) {
        let id = identifier.deviceId
        Task { @MainActor in self.koneksi = .nyambung(id) }
    }

    nonisolated func deviceConnected(_ identifier: PolarDeviceInfo) {
        let id = identifier.deviceId
        let nama = identifier.name
        Task { @MainActor in self.saatTerhubung(id: id, nama: nama) }
    }

    nonisolated func deviceDisconnected(_ identifier: PolarDeviceInfo, info: PolarBleDisconnectInfo) {
        let id = identifier.deviceId
        Task { @MainActor in self.saatPutus(id: id, info: info) }
    }
}

extension SensorManager: PolarBleApiPowerStateObserver {
    nonisolated func blePowerOn() {
        Task { @MainActor in
            self.bluetoothNyala = true
            self.sambungOtomatis()
        }
    }

    nonisolated func blePowerOff() {
        Task { @MainActor in self.bluetoothNyala = false }
    }
}

extension SensorManager: PolarBleApiDeviceInfoObserver {
    nonisolated func batteryLevelReceived(_ identifier: String, batteryLevel: UInt) {
        Task { @MainActor in self.baterai = batteryLevel }
    }

    nonisolated func batteryChargingStatusReceived(_ identifier: String, chargingStatus: BleBasClient.ChargeState) {}

    nonisolated func disInformationReceived(_ identifier: String, uuid: CBUUID, value: String) {
        // 2A26 = Firmware Revision String
        guard uuid.uuidString.uppercased() == "2A26" else { return }
        Task { @MainActor in self.firmware = value }
    }

    nonisolated func disInformationReceivedWithKeysAsStrings(_ identifier: String, key: String, value: String) {}
}

extension SensorManager: PolarBleApiDeviceFeaturesObserver {
    nonisolated func bleSdkFeatureReady(_ identifier: String, feature: PolarBleSdkFeature) {
        Task { @MainActor in self.fiturSiap(identifier, feature) }
    }
}

extension SensorManager: PolarBleApiLogger {
    nonisolated func message(_ str: String) {
        CatatanLog.shared.tambah(str)
    }
}
