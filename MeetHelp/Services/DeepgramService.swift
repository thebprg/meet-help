import Foundation

class DeepgramService: NSObject, ObservableObject {
    @Published var isConnected = false
    @Published var currentTranscript = ""
    @Published var error: String?
    
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    
    private var onUtteranceEnd: ((String) -> Void)?
    private var accumulatedTranscript = ""
    
    override init() {
        super.init()
    }
    
    func connect(onUtteranceEnd: @escaping (String) -> Void) {
        self.onUtteranceEnd = onUtteranceEnd
        
        // Build WebSocket URL with parameters
        var components = URLComponents(string: Config.deepgramWebSocketURL)!
        components.queryItems = [
            URLQueryItem(name: "model", value: Config.deepgramModel),
            URLQueryItem(name: "encoding", value: "linear16"),
            URLQueryItem(name: "sample_rate", value: String(Int(Config.audioSampleRate))),
            URLQueryItem(name: "channels", value: String(Config.audioChannels)),
            URLQueryItem(name: "interim_results", value: "true"),
            URLQueryItem(name: "utterance_end_ms", value: String(Config.utteranceEndMs)),
            URLQueryItem(name: "punctuate", value: "true"),
            URLQueryItem(name: "smart_format", value: "true")
        ]
        
        guard let url = components.url else {
            self.error = "Invalid Deepgram URL"
            return
        }
        
        var request = URLRequest(url: url)
        request.addValue("Token \(Config.deepgramAPIKey)", forHTTPHeaderField: "Authorization")
        
        urlSession = URLSession(configuration: .default)
        webSocketTask = urlSession?.webSocketTask(with: request)
        
        webSocketTask?.resume()
        isConnected = true
        
        print("[Deepgram] Connecting to WebSocket...")
        
        // Start receiving messages
        receiveMessage()
    }
    
    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        urlSession = nil
        isConnected = false
        accumulatedTranscript = ""
        print("[Deepgram] Disconnected")
    }
    
    func sendAudio(_ data: Data) {
        guard isConnected, let task = webSocketTask else { return }
        
        let message = URLSessionWebSocketTask.Message.data(data)
        task.send(message) { [weak self] error in
            if let error = error {
                DispatchQueue.main.async {
                    self?.error = "Send error: \(error.localizedDescription)"
                }
                print("[Deepgram] Send error: \(error)")
            }
        }
    }
    
    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleMessage(text)
                    }
                @unknown default:
                    break
                }
                
                // Continue receiving
                self.receiveMessage()
                
            case .failure(let error):
                DispatchQueue.main.async {
                    self.isConnected = false
                    self.error = "WebSocket error: \(error.localizedDescription)"
                }
                print("[Deepgram] Receive error: \(error)")
            }
        }
    }
    
    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        
        // Check for UtteranceEnd event
        if text.contains("\"type\":\"UtteranceEnd\"") || text.contains("\"type\": \"UtteranceEnd\"") {
            print("[Deepgram] UtteranceEnd detected")
            
            let finalTranscript = accumulatedTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
            if !finalTranscript.isEmpty {
                DispatchQueue.main.async {
                    self.onUtteranceEnd?(finalTranscript)
                    self.currentTranscript = ""  // Clear display after utterance ends
                }
            }
            accumulatedTranscript = ""
            return
        }
        
        // Parse transcript response
        do {
            let response = try JSONDecoder().decode(DeepgramResponse.self, from: data)
            
            if let transcript = response.channel?.alternatives.first?.transcript,
               !transcript.isEmpty {
                
                // Check if this is a final result
                if response.is_final == true {
                    accumulatedTranscript += " " + transcript
                    print("[Deepgram] Final transcript: \(transcript)")
                }
                
                // Show rolling/latest text for caption-like display
                // Combine accumulated + current interim, then take last ~150 chars
                let fullText = (accumulatedTranscript + " " + transcript).trimmingCharacters(in: .whitespacesAndNewlines)
                let displayText = getLastPortionOfText(fullText, maxLength: 150)
                
                DispatchQueue.main.async {
                    self.currentTranscript = displayText
                }
            }
        } catch {
            // Might be a different message type, ignore parsing errors
        }
    }
    
    /// Get the last portion of text, breaking at word boundaries
    private func getLastPortionOfText(_ text: String, maxLength: Int) -> String {
        if text.count <= maxLength {
            return text
        }
        
        // Take last maxLength characters
        let startIndex = text.index(text.endIndex, offsetBy: -maxLength)
        var truncated = String(text[startIndex...])
        
        // Try to break at a word boundary (find first space)
        if let spaceIndex = truncated.firstIndex(of: " ") {
            truncated = String(truncated[truncated.index(after: spaceIndex)...])
        }
        
        return "..." + truncated
    }
}
