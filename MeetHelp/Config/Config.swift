import Foundation
import AppKit

enum Config {
    // MARK: - API Keys (stored from Settings)
    static var deepgramAPIKey: String {
        apiKey(for: "deepgramAPIKey")
    }

    static var openRouterAPIKey: String {
        apiKey(for: "openRouterAPIKey")
    }

    static var geminiAPIKey: String {
        apiKey(for: "geminiAPIKey")
    }

    static func hasStoredAPIKey(_ key: String) -> Bool {
        !apiKey(for: key).isEmpty
    }

    private static func apiKey(for key: String) -> String {
        UserDefaults.standard.string(forKey: key)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    // MARK: - Deepgram Configuration
    static let deepgramWebSocketURL = "wss://api.deepgram.com/v1/listen"
    static let deepgramModel = "nova-3"
    static let utteranceEndMs = 1500

    // MARK: - LLM Configuration
    static let openRouterAPIURL = "https://openrouter.ai/api/v1/chat/completions"
    static let openRouterModelsURL = "https://openrouter.ai/api/v1/models"
    static let openRouterFreeModel = "openai/gpt-oss-120b:free"
    static let defaultGeminiModel = "gemini-3.1-flash-lite-preview"
    static let defaultOpenRouterImageModel = "nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free"
    static let defaultGeminiImageModel = "gemma-4-31b-it"

    static var geminiModel: String {
        let saved = UserDefaults.standard.string(forKey: "geminiModel")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return saved.isEmpty ? defaultGeminiModel : saved
    }

    static var geminiImageModel: String {
        let saved = UserDefaults.standard.string(forKey: "geminiImageModel")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return saved.isEmpty ? defaultGeminiImageModel : saved
    }

    static var geminiStreamURL: String {
        "https://generativelanguage.googleapis.com/v1beta/models/\(geminiModel):streamGenerateContent"
    }

    static var geminiImageURL: String {
        "https://generativelanguage.googleapis.com/v1beta/models/\(geminiImageModel):generateContent"
    }

    static var selectedLLMProvider: LLMProvider {
        let rawValue = UserDefaults.standard.string(forKey: "llmProvider") ?? LLMProvider.openRouter.rawValue
        return LLMProvider(rawValue: rawValue) ?? .openRouter
    }

    static var selectedOpenRouterModel: String {
        let selectedIndex = UserDefaults.standard.integer(forKey: "selectedOpenRouterModelIndex")
        let index = selectedIndex == 0 ? 1 : selectedIndex
        let key = "openRouterModel\(min(max(index, 1), 3))"
        let saved = UserDefaults.standard.string(forKey: key)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !saved.isEmpty else { return openRouterFreeModel }
        return saved.hasSuffix(":free") ? saved : openRouterFreeModel
    }

    static var openRouterImageModel: String {
        let saved = UserDefaults.standard.string(forKey: "openRouterImageModel")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !saved.isEmpty else { return defaultOpenRouterImageModel }
        return saved.hasSuffix(":free") ? saved : defaultOpenRouterImageModel
    }

    // MARK: - Audio Configuration
    static let audioSampleRate: Double = 16000
    static let audioChannels: Int = 1

    // MARK: - UI Configuration
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
}

enum LLMProvider: String, CaseIterable, Identifiable {
    case openRouter
    case google

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openRouter:
            return "OpenRouter"
        case .google:
            return "Google"
        }
    }
}
