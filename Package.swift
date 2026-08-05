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
        // A fork of rensbreur/SwiftTUI adding terminal mouse support, `.onClick`,
        // `.onHorizontalScroll` and a multi-line `TextEditor`. Pinned to an
        // exact commit so it cannot shift underfoot.
        .package(
            url: "https://github.com/vdsingh/SwiftTUI.git",
            revision: "fd9f0c609e67dfba3a9b88f72886a0fc0441e5f5"
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
