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
            sources: [
                "App/MeetHelpApp.swift",
                "App/AppDelegate.swift",
                "Config/Config.swift",
                "Windows/GhostWindow.swift",
                "Views/ChatOverlayView.swift",
                "Views/SettingsView.swift",
                "Views/Components/MessageBubble.swift",
                "Models/ChatMessage.swift",
                "Models/TranscriptState.swift",
                "Services/AudioCaptureManager.swift",
                "Services/DeepgramService.swift",
                "Services/CerebrasService.swift"
            ]
        )
    ]
)
