// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AppCommerce",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CommerceCore", targets: ["CommerceCore"]),
        .library(name: "CommerceStoreKit", targets: ["CommerceStoreKit"]),
        .library(name: "CommerceUI", targets: ["CommerceUI"])
    ],
    targets: [
        .target(name: "CommerceCore"),
        .target(name: "CommerceStoreKit", dependencies: ["CommerceCore"]),
        .target(name: "CommerceUI", dependencies: ["CommerceCore"], resources: [.process("Resources")]),
        .testTarget(name: "CommerceCoreTests", dependencies: ["CommerceCore"]),
        .testTarget(name: "CommerceStoreKitTests", dependencies: ["CommerceStoreKit"]),
        .testTarget(name: "CommerceUITests", dependencies: ["CommerceUI"]),
        .testTarget(name: "CommerceIntegrationTests", dependencies: ["CommerceCore", "CommerceStoreKit", "CommerceUI"])
    ],
    swiftLanguageModes: [.v6]
)