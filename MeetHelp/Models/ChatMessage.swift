import Foundation

struct ChatMessage: Identifiable, Codable {
    let id: UUID
    let role: Role
    let content: String
    let timestamp: Date
    let relatedQuestionID: UUID?
    
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
        relatedQuestionID: UUID? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.relatedQuestionID = relatedQuestionID
    }
}

// MARK: - Chat Completion API Request/Response Models

struct ChatCompletionRequest: Codable {
    let model: String
    let messages: [LLMMessage]
    let stream: Bool
    let temperature: Double
    let max_tokens: Int
    let top_p: Double
    
    init(messages: [LLMMessage], stream: Bool = false, model: String = Config.selectedOpenRouterModel) {
        self.model = model
        self.messages = messages
        self.stream = stream
        self.temperature = 0.7
        self.max_tokens = 4096
        self.top_p = 1.0
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
