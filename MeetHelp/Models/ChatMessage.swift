import Foundation

struct ChatMessage: Identifiable, Codable {
    let id: UUID
    let role: Role
    let content: String
    let timestamp: Date
    
    enum Role: String, Codable {
        case system
        case user
        case assistant
        case interviewer // Transcribed question
    }
    
    init(id: UUID = UUID(), role: Role, content: String, timestamp: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
}

// MARK: - Cerebras API Request/Response Models

struct CerebrasRequest: Codable {
    let model: String
    let messages: [CerebrasMessage]
    let stream: Bool
    let temperature: Double
    let max_completion_tokens: Int
    let top_p: Double
    
    init(messages: [CerebrasMessage], stream: Bool = false) {
        self.model = Config.cerebrasModel
        self.messages = messages
        self.stream = stream
        self.temperature = 0.7
        self.max_completion_tokens = 4096  // Increased to allow full responses with thinking
        self.top_p = 1.0
    }
}

struct CerebrasMessage: Codable {
    let role: String
    let content: String
}

struct CerebrasResponse: Codable {
    let choices: [Choice]
    
    struct Choice: Codable {
        let message: CerebrasMessage
        let finish_reason: String?
    }
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
