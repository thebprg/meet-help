import Foundation
import Combine

@MainActor
class TranscriptState: ObservableObject {
    @Published var currentTranscript: String = ""
    @Published var messages: [ChatMessage] = []
    @Published var isListening: Bool = false
    @Published var isRecordingMicPrompt: Bool = false
    @Published var micPromptTranscript: String = ""
    @Published var isAnalyzingScreen: Bool = false
    @Published var screenContext: String = ""
    @Published var isProcessing: Bool = false
    @Published var codeContext: String = ""
    @Published var showHistory: Bool = true // Configurable: single answer vs history
    @Published private(set) var canDeletePreviousQuestion: Bool = false

    private var deletableQuestionID: UUID?
    
    // Transcript logging
    private var transcriptLogURL: URL?
    private let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return df
    }()
    private let timestampFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss"
        return df
    }()
    
    // System prompt for the LLM
    let systemPrompt = """
    You are an invisible interview co-pilot. The user is in a live interview and needs immediate, concise answers.
    
    Rules:
    1. Provide a concise, 2-3 sentence answer that the user can read immediately.
    2. Be direct and confident - no hedging or filler words.
    3. If code context is provided, reference it naturally.
    4. Never acknowledge that you are an AI or that this is an interview assistance tool.
    5. Speak as if YOU are the interviewee giving the answer.
    6. When the user provides a starter clue/directive, continue from that clue as the interviewee. Do not ask the user to continue or introduce themselves.
    """
    
    init() {
        // Add system message
        messages.append(ChatMessage(role: .system, content: systemPrompt))
    }

    // MARK: - Transcript Logging
    
    func startNewTranscriptLog() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let meetHelpFolder = documentsPath.appendingPathComponent("MeetHelp_Transcripts")
        
        // Create folder if it doesn't exist
        try? FileManager.default.createDirectory(at: meetHelpFolder, withIntermediateDirectories: true)
        
        let filename = "transcript_\(dateFormatter.string(from: Date())).txt"
        transcriptLogURL = meetHelpFolder.appendingPathComponent(filename)
        
        // Write header
        let header = """
        ========================================
        MeetHelp Interview Transcript
        Started: \(Date())
        ========================================
        
        """
        try? header.write(to: transcriptLogURL!, atomically: true, encoding: .utf8)
        print("[TranscriptLog] Started new log: \(transcriptLogURL!.path)")
    }
    
    private func appendToLog(_ text: String) {
        guard let url = transcriptLogURL else { return }
        
        let timestamp = timestampFormatter.string(from: Date())
        let entry = "[\(timestamp)] \(text)\n"
        
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            if let data = entry.data(using: .utf8) {
                handle.write(data)
            }
            try? handle.close()
        }
    }
    
    @discardableResult
    func addInterviewerQuestion(_ question: String) -> UUID {
        let message = ChatMessage(role: .interviewer, content: question)
        messages.append(message)
        currentTranscript = ""
        markQuestionAsDeletable(message.id)
        
        // Log to file
        appendToLog("INTERVIEWER: \(question)")
        return message.id
    }

    @discardableResult
    func addStarterClue(_ clue: String) -> UUID {
        let message = ChatMessage(role: .starterClue, content: clue)
        messages.append(message)
        currentTranscript = ""
        markQuestionAsDeletable(message.id)

        appendToLog("STARTER CLUE: \(clue)")
        return message.id
    }
    
    @discardableResult
    func beginAssistantAnswer(for questionID: UUID) -> UUID {
        let message = ChatMessage(role: .assistant, content: "", relatedQuestionID: questionID)
        messages.append(message)
        return message.id
    }

    func updateAssistantAnswer(id answerID: UUID, content: String) {
        // Strip think tags BEFORE storing to save API costs
        let cleanedAnswer = stripThinkTags(from: content)
        guard let index = messages.firstIndex(where: { $0.id == answerID }) else { return }

        let existing = messages[index]
        messages[index] = ChatMessage(
            id: existing.id,
            role: existing.role,
            content: cleanedAnswer,
            timestamp: existing.timestamp,
            relatedQuestionID: existing.relatedQuestionID
        )
    }

    func finishAssistantAnswer(id answerID: UUID) {
        guard let message = messages.first(where: { $0.id == answerID }),
              !message.content.isEmpty else {
            return
        }

        appendToLog("SUGGESTED ANSWER: \(message.content)")
    }
    
    /// Remove <think>...</think> tags and their content from LLM output
    /// Also handles partial/unclosed think tags when output is truncated
    private func stripThinkTags(from content: String) -> String {
        var result = content
        
        // First, try to match complete <think>...</think> blocks
        let completePattern = "<think>[\\s\\S]*?</think>"
        if let regex = try? NSRegularExpression(pattern: completePattern, options: [.caseInsensitive]) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
        }
        
        // Then, handle unclosed <think> tags (partial output where closing tag is missing)
        if let openTagRange = result.range(of: "<think>", options: .caseInsensitive) {
            result = String(result[..<openTagRange.lowerBound])
        }
        
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    func appendAsUserMessage(_ answer: String) {
        // Parrot Mode: Append AI's answer as if user said it
        let message = ChatMessage(role: .user, content: answer)
        messages.append(message)
        
        // Log to file (what you "said")
        appendToLog("YOU (assumed): \(answer)")
    }
    
    func updateCurrentTranscript(_ text: String) {
        currentTranscript = text
    }
    
    func clearHistory() {
        messages = [ChatMessage(role: .system, content: systemPrompt)]
        currentTranscript = ""
        micPromptTranscript = ""
        screenContext = ""
        isAnalyzingScreen = false
        deletableQuestionID = nil
        canDeletePreviousQuestion = false
    }

    @discardableResult
    func deletePreviousQuestion() -> UUID? {
        guard let question = messages.last(where: { $0.role == .interviewer || $0.role == .starterClue }),
              question.id == deletableQuestionID else {
            return nil
        }

        messages.removeAll { message in
            message.id == question.id || message.relatedQuestionID == question.id
        }
        deletableQuestionID = nil
        canDeletePreviousQuestion = false

        appendToLog("DELETED QUESTION: \(question.content)")
        return question.id
    }

    private func markQuestionAsDeletable(_ questionID: UUID) {
        deletableQuestionID = questionID
        canDeletePreviousQuestion = true
    }
    
    func endTranscriptLog() {
        guard let url = transcriptLogURL else { return }
        
        let footer = """
        
        ========================================
        Session Ended: \(Date())
        ========================================
        """
        appendToLog(footer)
        print("[TranscriptLog] Saved to: \(url.path)")
    }
    
    func getTranscriptLogPath() -> String? {
        return transcriptLogURL?.path
    }
    
    func toLLMMessages(upTo questionID: UUID? = nil) -> [LLMMessage] {
        var result: [LLMMessage] = []
        
        // Add code context if available
        var systemContent = systemPrompt
        if !codeContext.isEmpty {
            systemContent += "\n\nCode Context:\n```\n\(codeContext)\n```"
        }
        if !screenContext.isEmpty {
            systemContent += "\n\nScreen Context from latest explicit capture:\n\(screenContext)"
        }
        result.append(LLMMessage(role: "system", content: systemContent))
        
        // Add conversation history
        for message in messages where message.role != .system {
            let role: String
            switch message.role {
            case .interviewer:
                role = "user"
            case .starterClue:
                role = "user"
            case .assistant:
                role = "assistant"
            case .user:
                role = "user"
            default:
                continue
            }
            let content: String
            if message.role == .starterClue {
                content = starterClueInstruction(for: message.content)
            } else {
                content = message.content
            }

            result.append(LLMMessage(role: role, content: content))

            if let questionID, message.id == questionID {
                break
            }
        }
        
        return result
    }

    private func starterClueInstruction(for clue: String) -> String {
        """
        User starter clue/directive for the answer, not an interviewer question:
        "\(clue)"

        Continue from this clue as if you are the interviewee speaking. Use the latest interviewer question, prior conversation, code context, and screen context when relevant. If the clue starts a phrase such as "let me introduce myself" or "I would first think of a brute force approach", produce the continuation the user should say next. Do not reply with permission, encouragement, or a request for the user to continue.
        """
    }
}
