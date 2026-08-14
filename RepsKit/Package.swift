// swift-tools-version: 6.0
import PackageDescription

// Static so the widget extension pays no dyld cost for linking it.
//
// macOS and Linux are listed so `swift test` runs without a simulator — the whole point
// of putting the rep machines and the plan engine in here. Nothing in this package may
// import UIKit, SwiftUI, HealthKit, ARKit or WidgetKit; that all lives in the app target.
let package = Package(
    name: "RepsKit",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "RepsKit", type: .static, targets: ["RepsKit"])
    ],
    targets: [
        .target(name: "RepsKit"),
        .testTarget(name: "RepsKitTests", dependencies: ["RepsKit"])
    ]
)
