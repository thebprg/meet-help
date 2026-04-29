// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MeetHelp",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "MeetHelp", targets: ["MeetHelp"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "MeetHelp",
            dependencies: [],
            path: "MeetHelp",
            exclude: ["Resources"]
        )
    ]
)
