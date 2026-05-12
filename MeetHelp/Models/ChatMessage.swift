import Foundation

struct ChatMessage: Identifiable, Codable {
    let id: UUID
    let role: Role
    let content: String
    let timestamp: Date
    let relatedQuestionID: UUID?
    let reasoningContent: String?
    
    enum Role: String, Codable {
        case system
        case user
        case assistant
        case interviewer // Transcribed question
        case starterClue // User-provided directive/starter for the answer
    }
    
    init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        timestamp: Date = Date(),
        relatedQuestionID: UUID? = nil,
        reasoningContent: String? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.relatedQuestionID = relatedQuestionID
        self.reasoningContent = reasoningContent
    }
}

// MARK: - Chat Completion API Request/Response Models

struct ChatCompletionRequest: Codable {
    let model: String
    let messages: [LLMMessage]
    let stream: Bool
    let temperature: Double?
    let max_tokens: Int?
    let top_p: Double?
    let frequency_penalty: Double?
    let presence_penalty: Double?
    let reasoning: OpenRouterReasoningRequest?
    let provider: OpenRouterProviderRouting?
    
    init(
        messages: [LLMMessage],
        stream: Bool = false,
        model: String = Config.selectedOpenRouterModel,
        options: OpenRouterRequestOptions = Config.openRouterOptions(for: Config.selectedOpenRouterModel),
        supportedParameters: Set<String>? = nil,
        providerRouting: OpenRouterProviderRouting? = nil
    ) {
        let normalizedOptions = options.normalized

        self.model = model
        self.messages = messages
        self.stream = stream
        self.temperature = normalizedOptions.temperatureEnabled && Self.supports("temperature", supportedParameters: supportedParameters, fallback: true) ? normalizedOptions.temperature : nil
        self.max_tokens = normalizedOptions.maxTokensEnabled && Self.supports("max_tokens", supportedParameters: supportedParameters, fallback: true) ? normalizedOptions.maxTokens : nil
        self.top_p = normalizedOptions.topPEnabled && Self.supports("top_p", supportedParameters: supportedParameters, fallback: true) ? normalizedOptions.topP : nil
        self.frequency_penalty = normalizedOptions.frequencyPenaltyEnabled && Self.supports("frequency_penalty", supportedParameters: supportedParameters, fallback: false) ? normalizedOptions.frequencyPenalty : nil
        self.presence_penalty = normalizedOptions.presencePenaltyEnabled && Self.supports("presence_penalty", supportedParameters: supportedParameters, fallback: false) ? normalizedOptions.presencePenalty : nil

        if normalizedOptions.reasoningEffort == .none ||
            (Self.supports("reasoning", supportedParameters: supportedParameters, fallback: false) &&
                normalizedOptions.reasoningEffort != .providerDefault) {
            self.reasoning = OpenRouterReasoningRequest(options: normalizedOptions)
        } else {
            self.reasoning = nil
        }

        self.provider = providerRouting
    }

    private static func supports(_ parameter: String, supportedParameters: Set<String>?, fallback: Bool) -> Bool {
        guard let supportedParameters else { return fallback }
        return supportedParameters.contains(parameter)
    }
}

struct OpenRouterProviderRouting: Codable {
    let order: [String]?
    let allow_fallbacks: Bool
    let sort: String?
}

struct OpenRouterReasoningRequest: Codable {
    let effort: String?
    let max_tokens: Int?
    let exclude: Bool?

    init(options: OpenRouterRequestOptions) {
        if options.reasoningEffort == .none {
            self.effort = "none"
            self.max_tokens = nil
            self.exclude = true
        } else {
            self.effort = options.reasoningEffort.rawValue
            self.max_tokens = options.reasoningMaxTokensEnabled ? options.reasoningMaxTokens : nil
            self.exclude = nil
        }
    }
}

struct LLMMessage: Codable {
    let role: String
    let content: String
}

// MARK: - Deepgram Response Models

struct DeepgramResponse: Codable {
    let type: String?
    let channel: DeepgramChannel?
    let is_final: Bool?
    let speech_final: Bool?
    
    struct DeepgramChannel: Codable {
        let alternatives: [Alternative]
        
        struct Alternative: Codable {
            let transcript: String
            let confidence: Double?
        }
    }
}

struct DeepgramUtteranceEnd: Codable {
    let type: String
    let channel: [Int]?
    let last_word_end: Double?
}
