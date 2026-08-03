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
        // focus/activate, wheel to scroll) and `.onClick` for clickable-but-not-
        // focusable views. Pinned to an exact commit so it cannot shift underfoot.
        .package(
            url: "https://github.com/vdsingh/SwiftTUI.git",
            revision: "12479f67bd42e812308cdf458a46bd77bce3a4f6"
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
