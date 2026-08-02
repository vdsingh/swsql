// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "swsql",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "swsql", targets: ["swsql"])
    ],
    dependencies: [
        // A fork of rensbreur/SwiftTUI that adds terminal mouse support (click to
        // focus/activate, wheel to scroll). Pinned to an exact commit rather than
        // a branch so the dependency cannot shift underfoot.
        .package(
            url: "https://github.com/vdsingh/SwiftTUI.git",
            revision: "7a9ca3fbd8931e38c658fdc23c2918842848a0a5"
        )
    ],
    targets: [
        .systemLibrary(
            name: "CLibPQ",
            pkgConfig: "libpq",
            providers: [
                .brew(["libpq"]),
                .apt(["libpq-dev"])
            ]
        ),
        .target(
            name: "SWSQLCore",
            dependencies: ["CLibPQ"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "swsql",
            dependencies: ["SWSQLCore", "SwiftTUI"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "SWSQLCoreTests",
            dependencies: ["SWSQLCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
