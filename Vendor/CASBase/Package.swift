// swift-tools-version: 5.9
import PackageDescription

// Thin local package: CleverAdsSolutions base binary only (no mediation adapters).
// Enough for Test Ads. Avoids SPM graph conflicts in the full CAS-iOS Package.swift.
//
// Uses a *local* xcframework path — the upstream release zip also contains LICENSE.md
// and CASBaseResources.bundle, which makes Xcode fail with:
//   binary target 'CleverAdsSolutions' could not be mapped to an artifact...
// If CleverAdsSolutions.xcframework is missing, run: Scripts/fetch-cas-binary.sh
let package = Package(
    name: "CASBase",
    platforms: [.iOS(.v13)],
    products: [
        .library(name: "CleverAdsSolutionsSPM", targets: ["CASBase"])
    ],
    targets: [
        .target(
            name: "CASBase",
            dependencies: ["CleverAdsSolutions"],
            path: "Sources/CASBase",
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreLocation"),
                .linkedFramework("Network"),
                .linkedFramework("StoreKit"),
                .linkedFramework("WebKit"),
            ]
        ),
        .binaryTarget(
            name: "CleverAdsSolutions",
            path: "CleverAdsSolutions.xcframework"
        ),
    ]
)
