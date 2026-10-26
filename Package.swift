// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MacUtils",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "MacUtils",
            path: "Sources/MacUtils",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
    ]
)
