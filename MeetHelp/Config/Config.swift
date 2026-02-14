import Foundation
import AppKit

enum Config {
    // MARK: - API Keys (loaded from .env file)
    static let deepgramAPIKey: String = {
        return loadEnvValue(key: "DEEPGRAM_API_KEY") ?? ""
    }()
    static let cerebrasAPIKey: String = {
        return loadEnvValue(key: "CEREBRAS_API_KEY") ?? ""
    }()
    
    // MARK: - Deepgram Configuration
    static let deepgramWebSocketURL = "wss://api.deepgram.com/v1/listen"
    static let deepgramModel = "nova-2"
    static let utteranceEndMs = 1500
    
    // MARK: - Cerebras Configuration
    static let cerebrasAPIURL = "https://api.cerebras.ai/v1/chat/completions"
    static let cerebrasModel = "qwen-3-32b"  // Using Qwen 3 32B model
    
    // MARK: - Audio Configuration
    static let audioSampleRate: Double = 16000
    static let audioChannels: Int = 1
    
    // MARK: - UI Configuration
    // Dynamic sizing based on screen (1/3 width, 2/3 height)
    static var defaultWindowWidth: CGFloat {
        guard let screen = NSScreen.main else { return 500 }
        return screen.frame.width / 3
    }
    static var defaultWindowHeight: CGFloat {
        guard let screen = NSScreen.main else { return 600 }
        return (screen.frame.height * 2) / 3
    }
    static let minWindowWidth: CGFloat = 300
    static let minWindowHeight: CGFloat = 400
    
    // Background styling
    static let overlayBackgroundColor: NSColor = NSColor(white: 0.2, alpha: 0.85)
    static let headerBackgroundColor: NSColor = NSColor(white: 0.15, alpha: 0.9)
    static let bubbleOpacity: Double = 0.5
    
    // MARK: - .env File Loader
    
    /// Load a value from the .env file in the project root
    private static func loadEnvValue(key: String) -> String? {
        // First check process environment (e.g. set via Xcode scheme)
        if let value = ProcessInfo.processInfo.environment[key], !value.isEmpty {
            return value
        }
        
        // Try loading from .env file relative to executable
        let envPaths = [
            // When running from .build/debug/
            URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0])
                .deletingLastPathComponent()  // debug/
                .deletingLastPathComponent()  // .build/
                .deletingLastPathComponent()  // project root
                .appendingPathComponent(".env"),
            // Current working directory
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(".env"),
            // Bundle resource
            Bundle.main.bundleURL.appendingPathComponent(".env")
        ]
        
        for envPath in envPaths {
            if let contents = try? String(contentsOf: envPath, encoding: .utf8) {
                let lines = contents.components(separatedBy: .newlines)
                for line in lines {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
                    
                    let parts = trimmed.split(separator: "=", maxSplits: 1)
                    if parts.count == 2 {
                        let envKey = String(parts[0]).trimmingCharacters(in: .whitespaces)
                        let envValue = String(parts[1]).trimmingCharacters(in: .whitespaces)
                            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                        if envKey == key {
                            return envValue
                        }
                    }
                }
            }
        }
        
        print("[Config] WARNING: Could not find \(key) in .env file or environment. Check your .env file.")
        return nil
    }
}
