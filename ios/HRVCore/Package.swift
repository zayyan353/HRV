// swift-tools-version:5.7
// Logika HRV murni (tanpa Bluetooth/UI) biar bisa dites pakai `swift test`.
import PackageDescription

let package = Package(
    name: "HRVCore",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "HRVCore", targets: ["HRVCore"]),
    ],
    targets: [
        .target(name: "HRVCore"),
        .testTarget(name: "HRVCoreTests", dependencies: ["HRVCore"]),
    ]
)
