// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "BookLens",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "BookLens", targets: ["BookLens"]),
        .executable(name: "BookLensSpike", targets: ["BookLensSpike"]),
        .library(name: "BookLensDomain", targets: ["BookLensDomain"]),
        .library(name: "BookLensData", targets: ["BookLensData"]),
        .library(name: "BookLensCodex", targets: ["BookLensCodex"]),
        .library(name: "BookLensSupport", targets: ["BookLensSupport"]),
    ],
    targets: [
        .target(
            name: "BookLensDomain",
            path: "Packages/BookLensDomain/Sources"
        ),
        .target(
            name: "BookLensSupport",
            path: "Packages/BookLensSupport/Sources",
            linkerSettings: [
                .linkedFramework("ImageIO")
            ]
        ),
        .target(
            name: "BookLensCodex",
            dependencies: ["BookLensDomain", "BookLensSupport"],
            path: "Packages/BookLensCodex/Sources"
        ),
        .target(
            name: "BookLensData",
            dependencies: ["BookLensDomain", "BookLensSupport"],
            path: "Packages/BookLensData/Sources",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ImageIO"),
                .linkedFramework("PDFKit"),
                .linkedFramework("NaturalLanguage"),
            ]
        ),
        .executableTarget(
            name: "BookLens",
            dependencies: [
                "BookLensDomain",
                "BookLensData",
                "BookLensCodex",
                "BookLensSupport",
            ],
            path: "BookLensApp",
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "BookLensSpike",
            dependencies: ["BookLensDomain", "BookLensData", "BookLensCodex", "BookLensSupport"],
            path: "Feasibility/BookLensSpike"
        ),
        .testTarget(
            name: "BookLensDomainTests",
            dependencies: ["BookLensDomain"],
            path: "BookLensTests/Domain"
        ),
        .testTarget(
            name: "BookLensSupportTests",
            dependencies: ["BookLensSupport"],
            path: "BookLensTests/Support"
        ),
        .testTarget(
            name: "BookLensCodexTests",
            dependencies: ["BookLensCodex"],
            path: "BookLensTests/Codex"
        ),
        .testTarget(
            name: "BookLensDataTests",
            dependencies: ["BookLensData", "BookLensDomain"],
            path: "BookLensTests/Data"
        ),
        .testTarget(
            name: "BookLensAppTests",
            dependencies: ["BookLens"],
            path: "BookLensTests/App"
        ),
    ],
    swiftLanguageModes: [.v6]
)
