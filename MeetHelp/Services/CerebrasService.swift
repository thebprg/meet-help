import Foundation

class CerebrasService: ObservableObject {
    @Published var isProcessing = false
    @Published var error: String?
    
    private let session: URLSession
    
    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
    }
    
    func generateAnswer(messages: [CerebrasMessage]) async -> String? {
        guard let url = URL(string: Config.cerebrasAPIURL) else {
            await MainActor.run { self.error = "Invalid API URL" }
            return nil
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(Config.cerebrasAPIKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody = CerebrasRequest(messages: messages, stream: false)
        
        do {
            request.httpBody = try JSONEncoder().encode(requestBody)
        } catch {
            await MainActor.run { self.error = "Failed to encode request: \(error.localizedDescription)" }
            return nil
        }
        
        await MainActor.run { self.isProcessing = true }
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                await MainActor.run {
                    self.isProcessing = false
                    self.error = "Invalid response"
                }
                return nil
            }
            
            guard httpResponse.statusCode == 200 else {
                let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
                await MainActor.run {
                    self.isProcessing = false
                    self.error = "API error (\(httpResponse.statusCode)): \(errorText)"
                }
                print("[Cerebras] Error response: \(errorText)")
                return nil
            }
            
            let cerebrasResponse = try JSONDecoder().decode(CerebrasResponse.self, from: data)
            
            guard let answer = cerebrasResponse.choices.first?.message.content else {
                await MainActor.run {
                    self.isProcessing = false
                    self.error = "No response content"
                }
                return nil
            }
            
            await MainActor.run { self.isProcessing = false }
            
            print("[Cerebras] Answer: \(answer)")
            return answer
            
        } catch {
            await MainActor.run {
                self.isProcessing = false
                self.error = "Request failed: \(error.localizedDescription)"
            }
            print("[Cerebras] Error: \(error)")
            return nil
        }
    }
    
    // Streaming version for future use
    func generateAnswerStreaming(messages: [CerebrasMessage], onChunk: @escaping (String) -> Void) async {
        guard let url = URL(string: Config.cerebrasAPIURL) else {
            await MainActor.run { self.error = "Invalid API URL" }
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(Config.cerebrasAPIKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody = CerebrasRequest(messages: messages, stream: true)
        
        do {
            request.httpBody = try JSONEncoder().encode(requestBody)
        } catch {
            await MainActor.run { self.error = "Failed to encode request" }
            return
        }
        
        await MainActor.run { self.isProcessing = true }
        
        do {
            let (bytes, response) = try await session.bytes(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                await MainActor.run {
                    self.isProcessing = false
                    self.error = "Streaming request failed"
                }
                return
            }
            
            for try await line in bytes.lines {
                if line.hasPrefix("data: ") {
                    let json = String(line.dropFirst(6))
                    if json == "[DONE]" { break }
                    
                    if let data = json.data(using: .utf8),
                       let chunk = try? JSONDecoder().decode(StreamChunk.self, from: data),
                       let content = chunk.choices.first?.delta.content {
                        await MainActor.run {
                            onChunk(content)
                        }
                    }
                }
            }
            
            await MainActor.run { self.isProcessing = false }
            
        } catch {
            await MainActor.run {
                self.isProcessing = false
                self.error = "Streaming error: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Streaming Response Model

struct StreamChunk: Codable {
    let choices: [StreamChoice]
    
    struct StreamChoice: Codable {
        let delta: DeltaContent
        
        struct DeltaContent: Codable {
            let content: String?
        }
    }
}
