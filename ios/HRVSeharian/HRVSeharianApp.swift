import SwiftUI

@main
struct HRVSeharianApp: App {
    @StateObject private var sensor = SensorManager()
    @StateObject private var data = PenyimpanHRV()
    @StateObject private var health = PenulisHealth()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(sensor)
                .environmentObject(data)
                .environmentObject(health)
                .tint(Color(red: 0.204, green: 0.827, blue: 0.600))
                .preferredColorScheme(.dark)
        }
    }
}
