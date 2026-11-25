import SwiftUI
import UIKit
import Charts
import HRVCore

struct FileBagikan: Identifiable {
    let id = UUID()
    let url: URL
}

struct ContentView: View {
    @EnvironmentObject private var sensor: SensorManager
    @EnvironmentObject private var health: PenulisHealth
    @State private var bagikan: FileBagikan?

    var body: some View {
        NavigationStack {
            List {
                KartuStatus()
                BagianSensor()
                if sensor.siapRekam {
                    BagianRekaman()
                }
                BagianHasil()
                BagianHealth()
                BagianLainnya(bagikan: $bagikan)
            }
            .navigationTitle("HRV Seharian")
        }
        .sheet(item: $bagikan) { f in
            LembarBagikan(item: f.url)
        }
        .onAppear { health.cek() }
    }
}

// MARK: - Status di paling atas

struct KartuStatus: View {
    @EnvironmentObject private var sensor: SensorManager

    var body: some View {
        if sensor.sibuk != nil || sensor.pesan != nil {
            Section {
                if let s = sensor.sibuk {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text(s)
                        }
                        if let p = sensor.progres {
                            ProgressView(value: p)
                        }
                    }
                }
                if let p = sensor.pesan {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: p.error ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .foregroundStyle(p.error ? Color.orange : Color.green)
                        Text(p.teks)
                            .font(.subheadline)
                        Spacer(minLength: 0)
                        Button {
                            sensor.pesan = nil
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
    }
}

// MARK: - Sensor

struct BagianSensor: View {
    @EnvironmentObject private var sensor: SensorManager

    var body: some View {
        Section("Sensor") {
            if !sensor.bluetoothNyala {
                Label("Bluetooth iPhone mati. Nyalain dulu.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
            switch sensor.koneksi {
            case .putus:
                if let id = sensor.idTersimpan {
                    Button {
                        sensor.sambungkan(id)
                    } label: {
                        Label("Sambungin ke Polar Sense \(id)", systemImage: "dot.radiowaves.left.and.right")
                    }
                }
                Button {
                    sensor.cariSensor()
                } label: {
                    Label(sensor.idTersimpan == nil ? "Cari sensor" : "Cari sensor lain", systemImage: "magnifyingglass")
                }
            case .nyari:
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Nyari sensor... pastiin Verity Sense nyala")
                }
                ForEach(sensor.ditemukan) { s in
                    Button {
                        sensor.sambungkan(s.id)
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(s.nama)
                                Text("ID \(s.id)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(s.rssi) dBm")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Button("Berhenti nyari", role: .cancel) {
                    sensor.berhentiCari()
                }
            case .nyambung(let id):
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Nyambung ke Polar Sense \(id)...")
                }
                Text("Kalau lama, pastiin sensornya nyala dan deket HP.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Batal", role: .cancel) {
                    sensor.putuskan()
                }
            case .terhubung(let id):
                LabeledContent("Tersambung", value: sensor.namaSensor ?? "Polar Sense \(id)")
                if let b = sensor.baterai {
                    LabeledContent("Baterai", value: "\(b)%")
                }
                if let fw = sensor.firmware {
                    LabeledContent("Firmware", value: fw)
                }
                if !sensor.siapRekam {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Nyiapin fitur rekaman...")
                    }
                }
                Button("Putusin", role: .destructive) {
                    sensor.putuskan()
                }
            }
        }
    }
}

// MARK: - Rekaman offline

struct BagianRekaman: View {
    @EnvironmentObject private var sensor: SensorManager
    @EnvironmentObject private var data: PenyimpanHRV
    @AppStorage("hapusSetelahTarik") private var hapusSetelahTarik = true

    private var lagiRekam: Bool { sensor.lagiRekam == true }

    private var teksStatus: String {
        switch sensor.lagiRekam {
        case .some(true): return "Lagi ngerekam PPI"
        case .some(false): return "Gak lagi ngerekam"
        case .none: return "Status belum kebaca"
        }
    }

    private var ringkasRekaman: String {
        let r = sensor.rekamanPPI
        if r.isEmpty { return "kosong" }
        let total = r.reduce(UInt64(0)) { $0 + UInt64($1.size) }
        return "\(r.count) file, \(Format.byte(total))"
    }

    private var triggerBinding: Binding<Bool> {
        Binding(
            get: { sensor.triggerNyala ?? false },
            set: { sensor.aturTrigger($0) }
        )
    }

    var body: some View {
        Section {
            HStack(spacing: 10) {
                Image(systemName: lagiRekam ? "record.circle.fill" : "pause.circle")
                    .foregroundStyle(lagiRekam ? Color.red : Color.secondary)
                Text(teksStatus)
            }
            if lagiRekam {
                Button("Stop rekam") { sensor.stopRekam() }
                    .disabled(sensor.sibuk != nil)
            } else {
                Button("Mulai rekam sekarang") { sensor.mulaiRekam() }
                    .disabled(sensor.sibuk != nil)
            }
            Toggle("Rekam otomatis tiap sensor dinyalain", isOn: triggerBinding)
                .disabled(sensor.triggerNyala == nil || sensor.sibuk != nil)
            LabeledContent("Rekaman di sensor", value: ringkasRekaman)
            if let kosong = sensor.ruangKosong, let total = sensor.ruangTotal, total > 0 {
                LabeledContent("Memori kosong", value: "\(Format.byte(kosong)) dari \(Format.byte(total))")
            }
            Toggle("Hapus dari sensor setelah ditarik", isOn: $hapusSetelahTarik)
            Button {
                sensor.tarikData(ke: data, hapusSetelah: hapusSetelahTarik)
            } label: {
                Label("Tarik data dari sensor", systemImage: "arrow.down.circle.fill")
            }
            .disabled(sensor.sibuk != nil)
            if let selisih = sensor.selisihJamDetik, abs(selisih) > 300 {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Jam sensor beda \(Int((abs(selisih) / 60).rounded())) menit dari iPhone, jadi jam rekamannya bisa geser.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                    Button("Samain jam sensor") { sensor.samakanJam() }
                        .disabled(sensor.sibuk != nil)
                }
            }
            Button("Cek ulang status") { sensor.segarkan() }
                .disabled(sensor.sibuk != nil)
        } header: {
            Text("Rekaman offline")
        } footer: {
            Text("Sensor nyimpen detak ke memorinya sendiri, jadi HP gak perlu deket. Tarik datanya minimal sehari sekali, dan jangan tutup app selama narik. Selama rekaman PPI jalan, halaman web HRV gak bisa dipakai.")
        }
    }
}

// MARK: - Hasil

struct BagianHasil: View {
    @EnvironmentObject private var data: PenyimpanHRV
    @State private var hariTerpilih: Date?

    var body: some View {
        Section("Hasil HRV") {
            if data.jendela.isEmpty {
                Text("Belum ada data. Nyalain rekaman, pakai sensornya kayak biasa, terus tarik datanya ke sini.")
                    .foregroundStyle(.secondary)
            } else {
                IsiHasil(daftarHari: data.hari, hariTerpilih: $hariTerpilih)
            }
        }
    }
}

struct IsiHasil: View {
    @EnvironmentObject private var data: PenyimpanHRV
    let daftarHari: [Date]
    @Binding var hariTerpilih: Date?

    private var hari: Date {
        if let h = hariTerpilih, daftarHari.contains(h) { return h }
        return daftarHari.first ?? Calendar.current.startOfDay(for: Date())
    }

    private var pilihanHari: Binding<Date> {
        Binding(get: { hari }, set: { hariTerpilih = $0 })
    }

    var body: some View {
        let isi = data.jendelaPada(hari: hari)
        let r = ProsesHRV.ringkas(isi)
        Picker("Hari", selection: pilihanHari) {
            ForEach(daftarHari, id: \.self) { h in
                Text(Format.hari(h)).tag(h)
            }
        }
        GrafikHari(jendela: isi)
        LabeledContent("RMSSD (median)", value: Format.ms(r.rmssdMedian))
        LabeledContent("SDNN (median)", value: Format.ms(r.sdnnMedian))
        LabeledContent("HR rata-rata", value: r.hrRata.map { "\(Int($0.rounded())) bpm" } ?? "–")
        LabeledContent("Jendela 5 menit bersih", value: "\(r.jumlahLayak) dari \(r.jumlahJendela)")
        LabeledContent("Data terekam", value: Format.durasi(jam: r.jamData))
        NavigationLink("Lihat semua jendela 5 menit") {
            DaftarJendelaView(jendela: isi, judul: Format.hari(hari))
        }
    }
}

struct GrafikHari: View {
    let jendela: [JendelaHRV]

    var body: some View {
        let layak = jendela.filter(\.layak)
        if layak.isEmpty {
            Text("Belum ada jendela 5 menit yang cukup bersih di hari ini. HRV cuma kebaca pas lu lagi diem (duduk tenang, rebahan, tidur).")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            Chart {
                ForEach(layak) { j in
                    PointMark(x: .value("Jam", j.mulai), y: .value("ms", j.rmssd ?? 0))
                        .foregroundStyle(by: .value("Metrik", "RMSSD"))
                        .symbolSize(24)
                    PointMark(x: .value("Jam", j.mulai), y: .value("ms", j.sdnn ?? 0))
                        .foregroundStyle(by: .value("Metrik", "SDNN"))
                        .symbolSize(24)
                }
            }
            .chartForegroundStyleScale(["RMSSD": Color.green, "SDNN": Color.blue])
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 3)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.hour())
                }
            }
            .chartYAxisLabel("ms")
            .frame(height: 220)
            .padding(.vertical, 4)
        }
    }
}

struct DaftarJendelaView: View {
    let jendela: [JendelaHRV]
    let judul: String

    var body: some View {
        List(Array(jendela.reversed())) { j in
            BarisJendela(j: j)
        }
        .navigationTitle(judul)
    }
}

struct BarisJendela: View {
    let j: JendelaHRV

    private var teksHr: String {
        j.hrRata.map { String(Int($0.rounded())) } ?? "–"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(Format.jam(j.mulai))–\(Format.jam(j.selesai))")
                    .font(.headline.monospacedDigit())
                Spacer()
                LencanaKualitas(k: j.kualitas)
                if j.keHealth {
                    Image(systemName: "heart.fill")
                        .font(.caption)
                        .foregroundStyle(.pink)
                }
            }
            Text("RMSSD \(Format.ms(j.rmssd)) · SDNN \(Format.ms(j.sdnn)) · HR \(teksHr)")
                .font(.subheadline)
            Text("\(j.dipakai)/\(j.total) detak dipakai (\(Int(j.persenDibuang.rounded()))% dibuang)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct LencanaKualitas: View {
    let k: KualitasJendela

    private var warna: Color {
        switch k {
        case .bagus: return .green
        case .lumayan: return .yellow
        case .jelek: return .red
        case .kurangData: return .gray
        }
    }

    var body: some View {
        Text(Format.kualitas(k))
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(warna.opacity(0.2), in: Capsule())
            .foregroundStyle(warna)
    }
}

// MARK: - Apple Health

struct BagianHealth: View {
    @EnvironmentObject private var sensor: SensorManager
    @EnvironmentObject private var data: PenyimpanHRV
    @EnvironmentObject private var health: PenulisHealth
    @State private var lagiKirim = false

    private var teksStatus: String {
        switch health.status {
        case .belumDicek: return "belum dicek"
        case .tidakTersedia: return "gak tersedia di HP ini"
        case .belumIzin: return "belum dikasih izin"
        case .siap: return "siap"
        case .ditolak: return "izin ditolak"
        case .gagal: return "gak bisa dipakai"
        }
    }

    var body: some View {
        let belum = data.belumKeHealth
        Section {
            LabeledContent("Status", value: teksStatus)
            LabeledContent("Belum terkirim", value: "\(belum.count) jendela")
            Button {
                Task { await kirim(belum) }
            } label: {
                Label("Kirim ke Apple Health", systemImage: "heart.fill")
            }
            .disabled(belum.isEmpty || lagiKirim)
            if case .ditolak = health.status {
                Text("Buka app Kesehatan > profil > Aplikasi > HRV Seharian, terus nyalain Variabilitas Detak Jantung.")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            if case .gagal(let alasan) = health.status {
                Text("HealthKit gak bisa dipakai: \(alasan)")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            if health.butuhCadangan {
                Button {
                    kirimCadangan(belum)
                } label: {
                    Label("Kirim lewat Shortcuts (cadangan)", systemImage: "square.2.layers.3d")
                }
                .disabled(belum.isEmpty)
            }
        } header: {
            Text("Apple Health")
        } footer: {
            Text("Yang dikirim: HRV (SDNN) tiap 5 menit, cuma dari jendela yang bersih. Jenisnya sama kayak HRV dari Apple Watch. RMSSD ikut disimpen di metadata.")
        }
    }

    @MainActor
    private func kirim(_ belum: [JendelaHRV]) async {
        lagiKirim = true
        defer { lagiKirim = false }
        if health.status != .siap {
            await health.mintaIzin()
        }
        switch health.status {
        case .siap:
            break
        case .ditolak:
            sensor.kabari("Izin Apple Health ditolak. Nyalain dulu di app Kesehatan.", error: true)
            return
        case .gagal(let alasan):
            sensor.kabari("Apple Health gak bisa dipakai di versi app ini (\(alasan)). Pakai tombol Shortcuts.", error: true)
            return
        default:
            sensor.kabari("Izin Apple Health belum dikasih.", error: true)
            return
        }
        do {
            let masuk = try await health.kirim(belum, namaSensor: sensor.namaSensor, firmware: sensor.firmware)
            data.tandaiKeHealth(masuk)
            sensor.kabari("\(masuk.count) jendela HRV masuk ke Apple Health.")
        } catch {
            sensor.kabari("Gagal nulis ke Apple Health: \(error.localizedDescription)", error: true)
        }
    }

    @MainActor
    private func kirimCadangan(_ belum: [JendelaHRV]) {
        let n = health.kirimLewatShortcuts(belum)
        if n > 0 {
            data.tandaiKeHealth(Set(belum.filter(\.layak).map(\.mulai)))
            sensor.kabari("\(n) jendela disalin. Shortcut \"\(PenulisHealth.namaShortcut)\" lagi dibuka.")
        } else {
            sensor.kabari("Belum ada jendela yang bersih buat dikirim.")
        }
    }
}

// MARK: - Lainnya

struct BagianLainnya: View {
    @EnvironmentObject private var sensor: SensorManager
    @EnvironmentObject private var data: PenyimpanHRV
    @Binding var bagikan: FileBagikan?
    @State private var tanyaHapus = false

    var body: some View {
        Section {
            Button {
                do {
                    let url = try data.fileCsvJendela()
                    bagikan = FileBagikan(url: url)
                } catch {
                    sensor.kabari("Gagal bikin CSV: \(error.localizedDescription)", error: true)
                }
            } label: {
                Label("Bagikan CSV hasil (semua hari)", systemImage: "square.and.arrow.up")
            }
            .disabled(data.jendela.isEmpty)
            NavigationLink {
                PanduanView()
            } label: {
                Label("Cara pakai & tips", systemImage: "questionmark.circle")
            }
            NavigationLink {
                LogView()
            } label: {
                Label("Log teknis", systemImage: "doc.text.magnifyingglass")
            }
            if sensor.idTersimpan != nil {
                Button("Lupain sensor ini", role: .destructive) {
                    sensor.lupakanSensor()
                }
            }
            Button("Hapus semua data di app", role: .destructive) {
                tanyaHapus = true
            }
            .disabled(data.jendela.isEmpty)
            .confirmationDialog("Hapus semua data HRV di app ini?", isPresented: $tanyaHapus, titleVisibility: .visible) {
                Button("Hapus", role: .destructive) { data.hapusSemua() }
            } message: {
                Text("Data yang udah masuk Apple Health gak ikut kehapus.")
            }
        } header: {
            Text("Lainnya")
        } footer: {
            Text("Detak mentah tiap rekaman juga disimpen di app Files > Di iPhone Saya > HRV Seharian > detak_mentah.")
        }
    }
}

struct LembarBagikan: UIViewControllerRepresentable {
    let item: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [item], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct LogView: View {
    @State private var baris: [String] = []

    var body: some View {
        List {
            Section {
                Button {
                    UIPasteboard.general.string = baris.joined(separator: "\n")
                } label: {
                    Label("Salin semua log", systemImage: "doc.on.doc")
                }
                Button("Muat ulang") {
                    baris = CatatanLog.shared.semua()
                }
            } footer: {
                Text("Kalau ada error, salin log ini terus kirim ke Claude.")
            }
            Section("\(baris.count) baris terakhir") {
                ForEach(Array(baris.reversed().enumerated()), id: \.offset) { _, b in
                    Text(b)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
            }
        }
        .navigationTitle("Log teknis")
        .onAppear { baris = CatatanLog.shared.semua() }
    }
}

struct PanduanView: View {
    var body: some View {
        List {
            Section("Alur harian") {
                Text("1. Sekali aja: sambungin sensor, nyalain \"Rekam otomatis tiap sensor dinyalain\", terus pencet \"Mulai rekam sekarang\".")
                Text("2. Pakai Verity Sense kayak biasa seharian. Sensor ngerekam sendiri ke memorinya, HP boleh jauh.")
                Text("3. Malem atau pagi: buka app ini, tunggu nyambung, pencet \"Tarik data dari sensor\".")
                Text("4. Pencet \"Kirim ke Apple Health\".")
            }
            Section("Biar datanya bagus") {
                Text("HRV dari sensor optik cuma akurat pas diem. Waktu lu gerak, detaknya otomatis dibuang, jadi grafik cuma keisi pas duduk tenang, rebahan, atau tidur.")
                Text("Pasang sensor agak kenceng biar gak ada cahaya masuk. Lengan atas atau pelipis (pakai klip kacamata renang) biasanya paling stabil.")
                Text("Satu jendela 5 menit dihitung kalau minimal 60 pasang detak berurutan bersih dan yang dibuang gak lebih dari 20%.")
            }
            Section("Penting") {
                Text("Jangan pakai mode rekam latihan atau mode renang di sensor pas mau narik data. Di mode itu sensor nolak transfer file. Nyalain rekaman PPI juga bakal ngehentiin latihan internal yang lagi jalan.")
                Text("Selama rekaman PPI jalan, halaman web HRV (Bluefy) gak bisa ngukur, karena PPI-nya lagi dipakai rekaman. Stop rekam dulu kalau mau pakai halaman web.")
                Text("Memori sensor gak kehapus sendiri. Biarin \"Hapus dari sensor setelah ditarik\" nyala, dan tarik data tiap hari.")
                Text("Pantau baterai sensor. Rekaman PPI seharian bikin baterai lebih cepet abis.")
            }
            Section("App sideload") {
                Text("App yang dipasang pakai Apple ID gratis berhenti bisa dibuka setelah 7 hari. Pasang ulang file .ipa yang sama lewat Impactor. Data di app tetep aman selama app-nya gak dihapus.")
                Text("Kalau sensor gak mau nyambung: buka Pengaturan > Bluetooth > Polar Sense > Lupakan Perangkat Ini, terus sambungin lagi dari app ini.")
            }
        }
        .navigationTitle("Cara pakai")
    }
}
