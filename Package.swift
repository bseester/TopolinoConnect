// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TopolinoConnect",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "TopolinoConnect", targets: ["TopolinoConnect"])],
    targets: [
        .target(name: "TopolinoConnect", path: "Sources"),
        .testTarget(name: "TopolinoConnectTests", dependencies: ["TopolinoConnect"], path: "Tests")
    ]
)
