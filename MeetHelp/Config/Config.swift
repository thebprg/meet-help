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

    static var youAPIKey: String {
        apiKey(for: "youAPIKey")
    }

    static var liveSearchEnabled: Bool {
        UserDefaults.standard.bool(forKey: "liveSearchEnabled")
    }

    static var openRouterFreeModeEnabled: Bool {
        UserDefaults.standard.object(forKey: "openRouterFreeModeEnabled") as? Bool ?? true
    }

    static var manualInterviewerSubmitEnabled: Bool {
        UserDefaults.standard.bool(forKey: "manualInterviewerSubmitEnabled")
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
    static let youSearchURL = "https://ydc-index.io/v1/search"
    static let openRouterFreeModel = "openai/gpt-oss-120b:free"
    static let defaultOpenRouterSearchModel = "openrouter/free"
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
        let index = selectedOpenRouterModelIndex
        let key = index == 0 ? "openRouterSearchModel" : "openRouterModel\(index)"
        let saved = UserDefaults.standard.string(forKey: key)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let fallback = index == 0 ? defaultOpenRouterSearchModel : openRouterFreeModel
        guard !saved.isEmpty else { return fallback }
        return openRouterFreeModeEnabled && !isFreeOpenRouterModel(saved) ? fallback : saved
    }

    static var selectedOpenRouterModelIndex: Int {
        let selectedIndex = UserDefaults.standard.object(forKey: "selectedOpenRouterModelIndex") as? Int ?? 1
        return min(max(selectedIndex, 0), 3)
    }

    static var openRouterSearchModel: String {
        let saved = UserDefaults.standard.string(forKey: "openRouterSearchModel")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !saved.isEmpty else { return defaultOpenRouterSearchModel }
        return openRouterFreeModeEnabled && !isFreeOpenRouterModel(saved) ? defaultOpenRouterSearchModel : saved
    }

    static var openRouterImageModel: String {
        let saved = UserDefaults.standard.string(forKey: "openRouterImageModel")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !saved.isEmpty else { return defaultOpenRouterImageModel }
        return openRouterFreeModeEnabled && !isFreeOpenRouterModel(saved) ? defaultOpenRouterImageModel : saved
    }

    static func isFreeOpenRouterModel(_ model: String) -> Bool {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasSuffix(":free") || trimmed == "openrouter/free"
    }

    static func openRouterOptions(for model: String) -> OpenRouterRequestOptions {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .default }

        let optionsByModel = openRouterOptionsByModel()
        return optionsByModel[trimmed] ?? .default
    }

    static var selectedOpenRouterOptions: OpenRouterRequestOptions {
        selectedOpenRouterModelIndex == 0
            ? openRouterOptions(forSlot: "search")
            : openRouterOptions(forSlot: "model\(selectedOpenRouterModelIndex)")
    }

    static var openRouterSearchOptions: OpenRouterRequestOptions {
        openRouterOptions(forSlot: "search")
    }

    static func openRouterOptions(forSlot slot: String) -> OpenRouterRequestOptions {
        let trimmed = slot.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .default }

        let optionsBySlot = openRouterOptionsBySlot()
        return optionsBySlot[trimmed] ?? .default
    }

    static func setOpenRouterOptions(_ options: OpenRouterRequestOptions, forSlot slot: String) {
        let trimmed = slot.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var optionsBySlot = openRouterOptionsBySlot()
        optionsBySlot[trimmed] = options.normalized

        do {
            let data = try JSONEncoder().encode(optionsBySlot)
            UserDefaults.standard.set(data, forKey: "openRouterOptionsBySlot")
        } catch {
            print("[Config] Failed to save OpenRouter slot options: \(error.localizedDescription)")
        }
    }

    static func openRouterProviderTag(forSlot slot: String) -> String {
        let trimmed = slot.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return openRouterProviderTagsBySlot()[trimmed] ?? ""
    }

    static func setOpenRouterProviderTag(_ providerTag: String, forSlot slot: String) {
        let trimmed = slot.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var tagsBySlot = openRouterProviderTagsBySlot()
        let tag = providerTag.trimmingCharacters(in: .whitespacesAndNewlines)
        if tag.isEmpty {
            tagsBySlot.removeValue(forKey: trimmed)
        } else {
            tagsBySlot[trimmed] = tag
        }

        do {
            let data = try JSONEncoder().encode(tagsBySlot)
            UserDefaults.standard.set(data, forKey: "openRouterProviderTagsBySlot")
        } catch {
            print("[Config] Failed to save OpenRouter provider selection: \(error.localizedDescription)")
        }
    }

    private static func openRouterProviderTagsBySlot() -> [String: String] {
        guard let data = UserDefaults.standard.data(forKey: "openRouterProviderTagsBySlot") else {
            return [:]
        }

        do {
            return try JSONDecoder().decode([String: String].self, from: data)
        } catch {
            print("[Config] Failed to decode OpenRouter provider selections: \(error.localizedDescription)")
            return [:]
        }
    }

    static func setOpenRouterOptions(_ options: OpenRouterRequestOptions, for model: String) {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var optionsByModel = openRouterOptionsByModel()
        optionsByModel[trimmed] = options.normalized

        do {
            let data = try JSONEncoder().encode(optionsByModel)
            UserDefaults.standard.set(data, forKey: "openRouterOptionsByModel")
        } catch {
            print("[Config] Failed to save OpenRouter options: \(error.localizedDescription)")
        }
    }

    private static func openRouterOptionsByModel() -> [String: OpenRouterRequestOptions] {
        guard let data = UserDefaults.standard.data(forKey: "openRouterOptionsByModel") else {
            return [:]
        }

        do {
            return try JSONDecoder().decode([String: OpenRouterRequestOptions].self, from: data)
        } catch {
            print("[Config] Failed to decode OpenRouter options: \(error.localizedDescription)")
            return [:]
        }
    }

    private static func openRouterOptionsBySlot() -> [String: OpenRouterRequestOptions] {
        guard let data = UserDefaults.standard.data(forKey: "openRouterOptionsBySlot") else {
            return [:]
        }

        do {
            return try JSONDecoder().decode([String: OpenRouterRequestOptions].self, from: data)
        } catch {
            print("[Config] Failed to decode OpenRouter slot options: \(error.localizedDescription)")
            return [:]
        }
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
    static var overlayOpacity: Double {
        get {
            let saved = UserDefaults.standard.object(forKey: "overlayOpacity") as? Double
            return min(max(saved ?? 0.68, 0.2), 0.95)
        }
        set {
            UserDefaults.standard.set(min(max(newValue, 0.2), 0.95), forKey: "overlayOpacity")
        }
    }

    static var overlayBackgroundColor: NSColor {
        NSColor(white: 0.2, alpha: overlayOpacity)
    }

    static let headerBackgroundColor: NSColor = NSColor(white: 0.15, alpha: 0.9)
    static let bubbleOpacity: Double = 0.5
}

enum OpenRouterReasoningEffort: String, CaseIterable, Codable, Identifiable {
    case providerDefault = "off"
    case none
    case low
    case medium
    case high

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .providerDefault:
            return "Default"
        case .none:
            return "Off"
        case .low:
            return "Low"
        case .medium:
            return "Medium"
        case .high:
            return "High"
        }
    }
}

struct OpenRouterRequestOptions: Codable, Equatable {
    var maxTokensEnabled: Bool
    var maxTokens: Int
    var temperatureEnabled: Bool
    var temperature: Double
    var topPEnabled: Bool
    var topP: Double
    var frequencyPenaltyEnabled: Bool
    var frequencyPenalty: Double
    var presencePenaltyEnabled: Bool
    var presencePenalty: Double
    var reasoningEffort: OpenRouterReasoningEffort
    var reasoningMaxTokensEnabled: Bool
    var reasoningMaxTokens: Int

    static let `default` = OpenRouterRequestOptions(
        maxTokensEnabled: false,
        maxTokens: 4096,
        temperatureEnabled: false,
        temperature: 0.7,
        topPEnabled: false,
        topP: 1.0,
        frequencyPenaltyEnabled: false,
        frequencyPenalty: 0.0,
        presencePenaltyEnabled: false,
        presencePenalty: 0.0,
        reasoningEffort: .providerDefault,
        reasoningMaxTokensEnabled: false,
        reasoningMaxTokens: 1024
    )

    var normalized: OpenRouterRequestOptions {
        OpenRouterRequestOptions(
            maxTokensEnabled: maxTokensEnabled,
            maxTokens: min(max(maxTokens, 1), 32768),
            temperatureEnabled: temperatureEnabled,
            temperature: min(max(temperature, 0.0), 2.0),
            topPEnabled: topPEnabled,
            topP: min(max(topP, 0.0), 1.0),
            frequencyPenaltyEnabled: frequencyPenaltyEnabled,
            frequencyPenalty: min(max(frequencyPenalty, -2.0), 2.0),
            presencePenaltyEnabled: presencePenaltyEnabled,
            presencePenalty: min(max(presencePenalty, -2.0), 2.0),
            reasoningEffort: reasoningEffort,
            reasoningMaxTokensEnabled: reasoningMaxTokensEnabled,
            reasoningMaxTokens: min(max(reasoningMaxTokens, 1), 32768)
        )
    }

    enum CodingKeys: String, CodingKey {
        case maxTokensEnabled
        case maxTokens
        case temperatureEnabled
        case temperature
        case topPEnabled
        case topP
        case frequencyPenaltyEnabled
        case frequencyPenalty
        case presencePenaltyEnabled
        case presencePenalty
        case reasoningEffort
        case reasoningMaxTokensEnabled
        case reasoningMaxTokens
    }

    init(
        maxTokensEnabled: Bool,
        maxTokens: Int,
        temperatureEnabled: Bool,
        temperature: Double,
        topPEnabled: Bool,
        topP: Double,
        frequencyPenaltyEnabled: Bool,
        frequencyPenalty: Double,
        presencePenaltyEnabled: Bool,
        presencePenalty: Double,
        reasoningEffort: OpenRouterReasoningEffort,
        reasoningMaxTokensEnabled: Bool,
        reasoningMaxTokens: Int
    ) {
        self.maxTokensEnabled = maxTokensEnabled
        self.maxTokens = maxTokens
        self.temperatureEnabled = temperatureEnabled
        self.temperature = temperature
        self.topPEnabled = topPEnabled
        self.topP = topP
        self.frequencyPenaltyEnabled = frequencyPenaltyEnabled
        self.frequencyPenalty = frequencyPenalty
        self.presencePenaltyEnabled = presencePenaltyEnabled
        self.presencePenalty = presencePenalty
        self.reasoningEffort = reasoningEffort
        self.reasoningMaxTokensEnabled = reasoningMaxTokensEnabled
        self.reasoningMaxTokens = reasoningMaxTokens
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.maxTokensEnabled = try container.decodeIfPresent(Bool.self, forKey: .maxTokensEnabled) ?? false
        self.maxTokens = try container.decodeIfPresent(Int.self, forKey: .maxTokens) ?? Self.default.maxTokens
        self.temperatureEnabled = try container.decodeIfPresent(Bool.self, forKey: .temperatureEnabled) ?? false
        self.temperature = try container.decodeIfPresent(Double.self, forKey: .temperature) ?? Self.default.temperature
        self.topPEnabled = try container.decodeIfPresent(Bool.self, forKey: .topPEnabled) ?? false
        self.topP = try container.decodeIfPresent(Double.self, forKey: .topP) ?? Self.default.topP
        self.frequencyPenaltyEnabled = try container.decodeIfPresent(Bool.self, forKey: .frequencyPenaltyEnabled) ?? false
        self.frequencyPenalty = try container.decodeIfPresent(Double.self, forKey: .frequencyPenalty) ?? Self.default.frequencyPenalty
        self.presencePenaltyEnabled = try container.decodeIfPresent(Bool.self, forKey: .presencePenaltyEnabled) ?? false
        self.presencePenalty = try container.decodeIfPresent(Double.self, forKey: .presencePenalty) ?? Self.default.presencePenalty
        self.reasoningEffort = try container.decodeIfPresent(OpenRouterReasoningEffort.self, forKey: .reasoningEffort) ?? .providerDefault
        self.reasoningMaxTokensEnabled = try container.decodeIfPresent(Bool.self, forKey: .reasoningMaxTokensEnabled) ?? false
        self.reasoningMaxTokens = try container.decodeIfPresent(Int.self, forKey: .reasoningMaxTokens) ?? Self.default.reasoningMaxTokens
    }
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

    var fallbackProvider: LLMProvider {
        switch self {
        case .openRouter:
            return .google
        case .google:
            return .openRouter
        }
    }
}
